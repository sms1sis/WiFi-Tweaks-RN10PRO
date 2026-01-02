#!/system/bin/sh
# WiFi Config Switcher - Hybrid Mount Core Logic
# Refactored for Version 3.6.0+

# --- 1. Dynamic Path Discovery ---
readonly SCRIPT_PATH=$(readlink -f "$0")
readonly SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
readonly MODULE_DIR=$(dirname "$SCRIPT_DIR")

# Key File Paths
readonly INTERNAL_CONFIG_FILE="${MODULE_DIR}/common/active_config.ini"
readonly SYSTEM_CONFIG_FILE="/vendor/etc/wifi/WCNSS_qcom_cfg.ini"
readonly ORIGINAL_STOCK_FILE="${MODULE_DIR}/common/original_stock.ini"
readonly CUSTOM_CONFIG_FILE="${MODULE_DIR}/webroot/config.ini"
readonly MODE_CONFIG_FILE="${MODULE_DIR}/common/mode.conf"

# Logging & State
readonly LOG_FILE="/data/local/tmp/wifi_tweaks.log"
readonly RESULT_FILE="/data/local/tmp/wifi_tweaks_result"

# Initialize Log safely
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" 2>/dev/null
    chmod 666 "$LOG_FILE" 2>/dev/null
fi

# --- 2. Helper Functions ---

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

write_result() {
    echo "$1" > "$2"
    chmod 666 "$2"
}

get_status() {
    [ -f "${MODE_CONFIG_FILE}" ] && cat "${MODE_CONFIG_FILE}" || echo "unknown"
}

get_stats() {
    local rssi="N/A" speed="N/A" freq="N/A"
    if command -v iw >/dev/null 2>&1; then
        local link_info=$(iw dev wlan0 link 2>/dev/null)
        if [ -n "$link_info" ]; then
            rssi=$(echo "$link_info" | awk '/signal:/ {print $2 " " $3}')
            speed=$(echo "$link_info" | awk '/tx bitrate:/ {print $3 " " $4}')
            freq=$(echo "$link_info" | awk '/freq:/ {print $2 " MHz"}')
        else
            rssi="Disconnected"
        fi
    else
        rssi="Tools missing"
    fi
    echo "RSSI: $rssi | Speed: $speed | Freq: $freq"
}

apply_param() {
    local file="$1" key="$2" value="$3"
    # Use sed to replace existing key or append if missing
    # Fixed for Android toybox/busybox: replaced \s with [[:space:]]
    if grep -q "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i "s/^[[:space:]]*${key}[[:space:]]*=.*/${key}=${value}/" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

patch_config() {
    local mode="$1" target="$2"
    log "Patching configuration for mode: $mode"
    
    case "$mode" in
        "perf")
            apply_param "$target" "gEnableBmps" "0"
            apply_param "$target" "TxPower2g" "15"
            apply_param "$target" "TxPower5g" "15"
            apply_param "$target" "gChannelBondingMode24GHz" "1"
            ;;
        "balanced")
            apply_param "$target" "gEnableBmps" "1"
            apply_param "$target" "TxPower2g" "12"
            apply_param "$target" "TxPower5g" "12"
            apply_param "$target" "gChannelBondingMode24GHz" "1"
            ;;
        "custom")
            if [ -f "${CUSTOM_CONFIG_FILE}" ]; then
                cp "${CUSTOM_CONFIG_FILE}" "$target"
            else
                log "Error: Custom config file not found!"
            fi
            ;;
    esac
}

cleanup_mounts() {
    # Check for existing bind mounts on the target file
    if nsenter -t 1 -m -- grep -q " ${SYSTEM_CONFIG_FILE} " /proc/mounts; then
        log "Cleaning up existing mount..."
        nsenter -t 1 -m -- umount -l "${SYSTEM_CONFIG_FILE}" 2>/dev/null
    fi
}

restart_wifi_service() {
    local ctx="$1"
    if [ "$ctx" = "live" ]; then
        log "Restarting Wi-Fi service (Live Mode)..."
        /system/bin/svc wifi disable
        sleep 1
        /system/bin/svc wifi enable
        log "Wi-Fi service restarted."
    else
        log "Boot Mode: Skipping service restart to prevent boot loop."
    fi
}

# --- 3. Main Switch Logic ---

perform_switch() {
    local MODE="$1"
    local CONTEXT="$2" # "boot" or "live"
    
    log "--- Switching to $MODE ($CONTEXT) ---"
    
    # A. Ensure Stock Backup Exists
    if [ ! -f "${ORIGINAL_STOCK_FILE}" ]; then
        # If we are live, unmount first to ensure we copy the REAL stock file
        [ "$CONTEXT" = "live" ] && cleanup_mounts
        
        if [ -f "${SYSTEM_CONFIG_FILE}" ]; then
            cp "${SYSTEM_CONFIG_FILE}" "${ORIGINAL_STOCK_FILE}"
            log "Created stock backup."
        else
            log "Error: System config file not found for backup!"
            return 1
        fi
    fi
    
    # B. Hybrid Persistence: Update the Physical Module File
    # This ensures that on next boot, the overlay system (Magisk/KSU) sees the updated file.
    mkdir -p "$(dirname "${INTERNAL_CONFIG_FILE}")"
    cp "${ORIGINAL_STOCK_FILE}" "${INTERNAL_CONFIG_FILE}"
    patch_config "$MODE" "${INTERNAL_CONFIG_FILE}"
    chmod 644 "${INTERNAL_CONFIG_FILE}"
    
    # SELinux Context Fix (Critical for KSU/Android 14+)
    # Try to copy context from system file, fallback to generic vendor type
    if [ -f "${SYSTEM_CONFIG_FILE}" ]; then
        chcon --reference="${SYSTEM_CONFIG_FILE}" "${INTERNAL_CONFIG_FILE}" 2>/dev/null
    else
        chcon u:object_r:vendor_configs_file:s0 "${INTERNAL_CONFIG_FILE}" 2>/dev/null
    fi
    
    log "Physical module file updated."

    # C. Live Application (Hot-Reload)
    # Only perform bind mounts if we are in 'live' mode.
    if [ "$CONTEXT" = "live" ]; then
        cleanup_mounts
        
        log "Applying live bind mount..."
        if nsenter -t 1 -m -- mount -o bind "${INTERNAL_CONFIG_FILE}" "${SYSTEM_CONFIG_FILE}"; then
            log "Live mount successful."
            write_result "SUCCESS" "$RESULT_FILE"
            
            # Restart Wi-Fi service ONLY in live mode
            restart_wifi_service "live"
        else
            log "Error: Bind mount failed."
            write_result "FAILED" "$RESULT_FILE"
        fi
    else
        log "Boot mode: Skipping live mount and service restart."
    fi

    # D. Save State
    echo "${MODE}" > "${MODE_CONFIG_FILE}"
    sync
}

# --- 4. CLI Router ---

case "$1" in
    "status") get_status ;;
    "stats") get_stats ;;
    "get_stock")
        if [ -f "${ORIGINAL_STOCK_FILE}" ]; then
            cat "${ORIGINAL_STOCK_FILE}"
        fi
        ;;
    "get_custom")
        if [ -f "${CUSTOM_CONFIG_FILE}" ]; then
            cat "${CUSTOM_CONFIG_FILE}"
        fi
        ;;
    "save_custom")
        # Read from stdin and save to custom config file
        # Used by WebUI via: echo "base64" | base64 -d | sh switch_mode.sh save_custom
        cat > "${CUSTOM_CONFIG_FILE}"
        chmod 666 "${CUSTOM_CONFIG_FILE}"
        ;;
    "apply_boot")
        # Apply the saved mode (or balanced default) physically, without mounting
        exec >> "$LOG_FILE" 2>&1
        MODE=$(cat "${MODE_CONFIG_FILE}" 2>/dev/null || echo "balanced")
        perform_switch "$MODE" "boot"
        ;;
    "perf"|"balanced"|"stock"|"custom")
        # Live switch with logging
        exec >> "$LOG_FILE" 2>&1
        perform_switch "$1" "live"
        ;;
    *)
        echo "Usage: $0 [perf|balanced|stock|custom|status|stats|apply_boot]"
        exit 1
        ;;
esac