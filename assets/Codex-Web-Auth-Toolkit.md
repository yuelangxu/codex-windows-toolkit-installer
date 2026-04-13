# Codex Web-Auth Toolkit

This guide explains the authenticated browser tooling that the Codex Windows Toolkit deploys into PowerShell.

## What gets installed

- `codex.web-auth-tools.ps1` in the PowerShell profile root
- `codex_auth_web.py` in the PowerShell `Scripts` folder
- ChatGPT automation commands such as `auth-chatgpt-list`, `auth-chatgpt-open`, and `auth-chatgpt-ask`
- Browser extension automation commands such as `auth-extension-install`, `auth-extension-open`, and `auth-extension-click`

## Managed state roots

The toolkit keeps its managed browser automation state under the PowerShell toolkit root:

- ChatGPT browser state: `Toolkit\\state\\chatgpt-browser`
- Browser extension state: `Toolkit\\state\\browser-extensions`
- Browser session registry: `Toolkit\\state\\browser-sessions`

This keeps the tooling close to PowerShell instead of depending on the Desktop or a hand-prepared browser profile.

## Key ChatGPT commands

- `auth-chatgpt-browser`
- `auth-chatgpt-list -Limit 20`
- `auth-chatgpt-open -NewChat`
- `auth-chatgpt-ask -NewChat -DestinationDir C:\\Exports "Summarize this file."`
- `auth-chatgpt-save -DestinationDir C:\\Exports -TitleContains "Atomic Physics"`
- `auth-chatgpt-delete -TitleContains "Atomic Physics" -Force`

Notes:

- Prompt text can be passed as a positional argument, from the pipeline, from `-PromptPath`, or from `-PromptBase64`.
- Long or multi-line prompts are automatically moved through a UTF-8 temp file.
- `TimeoutSeconds` acts as a stall timeout while waiting for the answer.

## Key browser extension commands

- `auth-extension-install -SourceUrl https://example.com/my-extension.zip -Name MyExtension`
- `auth-extension-install -PackagePath C:\\Downloads\\my-extension.crx -Name MyExtension`
- `auth-extension-install -DirectoryPath C:\\Dev\\MyExtension -Name MyExtension`
- `auth-extension-list -Browser edge -IncludeRuntime`
- `auth-extension-open -Name MyExtension -Surface popup`
- `auth-extension-click -Name MyExtension -Surface popup -Selector "#sign-in"`
- `auth-extension-remove -Name MyExtension`

Notes:

- Enabled extensions are loaded together into the managed automation browser session.
- Runtime matching falls back to browser profile state when `edge://extensions` does not expose enough metadata.
- Extension pages can be opened by popup, options page, explicit page path, or direct URL.

## Starter project

The installer also deploys a starter browser extension project under:

- `Toolkit\\examples\\browser-extension-starter`

You can load it directly with:

```powershell
auth-extension-install -DirectoryPath "$HOME\\Documents\\PowerShell\\Toolkit\\examples\\browser-extension-starter" -Name BrowserExtensionStarter
auth-extension-open -Name BrowserExtensionStarter -Surface popup
```

## Recommended workflow

1. Open a fresh PowerShell window after installation.
2. Run `toolkit-inventory` to confirm the web-auth commands are available.
3. Run `auth-help` to see the latest command examples.
4. Install one extension into the managed state root and test it with `auth-extension-open`.
5. Use `auth-chatgpt-browser` once to sign in to the managed ChatGPT automation profile if needed.
