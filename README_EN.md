# Drive & Battery Health Viewer (HarmonyOS)

> A lightweight HarmonyOS port of [drive-battery-health-viewer](https://github.com/xincheng1237/drive-battery-health-viewer).
> The original supports Windows (Go) and macOS (SwiftUI); this version targets **HarmonyOS PC / 2in1** (ArkTS + ArkUI).

## Features

| Module | Content | Data source (public HarmonyOS API) |
|---|---|---|
| 🔋 Battery | SOC %, health state, temperature, voltage, current, technology, charging state | `batteryInfo` (BasicServicesKit, no permission) |
| 💾 Storage | Total / free / used ratio of built-in storage | `storageStatistics` (CoreFileKit, API 15+) |
| 🖥️ Device | Model, hardware model, OS version, SDK API, disk serial | `deviceInfo`; serial requires `ohos.permission.ACCESS_DISK_PHY_INFO` |
| 📜 History | Auto snapshot every 5 min (SOC/health/temp/capacity), max 200 entries | `preferences` |
| 📤 Report export | Plain-text health report saved via picker | `DocumentViewPicker` (no storage permission needed) |

- Battery live data refreshes every 10 s on the main page.

## Project layout

```
AppScope/                App-level config (bundleName, icon)
entry/src/main/ets/
  entryability/          EntryAbility (PC window sizing)
  model/HealthData.ets   Data models
  service/DeviceScanner.ets   Hardware scanner (battery/storage/device)
  pages/Index.ets        Main page (3 cards)
  pages/HistoryPage.ets  History page
entry/src/main/module.json5   Module config + permission declaration
build/signing/           Signing materials & scripts
dist/                    Signed HAP
```

## Build

Requires DevEco Studio 6.1.0+ (bundled SDK API 23 / HarmonyOS 6.1.0), Node.js, ohpm.

```bash
# HarmonyOS projects locate the SDK via DEVECO_SDK_HOME (local.properties is ignored)
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk/default
export PATH=$PATH:/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin

cd <project>
ohpm install
node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
# Output: entry/build/default/outputs/default/entry-default-unsigned.hap
```

> The SDK root must contain `<sdkRoot>/<path>/sdk-pkg.json` where `<path>` equals
> `data.path` in that file (e.g. `HarmonyOS-6.1.0/`), with `openharmony/` and `hms/`
> component directories present.

## Signing & deployment

Local debug signing (OpenHarmony toolchain; **OpenHarmony devices/emulators only** —
HarmonyOS NEXT devices need DevEco Studio auto-signing, see below):

```bash
cd build/signing
L=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib
J="java -jar $L/hap-sign-tool.jar"

$J sign-profile -keyAlias "openharmony application profile debug" -signAlg SHA256withECDSA \
  -mode localSign -profileCertFile $L/OpenHarmonyProfileDebug.pem \
  -inFile profile-final.json -keystoreFile $L/OpenHarmony.p12 \
  -outFile p7b-final.p7b -keyPwd 123456 -keystorePwd 123456

# appCertFile must be a certificate CHAIN (leaf + CA)
$J sign-app -mode localSign -keyAlias "openharmony application release" -signAlg SHA256withECDSA \
  -appCertFile app-vanilla-chain.pem -profileFile p7b-final.p7b \
  -inFile <unsigned.hap> -keystoreFile $L/OpenHarmony.p12 \
  -outFile signed.hap -keyPwd 123456 -keystorePwd 123456 \
  -compatibleVersion 15 -signCode 0
```

Deploy: `hdc install signed.hap` (or `hdc install -r signed.hap` to overwrite).

**HarmonyOS NEXT devices (e.g. MateBook)**: local OpenHarmony signatures are rejected.
Use DevEco Studio: File → Project Structure → Signing Configs → check
"Automatically generate signature" (requires a Huawei developer account).

## Permissions

- `ohos.permission.ACCESS_DISK_PHY_INFO` (API 15+): reads the disk serial number.
  Restricted permission (system_basic); APL must be declared `system_basic` (done in
  profile). **Commercial release requires a Huawei-signed profile via AppGallery review**;
  the local self-signed profile works for debugging only.
- Without the permission the app runs normally; the serial shows "unauthorized".

## Limitations vs. desktop original

| Capability | Desktop (Win/macOS) | HarmonyOS |
|---|---|---|
| Battery health | Exact % (design/full capacity) | **Level** only (GOOD/OVERHEAT/...), no % or cycle count |
| Disk S.M.A.R.T. | Temp/power-on hours/read-write/health | **No API**; capacity + serial only |
| History/export/i18n | Full | History + report export (Chinese UI) |

HarmonyOS does not expose S.M.A.R.T. or deep battery APIs — a platform limitation.

## License

GPL v3.0 (same as the original project).
