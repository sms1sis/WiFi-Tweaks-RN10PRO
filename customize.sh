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
    # The root solution's overlay REQUIRES files to live under $MODPATH/system/
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

# ---------------------------------------------------------------------------
# 5. Optional: pick an initial profile with the Volume buttons
#    Volume Down = cycle, Volume Up = confirm. Auto-continues at Stock after
#    ~15s of no input so a headless flash (fastboot/ADB sideload, or a
#    manager app that doesn't forward /dev/input to this shell) never hangs.
# ---------------------------------------------------------------------------
CAN_PROMPT=1
command -v getevent >/dev/null 2>&1 || CAN_PROMPT=0
command -v timeout   >/dev/null 2>&1 || CAN_PROMPT=0
ls /dev/input/event* >/dev/null 2>&1 || CAN_PROMPT=0

if [ "$CAN_PROMPT" = "1" ] && [ -f "$PATCH_DIR/perf.patch" ] && [ -f "$PATCH_DIR/balanced.patch" ]; then
    ui_print " "
    ui_print "- Select an initial profile:"
    ui_print "  Volume Down = next option, Volume Up = confirm"
    ui_print "  (leaves at Stock automatically after 15s of no input)"

    PROFILES="stock balanced perf"
    cp_label() {
        # $1 = index into PROFILES (0/1/2)
        cpl_i=0
        for cpl_p in $PROFILES; do
            if [ "$cpl_i" -eq "$1" ]; then
                case "$cpl_p" in
                    stock)    echo "Stock (no changes)" ;;
                    balanced) echo "Balanced" ;;
                    perf)     echo "Performance" ;;
                esac
                return
            fi
            cpl_i=$((cpl_i + 1))
        done
    }
    cp_value() {
        cpv_i=0
        for cpv_p in $PROFILES; do
            [ "$cpv_i" -eq "$1" ] && echo "$cpv_p" && return
            cpv_i=$((cpv_i + 1))
        done
    }

    SEL=1  # start on Balanced — a safe, useful default
    LAST_PRINTED=""
    ELAPSED=0
    MAXWAIT=15
    CHOSEN=""

    while [ "$ELAPSED" -lt "$MAXWAIT" ]; do
        CUR_LABEL=$(cp_label "$SEL")
        if [ "$CUR_LABEL" != "$LAST_PRINTED" ]; then
            ui_print "  > ${CUR_LABEL}"
            LAST_PRINTED="$CUR_LABEL"
        fi

        LINE=$(timeout 1 getevent -lc 1 2>/dev/null | grep -m1 "KEY_VOLUME")
        ELAPSED=$((ELAPSED + 1))
        [ -z "$LINE" ] && continue

        # getevent -l format: "<device>: EV_KEY  KEY_VOLUMEUP/DOWN  DOWN/UP/REPEAT"
        # Fields, not substring match — "KEY_VOLUMEDOWN" itself contains "DOWN".
        KEYNAME=$(printf '%s' "$LINE" | awk '{print $(NF-1)}')
        STATE=$(printf '%s' "$LINE" | awk '{print $NF}')
        [ "$STATE" != "DOWN" ] && continue

        case "$KEYNAME" in
            KEY_VOLUMEDOWN)
                SEL=$(( (SEL + 1) % 3 ))
                ELAPSED=0
                ;;
            KEY_VOLUMEUP)
                CHOSEN=$(cp_value "$SEL")
                break
                ;;
        esac
    done

    if [ -z "$CHOSEN" ]; then
        ui_print "  (no input — leaving at Stock; pick a profile anytime in the app)"
    elif [ "$CHOSEN" = "stock" ]; then
        ui_print "- Profile: Stock (no changes applied)"
    else
        ui_print "- Applying ${CHOSEN} profile..."
        sh "$MODPATH/backend.sh" apply_mode "$CHOSEN" >/dev/null 2>&1
        ui_print "  Done — change anytime from the app"
    fi
else
    ui_print "- Profile selection needs button input, which isn't available"
    ui_print "  here (headless flash) — pick a profile anytime from the app"
fi

# Reflect the active profile (whatever it ended up being) on the module
# card in KernelSU/Magisk Manager, so it's visible without opening the WebUI.
sh "$MODPATH/backend.sh" sync_description >/dev/null 2>&1

ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  Installation complete!"
ui_print "  Patch: $PATCH_SOURCE"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
