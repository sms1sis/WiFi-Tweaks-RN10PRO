# Wi-Fi Tweaks for Redmi Note 10 Pro

This Magisk module replaces the default `WCNSS_qcom_cfg.ini` with a tuned configuration for improved Wi-Fi performance on the Redmi Note 10 Pro.

It boosts signal strength, enables wider channel bonding, and unlocks antenna diversity for a faster and more reliable connection. The module also includes a web UI to explain the applied tweaks.

> ⚠️ This module is designed specifically for the **Redmi Note 10 Pro**. It may work on other devices with similar Qualcomm Wi-Fi chipsets, but compatibility is not guaranteed.

---

## 🔧 The Tweaks

This module applies the following changes to your Wi-Fi configuration:

*   **2x2 MIMO Antenna Configuration:** Allows the firmware to use both antennas for sending and receiving data, potentially doubling your Wi-Fi speed.
*   **Increased Transmit Power:** Boosts the Wi-Fi signal strength for better range and stability, at the cost of slightly higher battery consumption.
*   **40MHz Channel Bonding (2.4GHz & 5GHz):** Enables the use of wider channels on both Wi-Fi bands for significantly higher throughput.
*   **WPA3 Security:** Enables the latest Wi-Fi security protocol for a more secure connection.

---

## 🖥️ Web UI

This module includes a web-based UI that clearly explains the changes it makes. You can access it by opening the `index.html` file located in the module's `webroot` directory.

The Web UI provides a breakdown of each tweak, showing the "before" and "after" values from the configuration file.

---

## 📂 Module Structure

```
WiFi-Tweaks-RN10PRO/
├── module.prop
├── system/
│   └── vendor/
│       └── etc/
│           └── wifi/
│               └── WCNSS_qcom_cfg.ini  # The modified config file
└── webroot/
    └── index.html                  # The Web UI file
```