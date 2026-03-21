# WiFi Config Switcher — Changelog

## v5.0.0
> Generic Qualcomm Edition — patch-based architecture

- **Architecture:** Replaced all hardcoded performance/balanced parameters with a `patches/` directory system. Each device or SoC gets its own `perf.patch` and `balanced.patch` text files. Adding a new device no longer requires editing any shell script.
- **Patch Resolution:** Install-time auto-detection walks a priority chain — `patches/devices/<codename>/` → `patches/soc/<platform>/` → `patches/generic_qcom/` — and picks the most specific match. Resolved path is written to `patch_dir.txt` for zero-overhead runtime lookups.
- **Device Alias Map:** Common hardware variants that share a patch (e.g. `sunny` → `mojito`, `sweet_k` → `sweet`) are resolved automatically.
- **Included Profiles:** Ships with patches for `sweet` (Redmi Note 10 Pro), `mojito`/`sunny` (Redmi Note 10), and SoC-level patches for `sm7150`, `sm6150`, `sm8150`, `sm8250`, plus a safe `generic_qcom` fallback.
- **New backend action:** `get_patch_info` — returns active patch source, device codename, SoC platform, and param counts for the Performance and Balanced profiles.
- **WebUI — Patch Info Card:** New card in the UI shows the active patch profile (device / SoC / generic), device identity, and how many params each mode will apply. Mode buttons now display param counts inline.
- **WebUI — Generic fallback warning:** If running on the `generic_qcom` fallback a log warning is shown encouraging a device-specific patch contribution.
- **`customize.sh`:** Expanded config search to cover `/odm/vendor/`, `/product/vendor/`, and `/data/vendor/wifi/` in addition to previous paths. Added deep `find` fallback across `/vendor` and `/system`. Config relative path recorded in `config_rel_path.txt` for robust runtime resolution.
- **`patches/README.md`:** Full contributor guide — patch format, resolution order, step-by-step instructions for adding a new device, existing profile table.

## v4.2.0
> Robustness and driver detection improvements

- **Fix:** Driver detection now uses six layered checks instead of one. Previous single symlink check (`/module`) incorrectly classified many modular drivers (e.g. `qca_cld3_wlan` on sm7150 devices) as built-in.
  - Added: `/sys/module/<driver_name>` lookup
  - Added: `/proc/modules` scan for resolved driver name
  - Added: `/proc/modules` scan for common Qualcomm/Broadcom/Intel Wi-Fi module names
  - Added: driver path `built-in`/`platform` string heuristic
  - Added: subsystem bus type heuristic (`platform`/`soc` → built-in; `pci`/`usb`/`sdio`/`mmc` → modular)
- **New backend action:** `get_driver_type` — called on WebUI init so driver type is known before any profile is applied.
- **Fix:** `apply_mode` now returns `driver_type` and `driver_name` in its JSON response, removing a redundant second round-trip from the frontend.
- **Fix:** `soft_reset` returns distinct `status: "builtin"` (was generic `"warning"`) so the frontend can show the reboot banner precisely.
- **Fix:** Shell argument escaping in `KsuBridge.runAction()` was a no-op (`"` → `"`). Replaced with correct POSIX single-quote wrapping with `'\''` escaping.
- **Fix:** `customize.sh` now mirrors the config at its actual device path rather than always targeting `/system/vendor/etc/wifi/`, fixing overlay mounting on devices that store the config under `/vendor/` or `/data/vendor/`.
- **WebUI — Driver pill:** Badge next to the mode indicator shows detected driver type and name with colour coding (green = modular, amber = built-in).
- **WebUI — Reboot banner:** Dismissible banner with a "Reboot Now" button shown automatically after a config change on built-in-driver devices.
- **WebUI — Log colours:** Log lines now have timestamped, colour-coded types — info (blue), success (green), warning (amber), error (red), builtin (purple), system (grey).
- **WebUI — SSID stat:** Added a 4th stats card showing the connected network name alongside RSSI, speed, and frequency.
- **WebUI — Log clear:** Added a "Clear" button to the log header.
- **WebUI — XSS fix:** Log messages are HTML-escaped before DOM insertion.
- **Performance modes:** Added `gEnableRoamDelayStats`, `gRoamScanOffloadEnabled`, and `gRoamRescanRssiDiff` to both profiles on supported devices.

## v4.1.2
- **Fix:** Corrected WebUI configuration for KernelSU (removed incorrect `web` property in `module.prop`) to fix connection issues.

## v4.1.1
- **Fix:** Improved stats engine to use `iw` as primary source for RSSI, speed, and frequency, with `/proc/net/wireless` fallback for RSSI.
- **Fix:** Improved `soft_reset` logic to correctly detect monolithic drivers and prompt for reboot.
- **Refactor:** Simplified `customize.sh` for improved reliability on supported devices.

## v4.1.0
- **UX:** Renamed backend script to `backend.sh`, preventing KernelSU Manager from displaying a non-functional "Action" button.
- **Cleanup:** Final removal of legacy code and optimisations for the v4 release.

## v4.0.0
- **Major Refactor:** Complete rewrite for KernelSU-Next V3 compliance.
- **Architecture:** Streamlined to a single `backend.sh` script (renamed from `action.sh`), removing complex/redundant legacy files (`post-fs-data`, `common/`).
- **Streamlined Dashboard:** Simplified WebUI focused purely on performance profiles and status monitoring.
- **Systemless & Self-Healing:** Automatically detects system configuration (`/vendor`, `/system`, etc.) and creates a safe overlay.
- **Smart Driver Management:** Auto-detects modular vs. monolithic drivers, preventing unsafe reset attempts.
- **Backup & Restore:** "Stock" mode now reliably restores the original imported configuration.
- **Removed:** Legacy KPatch and Editor features to maximise stability and simplicity.
- **Safety:** Implemented Base64-encoded configuration transfer to prevent shell injection.

## v3.7.0
- **KernelSU-Next V3 Ready:** Updated WebUI and internal scripts for full compatibility with the latest KernelSU-Next V3 API.
- **New Feature (Soft Driver Reset):** Implemented a "Safe Soft-Reset" mechanism (Unbind → Bind).
- **Improved (WebUI):** "Load System Default" now scans multiple standard paths to fix issues on non-standard ROMs.
- **Refactor:** Centralised high-privilege operations into a single script.

## v3.6.2
- **Fix (WebUI):** Resolved "Unknown Mode" issue on the Dashboard.

## v3.6.1
- **Fix (WebUI):** Resolved "Could not load existing settings due to isolation" error.
- **Fix (Compatibility):** POSIX-compliant regex usage for broader Android support.

## v3.6.0
- **Architectural Shift:** Fully transitioned to a Hybrid Mount strategy (Magisk/KernelSU).
- **Cleanup:** Removed legacy `magisk` and `dev` branches.
