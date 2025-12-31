#!/system/bin/sh

SKIPUNZIP=0

ui_print "- Installing WiFi-Config-Switcher..."

# Ensure config.ini exists for WebUI
# The WebUI expects common/config.ini to exist.
# Since it is a runtime file, we create it from original_stock.ini if missing.
if [ ! -f "$MODPATH/common/config.ini" ]; then
    if [ -f "$MODPATH/common/original_stock.ini" ]; then
        ui_print "- Creating default config.ini from stock backup..."
        cp "$MODPATH/common/original_stock.ini" "$MODPATH/common/config.ini"
        chmod 644 "$MODPATH/common/config.ini"
    else
        ui_print "! Warning: common/original_stock.ini not found!"
    fi
fi
