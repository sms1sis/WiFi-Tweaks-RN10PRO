#!/system/bin/sh
# This script runs at boot time to set the Wi-Fi configuration.

# --- Configuration ---
MODDIR=${0%/*}
WIFI_CONFIG_DIR="/vendor/etc/wifi"
WIFI_CONFIG_FILE="WCNSS_qcom_cfg.ini"
CONFIG_FILE_PATH="${WIFI_CONFIG_DIR}/${WIFI_CONFIG_FILE}"
MODE_CONFIG_FILE="${MODDIR}/common/mode.conf"
INTERNAL_CONFIG_FILE="${MODDIR}/system/vendor/etc/wifi/${WIFI_CONFIG_FILE}"

# --- Execution ---

# 1. Ensure helper script is executable
chmod +x "${MODDIR}/common/switch_mode.sh"

# 2. Determine Mode
if [ -f "${MODE_CONFIG_FILE}" ]; then
    MODE=$(cat "${MODE_CONFIG_FILE}")
else
    # Default to battery mode if not set
    MODE="battery"
    echo "$MODE" > "${MODE_CONFIG_FILE}"
fi

# 3. Prepare Module Config
TARGET_INI_FILE="${MODDIR}/system/vendor/etc/wifi/${MODE}.ini"

if [ -f "${TARGET_INI_FILE}" ]; then
    # Overwrite the internal config file with the selected mode
    cp -f "${TARGET_INI_FILE}" "${INTERNAL_CONFIG_FILE}"
    # Ensure correct permissions for the config file
    chmod 644 "${INTERNAL_CONFIG_FILE}"
fi