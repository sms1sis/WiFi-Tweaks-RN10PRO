# WiFi Config Switcher (KernelSU Module)

A KernelSU module to easily switch your device's Wi-Fi driver configuration between a high-performance, balanced, or default mode.

**Note:** A reboot is required for the selected mode to take effect if wifi driver is monolithic/built-in!

## 📦 Building (Packaging) the Module

This is a "build-less" project. To package the module for installation, you need to create a zip archive of the project's contents.

From the root of the project directory, run the following command:

```bash
zip -r WiFi-Switcher-MagicMount.zip . -x ".git*" ".github*" "GEMINI.md" ".gitignore" "README.md" "update.json" "changelog.md"
```

This will create `WiFi-Switcher-MagicMount.zip`, which can be flashed in the KernelSU/Magisk app.

---

## 📂 Key Files

*   `module.prop`: Defines the metadata for the KernelSU module (ID, name, version, etc.).
*   `common/switch_mode.sh`: The core shell script that handles dynamic patching, backups, and driver reloading.
*   `webroot/index.html`: The modern, single-page web interface for the module.
*   `common/original_stock.ini`: The backup of your device's original Wi-Fi configuration (created on first run).

---

## Safety Note

The script uses `svc wifi disable` and `svc wifi enable` to restart the Wi-Fi service, which is the standard and safe Android method for this operation. 

---
