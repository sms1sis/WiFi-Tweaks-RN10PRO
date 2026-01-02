#!/system/bin/sh
# post-fs-data.sh for WiFi-Config-Switcher
# Handles boot-time setup for Hybrid Mount strategy

# --- Dynamic Path Discovery ---
MODDIR=$(dirname "$(readlink -f "$0")")

# Logging
LOG_FILE="/data/local/tmp/wifi_tweaks.log"

# Ensure Log File Exists and is Writable (666)
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
fi
chmod 666 "$LOG_FILE"

exec >> "$LOG_FILE" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting post-fs-data..."

# 0. Safety Cleanup (Critical for KSU Next / Xiaomi)
# Remove the system/ directory to PREVENT Magisk/KSU from auto-mounting 
# the vendor file early in boot. We handle this manually in service.sh.
if [ -d "${MODDIR}/system" ]; then
    echo "Removing dangerous system overlay..."
    rm -rf "${MODDIR}/system"
fi

# 1. Permission Fix
# Ensure the core script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Hybrid Persistence Check
# Call the script in 'boot' mode to ensure the physical module file matches the saved preference.
# This does NOT mount anything and NO SERVICES are restarted.
# It prepares the file for the system's overlay mechanism (Magisk/KSU).
sh "${MODDIR}/common/switch_mode.sh" apply_boot

# 3. Stealth Fallback (WebUI Compatibility)
# Copy the stock config and core script to a world-readable temp location.
# This is crucial for devices with strict namespace isolation (like SUSFS)
# where the WebUI might not be able to read files inside /data/adb/modules.
STOCK_BACKUP="${MODDIR}/common/original_stock.ini"
FALLBACK_TARGET="/data/local/tmp/wifi_tweaks_stock.ini"
SCRIPT_SOURCE="${MODDIR}/common/switch_mode.sh"
SCRIPT_TARGET="/data/local/tmp/switch_mode.sh"

if [ -f "$STOCK_BACKUP" ]; then
    cp "$STOCK_BACKUP" "$FALLBACK_TARGET"
    chmod 666 "$FALLBACK_TARGET"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stealth fallback created at $FALLBACK_TARGET"
fi

if [ -f "$SCRIPT_SOURCE" ]; then
    cp "$SCRIPT_SOURCE" "$SCRIPT_TARGET"
    chmod 755 "$SCRIPT_TARGET"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stealth script deployed at $SCRIPT_TARGET"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Warning: Source script not found, skipping fallback creation."
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] post-fs-data setup complete."
