#!/system/bin/sh

# This script runs at boot time to set the Wi-Fi configuration.

# Module directory
MODDIR=${0%/*}

# Permissions are set during module packaging for post-fs-data.sh itself.
# However, other scripts might lose executable permissions during flashing.
# Re-ensure switch_mode.sh is executable.
chmod +x "${MODDIR}/common/switch_mode.sh"

# Configuration files
WIFI_CONFIG_DIR="/vendor/etc/wifi"
WIFI_CONFIG_FILE="WCNSS_qcom_cfg.ini"
CONFIG_FILE_PATH="${WIFI_CONFIG_DIR}/${WIFI_CONFIG_FILE}"

# Mode configuration file
MODE_CONFIG_FILE="${MODDIR}/common/mode.conf"

# Read the desired mode
if [ -f "${MODE_CONFIG_FILE}" ]; then
    MODE=$(cat "${MODE_CONFIG_FILE}")
else
    # Default to performance mode if the config file doesn't exist
    MODE="perf"
fi

# Target .ini file
TARGET_INI_FILE="${MODDIR}/system/vendor/etc/wifi/${MODE}.ini"

# Check if the target .ini file exists
if [ -f "${TARGET_INI_FILE}" ]; then
    # Copy the selected .ini file to the module's internal system mirror
    # This prepares the file for Magic Mount overlay
    cp -f "${TARGET_INI_FILE}" "${MODDIR}/system/vendor/etc/wifi/${WIFI_CONFIG_FILE}"
fi
