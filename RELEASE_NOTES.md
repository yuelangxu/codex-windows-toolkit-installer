# Release Notes

## v1.4.1

Installer reliability fixes from a real repair run.

### Highlights

- Fixed the OCR installer strict-mode failure when a pip step does not define `IndexUrl`
- Added retrying, explicit PyPI-based pip installs for web-auth and OCR dependency setup
- Changed Ollama model detection to read local manifests instead of running `ollama list`, so audits and profile initialization do not wake Ollama
- Made the installer default to demand-start Ollama by moving any Windows Startup shortcut into the toolkit backups folder
- Ignored local installer logs so repair transcripts are not accidentally committed

### Why this release matters

The guided wizard now carries the fixes that were needed during an actual partial-install recovery. A rerun should repair the machine directly instead of requiring manual `playwright` installs, OCR script edits, or Ollama startup cleanup.

## v1.4.0

VPS buying guidance and bootstrap bundle generation.

### Highlights

- Added `vps-provider-show` to surface official VPS pricing and buy pages for common starter providers
- Added `vps-plan-suggest` so the toolkit can recommend practical CPU, RAM, and disk sizing for proxy, browser, or mixed workloads
- Added `vps-bundle-new` to generate Ubuntu cloud-init plus bootstrap scripts for the VPS you buy next
- Updated the network docs, README, inventory, and shell hints so VPS lifecycle tasks sit next to SSH and Shadowsocks commands

### Why this release matters

The toolkit now covers the step before server deployment too. Instead of only managing a machine after it exists, it can help choose a sane VPS starting point and generate the files you will want immediately after checkout.

## v1.3.0

Official Shadowsocks Windows client handoff from PowerShell.

### Highlights

- Added `ss-client-info` to show the official `shadowsocks-windows` executable, current `gui-config.json` summary, and this computer's local network facts
- Added `ss-client-sync` so PowerShell can write discovered private Shadowsocks config plus local client settings directly into the official Windows client's `gui-config.json`
- Expanded the profile hints, inventory, and Shadowsocks guide to document the new official-client handoff workflow

### Why this release matters

The toolkit now does more than download the official client. It can bridge local private machine state into the official Shadowsocks GUI config, which removes a lot of manual clicking while still keeping secrets on the local machine only.

## v1.2.0

Installer refresh for the network toolkit and secret-safe Shadowsocks bootstrap flow.

### Highlights

- Added `codex.network-tools.ps1` to the installed helper profiles so SSH, proxy, and Shadowsocks commands are deployed with the main toolkit
- Added local-only Shadowsocks secret discovery/import commands: `ss-secret-discover`, `ss-secret-import`, and `ss-secret-clear`
- Added automatic private Shadowsocks bootstrap during install: the installer now looks for local env vars, private files, or existing client configs and imports them into local toolkit state without writing secrets into the repo
- Added network and Shadowsocks guides to the installed docs set and expanded inventory/audit coverage for the new commands and local state
- Added official Windows Shadowsocks client prefetch during private import so machines with a local private config can become usable faster

### Why this release matters

The toolkit can now carry a public installer while still becoming genuinely useful on a private machine. Real connection details stay local, but Codex still gets a predictable set of network commands and can bootstrap an actual usable client configuration automatically when the machine already has private state available.

## v1.1.0

Installer refresh for the newer authenticated browser automation stack.

### Highlights

- Updated the installer and wizard so the ChatGPT automation commands are treated as first-class installed capabilities instead of post-install drift
- Added browser-extension automation support to the installed toolkit, including install, list, enable, disable, open, click, and remove flows
- Added proactive installation of the Python packages required by `codex_auth_web.py`
- Added a toolkit web-auth guide that documents the managed ChatGPT and browser-extension workflow
- Added a starter browser-extension project under the toolkit examples directory so fresh machines have a ready local automation target
- Expanded the installer audit so it now checks the web-auth guide, starter project, and Python-side web-auth dependencies

### Why this release matters

The toolkit no longer stops at shell helpers and OCR. It now bootstraps a much more complete authenticated browser automation environment, which makes Codex more effective on Windows for ChatGPT-driven workflows and browser-extension-assisted tasks.

## v1.0.0

Initial public release of the Codex Windows Toolkit Installer.

### Highlights

- Added a guided installer wizard with inventory, audit, confirmation flow, and repair support
- Expanded the default CLI toolkit with Windows-friendly tools for search, navigation, formatting, benchmarking, and HTTP work
- Enabled shared PowerShell profile integration by default
- Added `codehint`, inventory helpers, prompt improvements, and shell quality-of-life modules
- Improved support for both `OneDrive\Documents` and local `Documents` layouts
- Hardened the OCR and document-processing environment around a Python 3.11 virtual environment
- Added wrapper scripts to smooth over Windows-specific dependency and PATH issues
- Split installation into clearer components for packages, profiles, wrappers, OCR, and auditing

### Why this release matters

This release turns the setup from a one-off machine transplant into a reusable Windows bootstrapper for Codex-heavy workflows. It is designed to make fresh machines productive faster and to reduce the environment mismatch problems that slow down shell-driven work.

### Included workflow improvements

- Faster first-run shell ergonomics
- Better command discoverability
- More reliable OCR setup on Windows
- Cleaner recovery path when a machine is only partially configured
- A more source-visible and maintainable installer structure

### Known limitations

- `Ghostscript` still requires an interactive step on Windows
- `llava` model download is intentionally optional because of size and time cost
- Some Python-backed OCR capabilities remain sensitive to upstream package changes over time, although this installer now pins and validates the critical pieces much more carefully
