// MNN LLM NAPI 桥 - 端语本地推理引擎
// 提供: init(modelDir) / submit(prompt) / poll() / reset() / release()
// 流式方案：自定义 streambuf 把 MNN 逐 token 输出写入 session->pending（加锁缓冲），
// ArkTS 侧用 setInterval 轮询 poll() 取新增内容 + done 标志。零 tsfn 依赖（鸿蒙 tsfn 不可靠）。
#include "napi/native_api.h"
#include <string>
#include <mutex>
#include <atomic>
#include <sstream>
#include <fstream>
#include <cerrno>
#include <chrono>
#include <thread>
#include <sys/stat.h>
#include "llm/llm.hpp"

// 鸿蒙 hilog 输出
#include <hilog/log.h>
#define LOG_TAG "MnnLlm"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

using ChatMessages = MNN::Transformer::ChatMessages;
using ChatMessage = MNN::Transformer::ChatMessage;

struct LlmSession {
    MNN::Transformer::Llm* llm = nullptr;
    std::mutex mtx;                    // 保护 llm 调用 + history
    std::atomic<bool> generating{false};
    // 多轮对话历史（response(ChatMessages) 传多轮上下文）
    MNN::Transformer::ChatMessages history;
    // 流式缓冲：SubmitWorker 追加，poll() 取走
    std::mutex pending_mtx;
    std::string pending;               // 未取走的 token 内容
    std::string fullResponse;          // 完整回复（累计，供历史记录用）
    std::atomic<bool> done{false};     // 推理完成标志
    std::atomic<bool> error{false};
    std::string errorMsg;
    std::atomic<bool> stopRequested{false};  // 用户请求停止生成
    std::atomic<bool> thinkingEnabled{true}; // 思考模式开关（Qwen3 系列生效）
    // 推理统计
    std::atomic<int> promptTokens{0};
    std::atomic<int> outputTokens{0};
    std::atomic<double> tokPerSec{0.0};
};

// 剥离 <think>...</think> 思维链标签：多轮历史只保留最终答案，避免下一轮双 think 污染
static std::string StripThink(const std::string& s) {
    const std::string open = "<think>";
    const std::string close = "</think>";
    std::string out;
    size_t pos = 0;
    while (true) {
        size_t i = s.find(open, pos);
        if (i == std::string::npos) {
            out += s.substr(pos);
            break;
        }
        out += s.substr(pos, i - pos);
        size_t j = s.find(close, i + open.size());
        if (j == std::string::npos) {
            break; // 无闭合标签：丢弃 think 段及之后
        }
        pos = j + close.size();
    }
    return out;
}

// 裁剪历史：最多 16 条（约 8 轮）+ 字符上限，防止上下文无限增长
static void TrimHistory(MNN::Transformer::ChatMessages& msgs) {
    const size_t MAX_MSGS = 16;
    const size_t MAX_CHARS = 24000;
    while (msgs.size() > MAX_MSGS) {
        if (msgs.size() >= 2 && msgs[0].first == "system") {
            msgs.erase(msgs.begin() + 1);
        } else {
            msgs.erase(msgs.begin());
        }
    }
    size_t chars = 0;
    for (const auto& m : msgs) {
        chars += m.second.size();
    }
    while (chars > MAX_CHARS && msgs.size() > 1) {
        chars -= msgs.front().second.size();
        msgs.erase(msgs.begin());
    }
}

// 自定义 streambuf：MNN 每 flush 一次把 token 写入 session->pending
class TokenStreamBuf : public std::streambuf {
public:
    explicit TokenStreamBuf(LlmSession* session) : session_(session) {}
protected:
    int_type overflow(int_type c) override {
        if (c != traits_type::eof()) {
            buf_.push_back(static_cast<char>(c));
        }
        // 换行或累积足够长度时刷出（减少锁竞争）
        if (c == '\n' || buf_.size() >= 32) {
            flush();
        }
        return c;
    }
    int sync() override {
        flush();
        return 0;
    }
private:
    void flush() {
        // 用户请求停止：抛异常中断 MNN 的 response()（每生成一个 token 都会写 ostream 触发这里）
        if (session_->stopRequested.load()) {
            throw std::runtime_error("generation stopped");
        }
        if (buf_.empty()) return;
        std::lock_guard<std::mutex> lock(session_->pending_mtx);
        session_->pending += buf_;
        session_->fullResponse += buf_;
        buf_.clear();
    }
    LlmSession* session_;
    std::string buf_;
};

static napi_value InitSession(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char buf[1024];
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], buf, sizeof(buf), &len);
    std::string modelDir(buf, len);

    LlmSession* session = new LlmSession();
    // 诊断：确认模型目录可访问
    {
        struct stat st;
        if (stat(modelDir.c_str(), &st) != 0) {
            LOGE("stat %{public}s failed errno=%{public}d", modelDir.c_str(), errno);
            napi_throw_error(env, "E_LOAD", ("stat failed errno=" + std::to_string(errno)).c_str());
            delete session;
            return nullptr;
        }
        std::string cfgPath = modelDir + "/config.json";
        std::ifstream f(cfgPath);
        if (!f.good()) {
            napi_throw_error(env, "E_LOAD", ("cannot open config: " + cfgPath).c_str());
            delete session;
            return nullptr;
        }
    }
    try {
        // createLLM 必须传 config.json 完整路径
        std::string configPath = modelDir + "/config.json";
        LOGI("createLLM configPath=%{public}s", configPath.c_str());
        session->llm = MNN::Transformer::Llm::createLLM(configPath);
        if (!session->llm) {
            napi_throw_error(env, "E_LOAD", "createLLM failed");
            delete session;
            return nullptr;
        }
        // 线程数自动适配：核心数-2（留核给系统/UI/其他工作），下限 4 上限 8
        // 依据：LLM 推理是内存带宽瓶颈，超 8 线程无收益（调研结论见技能 napi-bridge.md「GPU/NPU 加速可行性」）
        int cores = static_cast<int>(std::thread::hardware_concurrency());
        if (cores <= 0) cores = 8;   // 检测失败默认 8
        int threadNum = cores - 2;
        if (threadNum < 4) threadNum = 4;
        if (threadNum > 8) threadNum = 8;
        LOGI("auto thread_num: cores=%{public}d -> threads=%{public}d", cores, threadNum);
        std::string cfg = "{\"thread_num\":" + std::to_string(threadNum) + ",\"precision\":\"low\",\"memory\":\"low\"}";
        session->llm->set_config(cfg);
        if (!session->llm->load()) {
            LOGE("llm load() returned false");
            std::string log = session->llm->getLog();
            napi_throw_error(env, "E_LOAD", ("load() false. log: " + log.substr(0, 500)).c_str());
            delete session;
            return nullptr;
        }
        LOGI("engine loaded OK");
    } catch (const std::exception& e) {
        LOGE("exception: %{public}s", e.what());
        delete session;
        napi_throw_error(env, "E_LOAD", e.what());
        return nullptr;
    } catch (...) {
        LOGE("unknown exception");
        delete session;
        napi_throw_error(env, "E_LOAD", "unknown exception");
        return nullptr;
    }

    napi_value result;
    napi_create_external(env, session, nullptr, nullptr, &result);
    return result;
}

struct SubmitArgs {
    LlmSession* session;
    std::string prompt;
    napi_async_work work;
};

static void SubmitWorker(napi_env env, void* data) {
    SubmitArgs* args = static_cast<SubmitArgs*>(data);
    auto startTime = std::chrono::steady_clock::now();
    try {
        LOGI("submit: prompt=%{public}s", args->prompt.substr(0, 64).c_str());
        TokenStreamBuf tbuf(args->session);
        std::ostream tokenStream(&tbuf);

        // 多轮上下文：把本轮 prompt 追加到历史，用 response(ChatMessages) 传完整上下文
        LlmSession* s = args->session;
        ChatMessages msgs;
        {
            std::lock_guard<std::mutex> lock(s->mtx);
            msgs = s->history;           // 拷贝历史（含之前所有轮次）
        }
        msgs.emplace_back("user", args->prompt);
        s->promptTokens.store((int)(args->prompt.size() / 3 + 1));  // 粗略估算 prompt token

        // max_new_tokens 显式给大值：Qwen3 思考链长，默认 512 上限导致正文截断；4096 覆盖长思考+长正文
        s->llm->response(msgs, &tokenStream, nullptr, 4096);
        tokenStream.flush();
        LOGI("submit done (streamed)");

        // 记录 assistant 回复（剥离 think）到历史，供下一轮
        std::string full;
        {
            std::lock_guard<std::mutex> lock(s->pending_mtx);
            full = s->fullResponse;
        }
        // 输出 token 估算 + 速度
        double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - startTime).count();
        int outTok = (int)(full.size() / 3 + 1);
        s->outputTokens.store(outTok);
        s->tokPerSec.store(secs > 0 ? outTok / secs : 0.0);
        // 追加 assistant 回复到历史（剥离 think，只存正文）
        {
            std::lock_guard<std::mutex> lock(s->mtx);
            s->history.emplace_back("user", args->prompt);
            s->history.emplace_back("assistant", StripThink(full));
            TrimHistory(s->history);
        }
    } catch (const std::exception& e) {
        if (std::string(e.what()) == "generation stopped") {
            LOGI("generation stopped by user");
            // 用户主动停止：不设 error，正常结束
        } else {
            LOGE("submit exception: %{public}s", e.what());
            args->session->error.store(true);
            args->session->errorMsg = e.what();
        }
    }
    args->session->done.store(true);
    args->session->generating.store(false);
    args->session->stopRequested.store(false);
}

static void SubmitComplete(napi_env env, napi_status status, void* data) {
    SubmitArgs* args = static_cast<SubmitArgs*>(data);
    napi_delete_async_work(env, args->work);
    delete args;
}

static napi_value Submit(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_error(env, "E_ARGS", "submit(session, prompt)");
        return nullptr;
    }
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);
    if (!session || !session->llm || session->generating.load()) {
        napi_throw_error(env, "E_BUSY", "engine busy or not initialized");
        return nullptr;
    }
    // prompt
    size_t plen = 0;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &plen);
    char* pbuf = new char[plen + 1];
    napi_get_value_string_utf8(env, args[1], pbuf, plen + 1, &plen);
    std::string prompt(pbuf, plen);
    delete[] pbuf;

    // 重置流式状态
    {
        std::lock_guard<std::mutex> lock(session->pending_mtx);
        session->pending.clear();
        session->fullResponse.clear();
    }
    session->done.store(false);
    session->error.store(false);
    session->errorMsg.clear();
    session->generating.store(true);

    auto* a = new SubmitArgs{session, std::move(prompt), nullptr};
    napi_value rn;
    napi_create_string_utf8(env, "submitWorker", NAPI_AUTO_LENGTH, &rn);
    napi_create_async_work(env, nullptr, rn, SubmitWorker, SubmitComplete, a, &a->work);
    napi_queue_async_work(env, a->work);
    return nullptr;
}

// submitSync(session, prompt) -> Promise<string>
// 同步语义（Promise 包装）：后台线程推理，完成后 resolve 完整文本。供 API 服务器用。
struct SyncArgs {
    LlmSession* session;
    std::string prompt;
    napi_async_work work;
    napi_deferred deferred;
    std::string result;
};

static void SyncWorker(napi_env env, void* data) {
    SyncArgs* args = static_cast<SyncArgs*>(data);
    LOGI("syncWorker start: prompt=%{public}s", args->prompt.substr(0, 40).c_str());
    args->session->generating.store(true);
    try {
        TokenStreamBuf tbuf(args->session);
        std::ostream tokenStream(&tbuf);
        // 多轮历史（API 调用也走多轮上下文）
        ChatMessages msgs;
        {
            std::lock_guard<std::mutex> lock(args->session->mtx);
            msgs = args->session->history;
        }
        msgs.emplace_back("user", args->prompt);
        LOGI("syncWorker calling response");
        args->session->llm->response(msgs, &tokenStream, nullptr, 2048);
        tokenStream.flush();
        LOGI("syncWorker response done");
        {
            std::lock_guard<std::mutex> lock(args->session->pending_mtx);
            args->result = args->session->fullResponse;
        }
        // 记录历史
        {
            std::lock_guard<std::mutex> lock(args->session->mtx);
            args->session->history.emplace_back("user", args->prompt);
            args->session->history.emplace_back("assistant", StripThink(args->result));
            TrimHistory(args->session->history);
        }
    } catch (const std::exception& e) {
        LOGE("syncWorker exception: %{public}s", e.what());
        args->result = std::string("[error] ") + e.what();
    }
    LOGI("syncWorker finished, result len=%{public}zu", args->result.size());
    args->session->generating.store(false);
}

static void SyncComplete(napi_env env, napi_status status, void* data) {
    SyncArgs* args = static_cast<SyncArgs*>(data);
    LOGI("syncComplete: status=%{public}d result len=%{public}zu", (int)status, args->result.size());
    napi_value result;
    napi_create_string_utf8(env, args->result.c_str(), args->result.size(), &result);
    napi_resolve_deferred(env, args->deferred, result);
    napi_delete_async_work(env, args->work);
    delete args;
}

static napi_value SubmitSync(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_error(env, "E_ARGS", "submitSync(session, prompt)");
        return nullptr;
    }
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);
    if (!session || !session->llm || session->generating.load()) {
        napi_throw_error(env, "E_BUSY", "engine busy or not initialized");
        return nullptr;
    }
    size_t plen = 0;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &plen);
    char* pbuf = new char[plen + 1];
    napi_get_value_string_utf8(env, args[1], pbuf, plen + 1, &plen);
    std::string prompt(pbuf, plen);
    delete[] pbuf;

    napi_deferred deferred;
    napi_value promise;
    napi_create_promise(env, &deferred, &promise);

    auto* a = new SyncArgs{session, std::move(prompt), nullptr, deferred, ""};
    napi_value rn;
    napi_create_string_utf8(env, "syncWorker", NAPI_AUTO_LENGTH, &rn);
    napi_create_async_work(env, nullptr, rn, SyncWorker, SyncComplete, a, &a->work);
    napi_queue_async_work(env, a->work);
    return promise;
}

// 轮询：返回 { chunk: string, done: bool, error: string }，chunk 为新生成内容（取走后清空）
static napi_value Poll(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);

    napi_value obj;
    napi_create_object(env, &obj);

    std::string chunk;
    if (session) {
        std::lock_guard<std::mutex> lock(session->pending_mtx);
        chunk = session->pending;
        session->pending.clear();
    }

    napi_value chunkVal;
    napi_create_string_utf8(env, chunk.c_str(), chunk.size(), &chunkVal);
    napi_set_named_property(env, obj, "chunk", chunkVal);

    napi_value doneVal;
    napi_get_boolean(env, session ? session->done.load() : true, &doneVal);
    napi_set_named_property(env, obj, "done", doneVal);

    napi_value errVal;
    napi_create_string_utf8(env, (session ? session->errorMsg : std::string("")).c_str(), NAPI_AUTO_LENGTH, &errVal);
    napi_set_named_property(env, obj, "error", errVal);

    // 推理统计（done 后有效）
    napi_value promptTok, outTok, tps;
    napi_create_int32(env, session ? session->promptTokens.load() : 0, &promptTok);
    napi_set_named_property(env, obj, "promptTokens", promptTok);
    napi_create_int32(env, session ? session->outputTokens.load() : 0, &outTok);
    napi_set_named_property(env, obj, "outputTokens", outTok);
    napi_create_double(env, session ? session->tokPerSec.load() : 0.0, &tps);
    napi_set_named_property(env, obj, "tokPerSec", tps);

    return obj;
}

// stop(session)：请求停止当前生成（非阻塞）。置位标志后，streambuf flush 抛异常中断 response()
static napi_value Stop(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);
    if (session) {
        session->stopRequested.store(true);
        LOGI("stop requested");
    }
    return nullptr;
}

// setThinking(session, enabled)：思考模式开关（Qwen3 系列生效）
static napi_value SetThinking(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_error(env, "E_ARGS", "setThinking(session, enabled)");
        return nullptr;
    }
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);
    if (session) {
        bool enabled = true;
        napi_get_value_bool(env, args[1], &enabled);
        session->thinkingEnabled.store(enabled);
        // 通过 jinja context 的 enable_thinking 关闭思考（MNN 官方方式，见 dflash.cpp:84）
        // 这比 system prompt 可靠——它在 jinja 渲染层直接跳过 <think> 前缀
        if (!enabled) {
            session->llm->set_config("{\"jinja\":{\"context\":{\"enable_thinking\":false}}}");
        } else {
            session->llm->set_config("{\"jinja\":{\"context\":{\"enable_thinking\":true}}}");
        }
        LOGI("setThinking: %{public}s", enabled ? "on" : "off");
    }
    return nullptr;
}

static napi_value Reset(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);
    if (session && session->llm) {
        std::lock_guard<std::mutex> lock(session->mtx);
        session->llm->reset();
        session->history.clear();   // 清空多轮上下文
    }
    return nullptr;
}

// setConfig(session, jsonConfig)：运行时动态调参（温度/top_p/top_k 等）
static napi_value SetConfig(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_error(env, "E_ARGS", "setConfig(session, json)");
        return nullptr;
    }
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);
    if (!session || !session->llm) {
        napi_throw_error(env, "E_BUSY", "engine not initialized");
        return nullptr;
    }
    size_t plen = 0;
    napi_get_value_string_utf8(env, args[1], nullptr, 0, &plen);
    char* pbuf = new char[plen + 1];
    napi_get_value_string_utf8(env, args[1], pbuf, plen + 1, &plen);
    std::string cfg(pbuf, plen);
    delete[] pbuf;
    {
        std::lock_guard<std::mutex> lock(session->mtx);
        session->llm->set_config(cfg);
    }
    LOGI("setConfig: %{public}s", cfg.c_str());
    return nullptr;
}

static napi_value Release(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    void* raw = nullptr;
    napi_get_value_external(env, args[0], &raw);
    LlmSession* session = static_cast<LlmSession*>(raw);
    if (session) {
        if (session->llm) {
            MNN::Transformer::Llm::destroy(session->llm);
        }
        delete session;
    }
    return nullptr;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"init", nullptr, InitSession, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"submit", nullptr, Submit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"submitSync", nullptr, SubmitSync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"poll", nullptr, Poll, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setConfig", nullptr, SetConfig, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setThinking", nullptr, SetThinking, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"reset", nullptr, Reset, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"release", nullptr, Release, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "mnnllm",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterModule(void) {
    napi_module_register(&demoModule);
}
