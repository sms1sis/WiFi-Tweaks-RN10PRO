#!/system/bin/sh
# This script runs at boot time (post-fs-data) to set the Wi-Fi configuration.

# --- Configuration ---
MODDIR=${0%/*}

# --- Execution ---

# 1. Ensure helper script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Ensure runtime config exists for WebUI
# If webroot/config.ini is missing, try to create it from stock or system
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

# 3. Apply Boot Configuration
# This updates the physical file in $MODDIR/system/... using the 'apply_boot' mode.
# Magisk/KernelSU (and meta-overlayfs) will then automatically overlay this file 
# during the boot process.
sh "${MODDIR}/common/switch_mode.sh" apply_boot > /data/local/tmp/wifi_tweaks_boot.log 2>&1

# 4. Expose stock config to /data/local/tmp for WebUI fallback
# This is required because the WebUI (running as a non-root user) cannot access 
# /data/adb/modules directly due to Android security restrictions.
if [ -f "${MODDIR}/common/original_stock.ini" ]; then
    cp "${MODDIR}/common/original_stock.ini" "/data/local/tmp/wifi_tweaks_stock.ini"
    # Ensure standard shell permissions
    chown shell:shell "/data/local/tmp/wifi_tweaks_stock.ini" 2>/dev/null
    chmod 666 "/data/local/tmp/wifi_tweaks_stock.ini"
fi
