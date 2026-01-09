#!/system/bin/sh
# action.sh - Advanced Action Handler for WiFi-Config-Switcher
# Handles privileged operations: File I/O, KPatch, and Safe Driver Reset.

# Ensure we are in a clean environment
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin
MODDIR=${0%/*}

# --- Helper Functions ---

log_json() {
    # Output JSON formatted log for WebUI parsing
    echo "{\"status\": \"$1\", \"message\": \"$2\"}"
}

find_module_config() {
    # Find the config file INSIDE the module directory
    
    # Priority 1: Check standard paths
    for path in "$MODDIR/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
                "$MODDIR/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
                "$MODDIR/system/etc/wifi/WCNSS_qcom_cfg.ini"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # Priority 2: Recursively find it in module
    local found=$(find "$MODDIR" -name "WCNSS_qcom_cfg.ini" -print -quit)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

find_driver_path() {
    # Dynamic discovery of the Wi-Fi driver path
    # Priority: Platform drivers -> PCI drivers
    
    # 1. Check Platform Drivers (Standard for QC/MTK SoCs)
    for driver in "wlan" "qca_cld3" "icnss" "cnss2"; do
        if [ -d "/sys/bus/platform/drivers/$driver" ]; then
            echo "/sys/bus/platform/drivers/$driver"
            return 0
        fi
    done

    # 2. Check PCI Drivers (Some newer QC/Broadcom chips)
    for driver in "ath11k_pci" "qcacld"; do
        if [ -d "/sys/bus/pci/drivers/$driver" ]; then
            echo "/sys/bus/pci/drivers/$driver"
            return 0
        fi
    done
    
    return 1
}

apply_param() {
    local file="$1"
    local key="$2"
    local value="$3"
    
    # Ensure file exists
    if [ ! -f "$file" ]; then return 1; fi

    # Use sed to replace existing key or append if missing
    # We use a temp file to avoid partial writes if sed fails
    if grep -q "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i "s/^[[:space:]]*${key}[[:space:]]*=.*/${key}=${value}/" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# --- Action Switch ---

case "$1" in
    "apply_mode")
        MODE="$2"
        CONFIG_FILE=$(find_module_config)

        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Config file not found in module. Please reinstall."
            exit 1
        fi
        
        # 2. Apply parameters based on mode
        case "$MODE" in
            "perf")
                apply_param "$CONFIG_FILE" "gEnableBmps" "0"
                apply_param "$CONFIG_FILE" "TxPower2g" "15"
                apply_param "$CONFIG_FILE" "TxPower5g" "15"
                apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "1"
                ;;
            "balanced")
                apply_param "$CONFIG_FILE" "gEnableBmps" "1"
                apply_param "$CONFIG_FILE" "TxPower2g" "12"
                apply_param "$CONFIG_FILE" "TxPower5g" "12"
                apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "1"
                ;;
            "stock")
                # Safe defaults - closely mimics standard QC configs
                apply_param "$CONFIG_FILE" "gEnableBmps" "1"
                apply_param "$CONFIG_FILE" "TxPower2g" "10"
                apply_param "$CONFIG_FILE" "TxPower5g" "10"
                apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "0"
                ;;
            *)
                log_json "error" "Unknown mode: $MODE"
                exit 1
                ;;
        esac
        
        # Sync changes to disk
        sync
        log_json "success" "Applied $MODE to module config."
        ;;

    "read_config")
        CONFIG_FILE=$(find_module_config)
        
        if [ -n "$CONFIG_FILE" ]; then
            cat "$CONFIG_FILE"
        else
            echo "Error: Config file not found in module directory."
            echo "Path searched: $MODDIR/system/..."
        fi
        ;;

    "save_config")
        CONFIG_FILE=$(find_module_config)

        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Config file path not found in module."
            exit 1
        fi

        # 2. Read stdin, decode, and write
        read -r B64_DATA
        if [ -n "$B64_DATA" ]; then
            # Write to module file
            echo "$B64_DATA" | base64 -d > "$CONFIG_FILE"
            if [ $? -eq 0 ]; then
                sync
                log_json "success" "Config saved."
            else
                log_json "error" "Failed to write to $CONFIG_FILE"
            fi
        else
            log_json "error" "No data received."
        fi
        ;;

    "check_kpatch")
        # Check kernel support and module presence
        SUPPORTED=false
        KPM_FOUND=false
        KPM_PATH=""

        # Check Kernel Support
        if [ -f "/sys/kernel/livepatch/enabled" ] || [ -d "/sys/kernel/security/kpatch" ]; then
            SUPPORTED=true
        fi

        # Check for KPM file in module dir
        KPM_FILE=$(find "$MODDIR" -name "*.kpm" -print -quit)
        if [ -n "$KPM_FILE" ]; then
            KPM_FOUND=true
            KPM_PATH="$KPM_FILE"
        fi

        echo "{\"supported\": $SUPPORTED, \"kpm_found\": $KPM_FOUND, \"path\": \"$KPM_PATH\"}"
        ;;

    "inject_patch")
        KPM_PATH="$2"
        if [ -z "$KPM_PATH" ]; then
             KPM_PATH=$(find "$MODDIR" -name "*.kpm" -print -quit)
        fi

        if [ -f "$KPM_PATH" ]; then
            # Attempt injection
            # 1. Try insmod (standard KSU/Linux way for .kpm/.ko)
            insmod "$KPM_PATH" > /dev/null 2>&1
            RES=$?
            
            if [ $RES -eq 0 ]; then
                log_json "success" "Patch injected via insmod."
            else
                # 2. Try kpatch tool if available
                if command -v kpatch >/dev/null; then
                    kpatch load "$KPM_PATH" > /dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        log_json "success" "Patch injected via kpatch tool."
                    else
                        log_json "error" "Injection failed (insmod & kpatch)."
                    fi
                else
                    log_json "error" "Injection failed (insmod failed, kpatch tool missing)."
                fi
            fi
        else
            log_json "error" "KPM file not found."
        fi
        ;;

    "stats")
        # specific wifi stats fetcher
        # Returns JSON: {"rssi": "...", "speed": "...", "freq": "..."}
        
        RSSI="--"
        SPEED="--"
        FREQ="--"

        # Try using dumpsys wifi (works on most non-rooted shell if priv available, definitely works as root)
        # parsing depends on android version, but usually stable
        DUMP=$(cmd wifi status 2>/dev/null) 
        if [ -z "$DUMP" ]; then
             DUMP=$(dumpsys wifi | grep -A 10 "Current WifiInfo")
        fi

        # Extract RSSI (e.g., RSSI: -55)
        R_VAL=$(echo "$DUMP" | grep -o "RSSI: -[0-9]*" | head -n1 | cut -d' ' -f2)
        if [ -n "$R_VAL" ]; then RSSI="${R_VAL} dBm"; fi

        # Extract Link Speed (e.g., Link speed: 866 Mbps)
        S_VAL=$(echo "$DUMP" | grep -o "Link speed: [0-9]*" | head -n1 | cut -d' ' -f3)
        if [ -n "$S_VAL" ]; then SPEED="${S_VAL} Mbps"; fi

        # Extract Frequency (e.g., Frequency: 5240 MHz)
        F_VAL=$(echo "$DUMP" | grep -o "Frequency: [0-9]*" | head -n1 | cut -d' ' -f2)
        if [ -n "$F_VAL" ]; then FREQ="${F_VAL} MHz"; fi
        
        # Fallback to iw if dumpsys failed (common in some custom ROMs)
        if [ "$RSSI" = "--" ] && command -v iw >/dev/null; then
            IW_LINK=$(iw dev wlan0 link)
            
            # rssi from "signal: -46 dBm"
            R_VAL=$(echo "$IW_LINK" | grep "signal:" | awk '{print $2}')
            if [ -n "$R_VAL" ]; then RSSI="${R_VAL} dBm"; fi
            
            # speed from "tx bitrate: 866.7 MBit/s"
            S_VAL=$(echo "$IW_LINK" | grep "tx bitrate:" | awk '{print $3}')
            if [ -n "$S_VAL" ]; then SPEED="${S_VAL} Mbps"; fi
            
            # freq from "freq: 5180"
            F_VAL=$(echo "$IW_LINK" | grep "freq:" | awk '{print $2}')
            if [ -n "$F_VAL" ]; then FREQ="${F_VAL} MHz"; fi
        fi

        echo "{\"rssi\": \"$RSSI\", \"speed\": \"$SPEED\", \"freq\": \"$FREQ\"}"
        ;;

    "soft_reset")
        # Check for Monolithic Driver (Built-in)
        # If the driver is built-in, unbinding platform devices like icnss often causes
        # the system to hang or the wifi to never come back up.
        IS_MODULAR=false
        if [ -f "/proc/modules" ]; then
            if grep -qE "^(wlan|qca_cld3|qcacld|ath11k) " /proc/modules; then
                IS_MODULAR=true
            fi
        fi

        if [ "$IS_MODULAR" = false ]; then
            log_json "warning" "Monolithic driver detected. Reboot needed for changes to take place."
            exit 0
        fi

        DRIVER_DIR=$(find_driver_path)
        
        if [ -z "$DRIVER_DIR" ]; then
            log_json "error" "Could not locate Wi-Fi driver directory."
            exit 1
        fi

        # Find active devices in the driver directory
        DEVICES=$(ls -l "$DRIVER_DIR" | grep ^l | awk '{print $9}' | grep -E '^[0-9a-f.:]+$')

        if [ -z "$DEVICES" ]; then
            # Try finding devices directly if ls -l parsing failed (sometimes symlinks are different)
            DEVICES=$(find "$DRIVER_DIR" -maxdepth 1 -type l -exec basename {} \;)
        fi
        
        if [ -z "$DEVICES" ]; then
            log_json "warning" "No active devices found bound to driver $DRIVER_DIR."
            exit 0
        fi

        # Start Sequence
        svc wifi disable > /dev/null 2>&1
        sleep 1

        LOG_MSG=""
        for DEV in $DEVICES; do
            if [ -w "$DRIVER_DIR/unbind" ]; then
                echo "$DEV" > "$DRIVER_DIR/unbind"
                LOG_MSG="${LOG_MSG}Unbound $DEV. "
            fi
        done
        
        sleep 1 

        for DEV in $DEVICES; do
             if [ -w "$DRIVER_DIR/bind" ]; then
                echo "$DEV" > "$DRIVER_DIR/bind"
                LOG_MSG="${LOG_MSG}Bound $DEV. "
            fi
        done

        svc wifi enable > /dev/null 2>&1
        log_json "success" "Driver Reset Complete. $LOG_MSG"
        ;;

    *)
        log_json "error" "Unknown action: $1"
        exit 1
        ;;
esac
