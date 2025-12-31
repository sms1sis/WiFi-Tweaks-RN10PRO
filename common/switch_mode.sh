#!/system/bin/sh

# Wi-Fi Config Switcher Script (Hot-Reload Version)
# Improved logging, error handling, and dynamic patching

# --- Constants & Paths ---
readonly SCRIPT_NAME=$(basename "$0")
if echo "$0" | grep -q "/data/adb/modules/"; then
    readonly MODULE_DIR="/data/adb/modules/wifi_tweaks"
else
    # Fallback to current script location logic
    readonly SCRIPT_PATH=$(readlink -f "$0")
    readonly SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
    readonly MODULE_DIR=$(dirname "$SCRIPT_DIR")
fi

readonly MODULE_WIFI_DIR="${MODULE_DIR}/system/vendor/etc/wifi"
readonly INTERNAL_CONFIG_FILE="${MODULE_WIFI_DIR}/WCNSS_qcom_cfg.ini"
readonly SYSTEM_CONFIG_FILE="/vendor/etc/wifi/WCNSS_qcom_cfg.ini"
readonly ORIGINAL_STOCK_FILE="${MODULE_DIR}/common/original_stock.ini"

readonly MODE_CONFIG_FILE="${MODULE_DIR}/common/mode.conf"

readonly LOG_FILE="/data/local/tmp/wifi_tweaks.log"
readonly RESULT_FILE="/data/local/tmp/wifi_tweaks_result"

# Get version
readonly VERSION=$(grep "^version=" "${MODULE_DIR}/module.prop" | cut -d= -f2 || echo "Unknown")

# --- Logging Helper ---
log() {
    echo "[$(date +%T)] $1"
}

write_result() {
    echo "$1" > "$2"
    chmod 644 "$2"
}

# --- Core Functions ---

get_status() {
    if [ -f "${MODE_CONFIG_FILE}" ]; then
        cat "${MODE_CONFIG_FILE}"
    else
        echo "unknown"
    fi
}

get_stats() {
    # Suggestion 4: Real-time diagnostics
    local rssi="N/A"
    local speed="N/A"
    local freq="N/A"
    
    # Try using iw
    if command -v iw >/dev/null 2>&1; then
        local link_info=$(iw dev wlan0 link 2>/dev/null)
        if [ -n "$link_info" ]; then
            rssi=$(echo "$link_info" | grep "signal:" | awk '{print $2 " " $3}')
            speed=$(echo "$link_info" | grep "tx bitrate:" | cut -d: -f2 | xargs)
            freq=$(echo "$link_info" | grep "freq:" | awk '{print $2 " MHz"}')
        else
            rssi="Disconnected"
        fi
    else
        # Fallback to simple dumpsys check (less parsing, just existence)
        rssi="iw tool missing"
    fi
    
    echo "RSSI: $rssi | Speed: $speed | Freq: $freq"
}

apply_param() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    # If key exists (handling optional spaces), replace it. If not, append it.
    # Regex: Start of line, optional space, key, optional space, =, rest of line
    if grep -q "^\s*${key}\s*=" "$file"; then
        sed -i "s/^\s*${key}\s*=.*/${key}=${value}/" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

patch_config() {
    local mode="$1"
    local target="$2"
    
    log "[*] Patching config for mode: $mode"
    
    # Base params (Reset to known state if needed, but we start from stock)
    
    case "$mode" in
        "perf")
            # Performance Mode
            apply_param "$target" "gEnableBmps" "0"
            apply_param "$target" "gSetTxChainmask1x1" "0"
            apply_param "$target" "gSetRxChainmask1x1" "0"
            apply_param "$target" "TxPower2g" "15"
            apply_param "$target" "TxPower5g" "15"
            apply_param "$target" "gChannelBondingMode24GHz" "1"
            apply_param "$target" "gEnableGreenAp" "0"
            apply_param "$target" "gEnableEGAP" "0"
            apply_param "$target" "arp_ac_category" "3"
            ;;
        "balanced")
            # Balanced Mode
            apply_param "$target" "gEnableBmps" "1"
            apply_param "$target" "gSetTxChainmask1x1" "0"
            apply_param "$target" "gSetRxChainmask1x1" "0"
            
            apply_param "$target" "TxPower2g" "12"
            apply_param "$target" "TxPower5g" "12"
            apply_param "$target" "gChannelBondingMode24GHz" "1"
            apply_param "$target" "gEnableGreenAp" "1"
            apply_param "$target" "gEnableEGAP" "1"
            apply_param "$target" "arp_ac_category" "0"
            ;;
        "default"|"stock")
            # Stock/Default Mode
            log "[*] Using stock configuration."
            ;;
    esac
}

reload_driver() {
    log "[*] Starting driver reload sequence..."
    local modules="wlan qca_cld3_wlan qca_cld3"
    local reloaded=false
    local found_any=false

    if [ ! -f /proc/modules ]; then
        log "[!] /proc/modules missing. Assuming monolithic kernel."
        return 2
    fi

    for mod in $modules; do
        if lsmod 2>/dev/null | grep -q "^$mod "; then
            found_any=true
            log "[*] Found active module: $mod. Attempting reload..."
            
            ip link set wlan0 down 2>/dev/null
            sleep 0.5
            rmmod "$mod"
            sleep 1
            
            if lsmod 2>/dev/null | grep -q "^$mod "; then
                log "[!] Failed to unload $mod (Resource busy?)"
                continue
            fi
            
            local mod_path=""
            for path in "/vendor/lib/modules/$mod.ko" "/system/lib/modules/$mod.ko"; do
                if [ -f "$path" ]; then
                    mod_path="$path"
                    break
                fi
            done

            if [ -n "$mod_path" ]; then
                log "[*] Loading from: $mod_path"
                insmod "$mod_path"
            else
                log "[*] Loading via modprobe..."
                modprobe "$mod"
            fi
            
            sleep 1
            if lsmod 2>/dev/null | grep -q "^$mod "; then
                log "[+] $mod reloaded successfully."
                reloaded=true
            else
                log "[!] Failed to reload $mod."
            fi
        fi
    done

    if [ "$found_any" = false ]; then
        log "[!] No supported Wi-Fi modules found active."
        log "[?] System likely uses a Monolithic/Built-in Wi-Fi driver."
        return 2
    fi

    if [ "$reloaded" = false ]; then
        log "[!] Driver reload failed."
        return 1
    fi
    return 0
}

perform_switch() {
    local MODE="$1"
    
    log "[*] Operation: Switch to $MODE"
    log "[*] Version: $VERSION"
    
    if grep -q "susfs" /proc/filesystems; then
        log "[!] WARNING: SUSFS detected."
    fi

    # 1. Unmount existing config (to reveal stock or just to prepare for remount)
    log "[*] Unmounting existing overlay..."
    nsenter -t 1 -m -- umount "${SYSTEM_CONFIG_FILE}" 2>/dev/null
    
    # 2. Check/Create original stock backup
    # We do this AFTER unmount to ensure we copy the underlying system file,
    # not the overlay from a previous run or boot script.
    if [ ! -f "${ORIGINAL_STOCK_FILE}" ]; then
        log "[!] Original stock backup not found."
        log "[*] Creating backup from current system config..."
        cp "${SYSTEM_CONFIG_FILE}" "${ORIGINAL_STOCK_FILE}"
    fi
    
    # 3. Prepare Config via Patching
    log "[*] Generating config from stock base..."
    cp "${ORIGINAL_STOCK_FILE}" "${INTERNAL_CONFIG_FILE}"
    chmod 644 "${INTERNAL_CONFIG_FILE}"
    
    patch_config "$MODE" "${INTERNAL_CONFIG_FILE}"

    # 4. Bind Mount
    log "[*] Remounting config..."
    
    if nsenter -t 1 -m -- mount -o bind "${INTERNAL_CONFIG_FILE}" "${SYSTEM_CONFIG_FILE}"; then
        log "[+] Bind mount successful."
        if ! grep -q "${SYSTEM_CONFIG_FILE}" /proc/mounts; then
            log "[!] WARNING: Mount not visible in /proc/mounts."
        fi
    else
        log "[!] Bind mount failed."
    fi

    # 5. Persist Mode
    echo "${MODE}" > "${MODE_CONFIG_FILE}"

    # 6. Restart Driver/Service
    log "[*] Restarting Wi-Fi service..."
    svc wifi disable
    sleep 2

    reload_driver
    local RET=$?
    
    if [ $RET -eq 0 ]; then
        log "[+] Driver hot-reload successful."
        write_result "SUCCESS" "$RESULT_FILE"
    elif [ $RET -eq 2 ]; then
        log "[!] Hot-reload skipped (Built-in driver)."
        write_result "BUILTIN" "$RESULT_FILE"
    else
        log "[!] Hot-reload failed."
        write_result "FAILED" "$RESULT_FILE"
    fi

    svc wifi enable
    log "[*] Wi-Fi service enabled."
    log "[*] Switch operation completed."
    sync
}

# --- Entry Point ---

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Must run as root."
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 [perf|balanced|default|stock|status|stats]"
    exit 1
fi

CMD="$1"

if [ "$CMD" = "status" ]; then
    get_status
elif [ "$CMD" = "stats" ]; then
    get_stats
else
    # Setup Logging
    exec 3>&1
    exec > "$LOG_FILE" 2>&1
    chmod 644 "$LOG_FILE"

    echo "--- WiFi Tweaks Log $(date) ---"
    perform_switch "$CMD"

    # Restore stdout
    exec 1>&3 3>&-
fi

exit 0
