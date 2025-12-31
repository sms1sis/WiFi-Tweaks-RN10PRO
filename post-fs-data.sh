#!/system/bin/sh
# This script runs at boot time to set the Wi-Fi configuration.

# --- Configuration ---
MODDIR=${0%/*}
WIFI_CONFIG_DIR="/vendor/etc/wifi"
WIFI_CONFIG_FILE="WCNSS_qcom_cfg.ini"
CONFIG_FILE_PATH="${WIFI_CONFIG_DIR}/${WIFI_CONFIG_FILE}"
MODE_CONFIG_FILE="${MODDIR}/common/mode.conf"
INTERNAL_CONFIG_FILE="${MODDIR}/system/vendor/etc/wifi/${WIFI_CONFIG_FILE}"
ORIGINAL_STOCK_FILE="${MODDIR}/common/original_stock.ini"

# --- Helper Functions ---
log() {
    echo "[$(date +%T)] $1"
}

apply_param() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    # If key exists (handling optional spaces), replace it. If not, append it.
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
        "stock")
            # Stock Mode - No patching needed (already copied from stock)
            log "[*] Using stock configuration."
            ;;
    esac
}

# --- Execution ---

# 1. Ensure helper script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Backup Stock Config (True Stock)
if [ ! -f "${ORIGINAL_STOCK_FILE}" ]; then
    if [ -f "${CONFIG_FILE_PATH}" ]; then
        cp "${CONFIG_FILE_PATH}" "${ORIGINAL_STOCK_FILE}"
    fi
fi

# 3. Determine Mode
if [ -f "${MODE_CONFIG_FILE}" ]; then
    MODE=$(cat "${MODE_CONFIG_FILE}")
else
    # Default to balanced mode if not set
    MODE="balanced"
    echo "$MODE" > "${MODE_CONFIG_FILE}"
fi

# 4. Prepare Module Config
if [ -f "${ORIGINAL_STOCK_FILE}" ]; then
    # Start fresh from stock
    cp -f "${ORIGINAL_STOCK_FILE}" "${INTERNAL_CONFIG_FILE}"
    chmod 644 "${INTERNAL_CONFIG_FILE}"
    
    # Apply patches
    patch_config "${MODE}" "${INTERNAL_CONFIG_FILE}"
else
    # Fallback if stock file backup failed (unlikely)
    # We can't really do much here if we don't have a base.
    log "[!] Error: Stock config not found."
fi