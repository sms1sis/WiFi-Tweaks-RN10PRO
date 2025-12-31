# WiFi Config Switcher (KernelSU Module)

A KernelSU module to easily switch your device's Wi-Fi driver configuration between a high-performance, balanced, or default mode.

**Note:** A reboot is required for the selected mode to take effect if wifi driver is monolithic/built-in!

## ✨ Features

*   **Easy Mode Selection:** Choose your preferred Wi-Fi mode (Performance, Balanced, or Stock) via a simple WebUI or command-line interface.
*   **Three Modes:**
    *   **Performance:** Unleashes full power. Disables power saving for lowest latency, enables MIMO & 40MHz BW, and maximizes TX power.
    *   **Balanced:** A balanced sweet spot. Retains power saving for battery life but enables MIMO & 40MHz BW for better connectivity than stock. **(Default Mode)**
    *   **Stock:** Restores the exact configuration your device had before installing the module (Dynamic Backup).
*   **Real-Time Diagnostics:** WebUI displays live RSSI, Link Speed, and Frequency.
*   **Dynamic Patching:** Compatible with more devices by patching the system's original config instead of overwriting it with a static file.
*   **User-Friendly WebUI:** A modern, responsive web interface within the KernelSU app.

## ⚙️ Technical Breakdown

For those interested in the specific `.ini` flags changed:

| Feature | Flag | Default | Balanced | Performance | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Power Save** | `gEnableBmps` | `1` (On) | `1` (On) | `0` (Off) | Disabling reduces latency but drains battery. |
| **MIMO** | `gSetTxChainmask1x1` | `1` (SISO) | `0` (MIMO) | `0` (MIMO) | Uses multiple antennas for speed/stability. |
| **TX Power** | `TxPower2g/5g` | `10` | `12` | `15` | Signal transmit power in dBm. |
| **Green AP** | `gEnableGreenAp` | `1` (On) | `1` (On) | `0` (Off) | Power saving for hotspot mode. |
| **Bandwidth** | `gChannelBondingMode24GHz` | `0` (20MHz) | `1` (40MHz) | `1` (40MHz) | Wider channel for 2.4GHz band. |
| **ARP Priority** | `arp_ac_category` | `0` | `3` | `3` | Prioritizes ARP packets for responsiveness. |

---

## 🚀 Usage

Once the module is installed and the device is rebooted, you can switch modes using one of two methods:

### 1. WebUI (Recommended)

1.  Open the **KernelSU** app.
2.  Navigate to the **Modules** tab.
3.  Select **WiFi Config Switcher**.
4.  Open the **WebUI** and use the "Performance", "Balanced", or "Stock" buttons. The interface will display a status message indicating the current operation and result.

**Note:** The WebUI does not display the full execution log. To view the detailed log for debugging, use the command line below.

### 2. Command Line (Advanced)

Open a root shell (`su`) and execute the script directly:

```bash
# For Performance Mode
/data/adb/modules/wifi_tweaks/common/switch_mode.sh perf

# For Balanced Mode
/data/adb/modules/wifi_tweaks/common/switch_mode.sh balanced

# For Stock Mode
/data/adb/modules/wifi_tweaks/common/switch_mode.sh stock
```

### Real-Time Stats

```bash
/data/adb/modules/wifi_tweaks/common/switch_mode.sh stats
```

### Viewing Logs

To see the detailed execution log (useful for troubleshooting), run:
```bash
su -c cat /data/local/tmp/wifi_tweaks.log
```

---

## 📦 Building (Packaging) the Module

This is a "build-less" project. To package the module for installation, you need to create a zip archive of the project's contents.

From the root of the project directory, run the following command:

```bash
zip -r WiFi-Config-Switcher.zip . -x ".git*" "GEMINI.md" ".gitignore" "README.md" "update.json" "changelog.md" "WiFi-Config-Switcher.zip"
```

This will create `wifi_tweaks.zip`, which can be flashed in the KernelSU app.

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
