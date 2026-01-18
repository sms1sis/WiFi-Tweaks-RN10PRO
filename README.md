# WiFi Config Switcher V4

A next-generation Wi-Fi tuner module for Android, fully optimized for **KernelSU-Next V3**. It allows you to dynamically switch Wi-Fi driver configurations to boost performance or save battery, performing safe driver resets without rebooting (on supported devices).

## ✨ New in V4 (KernelSU-Next)

*   **V3 Architecture:** Built explicitly for the modern KernelSU-Next ecosystem with a streamlined, single-script architecture.
*   **Simplified Dashboard:** A clean, responsive WebUI focused purely on performance monitoring and profile switching.
*   **Systemless & Self-Healing:** Automatically detects your device's active Wi-Fi configuration (`/vendor`, `/system`, etc.) and creates a systemless overlay. No permanent changes are made to your system partitions.
*   **Backup & Restore:** The "Stock" mode now intelligently restores a backup of your original config, ensuring a safe return to factory defaults.
*   **Smart Driver Management:** Automatically detects if your Wi-Fi driver is modular (allowing instant soft resets) or monolithic (requiring a reboot), guiding you accordingly.

## 🚀 Features

*   **Three Modes:**
    *   **Performance:** Unlocks full power. Disables power saving (`gEnableBmps=0`), maximizes TX power (17dBm), and forces 40MHz bandwidth.
    *   **Balanced:** The sweet spot. Enables 40MHz BW & boosted power (14dBm) while keeping standard power saving features active. **(Default)**
    *   **Stock:** Restores your device's exact original configuration from backup.
*   **Safe Operations:** All operations use sanitized inputs and secure Base64 data transfer.
*   **Universal Compatibility:** Dynamically discovers driver paths (`/sys/bus/platform` or `/sys/bus/pci`) and configuration files across all standard Android partitions.

## ⚙️ Technical Breakdown

| Feature | Flag | Stock | Balanced | Performance | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Power Save** | `gEnableBmps` | `1` (On) | `1` (On) | `0` (Off) | Disabling reduces latency at cost of battery. |
| **TX Power** | `TxPower2g/5g` | Backup / `12` | `14` | `17` | Signal transmit power in dBm. |
| **Bandwidth** | `gChannelBondingMode24GHz` | Backup / `0` | `1` (40MHz) | `1` (40MHz) | Wider channel for 2.4GHz. |

---

## 🛠️ Usage

### 1. WebUI (Recommended)

1.  Open **KernelSU Next**.
2.  Navigate to the **WiFi Config Switcher** module.
3.  Tap **Open WebUI**.
4.  View real-time stats and tap a profile button to apply it instantly.

### 2. Command Line (Advanced)

The module uses a single `action.sh` script for operations.

```bash
# Enter module directory
cd /data/adb/modules/wifi_config_switcher

# Soft Reset Driver (Manually trigger driver reload)
sh action.sh soft_reset
```

---

## 📦 Packaging

To create a flashable zip:

```bash
zip -r WiFi-Config-Switcher.zip . -x ".git*" "README.md" "changelog.md" "update.json"
```
