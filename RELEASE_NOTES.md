# Release Notes

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
