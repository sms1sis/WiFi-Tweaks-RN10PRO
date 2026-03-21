#!/system/bin/sh
# backend.sh - WiFi Config Switcher Backend (Generic Qualcomm Edition)
# Patch-based architecture: reads perf.patch / balanced.patch instead of hardcoded params
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin

MODDIR=${0%/*}
WLAN_DEV="wlan0"
WLAN_SYS="/sys/class/net/${WLAN_DEV}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log_json() {
    printf '{"status":"%s","message":"%s"}\n' "$1" "$2"
}

detect_driver_type() {
    DEVICE_PATH="${WLAN_SYS}/device"

    # Check 1: /module symlink -> definitely loadable
    [ -L "${DEVICE_PATH}/driver/module" ] && echo "modular" && return

    # Check 2: driver name in /sys/module
    local driver_name=""
    [ -L "${DEVICE_PATH}/driver" ] && \
        driver_name=$(basename "$(readlink "${DEVICE_PATH}/driver" 2>/dev/null)" 2>/dev/null)

    if [ -n "$driver_name" ] && [ "$driver_name" != "." ]; then
        [ -d "/sys/module/${driver_name}" ] && echo "modular" && return
    fi

    # Check 3: driver name in /proc/modules
    if [ -n "$driver_name" ] && [ -f "/proc/modules" ]; then
        grep -q "^${driver_name} " /proc/modules 2>/dev/null && echo "modular" && return
    fi

    # Check 4: common Wi-Fi module names in /proc/modules
    for kmod in qca_cld3_wlan wlan qca6390 wl bcmdhd ath10k_pci ath11k brcmfmac mt7921e iwlwifi; do
        grep -q "^${kmod} " /proc/modules 2>/dev/null && echo "modular" && return
    done

    # Check 5: driver path contains built-in hint
    if [ -L "${DEVICE_PATH}/driver" ]; then
        local drv_link
        drv_link=$(readlink -f "${DEVICE_PATH}/driver" 2>/dev/null)
        case "$drv_link" in
            *built-in*|*platform*) echo "builtin"; return ;;
        esac
    fi

    # Check 6: subsystem bus type
    if [ -L "${DEVICE_PATH}/subsystem" ]; then
        local subsys
        subsys=$(basename "$(readlink "${DEVICE_PATH}/subsystem" 2>/dev/null)" 2>/dev/null)
        case "$subsys" in
            platform|soc)        echo "builtin";  return ;;
            pci|usb|sdio|mmc)   echo "modular"; return ;;
        esac
    fi

    echo "unknown"
}

get_driver_name() {
    local n="unknown"
    if [ -L "${WLAN_SYS}/device/driver" ]; then
        n=$(basename "$(readlink "${WLAN_SYS}/device/driver" 2>/dev/null)" 2>/dev/null)
        [ -z "$n" ] && n="unknown"
    fi
    echo "$n"
}

# Resolve the active Wi-Fi config file path.
# During runtime the module overlay is already mounted by Magisk/KSU,
# so we just need to find the live (possibly overlaid) config.
find_wifi_config() {
    # If customize.sh recorded the relative path, use that first
    if [ -f "$MODDIR/config_rel_path.txt" ]; then
        local rel
        rel=$(cat "$MODDIR/config_rel_path.txt")
        # Try the live (overlaid) path — this is what the system actually reads
        local live="/${rel}"
        [ -f "$live" ] && echo "$live" && return
        # Try inside the module dir (overlay source)
        local overlay="$MODDIR/${rel}"
        [ -f "$overlay" ] && echo "$overlay" && return
    fi

    # Fallback search
    for p in \
        /vendor/etc/wifi/WCNSS_qcom_cfg.ini \
        /system/vendor/etc/wifi/WCNSS_qcom_cfg.ini \
        /data/vendor/wifi/WCNSS_qcom_cfg.ini \
        /etc/wifi/WCNSS_qcom_cfg.ini; do
        [ -f "$p" ] && echo "$p" && return
    done

    return 1
}

# Resolve the patch directory for this device.
# Reads patch_dir.txt written by customize.sh; falls back to runtime detection.
find_patch_dir() {
    # Use recorded patch dir (most reliable)
    if [ -f "$MODDIR/patch_dir.txt" ]; then
        local pd
        pd=$(cat "$MODDIR/patch_dir.txt")
        [ -d "$pd" ] && echo "$pd" && return
    fi

    # Runtime fallback (if module was sideloaded or patch_dir.txt is missing)
    local device soc
    device=$(getprop ro.product.device 2>/dev/null | tr '[:upper:]' '[:lower:]')
    soc=$(getprop ro.board.platform 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ -z "$soc" ] && soc=$(getprop ro.hardware 2>/dev/null | tr '[:upper:]' '[:lower:]')

    local base="$MODDIR/patches"

    # Device alias map
    local resolved_device="$device"
    case "$device" in
        sunny)   resolved_device="mojito" ;;
        sweet_k) resolved_device="sweet"  ;;
        willow)  resolved_device="ginkgo" ;;
    esac

    [ -d "$base/devices/$resolved_device" ] && echo "$base/devices/$resolved_device" && return
    [ -d "$base/soc/$soc" ]                 && echo "$base/soc/$soc"                 && return
    [ -d "$base/generic_qcom" ]             && echo "$base/generic_qcom"             && return

    return 1
}

# Apply a patch file to a config file.
# Patch format: KEY=VALUE lines; lines starting with # or blank are ignored.
apply_patch() {
    local config_file="$1"
    local patch_file="$2"
    local applied=0
    local skipped=0

    [ ! -f "$config_file" ] && return 1
    [ ! -f "$patch_file"  ] && return 1

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and blank lines
        case "$line" in
            '#'*|'') continue ;;
        esac

        # Split on first '='
        local key value
        key="${line%%=*}"
        value="${line#*=}"

        # Trim whitespace from key
        key=$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$key" ] && continue

        # Update existing key (handles commented-out lines too) or append
        if grep -qE "^[#[:space:]]*${key}[[:space:]]*=" "$config_file" 2>/dev/null; then
            sed -i "s|^[#[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$config_file"
        else
            printf '%s=%s\n' "$key" "$value" >> "$config_file"
        fi
        applied=$((applied + 1))
    done < "$patch_file"

    printf '%d' "$applied"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

case "$1" in

    # -----------------------------------------------------------------------
    "get_driver_type")
        DTYPE=$(detect_driver_type)
        DNAME=$(get_driver_name)
        PATCH_DIR=$(find_patch_dir)
        PATCH_SOURCE="none"
        [ -f "$MODDIR/patch_source.txt" ] && PATCH_SOURCE=$(cat "$MODDIR/patch_source.txt")
        printf '{"status":"success","driver_type":"%s","driver_name":"%s","patch_source":"%s"}\n' \
            "$DTYPE" "$DNAME" "$PATCH_SOURCE"
        ;;

    # -----------------------------------------------------------------------
    "apply_mode")
        MODE="$2"

        # -- Validate mode --
        case "$MODE" in
            perf|balanced|stock) ;;
            *) log_json "error" "Unknown mode: $MODE"; exit 1 ;;
        esac

        # -- Find config --
        CONFIG_FILE=$(find_wifi_config)
        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Wi-Fi config file not found. Module may not be installed correctly."
            exit 1
        fi

        # -- Backup once --
        [ ! -f "${CONFIG_FILE}.bak" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

        if [ "$MODE" = "stock" ]; then
            if [ -f "${CONFIG_FILE}.bak" ]; then
                cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
                sync
                echo "stock" > "$MODDIR/mode_status.txt"
                DTYPE=$(detect_driver_type)
                DNAME=$(get_driver_name)
                printf '{"status":"success","message":"Stock config restored.","driver_type":"%s","driver_name":"%s","params_applied":0}\n' \
                    "$DTYPE" "$DNAME"
            else
                log_json "error" "Backup not found. Cannot restore stock config."
                exit 1
            fi
            exit 0
        fi

        # -- Find patch file --
        PATCH_DIR=$(find_patch_dir)
        if [ -z "$PATCH_DIR" ]; then
            log_json "error" "No patch directory found for this device. See patches/README.md."
            exit 1
        fi

        PATCH_FILE="$PATCH_DIR/${MODE}.patch"
        if [ ! -f "$PATCH_FILE" ]; then
            log_json "error" "Patch file missing: ${PATCH_FILE}"
            exit 1
        fi

        # -- Apply patch --
        N=$(apply_patch "$CONFIG_FILE" "$PATCH_FILE")
        sync
        echo "$MODE" > "$MODDIR/mode_status.txt"

        DTYPE=$(detect_driver_type)
        DNAME=$(get_driver_name)
        PATCH_SOURCE="none"
        [ -f "$MODDIR/patch_source.txt" ] && PATCH_SOURCE=$(cat "$MODDIR/patch_source.txt")

        printf '{"status":"success","message":"Mode %s applied (%s params).","driver_type":"%s","driver_name":"%s","patch_source":"%s","params_applied":%s}\n' \
            "$MODE" "$N" "$DTYPE" "$DNAME" "$PATCH_SOURCE" "${N:-0}"
        ;;

    # -----------------------------------------------------------------------
    "get_patch_info")
        PATCH_DIR=$(find_patch_dir)
        PATCH_SOURCE="none"
        [ -f "$MODDIR/patch_source.txt" ] && PATCH_SOURCE=$(cat "$MODDIR/patch_source.txt")

        DEVICE=$(getprop ro.product.device 2>/dev/null)
        SOC=$(getprop ro.board.platform 2>/dev/null)
        [ -z "$SOC" ] && SOC=$(getprop ro.hardware 2>/dev/null)

        PERF_COUNT=0
        BAL_COUNT=0
        if [ -n "$PATCH_DIR" ]; then
            [ -f "$PATCH_DIR/perf.patch" ]     && PERF_COUNT=$(grep -cE "^[^#[:space:]].*=" "$PATCH_DIR/perf.patch" 2>/dev/null || echo 0)
            [ -f "$PATCH_DIR/balanced.patch" ] && BAL_COUNT=$(grep -cE "^[^#[:space:]].*=" "$PATCH_DIR/balanced.patch" 2>/dev/null || echo 0)
        fi

        printf '{"status":"success","device":"%s","soc":"%s","patch_source":"%s","perf_params":%s,"balanced_params":%s}\n' \
            "${DEVICE:-unknown}" "${SOC:-unknown}" "$PATCH_SOURCE" "$PERF_COUNT" "$BAL_COUNT"
        ;;

    # -----------------------------------------------------------------------
    "stats")
        RSSI="--" SPEED="--" FREQ="--" SSID="--"

        if command -v iw >/dev/null 2>&1; then
            LINK=$(iw dev "$WLAN_DEV" link 2>/dev/null)
            if [ -n "$LINK" ]; then
                RSSI_RAW=$(printf '%s' "$LINK" | grep -o "signal: -[0-9]*" | awk '{print $2}')
                SPEED_RAW=$(printf '%s' "$LINK" | grep -o "tx bitrate: [0-9.]*" | awk '{print $3}')
                FREQ_RAW=$(printf '%s' "$LINK" | grep -o "freq: [0-9]*" | awk '{print $2}')
                SSID_RAW=$(printf '%s' "$LINK" | grep "SSID:" | sed 's/.*SSID: //')
                [ -n "$RSSI_RAW" ]  && RSSI="${RSSI_RAW} dBm"
                [ -n "$SPEED_RAW" ] && SPEED="${SPEED_RAW} Mbps"
                [ -n "$FREQ_RAW" ]  && FREQ="${FREQ_RAW} MHz"
                [ -n "$SSID_RAW" ]  && SSID="$SSID_RAW"
            fi
        fi

        if [ "$RSSI" = "--" ] && [ -r "/proc/net/wireless" ]; then
            RSSI_RAW=$(grep "${WLAN_DEV}" /proc/net/wireless | awk '{print $4}' | cut -d. -f1)
            [ -n "$RSSI_RAW" ] && RSSI="${RSSI_RAW} dBm"
        fi

        printf '{"rssi":"%s","speed":"%s","freq":"%s","ssid":"%s"}\n' \
            "$RSSI" "$SPEED" "$FREQ" "$SSID"
        ;;

    # -----------------------------------------------------------------------
    "soft_reset")
        DTYPE=$(detect_driver_type)
        DNAME=$(get_driver_name)

        if [ "$DTYPE" = "builtin" ]; then
            printf '{"status":"builtin","driver_type":"builtin","driver_name":"%s","message":"Built-in driver (%s) cannot be reloaded at runtime. Config written — reboot required."}\n' \
                "$DNAME" "$DNAME"
            exit 0
        fi

        if [ "$DTYPE" = "unknown" ]; then
            log_json "warning" "Driver type undetermined. Skipping reload to avoid instability."
            exit 0
        fi

        DEVICE_PATH="${WLAN_SYS}/device"
        [ ! -L "$DEVICE_PATH" ] && { log_json "error" "wlan0 device path not found."; exit 1; }

        DEVICE=$(basename "$(readlink "${DEVICE_PATH}"        2>/dev/null)" 2>/dev/null)
        DRIVER=$(basename "$(readlink "${DEVICE_PATH}/driver" 2>/dev/null)" 2>/dev/null)
        BUS=$(basename    "$(readlink "${DEVICE_PATH}/subsystem" 2>/dev/null)" 2>/dev/null)

        if [ -z "$DEVICE" ] || [ -z "$DRIVER" ] || [ -z "$BUS" ]; then
            log_json "error" "Could not resolve device/driver/bus paths for reload."
            exit 1
        fi

        BIND_PATH="/sys/bus/${BUS}/drivers/${DRIVER}"
        [ ! -d "$BIND_PATH" ] && { log_json "error" "Bind path not found: ${BIND_PATH}"; exit 1; }

        svc wifi disable >/dev/null 2>&1
        sleep 1
        echo "$DEVICE" > "${BIND_PATH}/unbind" 2>/dev/null
        sleep 1
        echo "$DEVICE" > "${BIND_PATH}/bind"   2>/dev/null
        sleep 1
        svc wifi enable >/dev/null 2>&1

        printf '{"status":"success","driver_type":"modular","driver_name":"%s","message":"Driver %s reloaded on %s bus. Wi-Fi re-enabled."}\n' \
            "$DRIVER" "$DRIVER" "$BUS"
        ;;

    # -----------------------------------------------------------------------
    "get_mode")
        if [ -f "$MODDIR/mode_status.txt" ]; then
            printf '{"mode":"%s"}\n' "$(cat "$MODDIR/mode_status.txt")"
        else
            printf '{"mode":"stock"}\n'
        fi
        ;;

    # -----------------------------------------------------------------------
    *)
        log_json "error" "Unknown action: $1"
        exit 1
        ;;
esac
