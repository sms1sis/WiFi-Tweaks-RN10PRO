#!/system/bin/sh
# action.sh - Advanced Action Handler for WiFi-Config-Switcher
# Handles privileged operations: File I/O, KPatch, and Safe Driver Reset.

# Ensure we are in a clean environment
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin
MODDIR=${0%/*}/..

# --- Helper Functions ---

log_json() {
    # Output JSON formatted log for WebUI parsing
    echo "{\"status\": \"$1\", \"message\": \"$2\"}"
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
        # 1. Discover config file
        CONFIG_FILE=""
        for path in \
            "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/data/vendor/wifi/WCNSS_qcom_cfg.ini" \
            "/odm/etc/wifi/WCNSS_qcom_cfg.ini"; do
            if [ -f "$path" ]; then
                CONFIG_FILE="$path"
                break
            fi
        done

        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Config file path not found."
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
                # Safe defaults
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
        
        log_json "success" "Applied $MODE configuration to $CONFIG_FILE"
        ;;

    "read_config")
        # Securely read the config file
        # Search multiple paths
        CONFIG_FILE=""
        for path in \
            "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/data/vendor/wifi/WCNSS_qcom_cfg.ini" \
            "/odm/etc/wifi/WCNSS_qcom_cfg.ini"; do
            if [ -f "$path" ]; then
                CONFIG_FILE="$path"
                break
            fi
        done

        if [ -n "$CONFIG_FILE" ]; then
            cat "$CONFIG_FILE"
        else
            echo "Error: Config file not found in standard paths."
        fi
        ;;

    "save_config")
        # Save content from stdin to the discovered config file
        # Expects base64 encoded input to prevent shell injection
        # Usage: echo "base64_content" | sh action.sh save_config
        
        # 1. Rediscover path (stateless)
        CONFIG_FILE=""
        for path in \
            "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/data/vendor/wifi/WCNSS_qcom_cfg.ini" \
            "/odm/etc/wifi/WCNSS_qcom_cfg.ini"; do
            if [ -f "$path" ]; then
                CONFIG_FILE="$path"
                break
            fi
        done

        if [ -z "$CONFIG_FILE" ]; then
            log_json "error" "Config file path not found."
            exit 1
        fi

        # 2. Read stdin, decode, and write
        # We rely on the caller piping the base64 content
        read -r B64_DATA
        if [ -n "$B64_DATA" ]; then
            echo "$B64_DATA" | base64 -d > "$CONFIG_FILE"
            if [ $? -eq 0 ]; then
                log_json "success" "Config saved to $CONFIG_FILE"
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

    "soft_reset")
        DRIVER_DIR=$(find_driver_path)
        
        if [ -z "$DRIVER_DIR" ]; then
            log_json "error" "Could not locate Wi-Fi driver directory."
            exit 1
        fi

        # Find active devices in the driver directory
        # Looks for symlinks (devices) or directories that start with numbers (bus IDs)
        DEVICES=$(ls -l "$DRIVER_DIR" | grep ^l | awk '{print $9}' | grep -E '^[0-9a-f.:]+$')

        if [ -z "$DEVICES" ]; then
            log_json "warning" "No active devices found bound to driver $DRIVER_DIR."
            exit 0
        fi

        # Start Sequence
        svc wifi disable
        sleep 1

        LOG_MSG=""
        for DEV in $DEVICES;
 do
            if [ -w "$DRIVER_DIR/unbind" ]; then
                echo "$DEV" > "$DRIVER_DIR/unbind"
                LOG_MSG="${LOG_MSG}Unbound $DEV. "
            fi
        done
        
        sleep 1 # Wait for kernel to release resources

        for DEV in $DEVICES;
 do
             if [ -w "$DRIVER_DIR/bind" ]; then
                echo "$DEV" > "$DRIVER_DIR/bind"
                LOG_MSG="${LOG_MSG}Bound $DEV. "
            fi
        done

        svc wifi enable
        log_json "success" "Driver Reset Complete. $LOG_MSG"
        ;;

    *)
        log_json "error" "Unknown action: $1"
        exit 1
        ;; 
esac