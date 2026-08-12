# 鸿蒙本地大模型聊天 App（MNN-Harmony Chat）立项文档

> 状态：2026-08-12 立项 · 可行性调研已完成（模型渠道 ✅ / 上架政策 ✅ 个人开发者可走通）

## 1. 项目定位

HarmonyOS NEXT 原生本地大模型聊天应用（LM Studio 风格）：
- **纯本地推理**：MNN 引擎（libMNN.so + libllm.so）端侧跑 4-bit MNN 格式模型，无云端依赖
- **模型管理**：应用内从 ModelScope（魔搭）MNN 官方组织下载/删除模型，支持多模型切换
- **流式聊天**：ArkTS 聊天界面 + 流式渲染，OpenAI 兼容无云、隐私本地化
- 与 Android 版 MNN-Chat 是**独立项目**（鸿蒙 NEXT 无 AOSP 层，技术栈完全不同）

背景缺口：鸿蒙 NEXT 应用市场目前无第三方本地 LLM 聊天 App（小艺为云优先），MNN 官方也无鸿蒙 LLM demo——本项目是该生态位首发。

## 2. 技术选型（已核实）

| 层 | 选型 | 依据 |
|---|---|---|
| 推理引擎 | MNN 官方鸿蒙构建 | `package_scripts/harmony/build.sh` → libMNN.so + libllm.so（LLM+vision+audio，arm64-v8a） |
| 桥接层 | NAPI（C++ ↔ ArkTS） | MNN 无纯 ArkTS 调用途径，NAPI 是唯一正规通道 |
| UI 层 | ArkUI（ArkTS） | HarmonyOS NEXT 唯一原生 UI 框架 |
| 模型渠道 | ModelScope MNN 组织 | 222 个模型（Qwen3/3.5/3.6、gemma-4、LFM），匿名 API 可下载，llm.mnn 跨平台同格式 |
| 构建链 | DevEco 6.1.0（本地已有）+ SDK 15/HarmonyOS-6.1.0 | 本机环境已具备 |

关键兼容性事实：
- `-DOHOS_PLATFORM_LEVEL=12` 是 **minSdk 语义**（编译最低 API），产物在 API 24 设备正常加载
- `-DOHOS_STL=c++_shared` → HAP 必须打包 `libc++_shared.so`
- 本地 SDK 为 API 15 / HarmonyOS 6.1.0(23)，构建 targetSdk 用 6.1.0(23) 即可，设备 API 24 向前兼容

## 3. 合规与分发路径（已核实，个人开发者可走通）

分类归属"深度合成或生成式人工智能服务"，但 **算法备案 + 安全评估只触发于"具有舆论属性或者社会动员能力"的服务**——纯本地单机聊天不触发（华为《应用审核指南》第17条原文限定）。

纯本地 App 仍需要的材料（全部低成本）：
1. AI 功能声明 = "涉及"（AGC 必填）
2. 显式标识：聊天界面"AI 生成"角标/文字 + 截图（**v1 不做导出/分享文件功能** → 免隐式标识材料）
3. 软著：个人可用《APP电子版权认证证书》替代
4. 实名认证 + 用户协议说明标识规范 + 投诉举报入口
5. 单机应用 → 免 APP 备案

模型来源（魔搭/开源）不影响备案判断——备案针对"服务提供者"而非模型训练者；纯本地不构成服务提供者。仅需模型许可证白名单（Qwen=Apache-2.0 可再分发；gemma 有使用条款）。

**分发阶梯**：hdc 侧载/开源发布（最快）→ AGC 指定设备发布（内测）→ AGC 公开测试（完整审核，30 天）→ 正式上架（远期，需企业主体）。

## 4. 里程碑

| 阶段 | 内容 | 验收标准 |
|---|---|---|
| **M0 环境与引擎** | 配置 DEVECO_SDK_HOME/hdc/ohpm；交叉编译 MNN 鸿蒙版 libllm.so；建工程模板 | libllm.so 产出；空 HAP 构建+侧载到 MateBook14 成功 |
| **M1 NAPI 桥** | C++ 封装 llm 加载/生成/流式回调；ArkTS 侧 ts 接口 | ArkTS 能调用原生层完成一次"加载→生成→返回" |
| **M2 聊天 UI** | 会话列表 + 流式消息渲染 + 参数设置（温度/上下文）+ "AI 生成"显式标识 | 真机全流程聊天可用 |
| **M3 模型管理** | ModelScope 匿名 API 下载/断点续传/删除/多模型切换 | 应用内下载 Qwen3 小模型并切换推理 |
| **M4 合规与发布** | 隐私政策/用户协议/举报入口/实名；软著（电子版权）；签名；开源发布（README 中文+EN） | HAP 侧载分发 + GitHub/Gitee Release |

## 5. 风险与对策

| 风险 | 对策 |
|---|---|
| NAPI 桥接开发成本（无鸿蒙 LLM demo 可抄） | 预算 1 周；参考 MNN LLM C++ API（llm.h）+ OpenHarmony NAPI 官方示例 |
| 麒麟 CPU 上 LLM 推理速度 | 选 1-3B 4-bit 模型起步（Qwen3-2B-Dflash 等）；CPU 多线程 + ARM82 指令集已开 |
| 模型下载需联网 → 与"单机应用"备案豁免冲突 | v1 声明为单机+用户导入/应用内下载；若审核质疑，模型下载走接入商备案补办（个人可备案） |
| 华为审核对 AIGC 从严 | 严格按第17条做全：显式标识、用户协议条款、举报入口、实名 |

## 6. 命名与包名

- 应用名（暂定）：待定（**软著名称须与上架应用名一致，命名在申请软著前定死**）
- bundle name：`io.mnnkeep.harmony` 或独立命名，立项后立即确定

## 7. 本地环境现状（2026-08-12 检查）

- DevEco Studio 6.1.0 ✅（/Applications/DevEco-Studio.app）
- SDK：`~/Library/OpenHarmony/Sdk/15/`（OpenHarmony 完整）+ `HarmonyOS-6.1.0/`（hms 组件）✅
- `DEVECO_SDK_HOME` 未设置、hdc/ohpm 不在 PATH → M0 需配置
- 测试设备：MateBook14 鸿蒙版（MNTXM-24B，API 24）
- MNN 源码：`~/Projects/mnn-fork`（含 `package_scripts/harmony/build.sh`）✅

## 8. M0 执行记录（2026-08-12）

**✅ 已完成**
1. MNN 鸿蒙交叉编译成功：`~/Projects/mnn-fork/package_scripts/harmony/build.sh -o prebuilt/harmony` → libMNN.so（5.6MB, aarch64 ELF）
   - 陷阱：脚本 `MNN_SEP_BUILD=OFF` 时 llm 是 OBJECT 库链入 libMNN.so，但**默认 `make` 不构建 llm 目标**，需先 `make llm` 再重链 libMNN.so（删掉 libMNN.so 强制重链）→ llvm-nm 确认 `MNN::Transformer::Llm::createLLM/forwardVec/reset/stoped` 全部导出
   - 注意：macOS 自带 nm/readelf 不认识 OHOS ELF（显示 0 符号），必须用 SDK 的 `native/llvm/bin/llvm-nm`/`llvm-readelf`
2. 鸿蒙工程骨架建立（复制 drive-health 模板改名）：bundleName=`io.mnnkeep.harmony`，versionName=0.1.0，删除了 ACCESS_DISK_PHY_INFO 权限
3. 首页壳 Index.ets + EntryAbility 已替换（MNN 本地对话 + "AI 生成"显式标识角标位）
4. 命令行构建验证：`node hvigorw.js assembleHap --mode module -p product=default -p buildMode=debug --no-daemon` → BUILD SUCCESSFUL（3s），产出 entry-default-unsigned.hap
5. 构建环境变量（临时生效，未写入 .zshrc）：`DEVECO_SDK_HOME=~/Library/OpenHarmony/Sdk` + PATH 加 DevEco 内置 node/ohpm

**⏳ 待完成（需要华为账号 GUI 操作）**
6. **签名**：本地 OpenHarmony 签名链对 HarmonyOS NEXT 真机**必被拒**（drive-health VERIFY.md 已验证）。必须 DevEco Studio 自动签名：File → Project Structure → Signing Configs → Automatically generate signature（需登录华为开发者账号）
7. **部署**：hdc 侧载到 MateBook14（需设备 USB/无线连接 + 开发者模式）
8. 签名前准备：AGC 创建应用 + 设备 UDID 注册（UDID=`4D4B96028CADF247AE80E474BE94CEDA4AC26D122028E9A2A61822E79E2E1BE1` 已知）

**关键文件**：prebuilt/harmony/libs/{libMNN.so, libc++_shared.so} + include/llm/{llm.hpp, reranker.hpp}（NAPI 桥接头文件就绪）
