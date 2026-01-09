#!/system/bin/sh

SKIPUNZIP=0

ui_print "- Installing WiFi Config Switcher V4..."

# Set execute permissions
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

# --- Config Discovery & Setup ---
ui_print "- Detecting Wi-Fi Configuration..."

CONFIG_SRC=""
CONFIG_DEST=""

# List of potential paths for the config file
# We are looking for WCNSS_qcom_cfg.ini which is standard for Qualcomm chips
# Add other filenames here if expanding support (e.g. wlan_cfg.ini)
PATHS_TO_CHECK="
/vendor/etc/wifi/WCNSS_qcom_cfg.ini
/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini
/data/vendor/wifi/WCNSS_qcom_cfg.ini
/odm/etc/wifi/WCNSS_qcom_cfg.ini
"

for path in $PATHS_TO_CHECK; do
    if [ -f "$path" ]; then
        CONFIG_SRC="$path"
        ui_print "  Found config at: $path"
        break
    fi
done

if [ -z "$CONFIG_SRC" ]; then
    ui_print "! Warning: No standard Wi-Fi config file found."
    ui_print "! The module will install but may not function until a config is manually placed."
else
    # Determine the systemless path
    # We strip the leading mount point (e.g., /vendor) to construct the module path
    # Magisk modules mount to /system (or /vendor via /system/vendor)
    
    case "$CONFIG_SRC" in
        /vendor/*)
            REL_PATH="${CONFIG_SRC#/vendor}"
            CONFIG_DEST="$MODPATH/system/vendor$REL_PATH"
            ;;
        /system/*)
            REL_PATH="${CONFIG_SRC#/system}"
            CONFIG_DEST="$MODPATH/system$REL_PATH"
            ;;
        /odm/*)
             # Magisk usually handles ODM via /system/odm or similar depending on android version
             # For safety, we map to system/odm if it exists, or just warn.
             REL_PATH="${CONFIG_SRC#/odm}"
             CONFIG_DEST="$MODPATH/system/odm$REL_PATH"
             ;;
        *)
            # Fallback or data path (which can't be systemlessly replaced easily without overlay)
            # If it's in /data, we might just copy it to system/vendor/etc/wifi as an override attempt
            ui_print "! Config is in /data. Creating systemless override in /system/vendor/etc/wifi/"
            CONFIG_DEST="$MODPATH/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini"
            ;;
    esac

    ui_print "- creating destination: $(dirname "$CONFIG_DEST")"
    mkdir -p "$(dirname "$CONFIG_DEST")"
    
    ui_print "- Copying config to module..."
    cp "$CONFIG_SRC" "$CONFIG_DEST"
    
    # Ensure the file is writable by the module logic (system/root ownership is usually fine)
    # But for editing via action.sh (running as root), it's fine.
fi

ui_print "- Module ready."