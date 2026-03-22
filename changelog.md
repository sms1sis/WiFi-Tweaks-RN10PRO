## v6.0.0 — Two-Page UI, Theme System & Config Editor

This is a major UI release. The WebUI has been restructured into a two-page app with a bottom navigation bar.

### Two-Page Layout with Bottom Navigation
- **Dashboard** — all status, stats, patch profile, profile buttons, utilities, and log
- **Config** — dedicated full-screen WCNSS_qcom_cfg.ini editor
- Bottom navigation bar with icons and labels to switch between pages
- Config page lazy-loads on first visit — no startup overhead
- Nav bar: larger icons (28px), bigger tap targets, dimmed inactive state, cyan active indicator with glow

### Built-in Config Editor
- Live editor for `WCNSS_qcom_cfg.ini` loaded directly from the module overlay
- **Reload** — fetch current config from device into editor
- **Save & Apply** — write edited config back and trigger driver reload (modular) or reboot banner (built-in)
- **Restore** — restore the stock backup taken at install time
- Edge-to-edge layout on the config page for maximum editing space
- Full panel frame visible (all four borders) with the textarea as a deep editing well inside

### Three-Theme System
The theme toggle (top-left of header) cycles through three themes:
- 🎨 **Sci-Fi** — dark navy, cyan/green/amber neon, circuit board background, Orbitron font
- 🌙 **Normal Light** — white/grey surfaces, Google-style palette, rounded cards, Inter font
- 🚀 **Normal Dark** — iOS-style dark grey (`#1c1c1e`), system color palette, rounded cards, Inter font

Theme preference is persisted in `localStorage` and restored on every load.

### Bug Fixes
- **Fix (critical):** Mode status (perf/balanced/stock) was reset to stock after every module flash/update. `mode_status.txt` was stored inside `$MODDIR` which is wiped on each install. Moved to `/data/adb/wcs/mode_status.txt` — a persistent directory outside the module that survives updates.
- **Fix:** Nav bar icon misalignment — SVG elements wrapped with `display: block`, text labels wrapped in `<span>` with `display: block; line-height: 1`, explicit `width`/`height` attributes added to SVG elements.
- **UI:** Increased panel, button, and row padding throughout for better readability and tap targets on small screens.
- **UI:** Config panel border fully visible on all sides with `12px` page padding.

## v5.1.1
- **UI:** Increased vertical padding across all panels, buttons, stat cells, and rows — elements were too short/cramped on device screens.
- **UI:** Reduced top-sided layout feel — increased header, container, and dashboard padding evenly so content is balanced vertically.
- **UI:** Increased gap between all panels and rows for better visual separation.

## v5.1.0
- **UI:** Complete sci-fi visual overhaul — Orbitron + Share Tech Mono fonts, deep navy background, cyan/green/amber accent system, corner-accented panels, animated status dot with glow, circuit board background art embedded as base64 SVG (no external files).
- **UI:** Profile buttons redesigned as compact single-line row (Perf / Balanced / Stock) with param count hints and per-mode color glow on active state.
- **UI:** Module banner image added (`banner.png`, 1280×320) — displayed on the module card in KernelSU/Magisk Manager before opening the WebUI.
- **UI:** Version badge — dynamically reads version from `module.prop` at runtime via new `get_version` backend action and displays it top-right of the header.
- **UI:** Log box is now dynamically sized — starts collapsed, expands naturally as log entries appear, caps at 60vh, scrolls internally beyond cap. Smart auto-scroll: only follows new entries when already near the bottom.
- **UI:** Full-viewport layout — all panels fill the display height correctly across screen sizes.
- **module.prop:** Description shortened to fit the module card cleanly.

## v5.0.7
- **Fix (critical):** Patching still had no effect despite the overlay being correctly mounted. Root cause: KSU bind-mounts the overlay source (`$MODDIR/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini`) directly onto the live path (`/vendor/etc/wifi/WCNSS_qcom_cfg.ini`) as a block device mount (`/dev/block/mmcblk0p87 on /vendor/etc/wifi/WCNSS_qcom_cfg.ini`). `find_wifi_config` was resolving the live path first — which on this mount type points back to the original read-only partition, not the overlay file. `backend.sh` was patching the wrong file. Fixed: `find_wifi_config` now always returns the overlay source at `$MODDIR/system/<rel>` first, skipping the live path entirely. The overlay source is both the file the driver reads (via bind mount) and the correct patch target.

## v5.0.6
- **Fix (critical):** New config keys (e.g. `gChannelBondingMode24GHz`) were appended after the `END` marker in `WCNSS_qcom_cfg.ini`. The Wi-Fi driver ignores everything past `END` — so these params had no effect. `apply_patch` now inserts missing keys **before** the `END` line using `sed` instead of appending to the end of the file.

## v5.0.5
- **Fix:** Stats cards (Signal, Speed, Frequency, SSID) empty on all devices. Root cause: `cmd wifi status` and `dumpsys wifi` both output all data on a **single line** (`WifiInfo: SSID: "x", RSSI: -37, Link speed: 433Mbps, Frequency: 5745MHz, ...`) — the previous multi-line grep/sed parsing extracted nothing. Rewrote parser to correctly extract each field inline using `grep -o` with precise patterns against the single-line WifiInfo format. Verified against real output from Redmi Note 8 (ginkgo).
- **Confirmed working:** `cmd wifi status` (primary) and `dumpsys wifi mWifiInfo` (fallback). `wpa_cli` not available on this device. `/proc/net/wireless` exists but returns all zeros on icnss-based Qualcomm devices.
- **New alias:** `sweetin` → `sweet` (Redmi Note 10 Pro India variant, same hardware as sweet).

## v5.0.4
- **Fix (critical):** Config overlay never mounted — patching had no effect on the live Wi-Fi config. Root cause: `customize.sh` was placing the imported config at `$MODPATH/vendor/etc/wifi/WCNSS_qcom_cfg.ini`. KernelSU (and Magisk) only mount paths under `$MODPATH/system/` over the root filesystem. Files placed outside `system/` are silently ignored and never bind-mounted. Fixed: destination is now always `$MODPATH/system/${REL_PATH}`, which correctly overlays as `/${REL_PATH}` at boot.
- **Fix:** `find_wifi_config` in `backend.sh` updated to look for the overlay source under `$MODDIR/system/<rel>` first, with a legacy fallback for the old incorrect `$MODDIR/<rel>` path for devices upgrading from a previous install.

## v5.0.3
- **Fix (critical):** Further hardened driver detection against false-modular classification on icnss-based kernels where `/proc/modules` is empty and `lsmod` returns only a header.
- **New check: `/proc/config.gz` (kernel config — ground truth).** `CONFIG_WLAN=y` or `CONFIG_ICNSS=y` definitively confirms built-in. `=m` confirms loadable module. This fires before any sysfs heuristic.
- **New check: `/sys/module/<driver>/sections/` directory.** Loadable modules always have a `sections/` subdirectory inside `/sys/module/`. Built-in drivers that appear in `/sys/module/` do not. This cleanly resolves the ambiguity where `icnss` appeared to be modular via `/sys/module/` lookup.
- **Reordered detection chain:** Blocklist → kernel config → sections dir → /module symlink → /proc/modules → subsystem bus → path heuristic.
- **New backend action: `get_driver_info`** — dumps all detection evidence as JSON: driver name, detected type, `kconf_wlan`, `kconf_driver`, `sys_module_sections`, `proc_modules_entry`, `module_symlink`, `subsystem`, `lsmod_empty`. Useful for diagnosing detection on new devices.
- **WebUI:** Added "Driver Info" button in the Utilities card — calls `get_driver_info` and prints all evidence lines to the log box.

## v5.0.2
- **Fix (critical):** Device reboot after applying config on Snapdragon 665 and other icnss-based platforms. Root cause: `icnss` (Qualcomm WCNSS platform glue) appears in `/sys/module/` and was incorrectly classified as a modular Wi-Fi driver, causing `soft_reset` to unbind it from the platform bus — kernel panic, instant reboot. Detection now uses seven layered checks with multiple safety gates:
  1. **Blocklist** — `icnss`, `icnss2`, `cnss`, `cnss2`, `wlan_platform` always return `builtin` immediately, before any other check
  2. **`/module` symlink** — present only on real loadable `.ko` drivers
  3. **`/proc/config.gz`** — definitive kernel config: `CONFIG_X=y` → builtin, `CONFIG_X=m` → modular
  4. **`/sys/module/<n>/sections/`** — kernel only creates this subdir for externally loaded modules; absent for `=y` compiled-in drivers. `/sys/module/<n>` alone is not sufficient (exists for both) — this was the specific check that misfired on `icnss`
  5. **`/proc/modules`** — only lists dynamically loaded modules
  6. **Known module name scan** in `/proc/modules`
  7. **Subsystem bus type** — `platform`/`soc` → builtin, `pci`/`usb`/`sdio`/`mmc` → modular
  8. **`lsmod` empty output** — zero loaded modules means everything is built-in
- **Fix:** Stats cards (Signal, Speed, Frequency, SSID) always showing `--`. `iw` is not available on stock Android. Stats now use four methods in priority order: `wpa_cli status` + `wpa_cli signal_poll` (primary — always present on Android), `/proc/net/wireless` sysfs fallback, `dumpsys wifi` framework fallback, `iw` last (custom ROMs only).

# WiFi Config Switcher — Changelog

## v5.0.1
- **New patch: `devices/ginkgo/`** — Redmi Note 8 (Snapdragon 665 / sm6125 / WCN3980).
  Device-specific patch derived from analysing the stock `WCNSS_qcom_cfg.ini`.
  Both files (`/vendor/etc/wifi/` and `/vendor/firmware/wlan/qca_cld/`) confirmed identical.
- **New patch: `soc/sm6125/`** — SoC-level patch covering all Snapdragon 665 devices
  (Redmi Note 8T, Samsung Galaxy A21s, Motorola One Fusion, and others).
- **Important: WCN3980 chipset differences** — `TxPower2g`, `TxPower5g`, and
  `gChannelBondingMode24GHz` are **not valid params** on WCN3980. These keys are
  absent from the stock config and must not be added. Patches for this chipset use
  `gEnableModulatedDTIM`, `gOptimizedPowerManagement`, `gEnableMemDeepSleep`,
  `gRoamBmissFirstBcnt/FinalBcnt`, and bus bandwidth thresholds instead.
- **Alias: `willow` → `ginkgo`** — Redmi Note 8T (willow) shares the same hardware
  and config as ginkgo. Added to the alias map in `customize.sh`.
- **Updated:** `patches/README.md` and root `README.md` profile tables.

## v5.0.2
- **Fix (critical):** Devices using `icnss`/`icnss2` as the wlan0 driver (Snapdragon 600/700 series on SNOC/AHB bus, including SD665) were being classified as modular and had their driver unbound, causing an immediate kernel panic / reboot. Added a blocklist check at the top of `detect_driver_type()` — `icnss`, `icnss2`, `cnss`, `cnss2`, `wlan_platform` are now immediately classified as `builtin` before any other check runs.
- **Fix:** Stats cards showing empty on Qualcomm devices. `wpa_cli` was called without a socket path but Qualcomm vendor `wpa_supplicant` uses a non-default socket under `/data/vendor/wifi/wpa/`. Stats method 1 now probes all known Qualcomm socket paths (`/data/vendor/wifi/wpa/wlan0`, `/data/vendor/wifi/wpa_supplicant/wlan0`, `/data/misc/wifi/sockets/wlan0`) before falling back to the default.
- **New backend action:** `get_debug_info` — dumps driver sysfs paths, detection result, wpa_supplicant socket search results, and output from all stats methods. Useful for diagnosing issues on unseen devices.
- **WebUI:** Added Debug button in Utilities that runs `get_debug_info` and prints results to the log box with colour coding.

## v5.0.1
- **New patch:** `soc/sm6125/` — Snapdragon 665 (WCN3980 chipset). Tuned against a real Redmi Note 8 config. Key differences from sm7150 family: uses `gTxPowerCap` instead of `TxPower2g`/`TxPower5g`; `gRoamScanOffloadEnabled` not present on this driver; `gEnableModulatedDTIM` must not be set to 0 (firmware assert risk on WCN3980); WMM is off in stock and is enabled in both profiles for proper QoS.
- **New patch:** `devices/ginkgo/` — Redmi Note 8 (device-level, verified config). Willow alias supported (`willow` → `ginkgo`).
- **Fix:** Added `willow` → `ginkgo` device alias in `customize.sh` and `backend.sh` runtime fallback.
- **Docs:** Updated profile tables in `README.md` and `patches/README.md` with sm6125 and ginkgo entries.

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
