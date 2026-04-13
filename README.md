# Codex Windows Toolkit Installer

This bundle recreates the PowerShell/Codex toolchain from the source machine and now installs a richer day-to-day PowerShell experience by default.

By default, it installs under `Documents\PowerShell\Toolkit`, wires a shared PowerShell profile, deploys wrapper scripts, installs OCR support, and upgrades the shell with command hints, prompt polish, and a broader CLI toolbelt.
It detects the actual Windows Documents folder dynamically, so setups using `OneDrive\Documents` and plain local `Documents` both work.

## What it installs

- Core CLI tools with `winget`: `pwsh`, `git`, `gh`, `rg`, `wget`, `node`, `npm`, `qpdf`, `fd`, `fzf`, `jq`, `yq`, `uv`, `pnpm`, `bat`, `delta`
- Extra shell-friendly tools: `eza`, `zoxide`, `starship`, `lazygit`, `just`, `hyperfine`, `7z`, `sd`
- Document/OCR tools: `tesseract`, `capture2text`, `ImageMagick`, `Poppler`, `mutool`, `PowerToys`, `Ollama`
- PowerShell modules: `Terminal-Icons`, `PSFzf`, `posh-git`
- Predictive shell hints: `CompletionPredictor`
- Shared PowerShell profile integration:
  - enabled by default
  - `codehint` / `Show-CodexShellHints`
  - `toolkit-inventory`
  - PSReadLine prediction + list view
  - `zoxide`, `eza`, `lazygit`, `just`, `hyperfine` friendly aliases
  - Starship prompt config stored inside the toolkit root
- Recommended optional CLI extras via the wizard: `xh`, `mise`, `dust`, `procs`
- OCR Python environment in an isolated Python 3.11 virtual environment
- Current helper profiles from the source machine:
  - `codex.document-tools.ps1`
  - `codex.ocr-translate-tools.ps1`
  - `codex.web-auth-tools.ps1`

## Why this boosts Codex productivity

This toolkit is designed to reduce the friction between "Codex can suggest it" and "Windows can actually execute it".

- It gives Codex a predictable PowerShell environment with stable command names, wrappers, and helper aliases.
- It adds fast search, file, JSON/YAML, archive, benchmarking, and HTTP tools that Codex can call immediately instead of re-deriving ad hoc workarounds.
- It installs shell quality-of-life improvements such as hints, inventory, better completion, richer listings, and prompt context so inspection and iteration are faster.
- It hardens the OCR/document stack, which is where Windows setups often lose the most time to version mismatches and missing DLL paths.
- It includes an inventory script and guided wizard so a fresh Windows machine can be brought closer to a "known-good Codex workstation" with one `Y` confirmation.

In practice, that means less environment drift, fewer broken helper commands, less setup repetition, and more time spent on actual coding, automation, scraping, document processing, and debugging.

## Design goals

- Work on fresh Windows machines with different usernames and different `Documents` locations
- Support both `OneDrive\Documents` and plain local `Documents`
- Prefer repairable, source-visible PowerShell scripts over opaque setup steps
- Detect health issues early instead of only checking whether files exist
- Keep the setup simple enough that a single wizard run can install or repair most of the stack

## Why the installer uses Python 3.11

The OCR stack on Windows is much more reliable with an isolated Python 3.11 environment. This avoids the version conflicts that happened during the original manual setup.

## Fast start

Audit only:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Audit-CodexWindowsToolkit.ps1 -IncludeProfileIntegration
```

Interactive install:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1
```

Guided wizard with inventory + one-key install:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Invoke-CodexToolkitWizard.ps1
```

The wizard shows current callable tools, audits compatibility, and lets you press `Y` to install/repair the toolkit plus recommended extras.

Show the current callable PowerShell tool inventory:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Show-CodexToolkitInventory.ps1
```

Install to a custom root instead of the default `Documents\PowerShell\Toolkit`:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1 -ToolkitRoot D:\PortablePowerShellTools
```

Install without wiring the shared PowerShell profile:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1 -DisableProfileIntegration
```

Unattended install with llava pull:

```powershell
powershell -NoLogo -ExecutionPolicy Bypass -File .\Install-CodexWindowsToolkit.ps1 -AutoApprove -IncludeLlavaModel
```

One-click launchers:

- `Start-Audit-CodexWindowsToolkit.cmd`
- `Start-Install-CodexWindowsToolkit.cmd`
- `Start-CodexToolkitWizard.cmd`

## Important notes

- `Ghostscript` still requires an interactive installer on Windows. The toolkit can download and launch the official installer for you, but that step is not fully silent.
- The `llava` model download is large. By default, unattended mode skips it unless `-IncludeLlavaModel` is supplied.
- After install, open a new `PowerShell` or `pwsh` window so PATH, prompt, and prediction features load cleanly.
