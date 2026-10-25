#!/bin/sh
# Runs tests/socketcan_probe.nv against two virtual CAN interfaces
# inside a user, mount and network namespace (a fresh sysfs, since
# /sys/class/net follows the namespace that mounted it): no privileges, and the host's
# interfaces are not visible or touched.
#
#   tests/socketcan.sh [path/to/novo]
set -e
NOVO=${1:-novo}
HERE=$(cd "$(dirname "$0")/.." && pwd)
exec unshare -rnm sh -c '
    mount -t sysfs sysfs /sys
    ip link add dev vcan0 type vcan
    ip link add dev vcan1 type vcan
    ip link set vcan0 up
    ip link set vcan1 up
    cd "$1" && "$2" run tests/socketcan_probe.nv
' sh "$HERE" "$NOVO"
