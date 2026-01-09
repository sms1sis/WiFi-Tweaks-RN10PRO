# WiFi Config Switcher V4

A next-generation Wi-Fi tuner module for Android, fully optimized for **KernelSU-Next V3**. It allows you to dynamically switch Wi-Fi driver configurations, patch kernel functions, and perform safe driver resets without rebooting.

## ✨ New in V4 (KernelSU-Next)

*   **V3 Architecture:** Built explicitly for the modern KernelSU-Next ecosystem with a streamlined, single-script architecture.
*   **WebUI 2.0:** A completely rewritten, responsive WebUI featuring a live syntax-highlighted editor.
*   **Soft Driver Reset:** Safely reloads the Wi-Fi driver (unbind/bind) to apply configurations immediately without a full system reboot.
*   **Kernel Patching (KPatch):** Detects and injects `.kpm` kernel patches for advanced functionality (requires kernel support).
*   **Universal Compatibility:** Dynamically discovers driver paths (`/sys/bus/platform` or `/sys/bus/pci`) and configuration files (`/vendor`, `/system`, `/data`).

## 🚀 Features

*   **Four Modes:**
    *   **Performance:** Unlocks full power. Disables power saving (`gEnableBmps=0`), maximizes TX power, and forces 40MHz bandwidth.
    *   **Balanced:** The sweet spot. Enables MIMO & 40MHz BW while keeping standard power saving features. **(Default)**
    *   **Stock:** Restores your device's exact original configuration.
    *   **Custom:** Edit `WCNSS_qcom_cfg.ini` directly via the built-in WebUI editor.
*   **Safe Operations:** All operations use sanitized inputs and secure Base64 data transfer.
*   **Live Diagnostics:** Check KPatch support and driver status directly from the Dashboard.

## ⚙️ Technical Breakdown

| Feature | Flag | Stock | Balanced | Performance | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Power Save** | `gEnableBmps` | `1` (On) | `1` (On) | `0` (Off) | Disabling reduces latency. |
| **MIMO** | `gSetTxChainmask1x1` | `1` (SISO) | `0` (MIMO) | `0` (MIMO) | Uses multiple antennas for stability. |
| **TX Power** | `TxPower2g/5g` | `10` | `12` | `15` | Signal transmit power in dBm. |
| **Bandwidth** | `gChannelBondingMode24GHz` | `0` (20MHz) | `1` (40MHz) | `1` (40MHz) | Wider channel for 2.4GHz. |

---

## 🛠️ Usage

### 1. WebUI (Recommended)

1.  Open **KernelSU Next**.
2.  Navigate to the **WiFi Config Switcher** module.
3.  Tap **Open WebUI**.
4.  Use the **Editor** to modify config or the **Driver Control** panel to reset the driver.

### 2. Command Line (Advanced)

The module now uses a single `action.sh` script for all operations.

```bash
# Enter module directory
cd /data/adb/modules/wifi_config_switcher

# Soft Reset Driver
sh action.sh soft_reset

# Inject Kernel Patch (if available)
sh action.sh inject_patch

# Read Config
sh action.sh read_config
```

---

## 📦 Packaging

To create a flashable zip:

```bash
zip -r WiFi-Config-Switcher.zip . -x ".git*" "README.md" "changelog.md" "update.json"
```