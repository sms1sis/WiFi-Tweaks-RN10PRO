#!/system/bin/sh

# Wi-Fi Config Switcher Script
#
# This script is designed to be robust and produce minimal, predictable output
# for easier integration with the WebUI.

# Exit on any error
set -e

# --- Configuration ---
WIFI_CONFIG_DIR="/vendor/etc/wifi"
WIFI_CONFIG_SYMLINK="WCNSS_qcom_cfg.ini"
SYMLINK_PATH="${WIFI_CONFIG_DIR}/${WIFI_CONFIG_SYMLINK}"

# --- Helper Functions ---
get_status() {
    if [ -L "${SYMLINK_PATH}" ]; then
        CURRENT_TARGET=$(readlink "${SYMLINK_PATH}")
        if echo "${CURRENT_TARGET}" | grep -q "perf.ini"; then
            echo "perf"
        elif echo "${CURRENT_TARGET}" | grep -q "battery.ini"; then
            echo "battery"
        else
            echo "unknown"
        fi
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
    echo "Usage: $0 [perf|battery|status]" >&2
    exit 1
fi

MODE="$1"

case "$MODE" in
    "perf"|"battery")
        TARGET_INI="${MODE}.ini"
        
        # Check if the target .ini file exists
        if [ ! -f "${WIFI_CONFIG_DIR}/${TARGET_INI}" ]; then
            echo "Error: Config file ${TARGET_INI} not found." >&2
            exit 1
        fi

        # Perform the switch
        rm -f "${SYMLINK_PATH}"
        ln -s "${TARGET_INI}" "${SYMLINK_PATH}"

        # Restart Wi-Fi services, silencing output for a cleaner WebUI experience.
        # The delays are important for service stability.
        svc wifi disable >/dev/null 2>&1
        sleep 1
        svc wifi enable >/dev/null 2>&1
        sleep 2

        # The final output is the new status, which confirms the operation succeeded.
        get_status
        ;;
    "status")
        get_status
        ;;
    *)
        echo "Usage: $0 [perf|battery|status]" >&2
        exit 1
        ;;
esac

exit 0
