# Android APK Tools

This folder is the managed home for locally staged Android helper APKs.

The public repository only carries metadata and usage notes. Actual APK binaries can be copied in later with:

```powershell
phone-apk-import -IncludeCommonLocalCandidates
```

Typical tools to stage here:

- Shizuku
- App Manager
- Hail
- ShizuWall
- Termux

After importing, use:

```powershell
phone-apk-list
phone-apk-install -Name Shizuku -Reinstall
```
