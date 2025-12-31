#!/system/bin/sh

# Wi-Fi Config Switcher Script (Hybrid Mount & KSU Optimized)
# Supports: meta-hybrid_mount, meta-overlayfs, meta-magic_mount

# --- Dynamic Path Discovery ---
# Use readlink and dirname to ensure path independence
readonly SCRIPT_PATH=$(readlink -f "$0")
readonly SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
# The script is in 'common/', so MODULE_DIR is one level up
readonly MODULE_DIR=$(dirname "$SCRIPT_DIR")

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
    if grep -q "^\s*${key}\s*=" "$file"; then
        sed -i "s/^\s*${key}\s*=.*/${key}=${value}/" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

patch_config() {
    local mode="$1" target="$2"
    log "[*] Patching configuration: $mode"
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
            [ -f "${CUSTOM_CONFIG_FILE}" ] && cp "${CUSTOM_CONFIG_FILE}" "$target" || log "[!] Custom config missing!"
            ;;
    esac
}

cleanup_mounts() {
    # Check if the target is already a hybrid mount or manual bind
    # Use nsenter to inspect the global mount table
    if nsenter -t 1 -m -- grep -q " ${SYSTEM_CONFIG_FILE} " /proc/mounts; then
        log "[*] Existing mount detected on target. Cleaning up..."
        nsenter -t 1 -m -- umount -l "${SYSTEM_CONFIG_FILE}" 2>/dev/null
    fi
}

perform_switch() {
    local MODE="$1"
    local CONTEXT="$2" # "boot" or "live"
    
    log "[*] Operation: Switch to $MODE (Context: $CONTEXT)"
    log "[*] Module Path: $MODULE_DIR"
    
    # 1. Ensure Stock Backup
    if [ ! -f "${ORIGINAL_STOCK_FILE}" ]; then
        # If live, we must unmount to see the TRUE stock file
        [ "$CONTEXT" = "live" ] && cleanup_mounts
        cp "${SYSTEM_CONFIG_FILE}" "${ORIGINAL_STOCK_FILE}"
        log "[+] Stock backup created."
    fi
    
    # 2. Update Physical File (Hybrid Source of Truth)
    # This ensures 'meta-hybrid_mount' picks it up on next boot
    mkdir -p "$(dirname "${INTERNAL_CONFIG_FILE}")"
    cp "${ORIGINAL_STOCK_FILE}" "${INTERNAL_CONFIG_FILE}"
    patch_config "$MODE" "${INTERNAL_CONFIG_FILE}"
    chmod 644 "${INTERNAL_CONFIG_FILE}"
    log "[+] Internal module file updated (Physical Patch)."

    # 3. Apply Live Mount if necessary
    if [ "$CONTEXT" = "live" ]; then
        cleanup_mounts
        log "[*] Applying manual bind mount via nsenter..."
        if nsenter -t 1 -m -- mount -o bind "${INTERNAL_CONFIG_FILE}" "${SYSTEM_CONFIG_FILE}"; then
            log "[+] Live switch successful."
            write_result "SUCCESS" "$RESULT_FILE"
            
            # Hot-Reload logic
            svc wifi disable
            sleep 1
            svc wifi enable
            log "[*] Wi-Fi service restarted."
        else
            log "[!] Bind mount failed!"
            write_result "FAILED" "$RESULT_FILE"
        fi
    else
        log "[*] Boot mode: Relying on hybrid overlay for mount."
    fi

    # 4. Persist Mode
    echo "${MODE}" > "${MODE_CONFIG_FILE}"
    sync
}

# --- CLI Entry ---
case "$1" in
    "status") get_status ;;
    "stats") get_stats ;;
    "apply_boot")
        MODE=$(cat "${MODE_CONFIG_FILE}" 2>/dev/null || echo "balanced")
        perform_switch "$MODE" "boot"
        ;;
    "perf"|"balanced"|"stock"|"custom")
        # Setup Logging for switch operations
        exec > "$LOG_FILE" 2>&1
        perform_switch "$1" "live"
        ;;
    *)
        echo "Usage: $0 [perf|balanced|stock|custom|status|stats|apply_boot]"
        exit 1
        ;;
esac

exit 0