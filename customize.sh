#!/system/bin/sh

SKIPUNZIP=0

ui_print "- Installing WiFi Config Switcher V4..."

# Set execute permissions
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

ui_print "- Module ready."