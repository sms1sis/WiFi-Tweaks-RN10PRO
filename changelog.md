# WiFi Config Switcher Changelog

## v4.1.0
- **UX Improvement:** Renamed backend script to `backend.sh`, preventing the KernelSU Manager from displaying a non-functional "Action" button.
- **Cleanup:** Final removal of legacy code and optimizations for the v4 release.

## v4.0.0
- **Major Refactor:** Complete rewrite for KernelSU-Next V3 compliance.
- **Architecture:** Streamlined to a single `backend.sh` script (renamed from `action.sh`), removing complex/redundant legacy files (`post-fs-data`, `common/`).
- **Streamlined Dashboard:** simplified WebUI focused purely on performance profiles and status monitoring.
- **Systemless & Self-Healing:** Automatically detects system configuration (`/vendor`, `/system`, etc.) and creates a safe overlay.
- **Smart Driver Management:** Auto-detects modular vs. monolithic drivers, preventing unsafe reset attempts.
- **Backup & Restore:** "Stock" mode now reliably restores the original imported configuration.
- **Removed:** Legacy KPatch and Editor features to maximize stability and simplicity.
- **Safety:** Implemented Base64-encoded configuration transfer to prevent shell injection.

## v3.7.0
- **KernelSU-Next V3 Ready:** Updated WebUI and internal scripts for full compatibility with the latest KernelSU-Next V3 API.
- **New Feature (Soft Driver Reset):** Implemented a "Safe Soft-Reset" mechanism (Unbind -> Bind).
- **Improved (WebUI):** "Load System Default" now scans multiple standard paths to fix issues on non-standard ROMs.
- **Refactor:** Centralized high-privilege operations into a single script.

## v3.6.2
- **Fix (WebUI):** Resolved "Unknown Mode" issue on the Dashboard.

## v3.6.1
- **Fix (WebUI):** Resolved "Could not load existing settings due to isolation" error.
- **Fix (Compatibility):** POSIX-compliant regex usage for broader Android support.

## v3.6.0
- **Architectural Shift:** Fully transitioned to a **Hybrid Mount** strategy (Magisk/KernelSU).
- **Cleanup:** Removed legacy `magisk` and `dev` branches.