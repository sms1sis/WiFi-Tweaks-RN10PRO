# GEMINI Project Context: Wi-Fi Config Switcher (KernelSU Module)

## Project Overview

This project is a KernelSU module named "WiFi Config Switcher" (`wifi_tweaks`). Its primary purpose is to allow a user to dynamically switch the device's Wi-Fi driver configuration between a high-performance mode and a battery-saving mode without requiring a reboot.

The module achieves this by using a shell script to manipulate a symbolic link (`WCNSS_qcom_cfg.ini`) in the `/vendor/etc/wifi/` directory, pointing it to either a `perf.ini` or a `battery.ini` file.

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

    # To get the current status
    /data/adb/modules/wifi_tweaks/common/switch_mode.sh status
    ```

## Key Files

*   `module.prop`: Defines the metadata for the KernelSU module (ID: `wifi_tweaks`, author: `sms1sis`, name, version, etc.).
*   `common/switch_mode.sh`: The core shell script that handles the logic of switching the symlink and restarting Wi-Fi services. It now includes a `status` command and uses `svc wifi disable/enable` for a more robust Wi-Fi restart.
*   `webroot/index.html`: A modern, single-page web interface that provides buttons to execute the `switch_mode.sh` script via `ksu.exec`. It actively displays the current mode on load and provides robust visual feedback and error handling during operations, correctly handling the synchronous return of `ksu.exec` (which provides `errno` and `stdout`).
*   `system/vendor/etc/wifi/perf.ini`: The Wi-Fi configuration file optimized for performance.
*   `system/vendor/etc/wifi/battery.ini`: The Wi-Fi configuration file optimized for battery saving.
*   `system/vendor/etc/wifi/WCNSS_qcom_cfg.ini`: A symbolic link that points to either `perf.ini` or `battery.ini`. This is the file the Android system reads.

## Development Conventions

The project follows the standard directory structure for a KernelSU module:

*   `common/`: Contains helper scripts that can be executed by the module.
*   `system/`: A directory whose contents are overlaid onto the device's `/system` partition. The path within this directory mirrors the system path (e.g., `system/vendor/etc/wifi/`).
*   `webroot/`: Contains the files for the module's WebUI.
*   `module.prop`: Must be in the root directory.