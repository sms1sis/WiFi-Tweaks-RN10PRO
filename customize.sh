#!/system/bin/sh
SKIPUNZIP=0

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  WiFi Config Tuner"
ui_print "  Generic Qualcomm Edition"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ---------------------------------------------------------------------------
# 1. Detect device identity
# ---------------------------------------------------------------------------
DEVICE=$(getprop ro.product.device 2>/dev/null | tr '[:upper:]' '[:lower:]')
MODEL=$(getprop ro.product.model 2>/dev/null)
SOC=$(getprop ro.board.platform 2>/dev/null | tr '[:upper:]' '[:lower:]')
# Some OEMs use ro.soc.model or ro.hardware instead
[ -z "$SOC" ] && SOC=$(getprop ro.hardware 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$SOC" ] && SOC=$(getprop ro.soc.model 2>/dev/null | tr '[:upper:]' '[:lower:]')

ui_print "- Device  : ${DEVICE:-unknown} (${MODEL:-unknown})"
ui_print "- Platform: ${SOC:-unknown}"

# ---------------------------------------------------------------------------
# 2. Resolve patch directory — most specific wins
#    Priority: devices/<codename> > soc/<platform> > generic_qcom
# ---------------------------------------------------------------------------
PATCHES_BASE="$MODPATH/patches"
PATCH_DIR=""
PATCH_SOURCE="none"

# Check exact device codename
if [ -n "$DEVICE" ] && [ -d "$PATCHES_BASE/devices/$DEVICE" ]; then
    if [ -f "$PATCHES_BASE/devices/$DEVICE/perf.patch" ] && \
       [ -f "$PATCHES_BASE/devices/$DEVICE/balanced.patch" ]; then
        PATCH_DIR="$PATCHES_BASE/devices/$DEVICE"
        PATCH_SOURCE="device:$DEVICE"
        ui_print "- Patch   : Device-specific ($DEVICE) ✓"
    fi
fi

# Also check common aliases (e.g. mojito and sunny share hardware).
# Alias map lives in device_aliases.txt (shipped alongside this script) so it
# only has to be maintained in one place — backend.sh's resolve_device_alias()
# reads the exact same file at runtime for its sideload fallback path.
if [ -z "$PATCH_DIR" ] && [ -n "$DEVICE" ]; then
    ALIAS=""
    if [ -f "$MODPATH/device_aliases.txt" ]; then
        ALIAS=$(grep -i "^${DEVICE}=" "$MODPATH/device_aliases.txt" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    fi
    if [ -n "$ALIAS" ] && [ -d "$PATCHES_BASE/devices/$ALIAS" ]; then
        if [ -f "$PATCHES_BASE/devices/$ALIAS/perf.patch" ] && \
           [ -f "$PATCHES_BASE/devices/$ALIAS/balanced.patch" ]; then
            PATCH_DIR="$PATCHES_BASE/devices/$ALIAS"
            PATCH_SOURCE="device-alias:$ALIAS"
            ui_print "- Patch   : Device alias ($ALIAS for $DEVICE) ✓"
        fi
    fi
fi

# Check SoC platform
if [ -z "$PATCH_DIR" ] && [ -n "$SOC" ]; then
    if [ -d "$PATCHES_BASE/soc/$SOC" ]; then
        if [ -f "$PATCHES_BASE/soc/$SOC/perf.patch" ] && \
           [ -f "$PATCHES_BASE/soc/$SOC/balanced.patch" ]; then
            PATCH_DIR="$PATCHES_BASE/soc/$SOC"
            PATCH_SOURCE="soc:$SOC"
            ui_print "- Patch   : SoC-level ($SOC) ✓"
        fi
    fi
fi

# Generic Qualcomm fallback
if [ -z "$PATCH_DIR" ]; then
    if [ -f "$PATCHES_BASE/generic_qcom/perf.patch" ] && \
       [ -f "$PATCHES_BASE/generic_qcom/balanced.patch" ]; then
        PATCH_DIR="$PATCHES_BASE/generic_qcom"
        PATCH_SOURCE="generic_qcom"
        ui_print "- Patch   : Generic Qualcomm fallback"
        ui_print "  (No device/SoC-specific patch found)"
        ui_print "  Consider contributing a patch for: $DEVICE / $SOC"
    fi
fi

# No patch found at all
if [ -z "$PATCH_DIR" ]; then
    ui_print "! ERROR: No patch files found for this device."
    ui_print "! Device: $DEVICE  SoC: $SOC"
    ui_print "! Please add a patch under patches/devices/$DEVICE/"
    ui_print "! See patches/README.md for instructions."
    exit 1
fi

# Write the resolved patch dir so backend.sh can find it at runtime
echo "$PATCH_DIR" > "$MODPATH/patch_dir.txt"
echo "$PATCH_SOURCE" > "$MODPATH/patch_source.txt"

# ---------------------------------------------------------------------------
# 3. Locate and import the Wi-Fi config file
# ---------------------------------------------------------------------------
CONFIG_SRC=""
for path in \
    "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
    "/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
    "/data/vendor/wifi/WCNSS_qcom_cfg.ini" \
    "/odm/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
    "/product/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
    "/etc/wifi/WCNSS_qcom_cfg.ini"; do
    if [ -f "$path" ]; then
        CONFIG_SRC="$path"
        break
    fi
done

# Deep search fallback
if [ -z "$CONFIG_SRC" ]; then
    ui_print "- Searching for WCNSS_qcom_cfg.ini..."
    CONFIG_SRC=$(find /vendor /system -name "WCNSS_qcom_cfg.ini" \
        -not -path "*/lost+found/*" -print -quit 2>/dev/null)
fi

if [ -n "$CONFIG_SRC" ]; then
    # KernelSU/Magisk overlay REQUIRES files to live under $MODPATH/system/
    # The framework mirrors $MODPATH/system/ over / at boot.
    # A file at $MODPATH/vendor/... is silently ignored — never mounted.
    REL_PATH="${CONFIG_SRC#/}"
    DEST="$MODPATH/system/${REL_PATH}"
    mkdir -p "$(dirname "$DEST")"
    cp "$CONFIG_SRC" "$DEST"
    chmod 644 "$DEST"
    ui_print "- Config  : Imported from $CONFIG_SRC ✓"
    ui_print "- Overlay : $MODPATH/system/${REL_PATH}"
    # Store the relative path (without leading "system/") for backend.sh
    # backend.sh finds the live path at /${REL_PATH} (the mounted overlay)
    echo "$REL_PATH" > "$MODPATH/config_rel_path.txt"
else
    ui_print "! Warning : WCNSS_qcom_cfg.ini not found on this device."
    ui_print "! Tuning features will be unavailable until config is found."
fi

# ---------------------------------------------------------------------------
# 4. Permissions
# ---------------------------------------------------------------------------
chmod +x "$MODPATH/backend.sh"

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  Installation complete!"
ui_print "  Patch: $PATCH_SOURCE"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
