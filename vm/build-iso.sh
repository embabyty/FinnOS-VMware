#!/bin/bash
# Build an ISO image of the FinnOS tree for use as a VMware CD-ROM.
#
#   vm/build-iso.sh [out.iso]
#
# The resulting ISO is a data disc: boot the VM from an Arch Linux
# installer ISO, mount this disc, and run the installer scripts from it.
# This removes the need for the Mac/Windows host to serve the repository
# over HTTP, which is the part of the old Parallels workflow that did not
# survive the move to VMware.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/finnos.iso}"

if command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs \
    -r -J -V 'FINNOS' \
    -o "$OUT" \
    -exclude '*.o' -exclude '*.a' -exclude '.git' \
    -exclude 'src/compositor/finn-comp' \
    -exclude 'src/control/finnd' \
    -exclude 'src/control/finnctl' \
    "$ROOT"
elif command -v mkisofs >/dev/null 2>&1; then
  mkisofs -r -J -V 'FINNOS' -o "$OUT" \
    -x '*.o' -x '*.a' -x '.git' \
    "$ROOT"
else
  echo "error: need xorriso or mkisofs to build the ISO" >&2
  exit 1
fi

echo "ISO written to $OUT"