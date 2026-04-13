# Release Notes

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
