#!/system/bin/sh
# service.sh
# Background service script

MODDIR=${0%/*}

# Just log that the service ran
echo "[wifi-ini-highperf] service executed" > /dev/kmsg