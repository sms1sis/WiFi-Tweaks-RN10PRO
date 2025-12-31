#!/system/bin/sh

SKIPUNZIP=0

ui_print "- Installing WiFi-Config-Switcher..."

# Ensure config.ini exists for WebUI
# The WebUI expects webroot/config.ini to exist.
if [ ! -f "$MODPATH/webroot/config.ini" ]; then
    if [ -f "$MODPATH/common/original_stock.ini" ]; then
        ui_print "- Creating default config.ini from stock backup..."
        cp "$MODPATH/common/original_stock.ini" "$MODPATH/webroot/config.ini"
        chmod 644 "$MODPATH/webroot/config.ini"
    else
        ui_print "! Warning: common/original_stock.ini not found!"
    fi
fi

# Set execute permission for the main script
set_perm "$MODPATH/common/switch_mode.sh" 0 0 0755