#!/system/bin/sh

# Wi-Fi Config Switcher Script (Hot-Reload Version)

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

# Function to attempt driver reload
reload_driver() {
    # 1. Try unloading common modules
    local modules="wlan qca_cld3_wlan qca_cld3"
    local reloaded=false

    for mod in $modules; do
        if lsmod | grep -q "^$mod"; then
            echo "[*] Unloading module $mod..."
            rmmod "$mod" 2>/dev/null
            sleep 1
            echo "[*] Loading module $mod..."
            # Attempt to find and reload the module
            if [ -f "/vendor/lib/modules/$mod.ko" ]; then
                insmod "/vendor/lib/modules/$mod.ko" 2>/dev/null
            elif [ -f "/system/lib/modules/$mod.ko" ]; then
                insmod "/system/lib/modules/$mod.ko" 2>/dev/null
            else
                modprobe "$mod" 2>/dev/null
            fi
            
            if lsmod | grep -q "^$mod"; then
                reloaded=true
            fi
        fi
    done

    if [ "$reloaded" = false ]; then
        echo "[!] Monolithic driver detected or module reload failed."
        return 1
    fi
    return 0
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
        echo "[*] Toggling WiFi..."
        svc wifi disable
        sleep 2

        if reload_driver; then
            echo "[+] Driver reloaded successfully."
        else
            echo "[!] Automatic reload failed (monolithic driver or busy)."
            echo "[!] PLEASE REBOOT your device to apply changes."
        fi

        svc wifi enable

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
