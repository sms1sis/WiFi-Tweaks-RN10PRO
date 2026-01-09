# WiFi Config Switcher Changelog

## v4.0.0
- **Major Refactor:** Complete rewrite for KernelSU-Next V3 compliance.
- **Architecture:** Streamlined to a single `action.sh` script, removing complex/redundant legacy files (`post-fs-data`, `common/`).
- **WebUI 2.0:** Brand new modern interface with syntax-highlighted editor, line numbers, and "Toast" notifications.
- **Feature (Soft Reset):** Added safe `unbind`/`bind` logic to reload Wi-Fi drivers without rebooting.
- **Feature (KPatch):** Added support for detecting and injecting `.kpm` kernel patches directly from the WebUI.
- **Safety:** Implemented Base64-encoded configuration transfer to prevent shell injection and corruption.
- **Discovery:** Improved dynamic path finding for both drivers and configuration files.

## v3.7.0
- **KernelSU-Next V3 Ready:** Updated WebUI and internal scripts for full compatibility with the latest KernelSU-Next V3 API (bridge isolation bypass).
- **New Feature (KPatch Integration):** Added a new "Advanced Actions" panel to the WebUI.
    - **Status Check:** Automatically detects if the running kernel supports Live Patching and if a `.kpm` module is present.
    - **Injection:** Provides a button to inject the kernel patch directly from the WebUI.
- **New Feature (Soft Driver Reset):** Implemented a "Safe Soft-Reset" mechanism.
    - Performs a controlled Unbind -> Bind cycle on the Wi-Fi driver to reload configurations without a full reboot.
    - Auto-detects driver paths for `wlan`, `qca_cld3`, `icnss`, and PCI-based drivers.
- **Improved (WebUI):**
    - "Load System Default" now scans multiple standard paths (`/vendor`, `/system`, `/data`) to locate the WCNSS configuration file, fixing issues on non-standard ROMs.
    - Added user fallback prompt to manually specify the config path if auto-detection fails.
- **Refactor:** Created `common/action.sh` to centralize high-privilege operations (file reading, patching, driver control).

## v3.6.2
- **Fix (WebUI):** Resolved "Unknown Mode" issue on the Dashboard by correcting the configuration file path lookup. The script now correctly prioritizes the persistent module directory even when running from the temporary WebUI location.

## v3.6.1
- **Fix (WebUI):** Resolved "Could not load existing settings due to isolation" error by implementing a robust Base64-based file reading fallback.
- **Fix (Compatibility):** Replaced non-portable `grep` and `sed` regex usage with POSIX-compliant character classes for broader Android support (Toybox/Busybox).
- **Fix (Core):** Corrected `svc` command path resolution to ensure reliable service restarts.

## v3.6.0
- **Architectural Shift:** Fully transitioned to a **Hybrid Mount** strategy as the primary method, merging Magisk and KernelSU logic into a single robust implementation.
- **Cleanup:** Removed legacy `magisk` and `dev` branches to focus on a unified `main` codebase.
- **Documentation:** Updated `README.md` to reflect the hybrid approach and its benefits for both Magisk and KernelSU users.
- **Refactor:** Simplified internal logic to prioritize dynamic patching and `nsenter`-based live switching.
