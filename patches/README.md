# Patch Directory Structure

Patches are plain key=value files (one param per line) that the module applies
on top of your device's stock Wi-Fi config (WCNSS_qcom_cfg.ini or equivalent).

## Resolution Order (most specific wins)

```
patches/devices/<ro.product.device>/   ← exact device codename  (e.g. sweet, miatoll)
patches/soc/<ro.board.platform>/       ← SoC platform name      (e.g. sm7150, sm8250)
patches/generic_qcom/                  ← fallback for any Qualcomm device
```

The module picks the **most specific** match automatically during install.

## Patch File Format

Each profile directory must contain:
- `perf.patch`     — parameters applied in Performance mode
- `balanced.patch` — parameters applied in Balanced mode

### Syntax

```ini
# Lines starting with # are comments — ignored
# Blank lines are ignored

KEY=VALUE

# Example:
gEnableBmps=0
TxPower2g=17
```

- Keys are case-sensitive and must match the INI key exactly.
- The module will UPDATE the key if it already exists (including commented-out lines).
- If the key is missing entirely it will be APPENDED to the config.
- Stock mode always restores from the original backup — no stock.patch needed.

## Adding a New Device

1. Find your device codename:
   ```sh
   adb shell getprop ro.product.device
   ```
2. Find your SoC platform:
   ```sh
   adb shell getprop ro.board.platform
   ```
3. Create `patches/devices/<codename>/perf.patch` and `balanced.patch`
   — or —
   Create `patches/soc/<platform>/perf.patch` and `balanced.patch`
   if you want it to apply to all devices on that SoC.

## Existing Profiles

| Path                         | Covers                                      |
|------------------------------|---------------------------------------------|
| `devices/sweet/`             | Redmi Note 10 Pro (sweet)                   |
| `devices/mojito/`            | Redmi Note 10 / sunny (alias supported)     |
| `devices/ginkgo/`            | Redmi Note 8 / willow (alias supported)     |
| `soc/sm7150/`                | Snapdragon 730 / 730G / 732G                |
| `soc/sm6150/`                | Snapdragon 675 / 710 / 712                  |
| `soc/sm6125/`                | Snapdragon 665 (WCN3980 chipset)            |
| `soc/sm8150/`                | Snapdragon 855 / 855+                       |
| `soc/sm8250/`                | Snapdragon 865 / 865+                       |
| `generic_qcom/`              | Any Qualcomm device (safe conservative vals)|
