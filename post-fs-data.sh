#!/system/bin/sh
# This script runs at boot time to set the Wi-Fi configuration.

# --- Configuration ---
MODDIR=${0%/*}

# --- Execution ---

# 1. Ensure helper script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Ensure runtime config exists for WebUI
if [ ! -f "${MODDIR}/webroot/custom.ini" ]; then
    if [ -f "${MODDIR}/common/original_stock.ini" ]; then
        cp "${MODDIR}/common/original_stock.ini" "${MODDIR}/webroot/custom.ini"
    elif [ -f "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" ]; then
        cp "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" "${MODDIR}/webroot/custom.ini"
    else
        touch "${MODDIR}/webroot/custom.ini"
    fi
    chmod 644 "${MODDIR}/webroot/custom.ini"
fi

# 3. Delegate to the main switcher script in 'apply_boot' mode
# This ensures consistency with the WebUI and handles all modes (perf, balanced, stock, custom)
# correctly without duplicating logic.
sh "${MODDIR}/common/switch_mode.sh" apply_boot > /dev/null 2>&1
