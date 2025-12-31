#!/system/bin/sh
# This script runs at boot time to set the Wi-Fi configuration.

# --- Configuration ---
MODDIR=${0%/*}

# --- Execution ---

# 1. Ensure helper script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Ensure runtime config exists for WebUI
# If webroot/config.ini is missing, try to create it from stock
if [ ! -f "${MODDIR}/webroot/config.ini" ]; then
    if [ -f "${MODDIR}/common/original_stock.ini" ]; then
        cp "${MODDIR}/common/original_stock.ini" "${MODDIR}/webroot/config.ini"
    elif [ -f "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" ]; then
        cp "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" "${MODDIR}/webroot/config.ini"
    else
        touch "${MODDIR}/webroot/config.ini"
    fi
    # Set generous permissions so WebUI can read/write it
    chmod 666 "${MODDIR}/webroot/config.ini"
fi

# 3. Delegate to the main switcher script in 'apply_boot' mode
# This ensures consistency with the WebUI and handles all modes (perf, balanced, stock, custom)
# correctly without duplicating logic.
sh "${MODDIR}/common/switch_mode.sh" apply_boot > /dev/null 2>&1

# 4. Expose stock config to /data/local/tmp for WebUI fallback
# This is CRITICAL for SUSFS/KSU isolation. The WebUI can always read /data/local/tmp
# even if /data/adb/modules is hidden from the webview process.
if [ -f "${MODDIR}/common/original_stock.ini" ]; then
    cp "${MODDIR}/common/original_stock.ini" "/data/local/tmp/wifi_tweaks_stock.ini"
    # Set permissions so the non-root WebUI process can read it
    chown shell:shell "/data/local/tmp/wifi_tweaks_stock.ini"
    chmod 666 "/data/local/tmp/wifi_tweaks_stock.ini"
fi