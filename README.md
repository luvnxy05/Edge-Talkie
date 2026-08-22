# 端语（DuanYu）—— 鸿蒙原生本地大模型对话应用

> 运行在 HarmonyOS NEXT 设备上的纯本地大语言模型聊天应用，无云端依赖，隐私数据不出设备。

端语是 HarmonyOS NEXT 生态位首发的本地 LLM 聊天应用：基于阿里巴巴 [MNN](https://github.com/alibaba/MNN) 引擎端侧推理 4-bit 量化模型，全程离线运行，你的对话内容永远不会离开设备。

## ✨ 特性

- **纯本地推理**：MNN 引擎 + ModelScope 的 4-bit MNN 格式模型，无任何云端 API 调用
- **多模型管理**：应用内下载 / 切换 / 删除模型（Qwen3、Qwen2.5 系列，433MB ~ 1.2GB）
- **流式输出**：逐 token 打字机效果，思考过程浅灰折叠展示
- **思考链折叠**：Qwen3 系列模型的 `<think>` 推理过程默认收起，可展开查看
- **多轮对话**：完整上下文记忆，历史会话持久化
- **本地 OpenAI 兼容 API**：`POST /v1/chat/completions`，供鸿蒙电脑上的智能体 / 第三方客户端接入本机模型
- **推理统计**：每条回复显示 token 数与生成速度
- **参数可调**：温度、思考模式开关

## 🏗️ 技术架构

| 层 | 选型 |
|---|---|
| 推理引擎 | MNN（`libMNN.so`，LLM 已链入，arm64-v8a） |
| 桥接层 | NAPI（C++ ↔ ArkTS，`libmnnllm.so`） |
| UI 层 | ArkUI（ArkTS，HarmonyOS NEXT 原生） |
| 模型渠道 | ModelScope MNN 官方组织（Apache-2.0 可再分发模型） |

```
ArkTS UI (聊天/模型管理/API服务)
        ↕ NAPI (libmnnllm.so)
   MNN::Transformer::Llm (libMNN.so)
        ↕
   4-bit MNN 模型 (llm.mnn + llm.mnn.weight)
```

## 🚀 快速开始

### 环境要求

- DevEco Studio 6.1.0+（内置 SDK API 23 / HarmonyOS 6.1.0）
- HarmonyOS NEXT 真机（API 12+，arm64-v8a）
- Node.js + ohpm

### 构建

```bash
export DEVECO_SDK_HOME="$HOME/Library/OpenHarmony/Sdk"
export PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH"

cd mnn-harmony-chat
ohpm install
node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
# 产物：entry/build/default/outputs/default/entry-default-signed.hap
```

### 签名与部署

HarmonyOS NEXT 真机需 DevEco Studio 自动签名（本地 OpenHarmony 签名会被拒）：

1. DevEco Studio → File → Project Structure → Signing Configs
2. 勾选 Automatically generate signature（需登录华为开发者账号）
3. `hdc install -r entry-default-signed.hap`

## 📦 模型下载

应用内「参数 → 模型管理」可下载以下模型（来自 ModelScope MNN 官方组织，均为 Apache-2.0 可再分发）：

| 模型 | 大小 | 说明 |
|---|---|---|
| Qwen3-0.6B-MNN | 433 MB | 最快，能力一般 |
| Qwen2.5-1.5B-Instruct-MNN | 839 MB | 均衡，能力较强 |
| Qwen3-1.7B-MNN | 1.2 GB | 最强 |
| Qwen2.5-0.5B-Instruct-MNN | 531 MB | 最小，能力最弱 |

## 🔌 本地 API 服务

端语内置 OpenAI 兼容的本地 HTTP 服务，供鸿蒙电脑上的智能体或其他客户端接入本机模型：

```bash
# 开启后（设置 → API 服务），监听 0.0.0.0:8080
curl http://<设备IP>:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"duanyu-local","messages":[{"role":"user","content":"你好"}]}'
```

- `POST /v1/chat/completions` — 对话补全（OpenAI 兼容）
- `GET /v1/models` — 模型列表
- `GET /health` — 健康检查

## ⚖️ 合规说明

端语是纯本地单机应用（模型在设备端推理，对话内容不出设备）：

- 聊天界面带「AI 生成」显式标识
- 模型均为 Apache-2.0 许可（Qwen 系列），可合法再分发
- 单机应用不触发算法备案 / 安全评估（无舆论属性或社会动员能力）

## 📄 许可证

本项目采用 [Apache License 2.0](LICENSE)。依赖的 MNN 引擎、Qwen 模型、以及部分借鉴自 [SKL-666666/mnn-local-ai-chat](https://github.com/SKL-666666/mnn-local-ai-chat)（Apache-2.0）的代码，均遵循其各自的许可证。
