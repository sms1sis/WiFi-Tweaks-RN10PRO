# WiFi Config Switcher (KernelSU Module)

A KernelSU module to easily switch your device's Wi-Fi driver configuration between a high-performance, battery-saving, or default mode.

**Note:** A reboot is required for the selected mode to take effect.

## ✨ Features

*   **Easy Mode Selection:** Choose your preferred Wi-Fi mode (Performance, Battery, or Default) via a simple WebUI or command-line interface.
*   **Three Modes:**
    *   **Performance (`perf.ini`):** Optimized for maximum throughput and low latency.
    *   **Battery (`battery.ini`):** Tuned for reduced power consumption.
    *   **Default (`default.ini`):** The stock configuration for your device.
*   **User-Friendly WebUI:** A modern, responsive web interface within the KernelSU app to switch modes with a single tap. The UI now includes icons for each mode.
*   **Command-Line Interface:** Advanced users can switch modes via a shell script.

---

## 🚀 Usage

Once the module is installed and the device is rebooted, you can switch modes using one of two methods:

### 1. WebUI (Recommended)

1.  Open the **KernelSU** app.
2.  Navigate to the **Modules** tab.
3.  Select **WiFi Config Switcher**.
4.  Open the **WebUI** and use the "Performance", "Battery", or "Default" buttons. The interface will show the script's output and the current active mode.

### 2. Command Line (Advanced)

Open a root shell (`su`) and execute the script directly:

```bash
# For Performance Mode
/data/adb/modules/wifi_tweaks/common/switch_mode.sh perf

# For Battery Mode
/data/adb/modules/wifi_tweaks/common/switch_mode.sh battery

# For Default Mode
/data/adb/modules/wifi_tweaks/common/switch_mode.sh default
```

---

## 📦 Building (Packaging) the Module

This is a "build-less" project. To package the module for installation, you need to create a zip archive of the project's contents.

From the root of the project directory, run the following command:

```bash
zip -r wifi_tweaks.zip . -x ".git/*" "GEMINI.md"
```

This will create `wifi_tweaks.zip`, which can be flashed in the KernelSU app.

---

## 📂 Key Files

*   `module.prop`: Defines the metadata for the KernelSU module (ID, name, version, etc.).
*   `common/switch_mode.sh`: The core shell script that handles the logic of switching the symlink and restarting Wi-Fi services.
*   `webroot/index.html`: The modern, single-page web interface for the module.
*   `system/vendor/etc/wifi/perf.ini`: The Wi-Fi configuration file optimized for performance.
*   `system/vendor/etc/wifi/battery.ini`: The Wi-Fi configuration file optimized for battery saving.
*   `system/vendor/etc/wifi/default.ini`: The default Wi-Fi configuration file.

---

## Safety Note

The script uses `svc wifi disable` and `svc wifi enable` to restart the Wi-Fi service, which is the standard and safe Android method for this operation. The script also verifies that it is running with root privileges before making any changes.

---
**Version:** 5.0.0