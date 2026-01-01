#!/system/bin/sh
# service.sh - Late boot operations for WiFi-Config-Switcher
# Handles safe bind-mounting after system boot to avoid KSU/Xiaomi issues.

MODDIR=$(dirname "$(readlink -f "$0")")
LOG_FILE="/data/local/tmp/wifi_tweaks.log"

# Append to log
exec >> "$LOG_FILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] service.sh started. Waiting for boot completion..."

# Wait for boot completion
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Boot completed. Applying late configuration..."

# Determine current mode
MODE_FILE="${MODDIR}/common/mode.conf"
if [ -f "$MODE_FILE" ]; then
    MODE=$(cat "$MODE_FILE")
else
    MODE="balanced"
    echo "No mode file found, defaulting to balanced."
fi

# Execute the switch script in 'live' mode (implied by passing just the mode name).
# This will:
# 1. Regenerate the config file in common/ (safe location)
# 2. Perform the bind mount using nsenter
# 3. Restart the Wi-Fi service to pick up changes
echo "Triggering live switch for mode: $MODE"
sh "${MODDIR}/common/switch_mode.sh" "$MODE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] service.sh execution finished."
