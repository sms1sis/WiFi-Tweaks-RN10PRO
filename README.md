# 📶 Wi-Fi INI High-Performance Overlay (Redmi Note 10 Pro)

This is a **KSU Next overlayfs module** that replaces the default `WCNSS_qcom_cfg.ini` with a **tuned configuration (`mine.ini`)** for maximum Wi-Fi performance on the **Redmi Note 10 Pro**.

It boosts signal strength, enables wider channel bonding, and unlocks antenna diversity — all while exposing a clean WebUI that shows exactly what changed and why.

> ⚠️ This module is designed specifically for the **Redmi Note 10 Pro** (Snapdragon 732G). It may work on other Snapdragon-powered devices with similar Wi-Fi chipsets, but compatibility is not guaranteed.

---

## 🔧 What It Does

- **Overlays** `/vendor/etc/wifi/WCNSS_qcom_cfg.ini` with a custom config
- **Boosts transmit power** for stronger signal at long range
- **Enables 40 MHz bonding** on 2.4 GHz for higher throughput
- **Lets firmware auto-select antenna chains** for better diversity (2x2 MIMO)
- **Activates beamforming and MU-MIMO** features
- **Provides a WebUI** with a color-coded diff and explanations

---

## 🖥️ WebUI Preview

The module includes a WebUI with:

- ✅ A **“Show diff”** button to view changes from the default config  
- 🎨 A **color-coded diff viewer** (GitHub-style)  
- 📘 Inline explanations for each tweak

---

## 📂 Module Structure

```text
wifi-ini-highperf/
├─ module.prop
├─ post-fs-data.sh
├─ service.sh
├─ overlay/
│  └─ vendor/etc/wifi/WCNSS_qcom_cfg.ini  # Modified config
├─ webroot/
│  ├─ index.html                          # WebUI page
│  └─ diff.txt                            # Static diff + explanations
