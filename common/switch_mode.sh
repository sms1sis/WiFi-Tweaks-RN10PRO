#!/system/bin/sh

# Wi-Fi Config Switcher Script (Overlay-friendly version)

# Exit on any error
set -e

# --- Configuration ---
# Dynamically set the module directory based on the execution path
if echo "$0" | grep -q "/data/adb/modules/"; then
    # Running as a KernelSU module
    MODULE_WIFI_DIR="/data/adb/modules/wifi_tweaks/system/vendor/etc/wifi"
else
    # Running in a local/dev environment
    MODULE_WIFI_DIR="$(dirname "$0")/../system/vendor/etc/wifi"
fi

ACTIVE_CONFIG_FILE="${MODULE_WIFI_DIR}/WCNSS_qcom_cfg.ini"
PERF_CONFIG_FILE="${MODULE_WIFI_DIR}/perf.ini"
BATTERY_CONFIG_FILE="${MODULE_WIFI_DIR}/battery.ini"
DEFAULT_CONFIG_FILE="${MODULE_WIFI_DIR}/default.ini"

# --- Helper Functions ---
get_status() {
    # Compare the active config with the perf and battery configs
    if cmp -s "${ACTIVE_CONFIG_FILE}" "${PERF_CONFIG_FILE}"; then
        echo "perf"
    elif cmp -s "${ACTIVE_CONFIG_FILE}" "${BATTERY_CONFIG_FILE}"; then
        echo "battery"
    elif cmp -s "${ACTIVE_CONFIG_FILE}" "${DEFAULT_CONFIG_FILE}"; then
        echo "default"
    else
        echo "unknown"
    fi
}

# --- Main Logic ---
# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 [perf|battery|default|status]" >&2
    exit 1
fi

MODE="$1"

case "$MODE" in
    "perf"|"battery"|"default")
        TARGET_INI_FILE="${MODULE_WIFI_DIR}/${MODE}.ini"
        
        # Check if the target .ini file exists
        if [ ! -f "${TARGET_INI_FILE}" ]; then
            echo "Error: Source config file ${TARGET_INI_FILE} not found." >&2
            exit 1
        fi

        # Perform the switch by copying the file content
        cp -f "${TARGET_INI_FILE}" "${ACTIVE_CONFIG_FILE}"

        # Restart Wi-Fi services to apply the new config via overlay
        svc wifi disable >/dev/null 2>&1
        sleep 1
        svc wifi enable >/dev/null 2>&1
        sleep 2

        # Output the new status to confirm
        get_status
        ;;
    "status")
        get_status
        ;;
    *)
        echo "Usage: $0 [perf|battery|default|status]" >&2
        exit 1
        ;;
esac

exit 0
