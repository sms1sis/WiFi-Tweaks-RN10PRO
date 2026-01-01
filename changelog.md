# WiFi Config Switcher Changelog

## v3.6.1
- **Fix (WebUI):** Resolved "Could not load existing settings due to isolation" error by implementing a robust Base64-based file reading fallback.
- **Fix (Compatibility):** Replaced non-portable `grep` and `sed` regex usage with POSIX-compliant character classes for broader Android support (Toybox/Busybox).
- **Fix (Core):** Corrected `svc` command path resolution to ensure reliable service restarts.

## v3.6.0
- **Architectural Shift:** Fully transitioned to a **Hybrid Mount** strategy as the primary method, merging Magisk and KernelSU logic into a single robust implementation.
- **Cleanup:** Removed legacy `magisk` and `dev` branches to focus on a unified `main` codebase.
- **Documentation:** Updated `README.md` to reflect the hybrid approach and its benefits for both Magisk and KernelSU users.
- **Refactor:** Simplified internal logic to prioritize dynamic patching and `nsenter`-based live switching.

## v3.5.0
- **Feature:** Added full support for `meta-hybrid_mount` for KernelSU.
- **Refactor:** Unified script logic to handle Hybrid, OverlayFS, and Magic Mount architectures automatically.
- **Improvement:** Enhanced namespace-aware mounting logic using `nsenter` to verify target mount states before applying live switches.
- **Path Independence:** Further improved path discovery to handle non-standard module locations used by hybrid mounting systems.

## v3.4.4
- **Refactor (OverlayFS):** Major architectural update to support `meta-overlayfs` and KernelSU standard overlay structures.
- **Path Independence:** Scripts now dynamically determine the module directory at runtime (`readlink -f "$0"`), ensuring compatibility with custom mount points and meta-modules.
- **Static Boot Mode:** Optimized `post-fs-data.sh` to update the physical module file, allowing the system's OverlayFS to handle the mount naturally.
- **SUSFS Awareness:** Added detection and safe handling for SUSFS environments.
- **Improved Mount Logic:** Implemented robust unmounting and re-mounting sequences to prevent "mount loops" during live switching.

## v3.4.3
# warning ⚠️ 
- **NotFixed:**New custom configuration (Could not load existing settings due to isolation) This is not fixed yet. Don't expect soon!
- **WebUI:** Improved resilience by re-checking the fallback file immediately after executing the backend script.
- **Boot:** Optimized `post-fs-data.sh` execution order to ensure the fallback file is correctly created on first boot/install.

## v3.4.2
- **Fix (SUSFS/KSU):** Added robust fallback mechanism for devices with strict mount namespace isolation (SUSFS). The module now exposes the stock configuration to a world-readable temporary location at boot, allowing the WebUI to function even when the module directory is hidden.
- **WebUI:** Added a diagnostic startup check to detect if the module files are inaccessible and display a helpful error message instead of failing silently.
- **WebUI:** Editor now automatically attempts to load the fallback stock configuration if the primary path is inaccessible.

## v3.4.1
- **Fix:** Resolved "Waiting for KernelSU API..." WebUI stall by removing strict filesystem API checks.
- **Improvement:** Implemented robust file system fallback mechanisms using shell commands for broader compatibility.

## v3.4.0
- **Refactor:** Standardized configuration handling to `webroot/config.ini` for KernelSU Next compatibility.
- **Fix:** WebUI now robustly waits for KernelSU API injection, preventing race conditions.
- **Fix:** "Load Stock" now persists changes to disk immediately.
- **Fix:** Updated boot scripts (`post-fs-data.sh`) and installer (`customize.sh`) to use the new config path.

## v3.3.3
- **Fix:** Implemented automated runtime creation of `common/config.ini` during installation (`customize.sh`) and boot (`post-fs-data.sh`).
- **Fix:** Resolved persistent "Could not load configuration" error in WebUI when the runtime config file was missing.
- **Documentation:** Added "Magisk / KernelSU Module Runtime Files" section to `GEMINI.md` to document runtime file generation.
- **Maintenance:** Added `.gitignore` to prevent tracking of runtime configuration files.

## v3.3.2
- **WebUI:** Centered the Dashboard for better vertical alignment.
- **WebUI:** Text Editor improvements:
    - Increased editor width for better readability on larger screens.
    - Implemented dynamic line number width.
    - Enhanced visual styling (shadows, better spacing).
- **Fix:** Resolved "Could not load configuration" error in the Editor by implementing a robust stock config fallback.
- **Config:** "Balanced" is now the default mode if no configuration is set.

## v3.3.1
- **WebUI:** Centered dashboard layout for improved aesthetics.
- **WebUI:** Enhanced log display and status reporting logic with better error handling.
- **Fix:** Corrected repository URLs for update checks.

## v3.3.0
- **WebUI Overhaul:** Introduced a completely new, modern interface with a "Single Page Application" design.
- **Advanced Editor:** Added a dedicated "Micro-style" configuration editor with line numbering, cursor position tracking, and syntax-friendly font.
- **Navigation:** Implemented a persistent bottom navigation bar for seamless switching between Dashboard and Editor.
- **Theming:** Updated to a "Tokyo Night" inspired dark theme for better aesthetics and readability.

## v3.2.0
- **New Feature:** Added "Custom" mode support.
- **WebUI:** Added a built-in INI Configuration Editor. You can now modify the stock config and save it as a custom profile directly from the WebUI.
- **Security:** Implemented safe configuration saving using Base64 encoding to prevent data corruption.

## v3.1.1
- **Cleanup:** Removed redundant "Default" mode. "Stock" mode is now the primary method for reverting to original settings.
- **WebUI:** Updated interface to remove the "Default" button.

## v3.1.0
- **New Feature:** "True Stock" Backup. Automatically backs up your original system config on first run.
- **New Feature:** "Stock" Mode. Restore your original system config anytime via WebUI/CLI.
- **New Feature:** Real-Time Diagnostics. WebUI now shows Signal Strength (RSSI), Link Speed, and Frequency.
- **Major Refactor:** Dynamic Patching. Removed static `.ini` files. The module now patches your specific device's config file dynamically, improving compatibility with different ROMs and devices.

## v3.0.4
- **Refactor:** Renamed "Battery" profile (`battery.ini`) to "Balanced" (`balanced.ini`) to better reflect its nature (MIMO/40MHz enabled).
- **WebUI:** Updated interface to show "Balanced" instead of "Battery".
- **Script:** Updated logic to handle the new "balanced" mode.

## v3.0.3
- **WebUI:** Fixed "Reboot Required" message logic by introducing `driver-type.conf`.
- **Script:** Added reliable driver type detection (Modular vs Built-in) that persists to `driver-type.conf`.
- **WebUI:** Now explicitly warns about reboot requirement if the driver is detected as Built-in.

## v3.0.2
- **WebUI:** Adjusted button layout (same length, Default in middle).
- **WebUI:** Simplified completion message and added log display.
- **Script:** Removed redundant reboot warnings from logs.

## v3.0.1
- **Feature:** Changed default mode to 'Battery'.
- **WebUI:** Reordered buttons to place 'Default' in the middle.
- **WebUI:** Added detailed status message indicating if a reboot is required based on driver type (Built-in vs Modular).
- **Script:** Improved driver reload detection logic.

## v3.0.0
- **Version Reset:** Synchronized versioning scheme to v3.0.0 and versionCode 30 for both local and remote updates.
- **Maintenance:** Retains all improvements from previous 5.x.x releases (minimal WebUI, optimized scripts).
- **WebUI Simplification:** Removed the "View Last Log" feature and real-time log streaming from the WebUI.
- **Documentation:** Added instructions to the README for manually viewing detailed logs via the command line.
