#!/system/bin/sh

# Wi-Fi Config Switcher Script (Hot-Reload Version)
# Improved logging for debugging

# --- Configuration ---
if echo "$0" | grep -q "/data/adb/modules/"; then
    MODULE_DIR="/data/adb/modules/wifi_tweaks"
else
    # Fallback to current script location
    SCRIPT_PATH=$(readlink -f "$0")
    SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
    MODULE_DIR=$(dirname "$SCRIPT_DIR")
fi

# Defined Paths
MODULE_WIFI_DIR="${MODULE_DIR}/system/vendor/etc/wifi"
INTERNAL_CONFIG_FILE="${MODULE_WIFI_DIR}/WCNSS_qcom_cfg.ini"
SYSTEM_CONFIG_FILE="/vendor/etc/wifi/WCNSS_qcom_cfg.ini"

# Get version from module.prop
VERSION=$(grep "^version=" "${MODULE_DIR}/module.prop" | cut -d= -f2)
[ -z "$VERSION" ] && VERSION="Unknown"

PERF_CONFIG_FILE="${MODULE_WIFI_DIR}/perf.ini"
BATTERY_CONFIG_FILE="${MODULE_WIFI_DIR}/battery.ini"
DEFAULT_CONFIG_FILE="${MODULE_WIFI_DIR}/default.ini"
MODE_CONFIG_FILE="${MODULE_DIR}/common/mode.conf"

LOG_FILE="/data/local/tmp/wifi_tweaks.log"

# Function to log (timestamps added, output redirected by main block)
log() {
    echo "[$(date +%T)] $1"
}

# --- Helper Functions ---
get_status() {
    # Check the ACTUAL system file to verify if the mount is active/visible
    if [ ! -f "${SYSTEM_CONFIG_FILE}" ]; then
        echo "unknown"
        return
    fi
    
    if cmp -s "${SYSTEM_CONFIG_FILE}" "${PERF_CONFIG_FILE}"; then
        echo "perf"
    elif cmp -s "${SYSTEM_CONFIG_FILE}" "${BATTERY_CONFIG_FILE}"; then
        echo "battery"
    elif cmp -s "${SYSTEM_CONFIG_FILE}" "${DEFAULT_CONFIG_FILE}"; then
        echo "default"
    else
        echo "unknown"
    fi
}

# Function to attempt driver reload
reload_driver() {
    log "[*] Starting driver reload sequence..."
    local modules="wlan qca_cld3_wlan qca_cld3"
    local reloaded=false
    local found_any=false

    # Check if lsmod can even run
    if [ ! -f /proc/modules ]; then
        log "[!] /proc/modules not found. Driver hot-reload is likely impossible."
        return 1
    fi

    for mod in $modules; do
        if lsmod 2>/dev/null | grep -q "^$mod"; then
            found_any=true
            log "[*] Found active module: $mod. Attempting unload..."
            # Safety: Ensure interface is down
            ip link set wlan0 down 2>/dev/null
            sleep 0.5
            
            rmmod "$mod"
            sleep 1
            
            if lsmod 2>/dev/null | grep -q "^$mod"; then
                log "[!] Failed to unload $mod (busy?)"
                continue
            fi
            
            log "[*] Module $mod unloaded. Searching for source..."
            local mod_path=""
            if [ -f "/vendor/lib/modules/$mod.ko" ]; then
                mod_path="/vendor/lib/modules/$mod.ko"
            elif [ -f "/system/lib/modules/$mod.ko" ]; then
                mod_path="/system/lib/modules/$mod.ko"
            fi

            if [ -n "$mod_path" ]; then
                log "[*] Found $mod.ko at $mod_path. Loading..."
                insmod "$mod_path"
            else
                log "[*] Source .ko not found, attempting modprobe $mod..."
                modprobe "$mod"
            fi
            
            sleep 1
            if lsmod 2>/dev/null | grep -q "^$mod"; then
                log "[+] $mod reloaded successfully."
                reloaded=true
            else
                log "[!] Failed to reload $mod."
            fi
        fi
    done

    if [ "$found_any" = false ]; then
        log "[!] No supported Wi-Fi modules found in lsmod."
        log "[?] System likely uses a Monolithic/Built-in Wi-Fi driver."
        return 1
    fi

    if [ "$reloaded" = false ]; then
        log "[!] No modules were successfully hot-reloaded."
        return 1
    fi
    return 0
}

perform_switch() {
    local MODE="$1"
    log "[*] Initiating switch operation..."
    log "[*] Script version: $VERSION"
    log "[*] Target mode: $MODE"
    
    # Check for potential interference
    if grep -q "susfs" /proc/filesystems; then
        log "[!] WARNING: SUSFS detected. This may hide mounts or prevent changes."
    fi
    
    TARGET_INI_FILE="${MODULE_WIFI_DIR}/${MODE}.ini"
    
    if [ ! -f "${TARGET_INI_FILE}" ]; then
        log "Error: Source config file ${TARGET_INI_FILE} not found."
        exit 1
    fi

    log "[*] Updating module config file..."
    cat "${TARGET_INI_FILE}" > "${INTERNAL_CONFIG_FILE}"

    log "[*] Applying bind mount to $SYSTEM_CONFIG_FILE..."
    # Unmount first if already mounted to avoid stacking
    nsenter -t 1 -m -- umount "${SYSTEM_CONFIG_FILE}" 2>/dev/null
    
    # Use nsenter with -- separator to correctly pass -o bind to mount
    if nsenter -t 1 -m -- mount -o bind "${INTERNAL_CONFIG_FILE}" "${SYSTEM_CONFIG_FILE}"; then
        log "[+] Bind mount command successful (Global Namespace)."
        # Verify visibility
        if grep -q "${SYSTEM_CONFIG_FILE}" /proc/mounts; then
            log "[+] Mount confirmed in /proc/mounts."
        else
            log "[!] WARNING: Mount not visible in /proc/mounts (SUSFS/Namespace issue?)"
        fi
    else
        log "[!] Bind mount failed!"
    fi

    echo "${MODE}" > "${MODE_CONFIG_FILE}"

    log "[*] Toggling WiFi service..."
    svc wifi disable
    sleep 2

    if reload_driver; then
        log "[+] Hot-reload complete."
    else
        log "[!] Hot-reload failed/unsupported."
        log "[!] *** REBOOT REQUIRED to apply changes ***"
    fi

    svc wifi enable
    log "[*] WiFi service re-enabled."
    log "[*] Mode switch to ${MODE} successful."
}

# --- Main Execution ---

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 [perf|battery|default|status]"
    exit 1
fi

MODE="$1"

if [ "$MODE" = "status" ]; then
    get_status
else
    # Save original stdout(1) and stderr(2) to FD 3 and 4
    exec 3>&1 4>&2

    # Redirect stdout and stderr to log file
    exec > "$LOG_FILE" 2>&1
    chmod 644 "$LOG_FILE"

    echo "--- WiFi Tweaks Log $(date) ---"
    perform_switch "$MODE"

    # Restore stdout and stderr
    exec 1>&3 2>&4

    # Close unused FDs
    exec 3>&- 4>&-
fi

exit 0