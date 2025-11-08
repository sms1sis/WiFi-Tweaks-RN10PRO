# GEMINI Project Context: Wi-Fi Config Switcher (KernelSU Module)

## Project Overview

This project is a KernelSU module named "WiFi Config Switcher" (`wifi_tweaks`). Its primary purpose is to allow a user to dynamically switch the device's Wi-Fi driver configuration between a high-performance mode, a battery-saving mode, and a default mode without requiring a reboot.

The module works by leveraging KernelSU's overlay filesystem. It contains a `WCNSS_qcom_cfg.ini` file that is presented to the system. A shell script, `switch_mode.sh`, modifies this file by copying the contents of either `perf.ini`, `battery.ini`, or `default.ini` to it, and then restarts the Wi-Fi services to apply the changes. This allows for a rebootless switch of the Wi-Fi configuration.

A user-friendly web interface (WebUI), accessible through the KernelSU app, provides buttons to trigger the switch. The module also includes the necessary configuration files and scripts to function as a standalone KernelSU module.

**Main Technologies:** Shell Scripting, HTML, CSS, JavaScript.

## Building and Running

### Building (Packaging) the Module

This is a "build-less" project. To package the module for installation, you need to create a zip archive of the project's contents.

**Command to package the module:**
```bash
zip -r wifi_tweaks.zip . -x ".git/*" "GEMINI.md"
```
This will create `wifi_tweaks.zip`, which can be flashed in the KernelSU app.

### Running and Using the Module

Once the module is installed and the device is rebooted, you can switch modes using one of two methods:

**1. WebUI (Recommended):**
*   Open the KernelSU app.
*   Navigate to the "Modules" tab.
*   Select "WiFi Config Switcher".
*   Open the WebUI and use the "Performance" or "Battery" buttons. The WebUI actively checks and displays the current Wi-Fi mode on load, provides clear feedback, and features robust error handling.

**2. Command Line (Advanced):**
*   Open a root shell (`su`).
*   Execute the script directly:
    ```bash
    # For Performance Mode
    /data/adb/modules/wifi_tweaks/common/switch_mode.sh perf

    # For Battery Mode
    /data/adb/modules/wifi_tweaks/common/switch_mode.sh battery

    # For Default Mode
    /data/adb/modules/wifi_tweaks/common/switch_mode.sh default

    # To get the current status
    /data/adb/modules/wifi_tweaks/common/switch_mode.sh status
    ```

## Key Files

*   `module.prop`: Defines the metadata for the KernelSU module (ID: `wifi_tweaks`, author: `sms1sis`, name, version, etc.).
*   `common/switch_mode.sh`: The core shell script that handles the logic of switching the Wi-Fi configuration by copying the appropriate `.ini` file and restarting Wi-Fi services.
*   `common/post-fs-data.sh`: A boot script that ensures the initial Wi-Fi configuration is applied correctly when the device starts.
*   `webroot/index.html`: A modern, single-page web interface that provides buttons to execute the `switch_mode.sh` script.
*   `system/vendor/etc/wifi/perf.ini`: The Wi-Fi configuration file optimized for performance.
*   `system/vendor/etc/wifi/battery.ini`: The Wi-Fi configuration file optimized for battery saving.
*   `system/vendor/etc/wifi/default.ini`: The default Wi-Fi configuration file.
*   `system/vendor/etc/wifi/WCNSS_qcom_cfg.ini`: A regular file that is a copy of either `perf.ini` or `battery.ini`. This is the file the Android system reads via the KernelSU overlay.

## Development Conventions

The project follows the standard directory structure for a KernelSU module:

*   `common/`: Contains helper scripts that can be executed by the module.
*   `system/`: A directory whose contents are overlaid onto the device's `/system` partition. The path within this directory mirrors the system path (e.g., `system/vendor/etc/wifi/`).
*   `webroot/`: Contains the files for the module's WebUI.
*   `module.prop`: Must be in the root directory.