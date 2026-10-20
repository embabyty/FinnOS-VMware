#!/bin/bash
# Build the bootable FinnOS install ISO.
#
#   ARCH_ISO=/path/to/archlinux-x86_64.iso vm/build-iso.sh [out.iso]
#
# The Arch Linux ISO is the base: it carries the kernel, the initramfs and
# the live environment the installer runs in. This script puts the FinnOS
# tree into that live root at /opt/finnos, then writes the disc back with
# the same boot images and the same label, so the result boots under UEFI
# (which is what VMware uses) and under BIOS.
#
# The base image is not stored in the tree: download it from
# https://archlinux.org/download/ and pass it in ARCH_ISO, or put it at
# .cache/archlinux-x86_64.iso.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/finnos.iso}"
BASE="${ARCH_ISO:-$ROOT/.cache/archlinux-x86_64.iso}"

die() { echo "error: $*" >&2; exit 1; }

for tool in xorriso unsquashfs mksquashfs sha512sum tar; do
  command -v "$tool" >/dev/null 2>&1 || die "need $tool (xorriso, squashfs-tools)"
done

[ -f "$BASE" ] || die "base image not found: $BASE
  download https://archlinux.org/download/ and set ARCH_ISO"
[ "$(cd "$(dirname "$BASE")" && pwd)/$(basename "$BASE")" != \
  "$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")" ] || \
  die "the output would overwrite the base image"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> staging the payload"
mkdir -p "$WORK/payload"
tar -C "$ROOT" -cf - \
    --exclude='.git' \
    --exclude='.cache' \
    --exclude='*.o' \
    --exclude='*.a' \
    --exclude='*.iso' \
    --exclude='src/compositor/finn-comp' \
    --exclude='src/control/finnd' \
    --exclude='src/control/finnctl' \
    --exclude='src/tools/vgtest' \
    --exclude='src/tools/dockprev' \
    . | tar -C "$WORK/payload" -xf -

echo "==> finding the live root on $BASE"
SFS=""
for p in /arch/x86_64/airootfs.sfs /arch/boot/x86_64/airootfs.sfs /arch/airootfs.sfs; do
  if xorriso -osirrox on -indev "$BASE" -extract "$p" "$WORK/airootfs.sfs" 2>/dev/null; then
    SFS="$p"
    break
  fi
done
[ -n "$SFS" ] || die "no airootfs.sfs on the base image; is it an Arch Linux ISO?"

echo "==> unpacking $SFS"
unsquashfs -q -d "$WORK/root" "$WORK/airootfs.sfs" >/dev/null

echo "==> adding FinnOS to the live root"
mkdir -p "$WORK/root/opt/finnos"
cp -a "$WORK/payload/." "$WORK/root/opt/finnos/"

mkdir -p "$WORK/root/usr/local/bin"
cat > "$WORK/root/usr/local/bin/finn-install" <<'EOF'
#!/bin/bash
# Install FinnOS from this disc onto /dev/sda.
exec /opt/finnos/vm/finn-install.sh "$@"
EOF
chmod 755 "$WORK/root/usr/local/bin/finn-install"

mkdir -p "$WORK/root/etc"
cat >> "$WORK/root/etc/issue" <<'EOF'

FinnOS install disc. Run "finn-install" to install onto /dev/sda.
EOF

echo "==> repacking the live root"
mksquashfs "$WORK/root" "$WORK/airootfs.sfs" -noappend -comp zstd -all-root \
    -no-progress >/dev/null
(cd "$WORK" && sha512sum airootfs.sfs > airootfs.sha512)

echo "==> writing $OUT"
rm -f "$OUT"
SFS_DIR="${SFS%/*}"
xorriso -indev "$BASE" -outdev "$OUT" \
    -map "$WORK/airootfs.sfs" "$SFS" \
    -map "$WORK/airootfs.sha512" "$SFS_DIR/airootfs.sha512" \
    -boot_image any replay -commit

echo
echo "==> boot images on the result"
xorriso -indev "$OUT" -report_el_torito plain 2>/dev/null | sed 's/^/    /'
echo
echo "ISO written to $OUT"
echo "Boot it in VMware, or test it here: vm/test-boot.sh $OUT"