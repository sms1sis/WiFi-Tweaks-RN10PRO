#!/system/bin/sh

# This script runs at boot time to set the Wi-Fi configuration.

# Module directory
MODDIR=${0%/*}

# Log file for post-fs-data.sh
LOG_FILE="${MODDIR}/post-fs-data.log"
echo "--- $(date) - post-fs-data.sh started ---" > "${LOG_FILE}"



# Permissions are set during module packaging for post-fs-data.sh itself.
# However, other scripts might lose executable permissions during flashing.
# Re-ensure switch_mode.sh is executable.
echo "Re-ensuring switch_mode.sh is executable..." >> "${LOG_FILE}"
chmod +x "${MODDIR}/common/switch_mode.sh" >> "${LOG_FILE}" 2>&1
echo "chmod +x for switch_mode.sh exit code: $?" >> "${LOG_FILE}"

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
    # Copy the selected .ini file to the target location
    # This will overwrite the existing file on the read-only partition
    # thanks to KernelSU's overlay.
    cp -f "${TARGET_INI_FILE}" "${CONFIG_FILE_PATH}"
fi
