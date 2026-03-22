#!/system/bin/sh
# backend.sh - WiFi Config Switcher Backend (Generic Qualcomm Edition)
# Patch-based architecture: reads perf.patch / balanced.patch instead of hardcoded params
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin

MODDIR=${0%/*}
WLAN_DEV="wlan0"
WLAN_SYS="/sys/class/net/${WLAN_DEV}"

# Persistent state directory — survives module updates/reflashes.
# The module dir ($MODDIR) is wiped on each flash; /data/adb/wcs/ is not.
WCS_STATE_DIR="/data/adb/wcs"
MODE_FILE="${WCS_STATE_DIR}/mode_status.txt"
mkdir -p "$WCS_STATE_DIR" 2>/dev/null

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
                echo "stock" > "$MODE_FILE"
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
        echo "$MODE" > "$MODE_FILE"

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
        # mWifiInfo line may have leading whitespace on some Android versions
        if [ "$RSSI" = "--" ]; then
            if command -v dumpsys >/dev/null 2>&1; then
                DMP_OUT=$(dumpsys wifi 2>/dev/null | grep -m1 "mWifiInfo" | sed 's/^[[:space:]]*//')
                [ -z "$DMP_OUT" ] && DMP_OUT=$(dumpsys wifi 2>/dev/null | grep -m1 "mConnectionInfo" | sed 's/^[[:space:]]*//')
                if [ -n "$DMP_OUT" ]; then
                    SSID_RAW=$(printf '%s' "$DMP_OUT"  | grep -o 'SSID: "[^"]*"'         | head -1 | cut -d'"' -f2)
                    RSSI_RAW=$(printf '%s' "$DMP_OUT"  | grep -o 'RSSI: -\{0,1\}[0-9]*'  | head -1 | awk '{print $2}')
                    FREQ_RAW=$(printf '%s' "$DMP_OUT"  | grep -o 'Frequency: [0-9]*'      | head -1 | awk '{print $2}')
                    SPEED_RAW=$(printf '%s' "$DMP_OUT" | grep -o 'Link speed: [0-9]*'     | head -1 | awk '{print $3}')
                    [ -n "$SSID_RAW"  ] && [ "$SSID"  = "--" ] && SSID="$SSID_RAW"
                    [ -n "$RSSI_RAW"  ] && [ "$RSSI"  = "--" ] && RSSI="${RSSI_RAW} dBm"
                    [ -n "$FREQ_RAW"  ] && [ "$FREQ"  = "--" ] && FREQ="${FREQ_RAW} MHz"
                    [ -n "$SPEED_RAW" ] && [ "$SPEED" = "--" ] && SPEED="${SPEED_RAW} Mbps"
                fi
            fi
        fi

        # --- Method 3: wpa_cli signal_poll ---
        if [ "$RSSI" = "--" ]; then
            for WPA_SOCK in \
                "/data/vendor/wifi/wpa/sockets/wlan0" \
                "/data/vendor/wifi/wpa/wlan0" \
                "/data/vendor/wifi/wpa_supplicant/sockets/wlan0" \
                "/data/vendor/wifi/wpa_supplicant/wlan0" \
                "/data/misc/wifi/sockets/wlan0"; do
                [ -S "$WPA_SOCK" ] || [ -e "$WPA_SOCK" ] || continue
                WPA_DIR=$(dirname "$WPA_SOCK")
                POLL=$(wpa_cli -i "$WLAN_DEV" -p "$WPA_DIR" signal_poll 2>/dev/null)
                if [ -n "$POLL" ]; then
                    RSSI_RAW=$(printf '%s' "$POLL" | grep "^RSSI="    | cut -d= -f2)
                    FREQ_RAW=$(printf '%s' "$POLL" | grep "^FREQUENCY="| cut -d= -f2)
                    SPEED_RAW=$(printf '%s' "$POLL"| grep "^LINKSPEED="| cut -d= -f2)
                    [ -n "$RSSI_RAW"  ] && RSSI="${RSSI_RAW} dBm"
                    [ -n "$FREQ_RAW"  ] && FREQ="${FREQ_RAW} MHz"
                    [ -n "$SPEED_RAW" ] && SPEED="${SPEED_RAW} Mbps"
                fi
                # Get SSID from wpa_cli status
                STATUS=$(wpa_cli -i "$WLAN_DEV" -p "$WPA_DIR" status 2>/dev/null)
                SSID_RAW=$(printf '%s' "$STATUS" | grep "^ssid=" | cut -d= -f2)
                [ -n "$SSID_RAW" ] && [ "$SSID" = "--" ] && SSID="$SSID_RAW"
                break
            done
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
        [ -L "${DEVICE_PATH}/subsystem" ] && \
            SUBSYS=$(basename "$(readlink "${DEVICE_PATH}/subsystem" 2>/dev/null)" 2>/dev/null)

        # lsmod empty?
        LSMOD_EMPTY="unknown"
        [ -f "/proc/modules" ] && {
            [ -s "/proc/modules" ] && LSMOD_EMPTY="no" || LSMOD_EMPTY="yes"
        }

        # ── Chip identification ──────────────────────────────────────────────

        # 1. PCI vendor:device ID (most precise — QCA6390=17cb:1101, WCN6855=17cb:1103, etc.)
        CHIP_PCI="unknown"
        for pci_dev in /sys/bus/pci/devices/*/; do
            if [ -f "${pci_dev}class" ]; then
                cls=$(cat "${pci_dev}class" 2>/dev/null)
                # PCI class 0x028000 = Network / Wireless
                case "$cls" in
                    0x028000|0x028900|0x020000)
                        vid=$(cat "${pci_dev}vendor" 2>/dev/null | sed 's/0x//')
                        did=$(cat "${pci_dev}device" 2>/dev/null | sed 's/0x//')
                        CHIP_PCI="${vid}:${did}"
                        break
                        ;;
                esac
            fi
        done

        # 2. SDIO/MMC modalias (QCA6174=sdio:c00v02D0d0301, etc.)
        CHIP_SDIO="unknown"
        for mmc_dev in /sys/bus/sdio/devices/*/; do
            [ -f "${mmc_dev}modalias" ] && {
                CHIP_SDIO=$(cat "${mmc_dev}modalias" 2>/dev/null)
                break
            }
        done
        # Also check mmc bus directly
        if [ "$CHIP_SDIO" = "unknown" ]; then
            for mmc_dev in /sys/bus/mmc/devices/mmc*/*/; do
                [ -f "${mmc_dev}modalias" ] && {
                    CHIP_SDIO=$(cat "${mmc_dev}modalias" 2>/dev/null)
                    break
                }
            done
        fi

        # 3. Device-tree compatible string (e.g. "qcom,wcn3990-wifi", "qcom,qca6390")
        CHIP_DT="unknown"
        for dt_compat in \
            "${DEVICE_PATH}/of_node/compatible" \
            "${DEVICE_PATH}/../of_node/compatible" \
            "/sys/firmware/devicetree/base/soc/wifi/compatible" \
            "/sys/firmware/devicetree/base/soc/qcom,wcnss-wlan/compatible"; do
            [ -f "$dt_compat" ] && {
                CHIP_DT=$(cat "$dt_compat" 2>/dev/null | tr '\0' ',' | sed 's/,$//')
                [ -n "$CHIP_DT" ] && break
            }
        done
        # Also search all DT nodes for wcn/wlan/qca compatible strings
        if [ "$CHIP_DT" = "unknown" ] || printf '%s' "$CHIP_DT" | grep -q "^qcom,icnss"; then
            DT_SEARCH=$(find /sys/firmware/devicetree/base -name "compatible" 2>/dev/null \
                | xargs grep -rl "wcn\|qca.*wifi\|wil6" 2>/dev/null | head -1)
            [ -n "$DT_SEARCH" ] && \
                CHIP_DT=$(cat "$DT_SEARCH" 2>/dev/null | tr '\0' ',' | sed 's/,$//')
        fi

        # 3b. SoC identity — key for SNOC/icnss devices (WCN3990 lives on SDM660/SDM665/etc.)
        SOC_ID="unknown"
        SOC_MACHINE="unknown"
        SOC_FAMILY="unknown"
        [ -f "/sys/devices/soc0/soc_id"  ] && SOC_ID=$(cat /sys/devices/soc0/soc_id 2>/dev/null)
        [ -f "/sys/devices/soc0/machine" ] && SOC_MACHINE=$(cat /sys/devices/soc0/machine 2>/dev/null)
        [ -f "/sys/devices/soc0/family"  ] && SOC_FAMILY=$(cat /sys/devices/soc0/family 2>/dev/null)

        # 3c. BDF (board data file) — filename encodes chip + board variant
        # Sourced from firmware dir or dmesg cnss-daemon log
        BDF_FILE="unknown"
        # Check firmware directory
        for fw_dir in /vendor/firmware/wlan/qca_cld /vendor/firmware/wlan \
                      /firmware/wlan /vendor/etc/wifi; do
            bdf=$(ls "${fw_dir}"/bdf_*.bin 2>/dev/null | head -1)
            [ -n "$bdf" ] && { BDF_FILE=$(basename "$bdf"); break; }
        done
        # Fallback: dmesg BDF log line from cnss-daemon
        if [ "$BDF_FILE" = "unknown" ]; then
            BDF_FILE=$(dmesg 2>/dev/null \
                | grep -i "wlfw_send_bdf_download_req.*bdf_\|BDF file.*bdf_" \
                | grep -v "regdb" \
                | tail -1 \
                | grep -o 'bdf[^[:space:]]*\.bin' | head -1)
            [ -z "$BDF_FILE" ] && BDF_FILE="unknown"
        fi

        # 3d. WCSS memory address from icnss device path — unique per SoC
        WCSS_ADDR="unknown"
        icnss_dev=$(find /sys/devices -maxdepth 5 -name "*icnss*" -type d 2>/dev/null | head -1)
        if [ -n "$icnss_dev" ]; then
            WCSS_ADDR=$(basename "$icnss_dev" | grep -o '[0-9a-f]*\.qcom,icnss' | cut -d. -f1)
            [ -z "$WCSS_ADDR" ] && WCSS_ADDR="unknown"
        fi

        # 4. Firmware version from wpa_cli / iw
        FW_VER="unknown"
        for WPA_SOCK in \
            "/data/vendor/wifi/wpa/sockets/wlan0" \
            "/data/vendor/wifi/wpa/wlan0" \
            "/data/vendor/wifi/wpa_supplicant/sockets/wlan0" \
            "/data/vendor/wifi/wpa_supplicant/wlan0" \
            "/data/misc/wifi/sockets/wlan0"; do
            [ -S "$WPA_SOCK" ] || [ -e "$WPA_SOCK" ] || continue
            WPA_DIR=$(dirname "$WPA_SOCK")
            FW_VER=$(wpa_cli -i "$WLAN_DEV" -p "$WPA_DIR" status 2>/dev/null \
                | grep -i "^fw_version\|^firmware_version\|^wifi_generation" \
                | head -1 | cut -d= -f2 | tr -d ' ')
            [ -n "$FW_VER" ] && break
        done
        # Fallback: iw dev info
        if [ "$FW_VER" = "unknown" ] || [ -z "$FW_VER" ]; then
            FW_VER=$(iw dev "$WLAN_DEV" info 2>/dev/null \
                | grep -i "firmware\|wiphy" | head -1 | sed 's/^[[:space:]]*//')
            [ -z "$FW_VER" ] && FW_VER="unknown"
        fi

        # 5. Hardware revision from sysfs uevent
        CHIP_HW_REV="unknown"
        if [ -f "${DEVICE_PATH}/uevent" ]; then
            CHIP_HW_REV=$(grep -i "^PCI_ID\|^SDIO_ID\|^OF_COMPATIBLE\|^DRIVER\b" \
                "${DEVICE_PATH}/uevent" 2>/dev/null | head -3 | tr '\n' ' ')
            [ -z "$CHIP_HW_REV" ] && CHIP_HW_REV="unknown"
        fi

        # 6. Chip name lookup — PCI ID first, then SoC ID for SNOC devices, then DT
        CHIP_NAME="unknown"
        case "$CHIP_PCI" in
            17cb:1101) CHIP_NAME="QCA6390" ;;
            17cb:1103) CHIP_NAME="WCN6855" ;;
            17cb:1104) CHIP_NAME="WCN6750" ;;
            17cb:1110) CHIP_NAME="QCA6490" ;;
            17cb:1112) CHIP_NAME="WCN7850" ;;
            17cb:0042) CHIP_NAME="QCA6174A" ;;
            168c:003e) CHIP_NAME="QCA6174" ;;
            168c:0041) CHIP_NAME="QCA9377" ;;
            168c:0042) CHIP_NAME="QCA9984" ;;
            168c:0046) CHIP_NAME="QCA9887" ;;
            168c:0056) CHIP_NAME="QCA9888" ;;
            168c:0050) CHIP_NAME="QCA10.2" ;;
            *:*)       CHIP_NAME="PCI-${CHIP_PCI}" ;;
        esac

        # SNOC/icnss devices have no PCI — identify by SoC ID instead.
        # Source: linux/drivers/soc/qcom/socinfo.c + linux/include/dt-bindings/arm/qcom,ids.h
        # Wi-Fi chip per SoC sourced from Qualcomm product pages and kernel DT files.
        #
        # WCN3615/WCN3620  — MSM8916/MSM8952/MSM8953 era (SNOC, very old)
        # WCN3680B          — SDM630/660/636 (SNOC)
        # WCN3990           — SDM665/SDM710/SM6150/SM6125/SM6115 (SNOC)
        # WCN3980           — SDM845 (SNOC)
        # WCN3998           — SM8150/SM7150/SM8250/SM7225 (SNOC)
        # WCN6750           — SM6375/SM7325/SM7350 (SNOC, Wi-Fi 6E)
        # WCN6855           — SM8350/SM8450/SM8475/SM7450 (PCIe primary, SNOC fallback)
        # WCN7850/WCN7851  — SM8550/SM8650/SM8750/SM7550/SM7675 (PCIe primary, SNOC fallback)
        if [ "$CHIP_NAME" = "unknown" ] && [ "$DNAME" = "icnss" -o "$SUBSYS" = "platform" ]; then
            case "$SOC_ID" in
                # ── MSM8x era (WCN3620) ───────────────────────────────────────
                206)  CHIP_NAME="WCN3620 (MSM8916)" ;;
                233)  CHIP_NAME="WCN3620 (MSM8936)" ;;
                239)  CHIP_NAME="WCN3620 (MSM8939)" ;;
                264)  CHIP_NAME="WCN3620 (MSM8952)" ;;
                246)  CHIP_NAME="WCN3660B (MSM8996)" ;;
                # ── SDM4xx budget era (WCN3615) ───────────────────────────────
                293)  CHIP_NAME="WCN3615 (MSM8937/SDM430)" ;;
                294)  CHIP_NAME="WCN3615 (MSM8940)" ;;
                303)  CHIP_NAME="WCN3615 (MSM8953/SDM450)" ;;
                338)  CHIP_NAME="WCN3615 (SDM632)" ;;
                # ── SDM630/660/636 (WCN3680B) ─────────────────────────────────
                317|318) CHIP_NAME="WCN3680B (SDM660)" ;;
                349|351) CHIP_NAME="WCN3680B (SDM636)" ;;
                345)     CHIP_NAME="WCN3680B (SDM630)" ;;
                # ── SDM710/712 (WCN3990) ──────────────────────────────────────
                360)  CHIP_NAME="WCN3990 (SDM710)" ;;
                393)  CHIP_NAME="WCN3990 (SDM712)" ;;
                # ── SDM675 (WCN3990) ──────────────────────────────────────────
                355)  CHIP_NAME="WCN3990 (SDM675)" ;;
                # ── SDM845 (WCN3980) ──────────────────────────────────────────
                321)  CHIP_NAME="WCN3980 (SDM845)" ;;
                # ── SDM665/Trinket vs SD732G/Lagoon — both report SoC ID 394 ──
                # Disambiguate using machine name
                394)
                    case "$SOC_MACHINE" in
                        TRINKET|trinket) CHIP_NAME="WCN3990 (SDM665/Trinket)" ;;
                        LAGOON|lagoon)   CHIP_NAME="WCN3998 (SD732G/Lagoon)" ;;
                        *)               CHIP_NAME="WCN3990/WCN3998 (SoC 394/${SOC_MACHINE})" ;;
                    esac
                    ;;
                407)  CHIP_NAME="WCN3990 (SDM662)" ;;
                441)  CHIP_NAME="WCN3990 (SM6125/Trinket+)" ;;
                # ── SM6150 family (WCN3990) ───────────────────────────────────
                400)  CHIP_NAME="WCN3990 (SM6150)" ;;
                440)  CHIP_NAME="WCN3990 (SM6150P)" ;;
                # ── SM6125/Bengal family (WCN3990) ────────────────────────────
                417)  CHIP_NAME="WCN3990 (SM6125/Bengal)" ;;
                443)  CHIP_NAME="WCN3990 (SM6115/Bengalp)" ;;
                518)  CHIP_NAME="WCN3990 (SM6115/Khaje)" ;;
                # ── SM6225/SM6350/SM6375 ──────────────────────────────────────
                384)  CHIP_NAME="WCN3990 (SM6350)" ;;
                457)  CHIP_NAME="WCN3990 (SM6225/SDM680)" ;;
                458)  CHIP_NAME="WCN6750 (SM6375)" ;;
                # ── SM8150/SM7150 (WCN3998) ───────────────────────────────────
                356)  CHIP_NAME="WCN3998 (SM8150/Kona)" ;;
                365)  CHIP_NAME="WCN3998 (SM7150)" ;;
                366)  CHIP_NAME="WCN3998 (SM7150P)" ;;
                # ── SM8250/SM7225 (WCN3998) ───────────────────────────────────
                415)  CHIP_NAME="WCN3998 (SM8250/Kona)" ;;
                434)  CHIP_NAME="WCN3998 (SM7225)" ;;
                # ── SM7325/SM7350 (WCN6750) ───────────────────────────────────
                450)  CHIP_NAME="WCN6750 (SM7325/Yupik)" ;;
                459)  CHIP_NAME="WCN6750 (SM7325P)" ;;
                480)  CHIP_NAME="WCN6750 (SM7350/Cedros)" ;;
                # ── SM8350/SM8450/SM8475/SM7450 (WCN6855, PCIe fallback) ──────
                439)  CHIP_NAME="WCN6855 (SM8350/Lahaina)" ;;
                456)  CHIP_NAME="WCN6855 (SM8450/Waipio)" ;;
                506)  CHIP_NAME="WCN6855 (SM7450/Waipio-lite)" ;;
                482)  CHIP_NAME="WCN6855 (SM8475)" ;;
                530)  CHIP_NAME="WCN6855 (SM7475)" ;;
                # ── SM8550/SM7550 (WCN7850, PCIe fallback) ───────────────────
                519)  CHIP_NAME="WCN7850 (SM8550/Kalama)" ;;
                536)  CHIP_NAME="WCN7850 (SM8550P)" ;;
                557)  CHIP_NAME="WCN7850 (SM7550)" ;;
                # ── SM8650/SM7675 (WCN7850, PCIe fallback) ───────────────────
                591)  CHIP_NAME="WCN7850 (SM8650/Pineapple)" ;;
                554)  CHIP_NAME="WCN7850 (SM7675)" ;;
                # ── SM8750 (WCN7851, PCIe fallback) ──────────────────────────
                603)  CHIP_NAME="WCN7851 (SM8750/Sun)" ;;
                # ── QCM/QCS industrial variants ──────────────────────────────
                347)  CHIP_NAME="WCN3990 (QCS605)" ;;
                # ── Fallback: WCSS address ────────────────────────────────────
                *)
                    case "$WCSS_ADDR" in
                        c800000)  CHIP_NAME="WCN3990 (SNOC@c800000)" ;;
                        18800000) CHIP_NAME="WCN3998 (SNOC@18800000)" ;;
                        a000000)  CHIP_NAME="WCN3990 (SNOC@a000000)" ;;
                        18900000) CHIP_NAME="WCN6750 (SNOC@18900000)" ;;
                        *)
                            [ -n "$SOC_ID" ] && [ "$SOC_ID" != "unknown" ] && \
                                CHIP_NAME="WCN-SNOC (SoC ${SOC_ID})" ;;
                    esac
                    ;;
            esac
        fi

        # Fallback: extract chip name token from DT compatible
        if [ "$CHIP_NAME" = "unknown" ] && [ "$CHIP_DT" != "unknown" ]; then
            CHIP_NAME=$(printf '%s' "$CHIP_DT" \
                | grep -o 'qca[0-9a-zA-Z_-]*\|wcn[0-9a-zA-Z_-]*\|qcn[0-9a-zA-Z_-]*\|wil[0-9a-zA-Z_-]*' \
                | head -1 | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            [ -z "$CHIP_NAME" ] && CHIP_NAME="unknown"
        fi

        # Escape values for JSON (strip quotes and newlines)
        _esc() { printf '%s' "$1" | tr -d '"' | tr '\n' ' ' | sed 's/[[:space:]]*$//'; }

        printf '{"status":"success","driver_name":"%s","driver_type":"%s","kconf_wlan":"%s","kconf_driver":"%s","sys_module_sections":"%s","proc_modules_entry":"%s","module_symlink":"%s","subsystem":"%s","lsmod_empty":"%s","chip_name":"%s","chip_pci_id":"%s","chip_sdio_id":"%s","chip_dt_compat":"%s","fw_version":"%s","hw_uevent":"%s","soc_id":"%s","soc_machine":"%s","soc_family":"%s","bdf_file":"%s","wcss_addr":"%s"}\n' \
            "$(_esc "$DNAME")" "$(_esc "$DTYPE")" \
            "$(_esc "$KCONF_WLAN")" "$(_esc "$KCONF_DRIVER")" \
            "$(_esc "$SECTIONS")" "$(_esc "$PROC_MOD")" \
            "$(_esc "$MOD_SYMLINK")" "$(_esc "$SUBSYS")" "$(_esc "$LSMOD_EMPTY")" \
            "$(_esc "$CHIP_NAME")" "$(_esc "$CHIP_PCI")" \
            "$(_esc "$CHIP_SDIO")" "$(_esc "$CHIP_DT")" \
            "$(_esc "$FW_VER")" "$(_esc "$CHIP_HW_REV")" \
            "$(_esc "$SOC_ID")" "$(_esc "$SOC_MACHINE")" "$(_esc "$SOC_FAMILY")" \
            "$(_esc "$BDF_FILE")" "$(_esc "$WCSS_ADDR")"
        ;;

    # -----------------------------------------------------------------------
    "get_version")
        VERSION=$(grep "^version=" "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)
        [ -z "$VERSION" ] && VERSION="unknown"
        printf '{"status":"success","version":"%s"}\n' "$VERSION"
        ;;

    # -----------------------------------------------------------------------
    "read_config")
        CONFIG_FILE=$(find_wifi_config)
        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Config file not found."
            exit 1
        fi
        LINES=$(wc -l < "$CONFIG_FILE" 2>/dev/null || echo 0)
        # Encode content as base64 to safely pass through JSON
        CONTENT=$(base64 "$CONFIG_FILE" 2>/dev/null | tr -d '\n')
        printf '{"status":"success","path":"%s","lines":%s,"content":"%s"}\n'             "$CONFIG_FILE" "$LINES" "$CONTENT"
        ;;

    # -----------------------------------------------------------------------
    "write_config")
        # $2 is base64-encoded config content
        B64="$2"
        if [ -z "$B64" ]; then
            log_json "error" "No content provided."
            exit 1
        fi
        CONFIG_FILE=$(find_wifi_config)
        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Config file not found."
            exit 1
        fi
        # Backup before first write if not already done
        [ ! -f "${CONFIG_FILE}.bak" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        # Decode and write
        printf '%s' "$B64" | base64 -d > "$CONFIG_FILE" 2>/dev/null
        if [ $? -ne 0 ]; then
            log_json "error" "Failed to decode or write config."
            exit 1
        fi
        sync
        LINES=$(wc -l < "$CONFIG_FILE" 2>/dev/null || echo 0)
        printf '{"status":"success","message":"Config written.","lines":%s}\n' "$LINES"
        ;;

    # -----------------------------------------------------------------------
    "restore_backup")
        CONFIG_FILE=$(find_wifi_config)
        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Config file not found."
            exit 1
        fi
        if [ ! -f "${CONFIG_FILE}.bak" ]; then
            log_json "error" "No backup found. Apply a profile first to create one."
            exit 1
        fi
        cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
        sync
        log_json "success" "Stock backup restored."
        ;;

    # -----------------------------------------------------------------------
    "get_mode")
        if [ -f "$MODE_FILE" ]; then
            printf '{"mode":"%s"}\n' "$(cat "$MODE_FILE")"
        else
            printf '{"mode":"stock"}\n'
        fi
        ;;

    # -----------------------------------------------------------------------
    "get_debug_info_json")
        # Same as get_debug_info but base64-encoded inside JSON so it
        # travels safely through runAction() without buffer truncation.
        DEBUG_OUT=$(
            printf '=== Chip identification ===\n'
            DEVICE_PATH="${WLAN_SYS}/device"
            for pci_dev in /sys/bus/pci/devices/*/; do
                [ -f "${pci_dev}class" ] || continue
                cls=$(cat "${pci_dev}class" 2>/dev/null)
                case "$cls" in
                    0x028000|0x028900|0x020000)
                        printf 'pci vendor:device : %s:%s\n' \
                            "$(cat "${pci_dev}vendor" 2>/dev/null)" \
                            "$(cat "${pci_dev}device" 2>/dev/null)"
                        break ;;
                esac
            done
            for mmc_dev in /sys/bus/sdio/devices/*/ /sys/bus/mmc/devices/mmc*/*/; do
                [ -f "${mmc_dev}modalias" ] && \
                    printf 'sdio modalias     : %s\n' "$(cat "${mmc_dev}modalias" 2>/dev/null)" && break
            done
            for dt_compat in \
                "${DEVICE_PATH}/of_node/compatible" \
                "${DEVICE_PATH}/../of_node/compatible" \
                "/sys/firmware/devicetree/base/soc/wifi/compatible"; do
                [ -f "$dt_compat" ] && \
                    printf 'dt compatible     : %s\n' "$(cat "$dt_compat" 2>/dev/null | tr '\0' ',')" && break
            done
            [ -f "${DEVICE_PATH}/uevent" ] && \
                printf 'uevent:\n' && \
                cat "${DEVICE_PATH}/uevent" 2>/dev/null | head -8 | sed 's/^/  /'

            printf '\n=== SoC identity ===\n'
            printf 'soc_id   : %s\n' "$(cat /sys/devices/soc0/soc_id  2>/dev/null || echo 'unknown')"
            printf 'machine  : %s\n' "$(cat /sys/devices/soc0/machine 2>/dev/null || echo 'unknown')"
            printf 'family   : %s\n' "$(cat /sys/devices/soc0/family  2>/dev/null || echo 'unknown')"

            printf '\n=== Driver sysfs ===\n'
            printf 'driver symlink : %s\n' "$(readlink "${WLAN_SYS}/device/driver" 2>/dev/null || echo 'not found')"
            printf 'module symlink : %s\n' "$(readlink "${WLAN_SYS}/device/driver/module" 2>/dev/null || echo 'not found')"
            printf 'subsystem      : %s\n' "$(basename "$(readlink "${WLAN_SYS}/device/subsystem" 2>/dev/null)" 2>/dev/null || echo 'not found')"
            printf 'detect_result  : %s\n' "$(detect_driver_type)"

            printf '\n=== BDF / firmware ===\n'
            for fw_dir in /vendor/firmware/wlan/qca_cld /vendor/firmware/wlan /firmware/wlan; do
                [ -d "$fw_dir" ] && ls "$fw_dir" 2>/dev/null | head -10 | sed "s|^|  ${fw_dir}/|" && break
            done

            printf '\n=== wpa_supplicant sockets ===\n'
            for WPA_SOCK in \
                "/data/vendor/wifi/wpa/sockets/wlan0" \
                "/data/vendor/wifi/wpa/wlan0" \
                "/data/vendor/wifi/wpa_supplicant/sockets/wlan0" \
                "/data/vendor/wifi/wpa_supplicant/wlan0" \
                "/data/misc/wifi/sockets/wlan0" \
                "/var/run/wpa_supplicant/wlan0"; do
                if [ -S "$WPA_SOCK" ] || [ -e "$WPA_SOCK" ]; then
                    printf 'FOUND  : %s\n' "$WPA_SOCK"
                else
                    printf 'absent : %s\n' "$WPA_SOCK"
                fi
            done

            printf '\n=== wpa_cli signal_poll ===\n'
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

            printf '\n=== current connection ===\n'
            # Extract clean current-state block — stop before the event log (rec[)
            DUMPSYS_OUT=$(dumpsys wifi 2>/dev/null | sed '/rec\[/,$d')
            if [ -n "$DUMPSYS_OUT" ]; then
                printf '%s\n' "$DUMPSYS_OUT" | grep -E \
                    "SSID|BSSID|linkSpeed|rssi|frequency|signalLevel|networkId|ipAddress|macAddress|WifiInfo|curState|mNetworkAgent" \
                    | grep -v "rec\[" | head -20
            else
                printf 'dumpsys not available\n'
            fi
        )
        ENCODED=$(printf '%s' "$DEBUG_OUT" | base64 2>/dev/null | tr -d '\n')
        printf '{"status":"success","content":"%s"}\n' "$ENCODED"
        ;;

    # -----------------------------------------------------------------------
    "get_debug_info")
        # Dumps sysfs driver info and tests every stats method.
        # Run this when stats are empty or driver detection seems wrong.
        printf '=== Chip identification ===\n'
        DEVICE_PATH="${WLAN_SYS}/device"
        # PCI
        for pci_dev in /sys/bus/pci/devices/*/; do
            [ -f "${pci_dev}class" ] || continue
            cls=$(cat "${pci_dev}class" 2>/dev/null)
            case "$cls" in
                0x028000|0x028900|0x020000)
                    printf 'pci vendor:device : %s:%s\n' \
                        "$(cat "${pci_dev}vendor" 2>/dev/null)" \
                        "$(cat "${pci_dev}device" 2>/dev/null)"
                    break ;;
            esac
        done
        # SDIO
        for mmc_dev in /sys/bus/sdio/devices/*/ /sys/bus/mmc/devices/mmc*/*/; do
            [ -f "${mmc_dev}modalias" ] && printf 'sdio modalias     : %s\n' "$(cat "${mmc_dev}modalias" 2>/dev/null)" && break
        done
        # DT compatible
        for dt_compat in \
            "${DEVICE_PATH}/of_node/compatible" \
            "${DEVICE_PATH}/../of_node/compatible" \
            "/sys/firmware/devicetree/base/soc/wifi/compatible"; do
            [ -f "$dt_compat" ] && printf 'dt compatible     : %s\n' "$(cat "$dt_compat" 2>/dev/null | tr '\0' ',')" && break
        done
        # uevent
        [ -f "${DEVICE_PATH}/uevent" ] && printf 'uevent            :\n' && cat "${DEVICE_PATH}/uevent" 2>/dev/null | head -8 | sed 's/^/  /'
        printf '\n=== Driver sysfs ===\n'
        printf 'driver symlink : %s\n' "$(readlink "${WLAN_SYS}/device/driver" 2>/dev/null || echo 'not found')"
        printf 'module symlink : %s\n' "$(readlink "${WLAN_SYS}/device/driver/module" 2>/dev/null || echo 'not found')"
        printf 'subsystem      : %s\n' "$(basename "$(readlink "${WLAN_SYS}/device/subsystem" 2>/dev/null)" 2>/dev/null || echo 'not found')"
        printf 'detect_result  : %s\n' "$(detect_driver_type)"
        printf '\n=== wpa_supplicant socket search ===\n'
        for WPA_SOCK in \
            "/data/vendor/wifi/wpa/sockets/wlan0" \
            "/data/vendor/wifi/wpa/wlan0" \
            "/data/vendor/wifi/wpa_supplicant/sockets/wlan0" \
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
        printf '\n=== current connection ===\n'
        DUMPSYS_OUT=$(dumpsys wifi 2>/dev/null | sed '/rec\[/,$d')
        if [ -n "$DUMPSYS_OUT" ]; then
            printf '%s\n' "$DUMPSYS_OUT" | grep -E \
                "SSID|BSSID|linkSpeed|rssi|frequency|signalLevel|networkId|ipAddress|macAddress|WifiInfo|curState|mNetworkAgent" \
                | grep -v "rec\[" | head -20
        else
            printf 'dumpsys not available\n'
        fi
        ;;

    # -----------------------------------------------------------------------
    *)
        log_json "error" "Unknown action: $1"
        exit 1
        ;;
esac
