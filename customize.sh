#!/system/bin/sh
SKIPUNZIP=0
ui_print "- Installing WiFi Tuner for Redmi Note 10 Pro..."

# Prioritize Clean System Paths (No /data for safety)
CONFIG_SRC=""
for path in "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" "/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini"; do
    if [ -f "$path" ]; then
        CONFIG_SRC="$path"
        break
    fi
done

if [ -n "$CONFIG_SRC" ]; then
    # Create systemless path
    DEST="$MODPATH/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini"
    mkdir -p "$(dirname "$DEST")"
    cp "$CONFIG_SRC" "$DEST"
    ui_print "- Config imported successfully."
else
    ui_print "! Warning: Hardware config not found."
fi
