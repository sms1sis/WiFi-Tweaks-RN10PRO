# WiFi Config Tuner

> **Generic Qualcomm Edition** — patch-based Wi-Fi tuning for any Qualcomm Android device, managed through a clean WebUI inside your root manager.
>
> *(Formerly "WiFi Config Switcher" — renamed in v7.0.0. See [Upgrading](#upgrading-from-wifi-config-switcher-pre-v700) if you have an existing install.)*

<p align="center">
  <img src="https://img.shields.io/badge/version-v7.2.1-blue?style=flat-square"/>
  <img src="https://img.shields.io/badge/platform-Qualcomm-red?style=flat-square"/>
  <img src="https://img.shields.io/badge/root-Universal-orange?style=flat-square"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square"/>
</p>

---

## Screenshots

<p align="center">
  <img src="screenshots/image1.png" width="23%" />
  <img src="screenshots/image2.png" width="23%" />
  <img src="screenshots/image3.png" width="23%" />
  <img src="screenshots/image4.png" width="23%" />
</p>

---

## What It Does

This root module lets you tune your device's Wi-Fi driver configuration between four profiles without touching system partitions:

| Profile | Effect |
|---|---|
| **Performance** | Disables power-saving, maximises TX power, disables roam scanning |
| **Balanced** | Moderate power-saving, reduced TX power, roam scanning enabled |
| **Custom** | Pick individual parameters yourself via sliders/switches — everything you don't touch is left as-is |
| **Stock** | Restores the original unmodified config from backup |

Every mode change is checkpointed automatically in **Snapshot History**, so you can always roll back — see [Snapshot History & Rollback](#snapshot-history--rollback) below.

All changes are **systemless** — the module overlays your vendor Wi-Fi config at install time and writes patches on top at runtime. A full uninstall leaves zero traces.

---

## Requirements

- Android device with a **Qualcomm Wi-Fi chipset** (WCN36xx / WCN39xx / QCA family)
- A root solution with WebUI support (KernelSU, KernelSU-Next, APatch, Magisk, etc.)
- Root access

---

## Installation

1. Download the latest `WiFi-Config-Tuner.zip` from [Releases](https://github.com/sms1sis/WiFi-Config-Tuner/releases).
2. Flash via your root manager's **Modules → Install from storage**.
3. During install the module will:
   - Detect your device codename and SoC platform automatically.
   - Select the most specific patch profile available (see [Patch Resolution](#patch-resolution) below).
   - Import your stock `WCNSS_qcom_cfg.ini` into the module overlay.
   - Prompt you to pick an initial profile with the **Volume buttons** — Volume Down cycles Stock → Balanced → Performance, Volume Up confirms. No input for 15s leaves it at Stock; you can always change it later from the app. Skipped automatically on headless flashes (fastboot/ADB sideload, or a manager that doesn't forward key events to the install shell) — install proceeds at Stock without waiting.
4. Reboot once after flashing.
5. Open **your root manager → Modules → WiFi Config Tuner → Open WebUI**.

> **No reboot needed** to switch profiles on devices with a modular (loadable) Wi-Fi driver — the driver is reloaded automatically. Devices with a built-in (kernel-compiled) driver will prompt you to reboot.

> The module card in your root manager's Modules list shows the currently active profile (e.g. `... [⚡ Performance]`) appended to the description — no need to open the WebUI just to check what's applied. It updates whenever you change profiles, and re-syncs on every boot.

### Upgrading from WiFi Config Switcher (pre-v7.0.0)

v7.0.0 renames the module's internal id (`wifi_config_switcher` → `wifi_config_tuner`) along with the display name. Because root solutions key a module's install directory off its id, **this does not upgrade in place** — flashing v7.0.0 installs it as a second, separate module alongside your existing one.

To move over cleanly:
1. Flash `WiFi-Config-Tuner.zip` as normal.
2. In your root manager → Modules, **remove the old "WiFi Config Switcher" entry**.
3. Reboot.

Your saved profile (`perf`/`balanced`/`custom`/`stock`) is preserved automatically — it's stored in `/data/adb/wcs/`, which lives outside either module's directory and isn't touched by this rename.

---

## Packaging

To package the module yourself, run the following command in the project root:

```sh
zip -r WiFi-Config-Tuner.zip . -x ".git/*" ".gitignore" "README.md" "LICENSE" "screenshots/*" "changelog.md"
```

---

## WebUI

The WebUI is accessible directly from your root manager and shows:

- **Active mode badge** — current profile (Performance / Balanced / Custom / Stock)
- **Driver pill** — detected driver type (`Modular · qca_cld3_wlan` or `Built-in · wlan`) with colour coding
- **Patch profile card** — which patch is active and how it was matched (device / SoC / generic fallback)
- **Live stats** — Signal (dBm), Link speed (Mbps), Frequency (MHz), SSID
- **Reboot banner** — shown automatically when a built-in driver is detected after a config change
- **Snapshot History** — timestamped rollback points on the Tools page, see below
- **Custom Profile Builder** — guided parameter editor on the Tools page, see below
- **Log box** — timestamped, colour-coded log of every action taken

---

## Snapshot History & Rollback

The Tools page keeps a rolling history of your `WCNSS_qcom_cfg.ini`, so tuning is never a one-way door:

- **Automatic checkpoints** — a snapshot is saved before every real mode change (Perf/Balanced/Stock) and before every Custom Profile apply.
- **Manual checkpoints** — tap **Save** with an optional label before hand-editing the raw config.
- Each entry shows its mode, a relative timestamp, and size; **Restore** and **Delete** are one tap each.
- Restoring a snapshot first saves a safety snapshot of the state you're restoring *from* — a rollback is always itself undoable.
- History is capped at **20 entries**; the oldest is pruned automatically once the cap is hit.
- Stored in `/data/adb/wcs/snapshots/`, outside the module directory, so it survives module updates and reflashes.

---

## Custom Profile Builder

A guided alternative to hand-editing the raw `.ini` for people who just want to tune one or two values, available on its own **Tools** tab (between Dashboard and Config):

- Exposes 7 known parameters: `gEnableBmps`, `gEnableImps`, `gDataInactivityTimeout`, `TxPower2g`, `TxPower5g`, `gChannelBondingMode24GHz`, `gRoamScanOffloadEnabled`.
- Each has its own **include** switch — only the parameters you turn on are written to the config; everything else is left exactly as your last-applied profile set it.
- Selections persist in `/data/adb/wcs/custom.patch` and are **re-applied automatically on boot**, the same as Perf/Balanced.
- Apply from the Dashboard's 4th profile button (**Custom**, jumps straight to the Tools tab) or directly from the Tools tab.

---

## Patch Resolution

At install time `customize.sh` reads your device properties and walks this priority chain, picking the **most specific** match:

```
patches/devices/<ro.product.device>/    ← 1st — exact device codename
       ↓ (alias map: sunny→mojito, sweet_k→sweet, willow→ginkgo, … — see device_aliases.txt)
patches/soc/<ro.board.platform>/        ← 2nd — SoC platform family
       ↓
patches/generic_qcom/                   ← 3rd — safe fallback for any Qualcomm device
```

The resolved path is written to `patch_dir.txt` at install time so the backend never repeats `getprop` lookups at runtime. The device-alias map itself lives in `device_aliases.txt` (a plain `codename=alias` text file), shared by both `customize.sh` (install time) and `backend.sh` (runtime sideload fallback) — add a new alias in one place and both pick it up.

### Included Patch Profiles

| Path | Covers |
|---|---|
| `patches/devices/sweet/` | Redmi Note 10 Pro (sweet) |
| `patches/devices/mojito/` | Redmi Note 10 / sunny (alias supported) |
| `patches/devices/ginkgo/` | Redmi Note 8 / willow (alias supported) |
| `patches/soc/sm7150/` | Snapdragon 730 / 730G / 732G |
| `patches/soc/sm6150/` | Snapdragon 675 / 710 / 712 |
| `patches/soc/sm6125/` | Snapdragon 665 — WCN3980 chipset |
| `patches/soc/sm8150/` | Snapdragon 855 / 855+ |
| `patches/soc/sm8250/` | Snapdragon 865 / 865+ |
| `patches/generic_qcom/` | Any Qualcomm device — conservative safe values |

---

## Adding a New Device

You don't need to touch any shell scripts. Just add two text files.

**Step 1 — Find your identifiers**
```sh
adb shell getprop ro.product.device    # e.g.  miatoll
adb shell getprop ro.board.platform   # e.g.  trinket
```

**Step 2 — Create a device patch** (most specific, recommended)
```sh
mkdir patches/devices/miatoll/
```

`patches/devices/miatoll/perf.patch`:
```ini
# Redmi Note 10S (miatoll) — Performance Profile
# SoC: Helio G95 — uses different param names if non-Qualcomm Wi-Fi
gEnableBmps=0
gEnableImps=0
gDataInactivityTimeout=0
TxPower2g=16
TxPower5g=15
gRoamScanOffloadEnabled=0
```

`patches/devices/miatoll/balanced.patch`:
```ini
# Redmi Note 10S (miatoll) — Balanced Profile
gEnableBmps=1
gEnableImps=1
gDataInactivityTimeout=200
TxPower2g=13
TxPower5g=13
gRoamScanOffloadEnabled=1
```

**Step 3 — Or create a SoC-level patch** (covers all devices on that platform)
```sh
mkdir patches/soc/trinket/
# add perf.patch and balanced.patch as above
```

**Step 4 — Submit a pull request** 🎉

### Patch File Format

```ini
# Lines beginning with # are comments — ignored at runtime
# Blank lines are ignored

KEY=VALUE

# The key must match the WCNSS_qcom_cfg.ini key exactly (case-sensitive).
# Existing keys (including commented-out ones) are updated in place.
# Missing keys are appended before the config's END marker (or at end-of-file
# if there is no END marker).
# No stock.patch is needed — Stock mode always restores from the .bak backup.
```

---

## Driver Types

The module auto-detects which kind of Wi-Fi driver your kernel uses and adjusts its behaviour accordingly.

| Driver Type | Detection | Behaviour after config change |
|---|---|---|
| **Modular** (loadable `.ko`) | Found in `/proc/modules` or `/sys/module/` | Driver is unbound → rebound automatically. No reboot needed. |
| **Built-in** (compiled into kernel) | Subsystem is `platform`/`soc`, no `/proc/modules` entry | Config is written. WebUI shows a **Reboot Required** banner. |
| **Unknown** | Detection inconclusive | Config is written. Reload is skipped to avoid instability. Manual reboot advised. |

Detection uses seven layered checks in order (blocklist for platform-glue drivers → `/module` symlink → `/proc/config.gz` → `/sys/module/.../sections` → `/proc/modules` → known module names → subsystem bus type → `lsmod`) to maximise accuracy across different kernel configurations.

---

## File Structure

```
WiFi-Config-Tuner/
├── backend.sh              ← All backend logic (driver detect, patch apply, stats, reload)
├── customize.sh            ← Install-time: device detect, patch resolution, config import
├── service.sh              ← Re-applies the saved profile on every boot
├── module.prop              ← Module metadata
├── update.json              ← OTA update descriptor
├── chip_map.tsv             ← SoC ID → Wi-Fi chip name lookup table (contributor-editable data file)
├── device_aliases.txt       ← Device codename → alias map, shared by customize.sh and backend.sh
├── webroot/
│   └── index.html          ← Full WebUI (single-file, no external dependencies at runtime)
└── patches/
    ├── README.md           ← Contributor guide for patch files
    ├── devices/
    │   ├── sweet/          ← Redmi Note 10 Pro
    │   │   ├── perf.patch
    │   │   └── balanced.patch
    │   ├── mojito/         ← Redmi Note 10 / sunny
    │   │   ├── perf.patch
    │   │   └── balanced.patch
    │   └── ginkgo/         ← Redmi Note 8 / willow
    │       ├── perf.patch
    │       └── balanced.patch
    ├── soc/
    │   ├── sm7150/         ← Snapdragon 730G / 732G
    │   ├── sm6150/         ← Snapdragon 675 / 710 / 712
    │   ├── sm6125/         ← Snapdragon 665 (WCN3980 — no TxPower params)
    │   ├── sm8150/         ← Snapdragon 855 / 855+
    │   └── sm8250/         ← Snapdragon 865 / 865+
    └── generic_qcom/       ← Safe fallback for any Qualcomm device
```

---

## How It Works (Technical)

1. **Install (`customize.sh`)** — Reads `ro.product.device` and `ro.board.platform`, resolves the best patch directory (via `device_aliases.txt` for aliased hardware), writes `patch_dir.txt` and `patch_source.txt`, then copies the stock `WCNSS_qcom_cfg.ini` into the module overlay tree so the root solution can mount it systemlessly.

2. **Mode Apply (`backend.sh apply_mode`)** — Restores the `.bak` backup first (clean slate), then reads the selected `.patch` file and rewrites the config in a single `awk` pass — updating existing `KEY=VALUE` lines in place and appending any new keys before the `END` marker. Writes the new mode to `mode_status.txt`. A snapshot of the pre-change config is saved automatically first (see below) whenever the mode is actually changing.

3. **Custom Profile Apply (`backend.sh apply_custom`)** — Takes a base64-encoded `KEY=VALUE` patch built by the WebUI from only the parameters the user enabled, snapshots the current config, writes the patch to the persistent `/data/adb/wcs/custom.patch`, then applies it through the same `awk` engine as step 2. Unmentioned keys are untouched.

4. **Snapshot History (`backend.sh snapshot_*`)** — `snapshot_create`/`snapshot_list`/`snapshot_restore`/`snapshot_delete` manage timestamped copies of the config under `/data/adb/wcs/snapshots/`, tracked in an append-only TSV manifest. Capped at 20 entries, oldest pruned first. `snapshot_restore` always snapshots the current state before overwriting it.

5. **Driver Reload (`backend.sh soft_reset`)** — For modular drivers: disables Wi-Fi via `svc`, unbinds the device from its driver via sysfs, rebinds it, re-enables Wi-Fi. For built-in drivers: skips reload and instructs the WebUI to show the reboot banner.

6. **Boot (`service.sh`)** — Re-applies the saved profile (`perf`/`balanced`/`custom`) on every boot, since a module update/reflash resets the overlay to the stock config.

7. **WebUI** — Pure HTML/JS served by your root manager's built-in web server. Calls `backend.sh` via `window.ksu.exec()` (the standard WebUI exec API implemented across root solutions). All log output is timestamped and colour-coded by type (info / success / warning / error / builtin).

---

## Troubleshooting

**"Config file not found"**
The module could not locate `WCNSS_qcom_cfg.ini` during install. Try manually finding it:
```sh
adb shell find /vendor /system -name "WCNSS_qcom_cfg.ini" 2>/dev/null
```
Then open a GitHub issue with your device codename and the path.

**"No patch directory found"**
No patch exists for your device or SoC and the `generic_qcom` folder is missing. Reinstall the module or add a patch file (see [Adding a New Device](#adding-a-new-device)).

**Profile applied but no effect**
If the driver is built-in (the WebUI will say so), you must reboot after applying a profile. The config is written correctly — only the running driver needs a restart.

**WebUI shows "Root manager API not detected (Browser Mode)"**
You're opening `index.html` directly in a browser instead of through your root manager. Open it via Manager → Modules → WiFi Config Tuner → Open WebUI.

**I flashed the update and now see two modules**
Expected for the v7.0.0 rename — see [Upgrading](#upgrading-from-wifi-config-switcher-pre-v700) above.

---

## Contributing

Pull requests for new device/SoC patches are very welcome. Please:

- Include the device codename, SoC platform, and model name in a comment at the top of the patch file.
- Test both profiles on your device before submitting.
- Keep `generic_qcom` values conservative — they run on hardware you haven't tested.
- New SoC-ID → chip-name mappings (for `get_driver_info`/debug output) go in `chip_map.tsv`, not inline shell — see the comments at the top of that file.

---

## License

GPL-3.0 — see [LICENSE](LICENSE).

---

## Credits

- **sms1sis** — original author and maintainer
- The root solution teams (KernelSU, KernelSU-Next, APatch, Magisk) behind the shared WebUI exec API
