#!/system/bin/sh

# Wi-Fi Config Switcher Script (OverlayFS & KSU Compatible)
# Improved logic for meta-overlayfs, SUSFS, and Live Switching

# --- Constants & Paths ---
readonly SCRIPT_NAME=$(basename "$0")
# Detect Module Directory
if echo "$0" | grep -q "/data/adb/modules/"; then
    readonly MODULE_DIR="/data/adb/modules/wifi_tweaks"
else
    # Fallback logic
    readonly SCRIPT_PATH=$(readlink -f "$0")
    readonly SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
    readonly MODULE_DIR=$(dirname "$SCRIPT_DIR")
fi

readonly MODULE_WIFI_DIR="${MODULE_DIR}/system/vendor/etc/wifi"
readonly INTERNAL_CONFIG_FILE="${MODULE_WIFI_DIR}/WCNSS_qcom_cfg.ini"
readonly SYSTEM_CONFIG_FILE="/vendor/etc/wifi/WCNSS_qcom_cfg.ini"
readonly ORIGINAL_STOCK_FILE="${MODULE_DIR}/common/original_stock.ini"
readonly CUSTOM_CONFIG_FILE="${MODULE_DIR}/webroot/config.ini"
readonly MODE_CONFIG_FILE="${MODULE_DIR}/common/mode.conf"

readonly LOG_FILE="/data/local/tmp/wifi_tweaks.log"
readonly RESULT_FILE="/data/local/tmp/wifi_tweaks_result"
readonly FALLBACK_FILE="/data/local/tmp/wifi_tweaks_stock.ini"

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
    
    if command -v iw >/dev/null 2>&1; then
        local link_info=$(iw dev wlan0 link 2>/dev/null)
        if [ -n "$link_info" ]; then
            rssi=$(echo "$link_info" | awk '/signal:/ {print $2 " " $3}')
            speed=$(echo "$link_info" | awk '/tx bitrate:/ {print $3 " " $4}')
            freq=$(echo "$link_info" | awk '/freq:/ {print $2 " MHz"}')
        else
            rssi="Disconnected"
        fi
    elif command -v dumpsys >/dev/null 2>&1; then
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
            if [ -f "${CUSTOM_CONFIG_FILE}" ]; then
                log "[*] Loading custom configuration..."
                cp "${CUSTOM_CONFIG_FILE}" "$target"
            else
                log "[!] Custom config not found! Falling back to stock."
            fi
            ;;
        "stock")
            log "[*] Using stock configuration."
            ;;
    esac
}

reload_driver() {
    log "[*] Starting driver reload sequence..."
    local modules="wlan qca_cld3_wlan qca_cld3" 
    local active_modules=""
    
    if [ ! -f /proc/modules ]; then
        log "[!] /proc/modules missing. Assuming monolithic kernel."
        return 2
    fi

    for mod in $modules; do
        if lsmod 2>/dev/null | grep -q "^$mod "; then
            log "[*] Found active module: $mod. Unloading..."
            ip link set wlan0 down 2>/dev/null
            rmmod "$mod"
            sleep 0.5
            if ! lsmod 2>/dev/null | grep -q "^$mod "; then
                active_modules="$active_modules $mod"
            fi
        fi
    done

    if [ -z "$active_modules" ]; then
        log "[!] No supported Wi-Fi modules found active."
        return 2
    fi
    
    local modules_to_load=""
    for mod in $active_modules; do
        modules_to_load="$mod $modules_to_load"
    done
    
    local all_loaded=true
    for mod in $modules_to_load; do
        log "[*] Reloading module: $mod"
        local mod_path=""
        for path in "/vendor/lib/modules/$mod.ko" "/system/lib/modules/$mod.ko"; do
            if [ -f "$path" ]; then mod_path="$path"; break; fi
        done

        if [ -n "$mod_path" ]; then insmod "$mod_path"; else modprobe "$mod"; fi
        sleep 0.5
        if ! lsmod 2>/dev/null | grep -q "^$mod "; then all_loaded=false; fi
    done

    if [ "$all_loaded" = false ]; then
        log "[!] Driver reload incomplete."
        return 1
    fi
    
    log "[+] All modules reloaded successfully."
    return 0
}

cleanup_mounts() {
    # Clean up any existing bind mounts on the target file
    # Loop to handle potential stacked mounts
    local count=0
    while grep -q " ${SYSTEM_CONFIG_FILE} " /proc/mounts; do
        log "[*] Cleaning up existing mount on ${SYSTEM_CONFIG_FILE}..."
        nsenter -t 1 -m -- umount "${SYSTEM_CONFIG_FILE}" 2>/dev/null
        local ret=$?
        if [ $ret -ne 0 ]; then
            log "[!] Umount failed. Trying lazy unmount..."
            nsenter -t 1 -m -- umount -l "${SYSTEM_CONFIG_FILE}" 2>/dev/null
        fi
        
        count=$((count + 1))
        if [ $count -gt 5 ]; then
            log "[!] Warning: Failed to unmount after 5 attempts."
            break
        fi
        sleep 0.1
    done
}

perform_switch() {
    local MODE="$1"
    local CONTEXT="$2" # "boot" or "live"
    
    log "[*] Operation: Switch to $MODE (Context: ${CONTEXT:-live})"
    log "[*] Version: $VERSION"
    
    # SUSFS Detection
    if grep -q "susfs" /proc/filesystems 2>/dev/null; then
        log "[!] SUSFS Environment detected. Proceeding with caution."
    fi

    # 1. Prepare Stock Backup
    # Only if missing, to preserve original system state.
    if [ ! -f "${ORIGINAL_STOCK_FILE}" ]; then
        log "[*] Original stock backup missing."
        
        # If in live mode, ensure we aren't copying a bind-mounted file
        if [ "$CONTEXT" != "boot" ]; then
            cleanup_mounts
        fi
        
        if [ -f "${SYSTEM_CONFIG_FILE}" ]; then
            log "[*] Creating backup from ${SYSTEM_CONFIG_FILE}..."
            cp "${SYSTEM_CONFIG_FILE}" "${ORIGINAL_STOCK_FILE}"
        else
            log "[!] ERROR: System config file not found!"
            write_result "FAILED" "$RESULT_FILE"
            return 1
        fi
    fi
    
    # 2. Patch Internal Config (Physical File Update)
    # This is crucial for "Static" mode (Boot) and consistency.
    mkdir -p "$(dirname "${INTERNAL_CONFIG_FILE}")"
    log "[*] Updating internal module file: ${INTERNAL_CONFIG_FILE}"
    cp "${ORIGINAL_STOCK_FILE}" "${INTERNAL_CONFIG_FILE}"
    chmod 644 "${INTERNAL_CONFIG_FILE}"
    
    patch_config "$MODE" "${INTERNAL_CONFIG_FILE}"

    # 3. Apply Changes
    if [ "$CONTEXT" = "boot" ]; then
        # BOOT MODE: Static update only.
        # Magisk/KernelSU will overlay the modified 'system' folder naturally.
        log "[*] Boot mode: Internal file updated. Skipping bind mount."
        
    else
        # LIVE MODE: Bind mount for immediate effect.
        cleanup_mounts
        
        # Check for OverlayFS on parent directory (Informational)
        local parent_dir=$(dirname "${SYSTEM_CONFIG_FILE}")
        if grep -q "overlay.*${parent_dir}" /proc/mounts; then
            log "[!] Notice: Parent directory is an OverlayFS mount."
        fi

        log "[*] Applying live bind mount..."
        if nsenter -t 1 -m -- mount -o bind "${INTERNAL_CONFIG_FILE}" "${SYSTEM_CONFIG_FILE}"; then
            log "[+] Bind mount successful."
            
            # 4. Driver Reload (Only for live mode)
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
        else
            log "[!] Bind mount failed!"
            write_result "FAILED" "$RESULT_FILE"
        fi
    fi

    # 5. Persist Mode
    echo "${MODE}" > "${MODE_CONFIG_FILE}"
    sync
}

# --- Entry Point ---

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Must run as root."
    exit 1
fi

CMD="$1"
ARGS="$2"

if [ -z "$CMD" ]; then
    echo "Usage: $0 [perf|balanced|stock|custom|status|stats|get_stock|get_custom|apply_boot]"
    exit 1
fi

if [ "$CMD" = "status" ]; then
    get_status
elif [ "$CMD" = "stats" ]; then
    get_stats
elif [ "$CMD" = "get_stock" ]; then
    if [ ! -f "${ORIGINAL_STOCK_FILE}" ] && [ -f "${SYSTEM_CONFIG_FILE}" ]; then
        cp "${SYSTEM_CONFIG_FILE}" "${ORIGINAL_STOCK_FILE}"
    fi
    cp "${ORIGINAL_STOCK_FILE}" "${FALLBACK_FILE}"
    chmod 644 "${FALLBACK_FILE}"
    cat "${ORIGINAL_STOCK_FILE}"
elif [ "$CMD" = "get_custom" ]; then
    if [ -f "${CUSTOM_CONFIG_FILE}" ]; then
        cat "${CUSTOM_CONFIG_FILE}"
    else
        echo "# No custom config found"
    fi
elif [ "$CMD" = "apply_boot" ]; then
    # Boot logic
    if [ -f "${MODE_CONFIG_FILE}" ]; then
        MODE=$(cat "${MODE_CONFIG_FILE}")
    else
        MODE="balanced"
    fi
    # Call perform_switch with "boot" context
    perform_switch "$MODE" "boot"
else
    # Standard Switch Command
    # Setup Logging
    exec 3>&1
    exec > "$LOG_FILE" 2>&1
    chmod 644 "$LOG_FILE"

    echo "--- WiFi Tweaks Log $(date) ---"
    perform_switch "$CMD" "live"

    # Restore stdout
    exec 1>&3 3>&-
fi

exit 0