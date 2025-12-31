#!/system/bin/sh
# This script runs at boot time to set the Wi-Fi configuration.

# --- Configuration ---
MODDIR=${0%/*}

# --- Execution ---

# 1. Ensure helper script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Ensure runtime config exists for WebUI
if [ ! -f "${MODDIR}/webroot/config.ini" ]; then
    if [ -f "${MODDIR}/common/original_stock.ini" ]; then
        cp "${MODDIR}/common/original_stock.ini" "${MODDIR}/webroot/config.ini"
    elif [ -f "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" ]; then
        cp "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" "${MODDIR}/webroot/config.ini"
    else
        touch "${MODDIR}/webroot/config.ini"
    fi
    chmod 644 "${MODDIR}/webroot/config.ini"
fi

# 3. Expose stock config to /data/local/tmp for WebUI fallback
# This helps when SUSFS/KSU hides the /data/adb/modules directory
if [ -f "${MODDIR}/common/original_stock.ini" ]; then
    cp "${MODDIR}/common/original_stock.ini" "/data/local/tmp/wifi_tweaks_stock.ini"
    chown shell:shell "/data/local/tmp/wifi_tweaks_stock.ini"
    chmod 644 "/data/local/tmp/wifi_tweaks_stock.ini"
fi

# 4. Delegate to the main switcher script in 'apply_boot' mode
# This ensures consistency with the WebUI and handles all modes (perf, balanced, stock, custom)
# correctly without duplicating logic.
sh "${MODDIR}/common/switch_mode.sh" apply_boot > /dev/null 2>&1