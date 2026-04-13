# Browser Extension Starter

This is a minimal Chromium extension project that ships with the Codex Windows Toolkit Installer.

It is meant to be a safe, local starter project for testing:

- `auth-extension-install`
- `auth-extension-list`
- `auth-extension-open`
- `auth-extension-click`

## Files

- `manifest.json`: Manifest V3 definition
- `popup.html`: popup UI
- `popup.js`: simple interaction logic
- `options.html`: lightweight settings page

## Try it from PowerShell

```powershell
auth-extension-install -DirectoryPath "$HOME\\Documents\\PowerShell\\Toolkit\\examples\\browser-extension-starter" -Name BrowserExtensionStarter
auth-extension-open -Name BrowserExtensionStarter -Surface popup
auth-extension-click -Name BrowserExtensionStarter -Surface popup -Selector "#starter-action"
```

The popup button changes the hash to `#clicked`, which makes it easy to verify that the click command really worked.
