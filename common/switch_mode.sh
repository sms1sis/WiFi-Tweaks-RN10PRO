#!/system/bin/sh

# Wi-Fi Config Switcher Script (Hot-Reload Version)

# Exit on any error
set -e

# --- Configuration ---
if echo "$0" | grep -q "/data/adb/modules/"; then
    MODULE_DIR="/data/adb/modules/wifi_tweaks"
else
    MODULE_DIR="$(dirname "$0")/.."
fi

# Defined Paths
MODULE_WIFI_DIR="${MODULE_DIR}/system/vendor/etc/wifi"
# The internal file inside the module
INTERNAL_CONFIG_FILE="${MODULE_WIFI_DIR}/WCNSS_qcom_cfg.ini"
# The live system file the driver actually reads
SYSTEM_CONFIG_FILE="/vendor/etc/wifi/WCNSS_qcom_cfg.ini"

PERF_CONFIG_FILE="${MODULE_WIFI_DIR}/perf.ini"
BATTERY_CONFIG_FILE="${MODULE_WIFI_DIR}/battery.ini"
DEFAULT_CONFIG_FILE="${MODULE_WIFI_DIR}/default.ini"
MODE_CONFIG_FILE="${MODULE_DIR}/common/mode.conf"

# --- Helper Functions ---
get_status() {
    # We compare against the internal module file to see what mode is 'selected'
    if cmp -s "${INTERNAL_CONFIG_FILE}" "${PERF_CONFIG_FILE}"; then
        echo "perf"
    elif cmp -s "${INTERNAL_CONFIG_FILE}" "${BATTERY_CONFIG_FILE}"; then
        echo "battery"
    elif cmp -s "${INTERNAL_CONFIG_FILE}" "${DEFAULT_CONFIG_FILE}"; then
        echo "default"
    else
        echo "unknown"
    fi
}

reload_driver() {
    # List of common Qualcomm-related Wi-Fi module names
    WLAN_MODULE_NAMES=("wlan" "wlan_mac" "qca_wlan" "wlan0")

    FOUND_MODULE=""

    # 1. Search for a loaded module
    for MOD_NAME in "${WLAN_MODULE_NAMES[@]}"; do
        if lsmod | grep -q "${MOD_NAME}"; then
            FOUND_MODULE="${MOD_NAME}"
            break
        fi
    done

    if [ -n "${FOUND_MODULE}" ]; then
        # --- MODULAR DRIVER RELOAD LOGIC (Hot-Reload) ---
        
        echo "Detected modular driver (${FOUND_MODULE}.ko)."
        
        echo "Stopping Wi-Fi service..."
        svc wifi disable
        sleep 1

        echo "Unloading module (${FOUND_MODULE})..."
        # rmmod attempts to remove the module. '2>/dev/null || true' suppresses errors if not found
        rmmod "${FOUND_MODULE}" 2>/dev/null || true 
        sleep 1

        echo "Starting Wi-Fi service (will load new config)..."
        svc wifi enable
        sleep 3
        
        echo ""
        echo "✅ Config applied successfully. No reboot required."

    else
        # --- MONOLITHIC DRIVER RELOAD LOGIC (Soft-Reset + Reboot Warning) ---
        
        echo "Driver not found in lsmod using common module names. Assuming monolithic or different name."

        echo "Attempting soft restart of Wi-Fi service..."
        svc wifi disable
        sleep 2
        svc wifi enable
        sleep 3

        echo ""
        echo "⚠️ WARNING: Driver is built-in. The new configuration has been written and bind-mounted, but a **FULL DEVICE REBOOT** is REQUIRED for the kernel driver to read the new settings."
        echo ""
    fi
}


# --- Main Logic ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 [perf|battery|default|status]" >&2
    exit 1
fi

MODE="$1"

case "$MODE" in
    "perf"|"battery"|"default")
        TARGET_INI_FILE="${MODULE_WIFI_DIR}/${MODE}.ini"
        
        if [ ! -f "${TARGET_INI_FILE}" ]; then
            echo "Error: Source config file ${TARGET_INI_FILE} not found." >&2
            exit 1
        fi

        # STEP 1: Update the persistent module file
        # Use 'cat' to preserve inode
        cat "${TARGET_INI_FILE}" > "${INTERNAL_CONFIG_FILE}"

        # STEP 2: Force update the live system file via bind mount
        # This ensures the /vendor path actually sees the new content immediately
        mount -o bind "${INTERNAL_CONFIG_FILE}" "${SYSTEM_CONFIG_FILE}"

        # Save persistence
        echo "${MODE}" > "${MODE_CONFIG_FILE}"

        # STEP 3: Reload Driver
        reload_driver

        # Output status
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
