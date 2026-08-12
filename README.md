# 硬盘与电池健康查看器（鸿蒙版）

> 基于 [drive-battery-health-viewer](https://github.com/xincheng1237/drive-battery-health-viewer) 的鸿蒙轻量版移植。
> 原版支持 Windows（Go）与 macOS（SwiftUI），本版本面向 **HarmonyOS PC / 2in1**（ArkTS + ArkUI）。

## 功能

| 模块 | 内容 | 数据来源（鸿蒙公开 API） |
|---|---|---|
| 🔋 电池 | 电量 %、健康状态、温度、电压、电流、电池技术、充电状态 | `batteryInfo`（BasicServicesKit，普通应用可用） |
| 💾 存储 | 内置存储总容量 / 可用空间 / 已用占比 | `storageStatistics`（CoreFileKit，API 15+） |
| 🖥️ 设备 | 型号、硬件型号、系统版本、SDK API、硬盘序列号 | `deviceInfo`，序列号需 `ohos.permission.ACCESS_DISK_PHY_INFO` |
| 📜 历史记录 | 每 5 分钟自动快照（电量/健康/温度/容量），最多 200 条 | `preferences` 持久化 |
| 📤 报告导出 | 生成纯文本健康报告，保存到用户选择位置 | `DocumentViewPicker`（无需存储权限） |

- 主界面每 10 秒自动刷新电池实时数据
- 磁盘序列号显示遵循原版隐私理念（鸿蒙版默认仅展示，报告导出含序列号）

## 项目结构

```
AppScope/                应用级配置（bundleName、图标）
entry/src/main/ets/
  entryability/          EntryAbility（含 PC 窗口尺寸适配）
  model/HealthData.ets   数据模型
  service/DeviceScanner.ets  硬件信息采集（battery/storage/device）
  pages/Index.ets        主界面（电池/存储/设备三卡片）
  pages/HistoryPage.ets  历史记录页
entry/src/main/module.json5   模块配置 + 权限声明
build/signing/           签名材料与脚本
dist/                    签名产物（.hap）
```

## 构建

环境：DevEco Studio 6.1.0+（内置 SDK API 23/HarmonyOS 6.1.0）、Node.js、ohpm。

```bash
# 关键：HarmonyOS 工程通过 DEVECO_SDK_HOME 定位 SDK（不读 local.properties）
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default
export PATH=$PATH:/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin

cd <工程目录>
ohpm install
node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
# 产物：entry/build/default/outputs/default/entry-default-unsigned.hap
```

> 若 `DEVECO_SDK_HOME` 指向标准 SDK 目录（如 `~/Library/OpenHarmony/Sdk`），
> 要求目录下存在 `<sdkRoot>/<path>/sdk-pkg.json`（`path` 取 sdk-pkg.json 中 `data.path`，
> 如 `HarmonyOS-6.1.0/`），且 `openharmony/`、`hms/` 组件齐全。

## 签名与部署

本地调试签名（OpenHarmony 工具链，**仅 OpenHarmony 设备/模拟器可用**；
HarmonyOS NEXT 真机需 DevEco Studio 自动签名，见下）：

```bash
cd build/signing
L=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib
J="java -jar $L/hap-sign-tool.jar"

# 1. 生成 profile（已含 bundle/apl/设备 UDID 配置：profile-final.json）
# 2. 签名 profile
$J sign-profile -keyAlias "openharmony application profile debug" -signAlg SHA256withECDSA \
  -mode localSign -profileCertFile $L/OpenHarmonyProfileDebug.pem \
  -inFile profile-final.json -keystoreFile $L/OpenHarmony.p12 \
  -outFile p7b-final.p7b -keyPwd 123456 -keystorePwd 123456
# 3. 签名 HAP（appCertFile 必须为证书链：叶子+CA）
$J sign-app -mode localSign -keyAlias "openharmony application release" -signAlg SHA256withECDSA \
  -appCertFile app-vanilla-chain.pem -profileFile p7b-final.p7b \
  -inFile <unsigned.hap> -keystoreFile $L/OpenHarmony.p12 \
  -outFile signed.hap -keyPwd 123456 -keystorePwd 123456 \
  -compatibleVersion 15 -signCode 0
```

部署：

```bash
hdc install signed.hap        # 或 hdc install -r signed.hap（覆盖安装）
```

**HarmonyOS NEXT 真机（如 MateBook）**：本地 OpenHarmony 签名会被拒，请用 DevEco Studio：
File → Project Structure → Signing Configs → 勾选 Automatically generate signature
（需登录华为开发者账号，生成华为签发的 profile 与证书）。

## 权限说明

- `ohos.permission.ACCESS_DISK_PHY_INFO`（API 15+）：读取硬盘序列号，属**受限权限**（system_basic）。
  普通应用需将 APL 声明为 `system_basic`（本工程 profile 已配置），
  **商用上架须在华为应用市场申请发布证书与 Profile 并通过审核**；调试阶段本地自签 profile 即可。
- 未获权限时应用正常运行，序列号显示"未授权"，不影响其他功能。

## 与桌面原版的能力差异（重要）

| 能力 | 桌面原版（Win/macOS） | 鸿蒙版 |
|---|---|---|
| 电池健康度 | 精确百分比（设计/满充容量） | 健康**等级**（正常/过热/过压/低温/僵死），无百分比/循环次数 |
| 硬盘 S.M.A.R.T. | 温度/通电时间/读写量/健康状态 | **无 API**，仅容量 + 序列号 |
| 历史/导出/多语言 | 全 | 历史 + 报告导出（中文界面） |

鸿蒙不开放 S.M.A.R.T. 与电池深度数据 API，属平台限制，非实现问题。

## 已知限制

- 磁盘序列号仅 PC/2in1 设备返回（`diskSN` 文档约定）
- 无真机回归验证清单见 `docs/VERIFY.md`（待补：真机功能核对）

## 许可证

GPL v3.0（与原项目一致），保留原版权声明。
