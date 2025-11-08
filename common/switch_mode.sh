#!/system/bin/sh

# Wi-Fi Config Switcher Script

# Exit on any error
set -e

# --- Configuration ---
# Path to the Wi-Fi configuration directory
WIFI_CONFIG_DIR="/vendor/etc/wifi"

# Name of the target symlink
WIFI_CONFIG_SYMLINK="WCNSS_qcom_cfg.ini"

# --- Main Logic ---
# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Check if an argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 [perf|battery|status]"
    exit 1
fi

MODE="$1"
TARGET_INI="${MODE}.ini"
SYMLINK_PATH="${WIFI_CONFIG_DIR}/${WIFI_CONFIG_SYMLINK}"

case "$MODE" in
    "perf"|"battery")
        # Check if the target .ini file exists
        if [ ! -f "${WIFI_CONFIG_DIR}/${TARGET_INI}" ]; then
            echo "Error: Configuration file ${TARGET_INI} not found in ${WIFI_CONFIG_DIR}"
            exit 1
        fi

        echo "Switching to ${MODE} mode..."

        # Remove the existing symlink
        echo "Removing old configuration..."
        rm -f "${SYMLINK_PATH}"

        # Create the new symlink
        echo "Applying new configuration..."
        ln -s "${TARGET_INI}" "${SYMLINK_PATH}"

        echo "Symlink created: ${SYMLINK_PATH} -> ${TARGET_INI}"

        # Restart Wi-Fi services using Android's service manager
        echo "Restarting Wi-Fi services..."
        svc wifi disable
        sleep 1
        svc wifi enable

        # A short delay to allow services to restart
        sleep 2

        echo "Wi-Fi configuration switched to ${MODE} mode."
        ;;
    "status")
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
        ;;
    *)
        echo "Usage: $0 [perf|battery|status]"
        exit 1
        ;;
esac
exit 0
