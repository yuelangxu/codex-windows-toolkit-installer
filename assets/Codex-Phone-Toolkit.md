# Codex Phone Toolkit

The phone toolkit turns a Windows PowerShell session into a more reusable Android debugging workstation.

It is designed for ADB-first workflows:

- inspect connected phones quickly
- capture repeatable diagnostics bundles
- audit noisy background apps
- summarize phone storage before cleanup
- capture UI screenshots plus hierarchy XML
- safely pull or archive phone files
- start Shizuku over ADB
- mirror the phone with `scrcpy`
- manage locally staged helper APKs such as Shizuku, Hail, App Manager, ShizuWall, or Termux

## Core commands

- `phone-status`
- `phone-diag`
- `phone-noise-audit`
- `phone-storage-scan`
- `phone-ui-dump`
- `phone-pull`
- `phone-archive`
- `phone-mirror`
- `phone-shizuku-start`
- `phone-apk-list`
- `phone-apk-import`
- `phone-apk-install`
- `phone-help`

## Examples

```powershell
phone-status
phone-diag -Samples 2
phone-ui-dump -OutputDir C:\Exports\phone-ui
phone-storage-scan
phone-pull -PhonePath /sdcard/Download
phone-archive -PhonePath /sdcard/DCIM/Camera/VID_20260426_123456.mp4
phone-noise-audit -Packages com.tencent.mm,com.zhihu.android
phone-mirror -StayAwake
phone-shizuku-start
phone-apk-import -IncludeCommonLocalCandidates
phone-apk-install -Name Shizuku -Reinstall
```

## Where state is stored

- Diagnostics: `Toolkit\state\phone-debug\diagnostics`
- UI dumps: `Toolkit\state\phone-debug\captures`
- Audits: `Toolkit\state\phone-debug\audits`
- Storage scans: `Toolkit\state\phone-debug\storage-scans`
- File pulls / archives: `Toolkit\state\phone-debug\pulls`
- APK helper examples: `Toolkit\examples\android-apk-tools`
- Termux bootstrap example: `Toolkit\examples\termux-bootstrap`

## Design notes

- The defaults are intentionally safe. Commands that delete phone files are opt-in through `phone-archive`.
- APK binaries are not bundled in the public repository. Instead, the toolkit can import local APKs into toolkit state with `phone-apk-import`.
- The installer now treats Android platform-tools as a first-class dependency, so `adb` can be installed and audited the same way as the rest of the toolkit.
