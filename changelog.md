# WiFi Config Switcher Changelog

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