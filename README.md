# Codex Windows Toolkit Installer

![Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-0f6cbd)
![PowerShell](https://img.shields.io/badge/shell-PowerShell%207%2B-5391fe)
![Status](https://img.shields.io/badge/status-ready%20for%20fresh%20machines-2ea043)

Recreate a high-leverage Windows PowerShell environment for Codex in one guided install.

This project turns a fresh Windows machine into a practical Codex workstation with:

- a reproducible PowerShell toolkit root
- shared profile wiring and shell hints
- fast CLI tools for search, files, JSON, YAML, archives, benchmarking, and HTTP work
- wrapper commands that smooth over Windows path and dependency issues
- a hardened OCR and document-processing stack
- an interactive wizard that can inventory, audit, install, and repair the environment

The goal is simple: reduce the gap between "Codex suggested a command" and "this Windows machine can actually run it."

## Why this exists

Codex is far more effective when the shell is predictable.

On many Windows setups, the bottleneck is not the model. It is environment drift:

- different usernames
- different `Documents` locations
- OneDrive vs local profile paths
- missing CLI tools
- broken OCR dependencies
- helper commands that work on one machine and fail on another

This installer packages those rough edges into a source-visible, repairable PowerShell workflow.

## What you get

### Core shell and developer tooling

- `pwsh`
- `git`, `gh`
- `rg`, `fd`, `fzf`
- `jq`, `yq`
- `uv`, `pnpm`
- `bat`, `delta`
- `eza`, `zoxide`
- `lazygit`, `just`, `hyperfine`
- `7z`, `sd`
- optional extras through the wizard: `xh`, `mise`, `dust`, `procs`

### PowerShell experience upgrades

- shared PowerShell profile integration enabled by default
- `codehint` and shell guidance helpers
- `toolkit-inventory` for callable command discovery
- PSReadLine prediction and list-style suggestions
- improved aliases for navigation and shell workflow
- `Terminal-Icons`, `PSFzf`, `posh-git`, `CompletionPredictor`
- `starship` prompt configuration deployed into the toolkit

### Document and OCR workflow

- `tesseract`
- `capture2text`
- `ImageMagick`
- `Poppler`
- `mutool`
- `PowerToys`
- `Ollama`
- isolated Python 3.11 OCR environment
- helper commands such as `ocr-smart`, `pdf-smart`, `easyocr-read`, `paddleocr-read`, and `donut-ocr`

### Source-carried helper scripts

- `codex.document-tools.ps1`
- `codex.ocr-translate-tools.ps1`
- `codex.web-auth-tools.ps1`

### ChatGPT automation helpers

- `auth-chatgpt-list`
- `auth-chatgpt-open`
- `auth-chatgpt-save`
- `auth-chatgpt-ask`
- `auth-chatgpt-dump`
- `auth-chatgpt-delete`

These commands extend the `authweb` family with authenticated ChatGPT browser automation, export, save, prompt, and delete workflows.
They now auto-bootstrap a ChatGPT-ready browser session in one command, and their managed browser state lives under the PowerShell toolkit root instead of the Desktop.

## Why this improves Codex productivity

This toolkit raises the floor and the ceiling for Codex on Windows.

- It gives Codex a stable set of command names and wrappers, so suggested commands are more likely to work immediately.
- It front-loads practical tooling for inspection, refactoring, automation, scraping, document handling, and debugging.
- It adds authenticated ChatGPT automation commands to the same PowerShell toolbelt, so browser-driven save, dump, ask, and cleanup workflows live beside the rest of the auth tooling.
- It improves shell feedback with inventory, prediction, aliases, and prompt context, which shortens the loop between idea and execution.
- It avoids common Windows failure modes around OCR, Python package compatibility, DLL paths, and profile location mismatches.
- It makes machine setup repeatable, so rebuilding a usable environment no longer depends on memory or handwritten notes.

In short: less setup debt, fewer broken commands, more useful Codex time.

## Design principles

- Work on fresh Windows machines with different usernames
- Support both `OneDrive\Documents` and local `Documents`
- Prefer readable PowerShell scripts over opaque installers
- Detect health problems instead of only checking whether files exist
- Keep the happy path fast, especially when the OCR stack is already healthy
- Make repair as easy as first-time setup

## Quick start

### Guided wizard

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Invoke-CodexToolkitWizard.ps1
```

The wizard:

- detects the active Windows documents root
- shows callable tool inventory
- audits the current machine
- asks for a single confirmation
- installs or repairs the toolkit and recommended extras

### Standard install

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1
```

### Audit only

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Audit-CodexWindowsToolkit.ps1 -IncludeProfileIntegration
```

### Inventory only

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Show-CodexToolkitInventory.ps1
```

## Useful install variants

Install to a custom toolkit root:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1 -ToolkitRoot D:\PortablePowerShellTools
```

Install without profile integration:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1 -DisableProfileIntegration
```

Unattended install with `llava` model pull:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1 -AutoApprove -IncludeLlavaModel
```

Launch from one-click wrappers:

- `Start-Audit-CodexWindowsToolkit.cmd`
- `Start-Install-CodexWindowsToolkit.cmd`
- `Start-CodexToolkitWizard.cmd`

## Repository layout

- `Invoke-CodexToolkitWizard.ps1`: guided setup and repair entry point
- `Install-CodexWindowsToolkit.ps1`: main installer
- `Audit-CodexWindowsToolkit.ps1`: compatibility and health checks
- `Show-CodexToolkitInventory.ps1`: callable command inventory
- `Install-CodexOcrEnvironment.ps1`: isolated OCR stack setup
- `Install-CodexProfilesAndWrappers.ps1`: profile deployment and wrapper installation
- `toolkit.manifest.psd1`: package and tool manifest
- `assets/`: shared profiles, wrappers, Python helpers, OCR helpers, and prompt assets

## Notes

- The installer detects the real Windows documents directory dynamically.
- The OCR environment uses Python 3.11 because it is substantially more reliable on Windows for this stack.
- `Ghostscript` still requires an interactive installer on Windows.
- Pulling the `llava` model can be large and slow, so it is not forced by default.
- Open a fresh `PowerShell` or `pwsh` window after installation so PATH and prompt changes load cleanly.

## Who this is for

This repository is especially useful if you want:

- a repeatable Codex-ready Windows shell
- better PowerShell ergonomics without hand-tuning every machine
- a practical document and OCR workflow on Windows
- a setup you can inspect, modify, and carry forward as source code
