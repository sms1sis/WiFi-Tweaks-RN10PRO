#!/system/bin/sh

# Wi-Fi Config Switcher Script (Hot-Reload Version)
# Improved logging and error handling

# --- Constants & Paths ---
readonly SCRIPT_NAME=$(basename "$0")
if echo "$0" | grep -q "/data/adb/modules/"; then
    readonly MODULE_DIR="/data/adb/modules/wifi_tweaks"
else
    # Fallback to current script location logic
    readonly SCRIPT_PATH=$(readlink -f "$0")
    readonly SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
    readonly MODULE_DIR=$(dirname "$SCRIPT_DIR")
fi

readonly MODULE_WIFI_DIR="${MODULE_DIR}/system/vendor/etc/wifi"
readonly INTERNAL_CONFIG_FILE="${MODULE_WIFI_DIR}/WCNSS_qcom_cfg.ini"
readonly SYSTEM_CONFIG_FILE="/vendor/etc/wifi/WCNSS_qcom_cfg.ini"

readonly PERF_CONFIG_FILE="${MODULE_WIFI_DIR}/perf.ini"
readonly BATTERY_CONFIG_FILE="${MODULE_WIFI_DIR}/battery.ini"
readonly DEFAULT_CONFIG_FILE="${MODULE_WIFI_DIR}/default.ini"
readonly MODE_CONFIG_FILE="${MODULE_DIR}/common/mode.conf"

readonly LOG_FILE="/data/local/tmp/wifi_tweaks.log"
readonly RESULT_FILE="/data/local/tmp/wifi_tweaks_result"
readonly DRIVER_TYPE_FILE="/data/local/tmp/driver-type.conf"

# Get version
readonly VERSION=$(grep "^version=" "${MODULE_DIR}/module.prop" | cut -d= -f2 || echo "Unknown")

# --- Logging Helper ---
log() {
    echo "[$(date +%T)] $1"
}

# --- Core Functions ---

check_driver_type() {
    local modules="wlan qca_cld3_wlan qca_cld3"
    
    # Check 1: /proc/modules existence
    if [ ! -f /proc/modules ]; then
        echo "BUILTIN" > "$DRIVER_TYPE_FILE"
        return
    fi
    
    # Check 2: Look for specific modules
    local found=false
    for mod in $modules; do
        if lsmod 2>/dev/null | grep -q "^$mod "; then
            found=true
            break
        fi
    done
    
    if [ "$found" = true ]; then
        echo "MODULAR" > "$DRIVER_TYPE_FILE"
    else
        echo "BUILTIN" > "$DRIVER_TYPE_FILE"
    fi
}

get_status() {
    # Check if system file exists
    if [ ! -f "${SYSTEM_CONFIG_FILE}" ]; then
        echo "unknown"
        return
    fi
    
    # Compare content to determine mode
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

reload_driver() {
    log "[*] Starting driver reload sequence..."
    local modules="wlan qca_cld3_wlan qca_cld3"
    local reloaded=false
    local found_any=false

    # Pre-check for module support
    if [ ! -f /proc/modules ]; then
        log "[!] /proc/modules missing. Assuming monolithic kernel."
        return 2
    fi

    for mod in $modules; do
        # Check if module is loaded
        if lsmod 2>/dev/null | grep -q "^$mod "; then
            found_any=true
            log "[*] Found active module: $mod. Attempting reload..."
            
            # 1. Unload
            ip link set wlan0 down 2>/dev/null
            sleep 0.5
            rmmod "$mod"
            sleep 1
            
            if lsmod 2>/dev/null | grep -q "^$mod "; then
                log "[!] Failed to unload $mod (Resource busy?)"
                continue
            fi
            
            # 2. Reload
            # Search for the module file (.ko)
            local mod_path=""
            for path in "/vendor/lib/modules/$mod.ko" "/system/lib/modules/$mod.ko"; do
                if [ -f "$path" ]; then
                    mod_path="$path"
                    break
                fi
            done

            if [ -n "$mod_path" ]; then
                log "[*] Loading from: $mod_path"
                insmod "$mod_path"
            else
                log "[*] Loading via modprobe..."
                modprobe "$mod"
            fi
            
            # 3. Verify
            sleep 1
            if lsmod 2>/dev/null | grep -q "^$mod "; then
                log "[+] $mod reloaded successfully."
                reloaded=true
            else
                log "[!] Failed to reload $mod."
            fi
        fi
    done

    if [ "$found_any" = false ]; then
        log "[!] No supported Wi-Fi modules found active."
        log "[?] System likely uses a Monolithic/Built-in Wi-Fi driver."
        return 2
    fi

    if [ "$reloaded" = false ]; then
        log "[!] Driver reload failed."
        return 1
    fi
    return 0
}

perform_switch() {
    local MODE="$1"
    local TARGET_INI_FILE="${MODULE_WIFI_DIR}/${MODE}.ini"

    log "[*] Operation: Switch to $MODE"
    log "[*] Version: $VERSION"
    
    # Detect Driver Type
    check_driver_type
    
    # Interference check
    if grep -q "susfs" /proc/filesystems; then
        log "[!] WARNING: SUSFS detected."
    fi
    
    if [ ! -f "${TARGET_INI_FILE}" ]; then
        log "[!] Error: Config file ${TARGET_INI_FILE} missing."
        exit 1
    fi

    # 1. Update Internal State
    log "[*] Updating internal config..."
    cat "${TARGET_INI_FILE}" > "${INTERNAL_CONFIG_FILE}"
    chmod 644 "${INTERNAL_CONFIG_FILE}"

    # 2. Bind Mount
    log "[*] Remounting config..."
    nsenter -t 1 -m -- umount "${SYSTEM_CONFIG_FILE}" 2>/dev/null
    
    if nsenter -t 1 -m -- mount -o bind "${INTERNAL_CONFIG_FILE}" "${SYSTEM_CONFIG_FILE}"; then
        log "[+] Bind mount successful."
        # Verify visibility
        if ! grep -q "${SYSTEM_CONFIG_FILE}" /proc/mounts; then
            log "[!] WARNING: Mount not visible in /proc/mounts."
        fi
    else
        log "[!] Bind mount failed."
    fi

    # 3. Persist Mode
    echo "${MODE}" > "${MODE_CONFIG_FILE}"

    # 4. Restart Driver/Service
    log "[*] Restarting Wi-Fi service..."
    svc wifi disable
    sleep 2

    reload_driver
    local RET=$?
    
    if [ $RET -eq 0 ]; then
        log "[+] Driver hot-reload successful."
        echo "SUCCESS" > "$RESULT_FILE"
    elif [ $RET -eq 2 ]; then
        log "[!] Hot-reload skipped (Built-in driver)."
        echo "BUILTIN" > "$RESULT_FILE"
    else
        log "[!] Hot-reload failed."
        echo "FAILED" > "$RESULT_FILE"
    fi

    svc wifi enable
    log "[*] Wi-Fi service enabled."
}

# --- Entry Point ---

# Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Must run as root."
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 [perf|battery|default|status]"
    exit 1
fi

CMD="$1"

if [ "$CMD" = "status" ]; then
    get_status
else
    # Setup Logging
    # Redirect stdout(1) and stderr(2) to log file, keeping original stdout on FD 3
    exec 3>&1
    exec > "$LOG_FILE" 2>&1
    chmod 644 "$LOG_FILE"

    echo "--- WiFi Tweaks Log $(date) ---"
    perform_switch "$CMD"

    # Restore stdout
    exec 1>&3 3>&-
fi

exit 0