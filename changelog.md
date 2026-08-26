## v7.2.0 — Volume-Key Profile Picker & Module Card Status

### New Features
- **Volume-key profile selection at install.** `customize.sh` now prompts during install: Volume Down cycles Stock → Balanced → Performance, Volume Up confirms. Picking Balanced or Performance applies it immediately via the existing `backend.sh apply_mode` path (same snapshot/backup safety as applying from the WebUI) — no need to open the app just to get off Stock. Auto-continues at Stock after 15s of no input, and is skipped entirely (with a log line explaining why) when `getevent`, `timeout`, or `/dev/input/event*` aren't available to the install shell — a headless flash (fastboot/ADB sideload, or a manager that doesn't forward key events) never hangs waiting for a button that can't be pressed.
- **Current profile shown on the module card.** `module.prop`'s `description` is now kept in sync with the active profile — e.g. `... driver-aware. [Profile: Balanced]` — visible in KernelSU/Magisk Manager's module list without opening the WebUI. New backend helper `sync_description()` (and a `sync_description` action for callers outside a WebUI action) reads the same saved mode `get_mode` does, so it can't disagree with what the app shows. Re-syncing is idempotent — a previous `[Profile: ...]` tag is stripped before the current one is appended, so repeated calls never nest tags.
- **`apply_mode`, `apply_custom`, and `reapply_custom` now sync the card automatically** on every successful mode change, so the description reflects the live state without any extra step.
- **`service.sh` syncs the description on every boot**, including for Stock and for a fresh install with no saved mode yet — `module.prop` is shipped fresh with every module update (the module dir is wiped on each flash, same as everything else under `$MODDIR`), so any previously-synced tag would otherwise disappear until the next mode change.

### Notes
- No changes to patch files or `WCNSS_qcom_cfg.ini` handling — this release is install UX and status visibility only.
- The appended `[Profile: ...]` tag adds a bit of length to the description; if your manager app truncates long module descriptions, the tag may get clipped on-screen (v5.1.0 already trimmed the base text once for the same reason). Functionally harmless either way — this is a display-only concern.

---

## v7.1.1 — Snapshot Delete Confirmation Fix

### WebUI Fixes
- **Fix: Snapshot delete button appeared unresponsive.** Delete used a tap-twice-to-confirm pattern (first tap armed it via a `.confirm` CSS class + `title` tooltip change, second tap within 3s actually deleted). On touch devices neither cue is visible — `:hover` doesn't fire and `title` tooltips don't show on tap — so a single tap looked like nothing happened, and users had no reliable way to discover the second tap was needed.
- **New: themed confirm modal.** Replaced the two-tap button state with a proper confirm dialog (`confirmAction()` on the `App` class) — shows the snapshot's label, "Delete" / "Cancel" actions, dismissible via backdrop click. Styled consistently across all three themes (Sci-Fi / Light / Dark) using the existing CSS custom properties, no new palette entries needed.
- `confirmAction()` is generic (`{ title, message, okLabel }` → resolves `true`/`false`), so other destructive actions (e.g. Restore Snapshot, Reset Preferences) can adopt the same dialog instead of ad hoc confirm patterns.
- No backend changes — `snapshot_delete` in `backend.sh` was already correct; this was a frontend confirmation-UX issue only.

---

## v7.1.0 — Snapshot History & Custom Profile Builder

### New Features

- **New "Tools" tab** — added between Dashboard and Config in the bottom nav, dedicated to Snapshot History and the Custom Profile Builder (see below). Keeps the raw Config Editor page exactly as it was — a first pass had these panels appended to the Config page, but that pushed the raw `.ini` editor out of easy reach, so they got their own home instead.
- **Snapshot History & Rollback.** Previously there was only a single stock backup slot (`.bak`), silently overwritten on first patch apply. Now every mode change creates a timestamped, labeled snapshot in `/data/adb/wcs/snapshots/` (persistent, survives reflashes), listed newest-first on the Tools tab with one-tap Restore/Delete. Manual "Save" is also available for checkpointing before hand-editing the raw config. History is capped at 20 entries (oldest pruned automatically) so it never grows unbounded. Restoring a snapshot itself creates a safety snapshot of the pre-restore state first, so a rollback is always itself undoable. New backend actions: `snapshot_create`, `snapshot_list`, `snapshot_restore`, `snapshot_delete`.
- **Custom Profile Builder.** A 4th profile alongside Performance / Balanced / Stock. Exposes 7 known `WCNSS_qcom_cfg.ini` keys (`gEnableBmps`, `gEnableImps`, `gDataInactivityTimeout`, `TxPower2g`, `TxPower5g`, `gChannelBondingMode24GHz`, `gRoamScanOffloadEnabled`) as individually toggleable sliders/switches on the Tools tab — friendlier than editing raw `.ini` text for users who just want to tune one or two values. Only the parameters you explicitly enable are written; everything else in the config is left exactly as the last-applied profile set it. The selection persists in `/data/adb/wcs/custom.patch` and is re-applied automatically on boot, the same as Perf/Balanced. New backend actions: `apply_custom`, `get_custom_patch`, `reapply_custom` (boot-only).
- **`apply_mode` now auto-snapshots before a real mode change** (skipped when re-applying the same mode, to avoid noise), and **`apply_custom` snapshots before every apply** — each custom edit is its own checkpoint since, unlike Perf/Balanced, the values can differ between applies while staying in the same mode.
- **`get_mode` now recognizes `custom`** as a valid saved mode (previously any value outside `perf`/`balanced`/`stock` silently fell back to `stock`).
- **`service.sh`** re-applies a saved Custom profile on boot (`reapply_custom`), extending the existing Perf/Balanced boot-restore behaviour introduced in v7.0.0.

### WebUI

- Dashboard's Performance Profile row is now a 4-across grid (2×2 under 380px) to fit the new Custom button, which jumps straight to the Tools tab; existing Perf/Balanced/Stock buttons are unchanged.
- Added a dedicated `--purple` accent (with `-dim`/`-glow` variants) across all three themes (Sci-Fi / Light / Dark) for Custom-mode styling, consistent with the existing green/amber/neutral treatment for Perf/Balanced/Stock.
- Tools tab content (Snapshot History + Custom Profile Builder) refreshes on every visit rather than once per session, since either can change from actions taken on the Dashboard or Config page.

### Assets

- **New `banner.png`.** Replaced the leftover "Wi-Fi Config Switcher" title text (unchanged since the v7.0.0 rename) with "WiFi Config Tuner". Also swapped the small glyph above the chip icon for an unambiguous WiFi signal icon (dot + fanning arcs) — the previous glyph's rectangle-with-an-arc silhouette read as a padlock to more than one person. Subtitle updated to "GENERIC QUALCOMM EDITION // UNIVERSAL ROOT" to match the root-solution-agnostic wording used everywhere else since v7.0.0.

---

## v7.0.0 — Rename & Maintenance Audit

### Renamed

- **Project renamed: WiFi Config Switcher → WiFi Config Tuner.** Module `id` changed from `wifi_config_switcher` to `wifi_config_tuner` (`module.prop`), which also updates the on-disk install path (`/data/adb/modules/<id>/`) and the WebUI's hardcoded `actionScript` path in lockstep — both were updated together since a mismatch here silently breaks every WebUI action. Display name, install banner, About page, and GitHub source links updated to match. The new name also resolves a naming inconsistency that predated this release: the WebUI `<title>` already said "Wi-Fi Config Tuner" while `module.prop` said "WiFi Config Switcher" — everything now agrees.
- **Breaking for existing installs:** because the module id changed, flashing this version installs alongside any existing "WiFi Config Switcher" install rather than replacing it in place. See the README's "Upgrading" section — the old module must be removed manually via KernelSU Manager. Saved profile state in `/data/adb/wcs/` is unaffected and carries over automatically.
- `update.json` and `module.prop`'s `updateJson` now point at the renamed `WiFi-Config-Tuner` repository.

### Reliability & Portability

- **Removed non-POSIX `local` keyword** (17 uses across `detect_driver_type`, `get_driver_name`, `find_wifi_config`, `find_patch_dir`, `apply_patch`). `local` is a bash/toybox/mksh extension, not POSIX `sh` — on ROMs whose `/system/bin/sh` doesn't support it, these variables would silently become global instead of raising an error, a dangerous failure mode. Replaced with per-function variable-name prefixes so correctness no longer depends on shell-specific behaviour.
- **Fix: `apply_patch` used a fixed `/tmp/wcs_patch_count` path** for passing the applied-key count out of an `awk` subprocess — a race risk if `apply_mode` were ever triggered twice concurrently (e.g. a double-tap on the WebUI profile button before it disables itself). Now uses `mktemp` under the module's own state directory, with the temp file cleaned up immediately after use.
- **Removed dead code: the non-JSON `get_debug_info` action** (~90 lines). The WebUI has only ever called `get_debug_info_json`; the plain-text twin was unreferenced and had already drifted slightly out of sync with it.
- **Removed dead code: legacy pre-v5.0.4 config-overlay path fallback** in `find_wifi_config()`. `MODDIR` is wiped on every flash (see `service.sh`), so a module update always re-runs `customize.sh` fresh — there was no upgrade path left that could still hit this branch.

### Internal Cleanup

- **Externalized the SoC-ID → Wi-Fi-chip-name table** (~90 lines of hardcoded `case` statements) into a new `chip_map.tsv` data file, looked up via `awk`. Contributing a new SoC ID is now a one-line data edit instead of a shell patch. The SDM665/SD732G (SoC 394) disambiguation and the WCSS-address fallback stay in `backend.sh` since they need logic beyond a flat lookup.
- **Deduplicated the device-alias map** (`sunny→mojito`, `sweet_k`/`sweetin→sweet`, `willow→ginkgo`) out of `customize.sh` and `backend.sh` into a single shared `device_aliases.txt`, read by both `customize.sh` (install time) and a new `resolve_device_alias()` helper in `backend.sh` (runtime sideload fallback). Previously the same map had to be updated by hand in two places.
- **Promoted the inline `_esc()` JSON-escaping helper** out of `get_driver_info` into the top-level Helpers section, next to `log_json()`.
- **`detect_driver_type()`** is now a thin memoizing wrapper around the original detection logic (renamed `_detect_driver_type_impl`), guarding against any future code path calling it twice within the same action (it re-runs a `zcat /proc/config.gz` decompression each time). Does not cache across separate WebUI actions — each is its own fresh process.

### WebUI Fixes

- **Fix: `parseJson()` used naive `indexOf('{')`/`lastIndexOf('}')` brace matching**, which would silently grab the wrong substring if any JSON string value ever legitimately contained a literal `{` or `}` (e.g. an unescaped device-tree compatible string). Replaced with a proper depth-tracking scanner that respects quoted strings and escape sequences, so it finds the actual end of the intended object.
- **Google Fonts stylesheet now loads asynchronously** (`media="print"` swapped to `all` on load, with a `<noscript>` fallback) instead of render-blocking. This is a Wi-Fi tuning tool — plausibly opened while the device's own connectivity is down or misconfigured — so first paint no longer waits on a network request that may never succeed. The existing `monospace`/`sans-serif` fallbacks in `--mono`/`--head` mean the UI stays fully legible either way.



### Bug Fixes

- **Fix (critical): `apply_patch` corrupts values containing `&` or `|`** — the old implementation used `sed -i "s|...|${key}=${value}|"` directly. Any value containing `&` expanded to the matched text in sed's replacement, silently writing wrong data. A `|` in the value broke the `s|...|` delimiter entirely. Current patch files only use integers so this was latent, but would have triggered the moment a patch added a string-typed value. Rewritten with `awk` — keys and values are passed as awk variables, never interpolated into a regex or replacement pattern.

- **Fix (critical): `apply_patch` inserts literal `\n` on Android (toybox `sed` bug)** — when a key was new and the config contained an `END` marker, the old code used `sed -i "s|^END|${key}=${value}\nEND|"`. Android's toybox `sed` does not support `\n` in replacements; it writes the two characters `\n` literally instead of a newline, producing a malformed config line. The `awk` rewrite handles END insertion with correct newline semantics on all POSIX shells.

- **Fix: `apply_patch` rewrites the whole file on every key** — the old implementation ran one `sed -i` per key, rewriting the entire config file N times (23 times for sm6125). The `awk` rewrite makes a single pass over the file regardless of patch size.

- **Fix: `apply_patch` write is now atomic** — the old implementation wrote directly to the config file. A kill mid-write (OOM killer, force-stop) left a truncated config the driver could not parse. The new implementation writes to a `.wcs_tmp` sibling and `mv`s it into place — `mv` on the same filesystem is atomic.

- **Fix: `write_config` (config editor save) is now atomic** — same issue as above. The base64 decode now targets a `.wcs_tmp` file; `mv` replaces the live config only after a successful decode.

- **Fix: `get_mode` sanitizes mode file** — `cat mode_status.txt` was written raw into a JSON string. A corrupt or manually edited file could produce invalid JSON, breaking the dashboard on next open. The value is now validated against the three known modes (`perf`, `balanced`, `stock`) and defaults to `stock` for anything else.

- **Fix: `apply_mode` ran `detect_driver_type` twice** — once in the stock-restore branch and once after applying a patch, each triggering a full sysfs scan. Now runs once at the top of the action, result shared by both paths.

- **Fix: duplicate `willow` alias in `customize.sh`** — two identical `willow) ALIAS="ginkgo"` entries in the device alias `case` block. Second entry was dead code but a maintenance hazard. Removed.

### New Features

- **Boot-time profile re-application (`service.sh`)** — after a module update or reflash, `customize.sh` copies a fresh unpatched config from `/vendor` into the overlay, silently reverting the tuning even though the saved mode still says `perf` or `balanced`. `service.sh` now reads the saved mode on every boot and re-applies it automatically. Output is logged to `/data/adb/wcs/boot_restore.log` for verification. Stock mode takes no action.

### WebUI Fixes

- **Fix: theme flash (FOUC) on open** — the saved theme was applied by JS after the page rendered, causing a brief Sci-Fi flash before switching to Light or Dark. A blocking inline `<script>` in `<head>` now reads `localStorage` and sets `data-theme` before the first paint. A `visibility: hidden` guard covers the remaining gap while the JS module loads. No visible flash at any network/CPU speed.

- **Fix: `data-theme` used empty string for Sci-Fi** — `setTheme('scifi')` set `data-theme=""` (empty string). While functional, it means `[data-theme]` attribute selectors would match the empty value unexpectedly. All theme paths now use explicit string values (`"scifi"`, `"normal"`, `"normal-dark"`). `:root` and `[data-theme="scifi"]` are co-selectors for the Sci-Fi variables.

- **Fix: settings checkmarks hardcoded in HTML** — `check-scifi` and `check-interval-5` had `✔` baked into the HTML. If the user had changed those settings, reopening Settings briefly showed the wrong checkmark before JS corrected it. All checkmarks are now blank in HTML; JS always writes them via `_syncThemeChecks` / `_syncIntervalChecks`.

- **Fix: theme checkmarks not updated on Settings visit** — `navigate('settings')` only called `_syncIntervalChecks`. If the theme was changed in the same session the checkmarks on the Settings page were stale until the page was re-visited. Now calls both sync functions on every visit.

- **Fix: deprecated `escape()`/`unescape()` removed** — three `decodeURIComponent(escape(atob(...)))` calls and one `btoa(unescape(encodeURIComponent(...)))` replaced with `TextDecoder` / `TextEncoder`. The old functions are removed from the Web standard and log deprecation warnings in modern WebViews.

- **Fix: stats interval timer not cleaned up** — `setInterval` for stats polling had no `clearInterval` on page unload. Added a `pagehide` listener to clean it up when the WebView is destroyed.

- **Removed dead `.theme-toggle` CSS** — three rule blocks for `.theme-toggle` (a button replaced by the Settings page in an earlier version) were still in the stylesheet. Removed.

---

## v6.1.4 — Config Editor Search & Replace

### Config Editor
- **Search bar** — tap the 🔍 icon in the config panel header to open. Type to find, match count shows as `1/N` in cyan or `no match` in red.
- **Next / Prev navigation** — ▲ ▼ buttons or Enter / Shift+Enter to jump between matches. Selection scrolls into view automatically.
- **Replace** — second input row with Replace (current match) and All (all occurrences) buttons. Replace All reports count in the status bar and log.
- **Keyboard shortcut** — Ctrl+F / Cmd+F opens the search bar when on the Config page. Esc closes it.
- **Case-insensitive** matching. Special regex characters in the search query are escaped so literal strings always work.

---

## v6.1.3 — Debug Dump Polish & wpa_cli Guard

### Bug Fixes
- **Fix: `=== current connection ===` empty in debug dump** — `cmd wifi status` is now tried first (primary source, no whitespace issues). `dumpsys wifi` used as fallback. Previously only `dumpsys` was called in the debug path.
- **Fix: `wpa_cli signal_poll` crashing on AOSP 16** — AOSP 16 removed `wpa_cli` entirely. Every `wpa_cli` call in the backend now checks `command -v wpa_cli` first and prints `wpa_cli not available on this ROM` instead of a shell error. Affects the debug dump signal_poll section and the Method 3 stats fallback.

---

## v6.1.2 — Fix Stats & wpa_supplicant Socket Path

### Bug Fixes
- **Fix: Link Telemetry showing dashes** — wpa_supplicant on many Qualcomm ROMs uses `/data/vendor/wifi/wpa/sockets/wlan0` with an extra `sockets/` subdirectory. The backend was only checking paths without that subdirectory so all socket paths came back absent, killing `wpa_cli` signal_poll and SSID detection. Added `sockets/` variants at the top of every socket search list throughout the backend.
- **Fix: `dumpsys wifi` stats parsing** — `mWifiInfo` line has leading whitespace on Android 13+. The `grep "^mWifiInfo"` anchor never matched so Method 2 was silently always failing. Fixed with `grep -m1 "mWifiInfo" | sed 's/^[[:space:]]*//'`.
- **Fix: Debug dump `=== current connection ===` empty** — same `^mWifiInfo` whitespace issue caused the current connection section to show nothing even when connected.
- **Added Method 3 stats fallback** — `wpa_cli signal_poll` via the corrected socket path, with `wpa_cli status` for SSID. Kicks in if both `cmd wifi status` and `dumpsys` fail.

---

## v6.1.1 — Debug Button Fix & Sci-Fi Default Theme

### Bug Fixes
- **Fix (critical): Debug button** was returning only one line (`mLastBssid …`) instead of the full diagnostic dump. Root cause: `runDebug()` and `exportDebugInfo()` used raw `ksu.exec()` which has a stdout buffer limit — output was silently truncated. Fixed by adding a new `get_debug_info_json` backend action that base64-encodes the full output inside a JSON envelope, then decoding it on the frontend. Both the Debug button and Settings → Export Debug Info are fixed.
- **Default theme restored to Sci-Fi** — was changed to Dark in v6.0.2, reverted back. Dark theme remains available in Settings.
- **Brighter banner** — reprocessed with gamma correction to lift shadows and dark areas into clearly visible range in KSU manager.

---

## v6.1.0 — Comprehensive Qualcomm Chip Coverage

### Backend (`backend.sh`)
- **Fixed duplicate SoC ID entries** — SoC IDs `415` and `457` appeared twice in the lookup table, causing silent misidentification. `415` is now correctly SM8250/WCN3998 (not SM8350), and `457` is SM6225/WCN3990 (not SM8450).
- **Added missing SoC entries:** SDM632 (338) → WCN3615, SDM630 (345) → WCN3680B, SM8475 (482) → WCN6855, SM7475 (530) → WCN6855, SM8650/Pineapple (591) → WCN7850, SM7675 (554) → WCN7850.
- **Cleaned up SoC table comments** — each chip family now has accurate generation notes clarifying which use PCIe (PCI ID path) vs SNOC (SoC ID path).

---

## v6.0.5 — Expanded SoC ID Table

### Backend (`backend.sh`)
- SoC ID → Wi-Fi chip lookup table expanded from 12 entries to 40+ entries, sourced directly from `linux/drivers/soc/qcom/socinfo.c` and `linux/include/dt-bindings/arm/qcom,ids.h`.
- Full coverage across all SNOC-attached Wi-Fi chip generations:
  - **WCN3620** — MSM8916/8936/8939/8952/8996
  - **WCN3615** — MSM8953/SDM450, MSM8937/SDM430, MSM8940
  - **WCN3680B** — SDM636, SDM660
  - **WCN3990** — SDM665/Trinket, SDM662, SDM675, SDM710, SDM712, SM6115/Bengal/Khaje, SM6125, SM6150, SM6225/SDM680, SM6350, QCS605
  - **WCN3980** — SDM845
  - **WCN3998** — SM7150, SM7150P, SM7225, SM8150
  - **WCN6750** — SM6375, SM7325/Yupik, SM7325P
  - **WCN6855** — SM7350/Cedros, SM7450, SM8250, SM8350, SM8350P, SM8450 (PCIe fallback)
  - **WCN7850** — SM7550, SM7675, SM8550, SM8550P, SM8650 (PCIe fallback)
  - **WCN7851** — SM8750/Sun (PCIe fallback)
- Added four additional WCSS memory address fallbacks: `a000000` (WCN3990), `18900000` (WCN6750).
- Added inline comments explaining which chips use PCIe (identified by PCI ID above) vs SNOC (identified by SoC ID here).

---

## v6.0.4 — SNOC/icnss Chip Identification

### Backend (`backend.sh`)
- **SoC ID → chip name mapping** for SNOC/icnss devices (no PCI bus). Maps `/sys/devices/soc0/soc_id` to chip name: SDM665/Trinket (394) → WCN3990, SDM845 (321) → WCN3980, SM8150 (356) → WCN3998, and more.
- **BDF file detection** — reads board data filename from `/vendor/firmware/wlan/qca_cld/` or falls back to dmesg `cnss-daemon` log. BDF name encodes chip + board variant (e.g. `bdf_c3j.bin`).
- **WCSS memory address** — extracted from the icnss device sysfs path (e.g. `c800000`). Used as a secondary chip identifier when SoC ID lookup has no match.
- **Broader DT search** — when `of_node/compatible` only returns `qcom,icnss` (the platform glue), now searches all DT nodes for `wcn`/`qca`/`wil6` compatible strings to find the actual chip node.
- **New JSON fields:** `soc_id`, `soc_machine`, `soc_family`, `bdf_file`, `wcss_addr`.

### Frontend (`webroot/index.html`)
- Driver button log now shows `[SOC]` section (id, machine, family) between chip and driver sections. BDF file and WCSS address lines added to `[CHIP]` section, highlighted green when found.

---

## v6.0.3 — Robust Driver & Chip Identification

### Backend (`backend.sh`)
- **`get_driver_info`** now collects six additional chip-specific fields:
  - **PCI vendor:device ID** — scans `/sys/bus/pci/devices/` for wireless-class devices (class `0x028x`). Gives the raw hardware ID, e.g. `17cb:1101`.
  - **Chip name lookup** — maps known Qualcomm PCI IDs to chip names: QCA6390, WCN6855, WCN6750, QCA6490, WCN7850, QCA6174A, QCA9377, QCA9984, and more.
  - **SDIO/MMC modalias** — scans `/sys/bus/sdio/devices/` and `/sys/bus/mmc/devices/` for the SDIO chip modalias string, covering SDIO-attached chips (e.g. QCA6174 on older devices).
  - **Device-tree compatible string** — reads `of_node/compatible` from the device sysfs path and known DT locations. Exposes strings like `qcom,wcn3990-wifi` or `qcom,qca6390`.
  - **Firmware version** — queries `wpa_cli status` for `fw_version`/`firmware_version`, with `iw dev info` as fallback.
  - **Hardware uevent** — reads `PCI_ID`, `SDIO_ID`, `OF_COMPATIBLE`, and `DRIVER` lines from the device uevent file for an additional hardware fingerprint.
- **`get_debug_info`** extended with a new **Chip identification** section at the top covering PCI ID, SDIO modalias, DT compatible string, and full uevent dump.
- Added `_esc()` helper to sanitise all values before JSON serialisation (strips quotes and newlines that would break the JSON).

### Frontend (`webroot/index.html`)
- **Driver button log output** restructured — chip fields (`[CHIP]`) shown first and highlighted, driver evidence (`[DRV]`) follows. Chip name line uses `success` colour when identified, `warning` when unknown.

---

## v6.0.2 — Settings Expansion & UI Polish

### Settings Page
- **Stats Refresh Interval** — pick 3s / 5s / 10s / 30s. Preference persisted in `localStorage`. Timer restarts immediately on change.
- **Diagnostics panel** — Export Log copies the current session log to clipboard as plain text. Export Debug Info runs the full `get_debug_info` backend action and copies the result to clipboard.
- **Advanced panel** — Force Driver Reload exposes the soft reset action from the dashboard. Reset Preferences wipes saved theme and interval and restores defaults.

### UI Fixes
- Reboot banner warning icon is now red instead of default text color.
- Patch profile device name is now `var(--cyan)`, meta line is `var(--text-bright)` — both fully visible instead of dimmed.
- Default theme changed from Sci-Fi to Dark (Normal Dark). First-time users see the dark theme instead of the neon sci-fi theme.

---

## v6.0.1 — UI Polish & Config Editor Fix

### Bug Fixes
- **Fix:** Config editor was displaying raw base64 string instead of the decoded file content. Backend correctly encodes the config as base64 for safe JSON transport, but the frontend was setting the textarea value without decoding it first. Now properly decodes via `atob()` with UTF-8 handling before populating the editor.
- **UI:** Bottom navigation bar was oversized — reduced button padding from `16px 0 20px` to `8px 0 10px`, icon size from `28px` to `20px`, and internal gap from `6px` to `4px` for a more proportionate nav bar height.

---

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

# WiFi Config Tuner — Changelog

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
