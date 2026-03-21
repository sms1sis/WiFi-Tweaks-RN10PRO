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

    # Resolve driver name first — needed by multiple checks below
    local driver_name=""
    [ -L "${DEVICE_PATH}/driver" ] && \
        driver_name=$(basename "$(readlink "${DEVICE_PATH}/driver" 2>/dev/null)" 2>/dev/null)

    # ---- BLOCKLIST: platform glue / connectivity subsystem drivers ----
    # These appear in /sys/module but are NOT the real Wi-Fi driver.
    # They are platform bus glue — unbinding them causes a kernel panic.
    #   icnss / icnss2  : Qualcomm SNOC/AHB integrated connectivity subsystem
    #   cnss  / cnss2   : Qualcomm PCIe connectivity subsystem
    #   wlan_platform   : Generic Qualcomm platform glue
    case "$driver_name" in
        icnss|icnss2|cnss|cnss2|wlan_platform)
            echo "builtin"
            return
            ;;
    esac

    # Check 1: /module symlink -> definitely a loadable .ko
    [ -L "${DEVICE_PATH}/driver/module" ] && echo "modular" && return

    # Check 2: /proc/config.gz — definitive source of truth
    # CONFIG_X=y -> compiled into kernel (builtin)
    # CONFIG_X=m -> loadable module (modular)
    if [ -n "$driver_name" ] && [ -r "/proc/config.gz" ]; then
        local cfg_key=""
        case "$driver_name" in
            wlan|qca_cld3_wlan|qca_cld_wlan) cfg_key="CONFIG_WLAN" ;;
            ath10k*)                          cfg_key="CONFIG_ATH10K" ;;
            ath11k*)                          cfg_key="CONFIG_ATH11K" ;;
            brcmfmac)                         cfg_key="CONFIG_BRCMFMAC" ;;
            bcmdhd)                           cfg_key="CONFIG_BCMDHD" ;;
            iwlwifi)                          cfg_key="CONFIG_IWLWIFI" ;;
        esac
        if [ -n "$cfg_key" ]; then
            local cfg_val
            cfg_val=$(zcat /proc/config.gz 2>/dev/null | grep "^${cfg_key}=" | cut -d= -f2)
            case "$cfg_val" in
                y) echo "builtin";  return ;;
                m) echo "modular";  return ;;
            esac
        fi
    fi

    # Check 3: /sys/module/<name>/sections directory
    # The kernel only creates sections/ for externally loaded .ko modules.
    # It is absent for drivers compiled in with CONFIG=y.
    # /sys/module/<name> itself exists for BOTH cases, so its mere presence
    # is not sufficient — this was the bug that caused the reboot on icnss.
    if [ -n "$driver_name" ] && [ "$driver_name" != "." ]; then
        if [ -d "/sys/module/${driver_name}" ]; then
            if [ -d "/sys/module/${driver_name}/sections" ]; then
                echo "modular" && return   # sections/ present -> real .ko
            else
                echo "builtin" && return   # no sections/ -> compiled in
            fi
        fi
    fi

    # Check 4: /proc/modules — only lists dynamically loaded modules.
    # If driver_name appears here it is definitely a loaded .ko.
    if [ -n "$driver_name" ] && [ -f "/proc/modules" ]; then
        grep -q "^${driver_name} " /proc/modules 2>/dev/null && echo "modular" && return
    fi

    # Check 5: scan known real Wi-Fi loadable module names in /proc/modules
    for kmod in qca_cld3_wlan qca_cld_wlan qca6390 wl bcmdhd ath10k_pci ath11k brcmfmac mt7921e iwlwifi; do
        grep -q "^${kmod} " /proc/modules 2>/dev/null && echo "modular" && return
    done

    # Check 6: subsystem bus type
    # Qualcomm icnss/cnss devices always sit on platform/soc bus
    if [ -L "${DEVICE_PATH}/subsystem" ]; then
        local subsys
        subsys=$(basename "$(readlink "${DEVICE_PATH}/subsystem" 2>/dev/null)" 2>/dev/null)
        case "$subsys" in
            platform|soc)     echo "builtin";  return ;;
            pci|usb|sdio|mmc) echo "modular";  return ;;
        esac
    fi

    # Check 7: lsmod — empty output (header only) means no loadable modules
    if command -v lsmod >/dev/null 2>&1; then
        local mod_count
        mod_count=$(lsmod 2>/dev/null | tail -n +2 | wc -l)
        [ "$mod_count" -eq 0 ] && echo "builtin" && return
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
    # IMPORTANT: Always patch the overlay source file inside the module tree,
    # NOT the live mounted path at /<rel>.
    #
    # KSU/Magisk bind-mounts $MODDIR/system/<rel> over /<rel> at boot.
    # On some devices (e.g. f2fs block device mounts) the live path
    # /<rel> resolves to the original read-only partition block device,
    # not the overlay file — so patching /<rel> modifies the wrong file.
    # The overlay source at $MODDIR/system/<rel> is always the correct target.

    if [ -f "$MODDIR/config_rel_path.txt" ]; then
        local rel
        rel=$(cat "$MODDIR/config_rel_path.txt")

        # 1. Overlay source (system/ prefix) — always patch this one
        local overlay_system="$MODDIR/system/${rel}"
        [ -f "$overlay_system" ] && echo "$overlay_system" && return

        # 2. Legacy incorrect path (pre-v5.0.4 installs without system/ prefix)
        local overlay_legacy="$MODDIR/${rel}"
        [ -f "$overlay_legacy" ] && echo "$overlay_legacy" && return
    fi

    # Fallback: search live paths (covers devices without config_rel_path.txt)
    for p in \
        /vendor/etc/wifi/WCNSS_qcom_cfg.ini \
        /system/vendor/etc/wifi/WCNSS_qcom_cfg.ini \
        /data/vendor/wifi/WCNSS_qcom_cfg.ini \
        /odm/vendor/etc/wifi/WCNSS_qcom_cfg.ini \
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
        sweetin)  resolved_device="sweet"  ;;
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

        # Update existing key (handles commented-out lines too) or insert before END marker
        if grep -qE "^[#[:space:]]*${key}[[:space:]]*=" "$config_file" 2>/dev/null; then
            sed -i "s|^[#[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$config_file"
        else
            # Insert before the END marker so the driver sees the new key.
            # If no END marker exists, append normally.
            if grep -q "^END" "$config_file" 2>/dev/null; then
                sed -i "s|^END|${key}=${value}\nEND|" "$config_file"
            else
                printf '%s=%s\n' "$key" "$value" >> "$config_file"
            fi
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

        export PATH=/vendor/bin:/system/bin:/system/xbin:$PATH

        # --- Method 1: cmd wifi status ---
        # Single-line WifiInfo output, available on all Android 11+
        # Format: WifiInfo: SSID: "name", ..., RSSI: -37, Link speed: 433Mbps, Frequency: 5745MHz, ...
        if command -v cmd >/dev/null 2>&1; then
            CMD_OUT=$(cmd wifi status 2>/dev/null | grep "^WifiInfo:")
            if [ -n "$CMD_OUT" ]; then
                SSID_RAW=$(printf '%s' "$CMD_OUT"  | grep -o 'SSID: "[^"]*"'      | head -1 | cut -d'"' -f2)
                RSSI_RAW=$(printf '%s' "$CMD_OUT"  | grep -o 'RSSI: -\{0,1\}[0-9]*' | head -1 | awk '{print $2}')
                FREQ_RAW=$(printf '%s' "$CMD_OUT"  | grep -o 'Frequency: [0-9]*'  | head -1 | awk '{print $2}')
                SPEED_RAW=$(printf '%s' "$CMD_OUT" | grep -o 'Link speed: [0-9]*' | head -1 | awk '{print $3}')
                [ -n "$SSID_RAW"  ] && SSID="$SSID_RAW"
                [ -n "$RSSI_RAW"  ] && RSSI="${RSSI_RAW} dBm"
                [ -n "$FREQ_RAW"  ] && FREQ="${FREQ_RAW} MHz"
                [ -n "$SPEED_RAW" ] && SPEED="${SPEED_RAW} Mbps"
            fi
        fi

        # --- Method 2: dumpsys wifi mWifiInfo (fallback) ---
        # Same single-line format, key is "mWifiInfo" on Android <=12
        if [ "$RSSI" = "--" ]; then
            if command -v dumpsys >/dev/null 2>&1; then
                DMP_OUT=$(dumpsys wifi 2>/dev/null | grep "^mWifiInfo")
                [ -z "$DMP_OUT" ] && DMP_OUT=$(dumpsys wifi 2>/dev/null | grep "^mConnectionInfo")
                if [ -n "$DMP_OUT" ]; then
                    SSID_RAW=$(printf '%s' "$DMP_OUT"  | grep -o 'SSID: "[^"]*"'      | head -1 | cut -d'"' -f2)
                    RSSI_RAW=$(printf '%s' "$DMP_OUT"  | grep -o 'RSSI: -\{0,1\}[0-9]*' | head -1 | awk '{print $2}')
                    FREQ_RAW=$(printf '%s' "$DMP_OUT"  | grep -o 'Frequency: [0-9]*'  | head -1 | awk '{print $2}')
                    SPEED_RAW=$(printf '%s' "$DMP_OUT" | grep -o 'Link speed: [0-9]*' | head -1 | awk '{print $3}')
                    [ -n "$SSID_RAW"  ] && [ "$SSID"  = "--" ] && SSID="$SSID_RAW"
                    [ -n "$RSSI_RAW"  ] && [ "$RSSI"  = "--" ] && RSSI="${RSSI_RAW} dBm"
                    [ -n "$FREQ_RAW"  ] && [ "$FREQ"  = "--" ] && FREQ="${FREQ_RAW} MHz"
                    [ -n "$SPEED_RAW" ] && [ "$SPEED" = "--" ] && SPEED="${SPEED_RAW} Mbps"
                fi
            fi
        fi

        printf '{"rssi":"%s","speed":"%s","freq":"%s","ssid":"%s"}\n' \
            "$RSSI" "$SPEED" "$FREQ" "$SSID"
        ;;    # -----------------------------------------------------------------------
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
    "get_driver_info")
        # Detailed driver evidence dump — for debugging detection on new devices
        DEVICE_PATH="${WLAN_SYS}/device"
        DNAME=$(get_driver_name)
        DTYPE=$(detect_driver_type)

        # /proc/config.gz
        KCONF_WLAN="unavailable"
        KCONF_DRIVER="unavailable"
        if [ -f "/proc/config.gz" ]; then
            KCONF_WLAN=$(zcat /proc/config.gz 2>/dev/null | grep "^CONFIG_WLAN=" | head -1 || echo "not_found")
            CFG_KEY=$(printf '%s' "$DNAME" | tr '[:lower:]' '[:upper:]')
            KCONF_DRIVER=$(zcat /proc/config.gz 2>/dev/null | grep "^CONFIG_${CFG_KEY}=" | head -1 || echo "not_found")
        fi

        # /sys/module sections
        SECTIONS="no_module_dir"
        [ -d "/sys/module/${DNAME}" ] && {
            [ -d "/sys/module/${DNAME}/sections" ] && SECTIONS="present" || SECTIONS="absent"
        }

        # /proc/modules
        PROC_MOD="not_found"
        [ -f "/proc/modules" ] && grep -q "^${DNAME} " /proc/modules 2>/dev/null && PROC_MOD="found"

        # /module symlink
        MOD_SYMLINK="absent"
        [ -L "${DEVICE_PATH}/driver/module" ] && MOD_SYMLINK="present"

        # subsystem
        SUBSYS="unknown"
        [ -L "${DEVICE_PATH}/subsystem" ] &&             SUBSYS=$(basename "$(readlink "${DEVICE_PATH}/subsystem" 2>/dev/null)" 2>/dev/null)

        # lsmod empty?
        LSMOD_EMPTY="unknown"
        [ -f "/proc/modules" ] && {
            [ -s "/proc/modules" ] && LSMOD_EMPTY="no" || LSMOD_EMPTY="yes"
        }

        printf '{"status":"success","driver_name":"%s","driver_type":"%s","kconf_wlan":"%s","kconf_driver":"%s","sys_module_sections":"%s","proc_modules_entry":"%s","module_symlink":"%s","subsystem":"%s","lsmod_empty":"%s"}
'             "$DNAME" "$DTYPE" "$KCONF_WLAN" "$KCONF_DRIVER" "$SECTIONS"             "$PROC_MOD" "$MOD_SYMLINK" "$SUBSYS" "$LSMOD_EMPTY"
        ;;

    # -----------------------------------------------------------------------
    "get_version")
        VERSION=$(grep "^version=" "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)
        [ -z "$VERSION" ] && VERSION="unknown"
        printf '{"status":"success","version":"%s"}\n' "$VERSION"
        ;;

    "get_mode")
        if [ -f "$MODDIR/mode_status.txt" ]; then
            printf '{"mode":"%s"}\n' "$(cat "$MODDIR/mode_status.txt")"
        else
            printf '{"mode":"stock"}\n'
        fi
        ;;

    # -----------------------------------------------------------------------
    "get_debug_info")
        # Dumps sysfs driver info and tests every stats method.
        # Run this when stats are empty or driver detection seems wrong.
        printf '=== Driver sysfs ===\n'
        printf 'driver symlink : %s\n' "$(readlink "${WLAN_SYS}/device/driver" 2>/dev/null || echo 'not found')"
        printf 'module symlink : %s\n' "$(readlink "${WLAN_SYS}/device/driver/module" 2>/dev/null || echo 'not found')"
        printf 'subsystem      : %s\n' "$(basename "$(readlink "${WLAN_SYS}/device/subsystem" 2>/dev/null)" 2>/dev/null || echo 'not found')"
        printf 'detect_result  : %s\n' "$(detect_driver_type)"
        printf '\n=== wpa_supplicant socket search ===\n'
        for WPA_SOCK in \
            "/data/vendor/wifi/wpa/wlan0" \
            "/data/vendor/wifi/wpa_supplicant/wlan0" \
            "/data/misc/wifi/sockets/wlan0" \
            "/var/run/wpa_supplicant/wlan0"; do
            if [ -S "$WPA_SOCK" ] || [ -e "$WPA_SOCK" ]; then
                printf 'FOUND  : %s\n' "$WPA_SOCK"
            else
                printf 'absent : %s\n' "$WPA_SOCK"
            fi
        done
        printf '\n=== wpa_cli signal_poll (vendor socket) ===\n'
        for WPA_SOCK in \
            "/data/vendor/wifi/wpa/wlan0" \
            "/data/vendor/wifi/wpa_supplicant/wlan0" \
            "/data/misc/wifi/sockets/wlan0"; do
            if [ -S "$WPA_SOCK" ] || [ -e "$WPA_SOCK" ]; then
                WPA_DIR=$(dirname "$WPA_SOCK")
                wpa_cli -i "$WLAN_DEV" -p "$WPA_DIR" signal_poll 2>&1 | head -6
                break
            fi
        done
        printf '\n=== /proc/net/wireless ===\n'
        cat /proc/net/wireless 2>/dev/null || printf 'not available\n'
        printf '\n=== iw dev wlan0 link ===\n'
        iw dev "$WLAN_DEV" link 2>/dev/null || printf 'iw not available or not connected\n'
        printf '\n=== dumpsys wifi (mWifiInfo) ===\n'
        dumpsys wifi 2>/dev/null | grep -A5 "mWifiInfo" | head -8 || printf 'dumpsys not available\n'
        ;;

    # -----------------------------------------------------------------------
    *)
        log_json "error" "Unknown action: $1"
        exit 1
        ;;
esac
