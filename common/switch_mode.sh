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
readonly CUSTOM_CONFIG_FILE="${MODULE_DIR}/common/custom.ini"

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
    local rssi="N/A"
    local speed="N/A"
    local freq="N/A"
    
    # Try using iw (Preferred)
    if command -v iw >/dev/null 2>&1; then
        local link_info=$(iw dev wlan0 link 2>/dev/null)
        if [ -n "$link_info" ]; then
            # Parse all info in one pass from the variable
            rssi=$(echo "$link_info" | awk '/signal:/ {print $2 " " $3}')
            speed=$(echo "$link_info" | awk '/tx bitrate:/ {print $3 " " $4}')
            freq=$(echo "$link_info" | awk '/freq:/ {print $2 " MHz"}')
        else
            rssi="Disconnected"
        fi
    elif command -v dumpsys >/dev/null 2>&1; then
        # Fallback to dumpsys wifi
        local dump=$(dumpsys wifi | grep -E "RSSI:|Link speed:|Frequency:")
        if [ -n "$dump" ]; then
            rssi=$(echo "$dump" | grep "RSSI:" | awk '{print $2 " dBm"}')
            speed=$(echo "$dump" | grep "Link speed:" | awk '{print $3 " " $4}')
            freq=$(echo "$dump" | grep "Frequency:" | awk '{print $2 " MHz"}')
        else
            rssi="No iw/dumpsys data"
        fi
    else
        rssi="Tools missing"
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
        "custom")
            # Custom Mode
            if [ -f "${CUSTOM_CONFIG_FILE}" ]; then
                log "[*] Loading custom configuration..."
                cp "${CUSTOM_CONFIG_FILE}" "$target"
            else
                log "[!] Custom config not found! Falling back to stock."
            fi
            ;;
        "stock")
            # Stock Mode
            log "[*] Using stock configuration."
            ;;
    esac
}

reload_driver() {
    log "[*] Starting driver reload sequence..."
    # Module list ordered by dependency (dependent first)
    # e.g., wlan depends on qca_cld3_wlan, which depends on qca_cld3
    local modules="wlan qca_cld3_wlan qca_cld3" 
    local active_modules=""
    
    if [ ! -f /proc/modules ]; then
        log "[!] /proc/modules missing. Assuming monolithic kernel."
        return 2
    fi

    # 1. Unload Phase
    for mod in $modules; do
        if lsmod 2>/dev/null | grep -q "^$mod "; then
            log "[*] Found active module: $mod. Unloading..."
            ip link set wlan0 down 2>/dev/null
            rmmod "$mod"
            sleep 0.5
            
            if lsmod 2>/dev/null | grep -q "^$mod "; then
                log "[!] Failed to unload $mod (Resource busy?)"
                # If we fail to unload a top-level module, we shouldn't try to unload dependencies
                # But we should try to reload what we unloaded?
                # For now, we continue but record it?
                # Actually, if unload fails, we might as well abort the whole thing and try to reload whatever we unloaded.
                # But for simplicity, we just continue and see what happens (insmod will just say 'exists').
            else
                active_modules="$active_modules $mod"
            fi
        fi
    done

    if [ -z "$active_modules" ]; then
        log "[!] No supported Wi-Fi modules found active."
        log "[?] System likely uses a Monolithic/Built-in Wi-Fi driver."
        return 2
    fi
    
    # 2. Load Phase (Reverse Order)
    # We need to reverse the order of $active_modules
    local modules_to_load=""
    for mod in $active_modules; do
        modules_to_load="$mod $modules_to_load"
    done
    
    local all_loaded=true
    
    for mod in $modules_to_load; do
        log "[*] Reloading module: $mod"
        
        local mod_path=""
        for path in "/vendor/lib/modules/$mod.ko" "/system/lib/modules/$mod.ko"; do
            if [ -f "$path" ]; then
                mod_path="$path"
                break
            fi
        done

        if [ -n "$mod_path" ]; then
            insmod "$mod_path"
        else
            modprobe "$mod"
        fi
        
        sleep 0.5
        if ! lsmod 2>/dev/null | grep -q "^$mod "; then
             log "[!] Failed to reload $mod!"
             all_loaded=false
        fi
    done

    if [ "$all_loaded" = false ]; then
        log "[!] Driver reload incomplete."
        return 1
    fi
    
    log "[+] All modules reloaded successfully."
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
    echo "Usage: $0 [perf|balanced|stock|custom|status|stats|get_stock|get_custom|save_custom]"
    exit 1
fi

CMD="$1"

if [ "$CMD" = "status" ]; then
    get_status
elif [ "$CMD" = "stats" ]; then
    get_stats
elif [ "$CMD" = "get_stock" ]; then
    # Ensure stock file exists first
    if [ ! -f "${ORIGINAL_STOCK_FILE}" ]; then
        # Try to grab it from system if missing (best effort without unmount)
        if [ -f "${SYSTEM_CONFIG_FILE}" ]; then
            cp "${SYSTEM_CONFIG_FILE}" "${ORIGINAL_STOCK_FILE}"
        fi
    fi
    cat "${ORIGINAL_STOCK_FILE}"
elif [ "$CMD" = "get_custom" ]; then
    if [ -f "${CUSTOM_CONFIG_FILE}" ]; then
        cat "${CUSTOM_CONFIG_FILE}"
    elif [ -f "${ORIGINAL_STOCK_FILE}" ]; then
        cat "${ORIGINAL_STOCK_FILE}"
    fi
elif [ "$CMD" = "save_custom" ]; then
    if [ -n "$2" ]; then
        echo "$2" | base64 -d > "${CUSTOM_CONFIG_FILE}"
        echo "Saved"
    else
        echo "Error: No data provided"
    fi
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
