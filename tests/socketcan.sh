#!/bin/bash
# cansocket on virtual CAN interfaces, in a user network namespace.
#
#   bash tests/socketcan.sh
#
# The package's suites run on a machine with no CAN interface, so the
# paths of src/cansocket.nv that need one carry `cov: skip` markers that
# name this script.  It builds tests/vcan_probe.nv, then runs it in a
# new user, network and mount namespace (`unshare -rnm`), where it adds
# vcan0 with the classic MTU of 16 bytes and vcan1 with the CAN FD MTU of
# 72 bytes, brings both up, and mounts sysfs for that namespace, so
# /sys/class/net lists the two interfaces.  No privilege is needed on a
# kernel that allows unprivileged user namespaces and has the vcan
# module.  The probe prints one PASS or FAIL line per check and a count;
# the script exits 1 when a check fails or the namespace cannot be set
# up.
#
# Needs unshare (util-linux) and ip (iproute2).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
# The compiler is $NOVO, or the `novo` on PATH.
NOVO="${NOVO:-$(command -v novo)}"

echo "══════════════════════════════════════════"
echo "  can-nv: cansocket on vcan0 and vcan1"
echo "══════════════════════════════════════════"

[ -n "$NOVO" ] && [ -x "$NOVO" ] || { echo "ERROR: no novo found; set NOVO or put novo on PATH" >&2; exit 1; }
for t in unshare ip; do
  command -v "$t" > /dev/null || { echo "  - $t not found; skipped"; exit 0; }
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/can_nv_socketcan_XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PROBE="$WORK/vcan_probe"
if ! (cd "$PKG" && "$NOVO" build -o "$PROBE" tests/vcan_probe.nv) > "$WORK/build.log" 2>&1; then
  echo "FAIL tests/vcan_probe.nv does not build"
  tail -10 "$WORK/build.log" | sed 's/^/    /'
  exit 1
fi
echo "PASS tests/vcan_probe.nv builds"

SETUP='ip link add vcan0 type vcan &&
  ip link set vcan0 up &&
  ip link add vcan1 type vcan &&
  ip link set vcan1 mtu 72 &&
  ip link set vcan1 up &&
  mount -t sysfs sysfs /sys'
if ! unshare -rnm sh -c "$SETUP" > "$WORK/setup.log" 2>&1; then
  echo "FAIL the namespace with vcan0 and vcan1 could not be set up"
  sed 's/^/    /' "$WORK/setup.log"
  echo "    the kernel needs unprivileged user namespaces and the vcan module"
  exit 1
fi

unshare -rnm sh -c "$SETUP && exec \"\$0\"" "$PROBE" | tee "$WORK/probe.log"
status=${PIPESTATUS[0]}
if ! grep -qE '^[0-9]+ of [0-9]+ passed$' "$WORK/probe.log"; then
  echo "FAIL the probe did not run to its end"
  exit 1
fi
exit "$status"
