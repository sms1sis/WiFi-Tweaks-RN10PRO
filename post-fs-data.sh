#!/system/bin/sh
# post-fs-data.sh for WiFi-Config-Switcher
# Hybrid Mount Compatible

# Determine the directory where this script resides dynamically
MODDIR=$(dirname "$(readlink -f "$0")")

# 1. Ensure the switcher script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Hybrid Support: Patch the module's system files at boot
# This ensures meta-hybrid_mount sees the correct file during its overlay phase.
# The 'apply_boot' command updates the physical files without manual bind mounts.
sh "${MODDIR}/common/switch_mode.sh" apply_boot > /data/local/tmp/wifi_tweaks_boot.log 2>&1

# 3. Maintain WebUI Fallback for path-independent access
if [ -f "${MODDIR}/common/original_stock.ini" ]; then
    cp "${MODDIR}/common/original_stock.ini" "/data/local/tmp/wifi_tweaks_stock.ini"
    chmod 666 "/data/local/tmp/wifi_tweaks_stock.ini"
fi
