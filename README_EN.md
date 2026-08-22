# DuanYu (端语) — A Native On-Device LLM Chat App for HarmonyOS NEXT

> A fully local large-language-model chat app for HarmonyOS NEXT devices. No cloud, no telemetry — your conversations never leave the device.

DuanYu is the first local-LLM chat app in the HarmonyOS NEXT ecosystem: it runs 4-bit quantized models entirely on-device via Alibaba's [MNN](https://github.com/alibaba/MNN) engine, completely offline.

## ✨ Features

- **Fully local inference**: MNN engine + 4-bit MNN models from ModelScope, zero cloud API calls
- **Model management**: in-app download / switch / delete models (Qwen3, Qwen2.5, 433MB ~ 1.2GB)
- **Streaming output**: token-by-token typewriter effect, with reasoning steps collapsed in light gray
- **Thinking-chain folding**: `<think>` reasoning from Qwen3 models collapsed by default, expandable
- **Multi-turn context**: full conversation memory with persistent chat history
- **Local OpenAI-compatible API**: `POST /v1/chat/completions` so agents/third-party clients on HarmonyOS PCs can call the local model
- **Inference stats**: token count and generation speed per reply
- **Tunable parameters**: temperature, thinking-mode toggle

## 🏗️ Architecture

| Layer | Choice |
|---|---|
| Inference engine | MNN (`libMNN.so`, LLM linked in, arm64-v8a) |
| Bridge | NAPI (C++ ↔ ArkTS, `libmnnllm.so`) |
| UI | ArkUI (ArkTS, native HarmonyOS NEXT) |
| Model source | ModelScope MNN official org (Apache-2.0 redistributable models) |

```
ArkTS UI (chat / model management / API server)
        ↕ NAPI (libmnnllm.so)
   MNN::Transformer::Llm (libMNN.so)
        ↕
   4-bit MNN models (llm.mnn + llm.mnn.weight)
```

## 🚀 Getting Started

### Requirements

- DevEco Studio 6.1.0+ (bundled SDK API 23 / HarmonyOS 6.1.0)
- HarmonyOS NEXT device (API 12+, arm64-v8a)
- Node.js + ohpm

### Build

```bash
export DEVECO_SDK_HOME="$HOME/Library/OpenHarmony/Sdk"
export PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH"

cd mnn-harmony-chat
ohpm install
node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
# Output: entry/build/default/outputs/default/entry-default-signed.hap
```

### Sign & Deploy

HarmonyOS NEXT devices require DevEco Studio auto-signing:

1. DevEco Studio → File → Project Structure → Signing Configs
2. Check "Automatically generate signature" (requires Huawei developer login)
3. `hdc install -r entry-default-signed.hap`

## 📦 Model Download

In-app: **Settings → Model Management** (all from the ModelScope MNN official org, Apache-2.0):

| Model | Size | Notes |
|---|---|---|
| Qwen3-0.6B-MNN | 433 MB | Fastest, average quality |
| Qwen2.5-1.5B-Instruct-MNN | 839 MB | Balanced, better quality |
| Qwen3-1.7B-MNN | 1.2 GB | Best quality |
| Qwen2.5-0.5B-Instruct-MNN | 531 MB | Smallest, weakest |

## 🔌 Local API Server

DuanYu ships a local OpenAI-compatible HTTP server for agents/other clients on HarmonyOS PCs:

```bash
# After enabling (Settings → API Service), listens on 0.0.0.0:8080
curl http://<device-IP>:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"duanyu-local","messages":[{"role":"user","content":"Hello"}]}'
```

- `POST /v1/chat/completions` — chat completion (OpenAI-compatible)
- `GET /v1/models` — model list
- `GET /health` — health check

## ⚖️ Compliance

DuanYu is a pure on-device app (models run locally, conversations never leave the device):

- Chat UI carries an "AI 生成" (AI-generated) label
- All models are Apache-2.0 licensed (Qwen series), legally redistributable
- Standalone apps do not trigger China's algorithm filing / safety assessment (no public-opinion or social-mobilization attributes)

## 📄 License

[Apache License 2.0](LICENSE). The MNN engine, Qwen models, and portions adapted from [SKL-666666/mnn-local-ai-chat](https://github.com/SKL-666666/mnn-local-ai-chat) (Apache-2.0) remain under their respective licenses.
