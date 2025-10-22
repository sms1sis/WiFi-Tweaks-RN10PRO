#!/system/bin/sh
# post-fs-data.sh
# Runs once after filesystems are mounted

MODDIR=${0%/*}

# Ensure webui assets are readable
chmod 0644 "$MODDIR"/webui/* 2>/dev/null

# Log for debugging
echo "[wifi-ini-highperf] post-fs-data executed" > /dev/kmsg