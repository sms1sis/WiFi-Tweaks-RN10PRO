#!/system/bin/sh
# backend.sh - Advanced Action Handler for WiFi-Config-Switcher
# Handles privileged operations: File I/O, KPatch, and Safe Driver Reset.

# Ensure we are in a clean environment
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin
MODDIR=${0%/*}

# --- Helper Functions ---

log_json() {
    # Output JSON formatted log for WebUI parsing
    echo "{"status": "$1", "message": "$2"}"
}

find_module_config() {
    # 1. Search for existing config in module (Recursive find)
    local existing=$(find "$MODDIR" -name "WCNSS_qcom_cfg.ini" -print -quit)
    if [ -n "$existing" ]; then
        echo "$existing"
        return 0
    fi

    # 2. Self-Healing: If not found in module, find in system and import
    # This ensures we always have a base config to patch (Systemless-ly)
    local system_path=""
    for path in "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
                "/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
                "/data/vendor/wifi/WCNSS_qcom_cfg.ini" \
                "/odm/etc/wifi/WCNSS_qcom_cfg.ini"; do
        if [ -f "$path" ]; then
            system_path="$path"
            break
        fi
    done

    if [ -n "$system_path" ]; then
        # Construct destination path to mirror system structure for Magisk/KSU overlay
        local dest_file=""
        
        case "$system_path" in
            /vendor/*)
                # Map /vendor/... -> $MODDIR/system/vendor/...
                dest_file="$MODDIR/system/vendor${system_path#/vendor}"
                ;;
            /system/*)
                # Map /system/... -> $MODDIR/system/...
                dest_file="$MODDIR/system${system_path#/system}"
                ;;
            /odm/*)
                # Map /odm/... -> $MODDIR/system/odm/...
                dest_file="$MODDIR/system/odm${system_path#/odm}"
                ;;
            *)
                # Fallback for /data or others -> Force into system/vendor
                dest_file="$MODDIR/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini"
                ;;
        esac

        mkdir -p "$(dirname "$dest_file")"
        cp "$system_path" "$dest_file"
        
        # Verify copy
        if [ -f "$dest_file" ]; then
            echo "$dest_file"
            return 0
        fi
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
            log_json "error" "Config file not found in system or module."
            exit 1
        fi
        
        # Create a backup of the 'stock' imported config if not exists
        if [ ! -f "${CONFIG_FILE}.bak" ]; then
            cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        fi

        # 2. Apply parameters based on mode
        case "$MODE" in
            "perf")
                apply_param "$CONFIG_FILE" "gEnableBmps" "0"
                apply_param "$CONFIG_FILE" "TxPower2g" "17"
                apply_param "$CONFIG_FILE" "TxPower5g" "17"
                apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "1"
                ;;
            "balanced")
                apply_param "$CONFIG_FILE" "gEnableBmps" "1"
                apply_param "$CONFIG_FILE" "TxPower2g" "14"
                apply_param "$CONFIG_FILE" "TxPower5g" "14"
                apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "1"
                ;;
            "stock")
                # Restore from backup if available, else apply safe defaults
                if [ -f "${CONFIG_FILE}.bak" ]; then
                    cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
                else
                    apply_param "$CONFIG_FILE" "gEnableBmps" "1"
                    apply_param "$CONFIG_FILE" "TxPower2g" "12"
                    apply_param "$CONFIG_FILE" "TxPower5g" "12"
                    apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "0"
                fi
                ;;
            *)
                log_json "error" "Unknown mode: $MODE"
                exit 1
                ;;
        esac
        
        # Sync changes to disk
        sync
        echo "$MODE" > "$MODDIR/mode_status.txt"
        log_json "success" "Applied $MODE to module config."
        ;;

    "get_mode")
        if [ -f "$MODDIR/mode_status.txt" ]; then
            CURRENT_MODE=$(cat "$MODDIR/mode_status.txt")
            echo "{"mode": "$CURRENT_MODE"}"
        else
            echo "{"mode": "unknown"}"
        fi
        ;;

    "stats")
        # specific wifi stats fetcher
        # Returns JSON: {"rssi": "...", "speed": "...", "freq": "..."}
        
        RSSI="--"
        SPEED="--"
        FREQ="--"

        # Try using dumpsys wifi
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
        
        # Fallback to iw
        if [ "$RSSI" = "--" ] && command -v iw >/dev/null; then
            IW_LINK=$(iw dev wlan0 link)
            R_VAL=$(echo "$IW_LINK" | grep "signal:" | awk '{print $2}')
            if [ -n "$R_VAL" ]; then RSSI="${R_VAL} dBm"; fi
            
            S_VAL=$(echo "$IW_LINK" | grep "tx bitrate:" | awk '{print $3}')
            if [ -n "$S_VAL" ]; then SPEED="${S_VAL} Mbps"; fi
            
            F_VAL=$(echo "$IW_LINK" | grep "freq:" | awk '{print $2}')
            if [ -n "$F_VAL" ]; then FREQ="${F_VAL} MHz"; fi
        fi

        echo "{"rssi": "$RSSI", "speed": "$SPEED", "freq": "$FREQ"}"
        ;;

    "soft_reset")
        # Check for Monolithic Driver (Built-in)
        IS_MODULAR=false
        if [ -f "/proc/modules" ]; then
            if grep -qE "^(wlan|qca_cld3|qcacld|ath11k) " /proc/modules; then
                IS_MODULAR=true
            fi
        fi

        if [ "$IS_MODULAR" = false ]; then
            log_json "warning" "Monolithic/Built-in driver detected. Please reboot your device to apply changes."
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