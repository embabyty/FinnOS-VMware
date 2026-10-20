#!/bin/bash
# Build an ISO image of the FinnOS tree for use as a VMware CD-ROM.
#
#   vm/build-iso.sh [out.iso]
#
# The resulting ISO is the install disc: it carries the repository, the
# installer scripts and the assets, so the guest can install FinnOS
# without a host HTTP server. Boot the VM from an Arch Linux installer
# ISO, attach this disc as the second CD-ROM, and run the installer.
#
# The disc is labelled FINNOS, which is how the installer finds it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/finnos.iso}"

if ! command -v xorriso >/dev/null 2>&1 && ! command -v mkisofs >/dev/null 2>&1; then
  echo "error: need xorriso or mkisofs to build the ISO" >&2
  exit 1
fi

# The tree is staged first, so that what lands on the disc is exactly the
# sources and the assets: no build output, no .git, no binaries.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
tar -C "$ROOT" -cf - \
    --exclude='.git' \
    --exclude='*.o' \
    --exclude='*.a' \
    --exclude='*.iso' \
    --exclude='src/compositor/finn-comp' \
    --exclude='src/control/finnd' \
    --exclude='src/control/finnctl' \
    --exclude='src/tools/vgtest' \
    --exclude='src/tools/dockprev' \
    . | tar -C "$STAGE" -xf -

if command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs -r -J -V 'FINNOS' -o "$OUT" "$STAGE"
else
  mkisofs -r -J -V 'FINNOS' -o "$OUT" "$STAGE"
fi

echo "ISO written to $OUT"