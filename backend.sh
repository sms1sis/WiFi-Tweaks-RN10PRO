#!/system/bin/sh
# backend.sh - Optimized for Redmi Note 10 Pro (Sweet)
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin
MODDIR=${0%/*}

log_json() { echo "{\"status\": \"$1\", \"message\": \"$2\"}"; }

find_module_config() {
    local existing=$(find "$MODDIR" -name "WCNSS_qcom_cfg.ini" -print -quit)
    [ -n "$existing" ] && echo "$existing" || return 1
}

# IMPROVED: Handles comments and prevents duplicates
apply_param() {
    local file="$1" key="$2" value="$3"
    [ ! -f "$file" ] && return 1
    if grep -qE "^[#[:space:]]*${key}[[:space:]]*=" "$file"; then
        sed -i "s|^[#[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

case "$1" in
    "apply_mode")
        MODE="$2"
        CONFIG_FILE=$(find_module_config)
        [ -z "$CONFIG_FILE" ] && { log_json "error" "Config missing"; exit 1; }
        
        [ ! -f "${CONFIG_FILE}.bak" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

        case "$MODE" in
            "perf")
                apply_param "$CONFIG_FILE" "gEnableBmps" "0"
                apply_param "$CONFIG_FILE" "gEnableImps" "0"
                apply_param "$CONFIG_FILE" "gDataInactivityTimeout" "0"
                apply_param "$CONFIG_FILE" "TxPower2g" "17"
                apply_param "$CONFIG_FILE" "TxPower5g" "17"
                apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "1"
                ;;
            "balanced")
                apply_param "$CONFIG_FILE" "gEnableBmps" "1"
                apply_param "$CONFIG_FILE" "gEnableImps" "1"
                apply_param "$CONFIG_FILE" "gDataInactivityTimeout" "200"
                apply_param "$CONFIG_FILE" "TxPower2g" "14"
                apply_param "$CONFIG_FILE" "TxPower5g" "14"
                apply_param "$CONFIG_FILE" "gChannelBondingMode24GHz" "1"
                ;;
            "stock")
                cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
                ;;
        esac
        sync
        echo "$MODE" > "$MODDIR/mode_status.txt"
        log_json "success" "Mode $MODE applied."
        ;;

    "stats")
        RSSI="--" SPEED="--" FREQ="--"
        if command -v iw >/dev/null; then
            LINK=$(iw dev wlan0 link 2>/dev/null)
            RSSI=$(echo "$LINK" | grep "signal:" | awk '{print $2}')
            [ -n "$RSSI" ] && RSSI="${RSSI} dBm" || RSSI="--"
            SPEED=$(echo "$LINK" | grep "tx bitrate:" | awk '{print $3}')
            [ -n "$SPEED" ] && SPEED="${SPEED} Mbps" || SPEED="--"
            FREQ=$(echo "$LINK" | grep "freq:" | awk '{print $2}')
            [ -n "$FREQ" ] && FREQ="${FREQ} MHz" || FREQ="--"
        fi

        if [ "$RSSI" = "--" ] && [ -r "/proc/net/wireless" ]; then
            RSSI=$(grep "wlan0" /proc/net/wireless | awk '{print $4}' | cut -d. -f1)" dBm"
        fi
        echo "{\"rssi\": \"$RSSI\", \"speed\": \"$SPEED\", \"freq\": \"$FREQ\"}"
        ;;
    
    "get_mode")
        [ -f "$MODDIR/mode_status.txt" ] && echo "{\"mode\": \"$(cat $MODDIR/mode_status.txt)\"}" || echo "{\"mode\": \"unknown\"}"
        ;;

    "soft_reset")
        DEVICE_PATH="/sys/class/net/wlan0/device"
        if [ -L "$DEVICE_PATH" ]; then
            DRIVER_PATH=$(readlink "$DEVICE_PATH/driver" 2>/dev/null)
            if [ -n "$DRIVER_PATH" ]; then
                DEVICE=$(basename $(readlink "$DEVICE_PATH"))
                DRIVER=$(basename "$DRIVER_PATH")
                BUS=$(basename $(readlink "$DEVICE_PATH/subsystem"))
                
                echo "$DEVICE" > "/sys/bus/$BUS/drivers/$DRIVER/unbind" 2>/dev/null
                sleep 1
                echo "$DEVICE" > "/sys/bus/$BUS/drivers/$DRIVER/bind" 2>/dev/null
                log_json "success" "Reset $DRIVER ($DEVICE)"
            else
                log_json "warning" "Monolithic driver - Reboot required for changes to take effect"
            fi
        else
            log_json "warning" "Monolithic driver - Reboot required for changes to take effect"
        fi
        ;;
esac
