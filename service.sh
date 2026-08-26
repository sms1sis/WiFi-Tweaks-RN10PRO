#!/system/bin/sh
# service.sh — runs on every boot after module is mounted
MODDIR=${0%/*}
chmod +x "$MODDIR/backend.sh"

# Re-apply the saved performance profile on boot.
# This matters after a module update/reflash: customize.sh copies a fresh
# (unmodified) config from /vendor into the overlay, which would otherwise
# silently downgrade back to stock settings until the user re-applies manually.
#
# We read the mode written by backend.sh to /data/adb/wcs/mode_status.txt
# and re-apply it if it is perf or balanced (stock = no action needed).
WCS_STATE_DIR="/data/adb/wcs"
MODE_FILE="${WCS_STATE_DIR}/mode_status.txt"

if [ -f "$MODE_FILE" ]; then
    SAVED_MODE=$(cat "$MODE_FILE" 2>/dev/null | tr -d '[:space:]')
    case "$SAVED_MODE" in
        perf|balanced)
            # Re-apply silently — output goes to log only
            sh "$MODDIR/backend.sh" apply_mode "$SAVED_MODE" \
                >> "${WCS_STATE_DIR}/boot_restore.log" 2>&1
            ;;
        custom)
            sh "$MODDIR/backend.sh" reapply_custom \
                >> "${WCS_STATE_DIR}/boot_restore.log" 2>&1
            ;;
        *)
            # Stock (or unset) needs no re-apply, but module.prop's
            # description gets shipped fresh with every module update —
            # any previously-synced "[Profile: ...]" tag is gone until
            # this runs, so re-sync it on every boot regardless of mode.
            sh "$MODDIR/backend.sh" sync_description \
                >> "${WCS_STATE_DIR}/boot_restore.log" 2>&1
            ;;
    esac
else
    # No saved mode yet (fresh install, no profile chosen at install time) —
    # still sync so the card reads "Stock" instead of the bare default text.
    sh "$MODDIR/backend.sh" sync_description \
        >> "${WCS_STATE_DIR}/boot_restore.log" 2>&1
fi
