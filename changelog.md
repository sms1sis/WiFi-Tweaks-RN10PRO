# WiFi Config Switcher Changelog

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