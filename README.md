# WiFi Config Switcher

A versatile Magisk and KernelSU module to easily switch your device's Wi-Fi driver configuration between high-performance, balanced, or stock modes.

## 🚀 Hybrid Mount Strategy

This module employs a **Hybrid Mount** strategy, making it compatible with both Magisk (Magic Mount) and KernelSU (OverlayFS). 

*   **Boot Persistence:** Uses the native module system to overlay configurations during the boot process.
*   **Live Switching:** Utilizes `nsenter` and bind mounts to apply configuration changes instantly without requiring a reboot.

## ✨ Features

*   **Easy Mode Selection:** Choose your preferred Wi-Fi mode via a modern WebUI or command-line interface.
*   **Four Modes:**
    *   **Performance:** Unleashes full power. Disables power saving, enables MIMO & 40MHz BW, and maximizes TX power.
    *   **Balanced:** A balanced sweet spot. Retains power saving but enables MIMO & 40MHz BW. **(Default)**
    *   **Stock:** Restores the exact configuration your device had before installing the module (Dynamic Backup).
    *   **Custom:** Edit your own configuration via the built-in WebUI editor.
*   **Real-Time Diagnostics:** WebUI displays live RSSI, Link Speed, and Frequency.
*   **Dynamic Patching:** Compatible with various devices by patching the system's original config instead of overwriting it with a static file.
*   **User-Friendly WebUI:** A modern, responsive web interface accessible within the Magisk/KernelSU manager.

## ⚙️ Technical Breakdown

| Feature | Flag | Default | Balanced | Performance | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Power Save** | `gEnableBmps` | `1` (On) | `1` (On) | `0` (Off) | Disabling reduces latency. |
| **MIMO** | `gSetTxChainmask1x1` | `1` (SISO) | `0` (MIMO) | `0` (MIMO) | Uses multiple antennas for stability. |
| **TX Power** | `TxPower2g/5g` | `10` | `12` | `15` | Signal transmit power in dBm. |
| **Bandwidth** | `gChannelBondingMode24GHz` | `0` (20MHz) | `1` (40MHz) | `1` (40MHz) | Wider channel for 2.4GHz. |

---

## 🚀 Usage

### 1. WebUI (Recommended)

1.  Open your module manager (Magisk or KernelSU).
2.  Navigate to the **WiFi Config Switcher** module.
3.  Open the **WebUI** to switch modes or use the editor.

### 2. Command Line (Advanced)

```bash
# Switch mode
su -c /data/adb/modules/wifi_tweaks/common/switch_mode.sh [perf|balanced|stock|custom]

# View stats
su -c /data/adb/modules/wifi_tweaks/common/switch_mode.sh stats
```

---

## 📦 Packaging

To create a flashable zip:

```bash
zip -r WiFi-Config-Switcher.zip . -x ".git*" "GEMINI.md" "README.md"
```
