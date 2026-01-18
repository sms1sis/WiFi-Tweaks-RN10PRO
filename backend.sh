#!/system/bin/sh
# backend.sh - Optimized for Redmi Note 10 Pro (Sweet)
export PATH=/data/adb/ap/bin:/data/adb/ksu/bin:/system/bin:/system/xbin:/vendor/bin
MODDIR=${0%/*}

log_json() { echo "{\"status\": \"$1\", \"message\": \"$2\"}"; }

find_module_config() {
    local existing=$(find "$MODDIR" -name "WCNSS_qcom_cfg.ini" -print -quit)
    [ -n "$existing" ] && echo "$existing" || return 1
}

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
            LINK=$(iw dev wlan0 link)
            RSSI=$(echo "$LINK" | grep -o "signal: -[0-9]*" | awk '{print $2}')" dBm"
            SPEED=$(echo "$LINK" | grep -o "tx bitrate: [0-9.]*" | awk '{print $3}')" Mbps"
            FREQ=$(echo "$LINK" | grep -o "freq: [0-9]*" | awk '{print $2}')" MHz"
        fi
        if [ "$RSSI" = "--" ] && [ -r "/proc/net/wireless" ]; then
            RSSI=$(grep "wlan0" /proc/net/wireless | awk '{print $4}' | cut -d. -f1)" dBm"
        fi
        echo "{\"rssi\": \"$RSSI\", \"speed\": \"$SPEED\", \"freq\": \"$FREQ\"}"
        ;;

    "soft_reset")
        # --- MONOLITHIC GUARD ---
        # If the 'module' file is missing (as you confirmed), it's built-in.
        if [ ! -e "/sys/class/net/wlan0/device/driver/module" ]; then
            log_json "warning" "Built-in driver detected. Please reboot manually to apply changes."
            exit 0
        fi

        # Logic for Loadable Modules ONLY (Safe)
        DEVICE_PATH="/sys/class/net/wlan0/device"
        if [ -L "$DEVICE_PATH" ]; then
            DRIVER_PATH=$(readlink "$DEVICE_PATH/driver" 2>/dev/null)
            DEVICE=$(basename $(readlink "$DEVICE_PATH"))
            DRIVER=$(basename "$DRIVER_PATH")
            BUS=$(basename $(readlink "$DEVICE_PATH/subsystem"))
            
            svc wifi disable >/dev/null 2>&1
            echo "$DEVICE" > "/sys/bus/$BUS/drivers/$DRIVER/unbind" 2>/dev/null
            sleep 1
            echo "$DEVICE" > "/sys/bus/$BUS/drivers/$DRIVER/bind" 2>/dev/null
            svc wifi enable >/dev/null 2>&1
            log_json "success" "Driver Reset Complete."
        fi
        ;;

    "get_mode")
        [ -f "$MODDIR/mode_status.txt" ] && echo "{\"mode\": \"$(cat $MODDIR/mode_status.txt)\"}" || echo "{\"mode\": \"unknown\"}"
        ;;
esac
