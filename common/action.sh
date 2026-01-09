#!/system/bin/sh
# action.sh - Privileged actions for WiFi-Config-Switcher WebUI
# Handles File I/O, KPatch injection, and Driver Soft-Reset

# Redirect stderr to stdout for easier capture in WebUI
exec 2>&1

ACTION="$1"
ARG1="$2"

# 1. Config Reading
case "$ACTION" in
    "read_stock")
        # Direct read of the vendor configuration
        # Check multiple common locations
        FOUND="false"
        for FILE in \
            "/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/system/vendor/etc/wifi/WCNSS_qcom_cfg.ini" \
            "/data/vendor/wifi/WCNSS_qcom_cfg.ini" \
            "/vendor/firmware/wlan/qca_cld/WCNSS_qcom_cfg.ini" \
            "/system/etc/wifi/WCNSS_qcom_cfg.ini"; do
            
            if [ -f "$FILE" ]; then
                cat "$FILE"
                FOUND="true"
                break
            fi
        done
        
        if [ "$FOUND" = "false" ]; then
            echo "Error: Could not find WCNSS_qcom_cfg.ini in standard paths."
        fi
        exit 0
        ;; 
    
    "check_kpatch")
        # Check if kernel supports livepatching/kpatch
        # Common indicators: /sys/kernel/security/kpatch or /proc/config.gz grep
        SUPPORTED="false"
        if [ -d "/sys/kernel/security/kpatch" ]; then
            SUPPORTED="true"
        elif [ -f "/sys/kernel/livepatch" ]; then # Some kernels use this
            SUPPORTED="true"
        fi
        
        # Check if we have a .kpm file to inject
        KPM_FILE=$(find /data/adb/modules/wifi_tweaks -name "*.kpm" | head -n 1)
        HAS_KPM="false"
        [ -n "$KPM_FILE" ] && HAS_KPM="true"

        echo "{\"supported\": $SUPPORTED, \"has_kpm\": $HAS_KPM, \"kpm_path\": \"$KPM_FILE\"}"
        exit 0
        ;;

    "inject_patch")
        KPM_FILE="$ARG1"
        if [ ! -f "$KPM_FILE" ]; then
            # Try to find it auto
            KPM_FILE=$(find /data/adb/modules/wifi_tweaks -name "*.kpm" | head -n 1)
        fi

        if [ -f "$KPM_FILE" ]; then
            # Use kpatch-next or insmod if kpatch tool not available
            # Assuming kpatch tool might not be in path, rely on insmod/kpatch-next mechanics
            # KSU-Next often provides 'kpatch' binary
            if command -v kpatch >/dev/null; then
                kpatch load "$KPM_FILE"
            else
                # Fallback to insmod if it's a raw module, but kpatch usually needs 'kpatch load'
                # Attempt manual insertion if it is a kpatch module
                insmod "$KPM_FILE"
            fi
            
            if [ $? -eq 0 ]; then
                echo "Success: Patch injected."
            else
                echo "Error: Failed to inject patch."
            fi
        else
            echo "Error: No .kpm file found."
        fi
        exit 0
        ;;

    "soft_reset")
        echo "[*] Starting Soft-Reset..."
        
        # 1. Disable Wi-Fi Service
        svc wifi disable
        echo "[-] Wi-Fi service disabled."
        sleep 2

        # 2. Dynamic Driver Finding
        # Look for wlan or qca_cld3 in platform drivers
        DRIVER_PATH=""
        for d in "wlan" "qca_cld3" "icnss"; do
            if [ -d "/sys/bus/platform/drivers/$d" ]; then
                DRIVER_PATH="/sys/bus/platform/drivers/$d"
                break
            fi
        done
        
        # If not found in platform, check PCI (some devices use PCI for wlan)
        if [ -z "$DRIVER_PATH" ]; then
             DRIVER_PATH=$(find /sys/bus/pci/drivers -name "ath11k_pci" -o -name "qcacld" 2>/dev/null | head -n 1)
        fi

        if [ -n "$DRIVER_PATH" ]; then
            echo "[*] Found driver at: $DRIVER_PATH"
            
            # 3. Unbind
            # We need to find the device ID to unbind. Usually listed in the driver dir.
            # But writing '1' to unbind might not work universally on all kernels/drivers if it expects a device ID.
            # However, prompt suggested 'echo 1 > .../unbind' which is unusual for standard linux (usually echo "device_id" > unbind).
            # But some android drivers have a global kill switch or we unbind the specific device.
            
            # Let's try to identify the device bound to this driver.
            # The 'unbind' file expects a BusID.
            
            # Simple approach: Iterate over links in the driver directory that look like devices
            DEVICES=$(find "$DRIVER_PATH" -maxdepth 1 -type l -name "*.*" -o -name "0000:*" | xargs -n 1 basename)
            
            if [ -n "$DEVICES" ]; then
                for DEV in $DEVICES; do
                    echo "[-] Unbinding device: $DEV"
                    echo "$DEV" > "$DRIVER_PATH/unbind"
                done
                
                sleep 2
                
                # 4. Bind
                for DEV in $DEVICES; do
                    echo "[+] Binding device: $DEV"
                    echo "$DEV" > "$DRIVER_PATH/bind"
                done
                echo "[*] Driver reload cycle complete."
            else
                echo "[!] No devices found bound to driver. Skipping low-level reload."
            fi
        else
            echo "[!] Could not locate WLAN driver path. Skipping driver reload."
        fi

        # 5. Re-enable Wi-Fi
        sleep 1
        svc wifi enable
        echo "[+] Wi-Fi service enabled."
        echo "Soft-Reset Complete."
        exit 0
        ;; 
    
    *)
        echo "Usage: $0 {read_stock|check_kpatch|inject_patch|soft_reset}"
        exit 1
        ;; 
esac
