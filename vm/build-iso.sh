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
trap 'chmod -R u+rwX "$WORK" 2>/dev/null || true; rm -rf "$WORK" 2>/dev/null || true' EXIT

# The live root has file capabilities on ping and newuidmap. Only root may
# write those xattrs; without them the tools in the live environment simply
# have no capabilities, which is acceptable but worth saying out loud.
XATTR=(-no-xattrs)
if [ "$(id -u)" = 0 ]; then
  XATTR=()
else
  echo "==> not root: file capabilities are dropped from the live root"
fi

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
unsquashfs -q "${XATTR[@]}" -d "$WORK/root" "$WORK/airootfs.sfs" >/dev/null

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

# The default boot entry passes finn.install on the kernel command line.
# When it is there, the live shell hands over to the installer once it is
# up, after a moment to back out.
PROFILE="$WORK/root/root/.bash_profile"
touch "$PROFILE"
cat >> "$PROFILE" <<'EOF'

# Booted with the "Install FinnOS" entry of the install disc.
if grep -qw finn.install /proc/cmdline 2>/dev/null; then
  echo
  echo "FinnOS: starting the installer in 10 seconds."
  echo "Press Ctrl-C to stay in the live shell."
  sleep 10
  /usr/local/bin/finn-install
fi
EOF
chmod 644 "$PROFILE"

echo "==> adding the FinnOS boot entries"
# BIOS boots through syslinux and UEFI through systemd-boot; both menus
# still say "Arch Linux" unless they are rewritten. The kernel, initrd and
# the archiso parameters are read out of the shipped entry rather than
# guessed, because they carry the release's kernel path and volume label.
# The layout has moved between releases, so the files are looked for in a
# few known places instead of one.
SYSCFG=""
for p in /boot/syslinux/syslinux.cfg /syslinux/syslinux.cfg \
         /boot/syslinux/isolinux.cfg /isolinux/isolinux.cfg; do
  rm -rf "$WORK/syslinux.cfg"
  if xorriso -osirrox on -indev "$BASE" -extract "$p" "$WORK/syslinux.cfg" 2>/dev/null; then
    SYSCFG="$p"
    break
  fi
done

ENTRIES=""
for p in /loader/entries /boot/loader/entries /EFI/loader/entries; do
  rm -rf "$WORK/entries"
  if xorriso -osirrox on -indev "$BASE" -extract "$p" "$WORK/entries" 2>/dev/null; then
    ENTRIES="$p"
    break
  fi
done

MAPS=()
if [ -n "$SYSCFG" ]; then
  echo "    BIOS menu: $SYSCFG"
  LINUX_LINE="$(sed -n 's/^[[:space:]]*LINUX[[:space:]]*//p' "$WORK/syslinux.cfg" | head -1)"
  INITRD_LINE="$(sed -n 's/^[[:space:]]*INITRD[[:space:]]*//p' "$WORK/syslinux.cfg" | head -1)"
  APPEND_LINE="$(sed -n 's/^[[:space:]]*APPEND[[:space:]]*//p' "$WORK/syslinux.cfg" | head -1)"
  if [ -n "$LINUX_LINE" ] && [ -n "$APPEND_LINE" ]; then
    {
      echo "DEFAULT finnos"
      echo "PROMPT 0"
      echo "TIMEOUT 100"
      grep -viE '^[[:space:]]*(DEFAULT|PROMPT|TIMEOUT)[[:space:]]' "$WORK/syslinux.cfg" |
        sed -E 's/^[[:space:]]*MENU TITLE.*/MENU TITLE FinnOS/'
      echo
      echo "LABEL finnos"
      echo "  MENU LABEL Install FinnOS"
      echo "  LINUX $LINUX_LINE"
      if [ -n "$INITRD_LINE" ]; then echo "  INITRD $INITRD_LINE"; fi
      echo "  APPEND $APPEND_LINE finn.install"
      echo
      echo "LABEL finnos-shell"
      echo "  MENU LABEL FinnOS live shell"
      echo "  LINUX $LINUX_LINE"
      if [ -n "$INITRD_LINE" ]; then echo "  INITRD $INITRD_LINE"; fi
      echo "  APPEND $APPEND_LINE"
    } > "$WORK/syslinux.cfg.new"
    MAPS+=(-map "$WORK/syslinux.cfg.new" "$SYSCFG")
  else
    echo "warning: could not read the kernel and append lines from $SYSCFG" >&2
  fi
else
  echo "warning: no syslinux menu found; the BIOS menu stays Arch's" >&2
fi

if [ -n "$ENTRIES" ]; then
  echo "    UEFI entries: $ENTRIES"
  ENTRY="$(ls "$WORK/entries"/*.conf 2>/dev/null | head -1 || true)"
  if [ -n "$ENTRY" ]; then
    cp "$ENTRY" "$WORK/entries/finnos.conf"
    sed -i -E 's/^title.*/title   Install FinnOS/' "$WORK/entries/finnos.conf"
    sed -i -E '/^options/ s/$/ finn.install/' "$WORK/entries/finnos.conf"
    LOADER_DIR="${ENTRIES%/*}"
    printf 'default finnos.conf\ntimeout 10\n' > "$WORK/loader.conf"
    MAPS+=(-map "$WORK/loader.conf" "$LOADER_DIR/loader.conf")
    for f in "$WORK/entries"/*.conf; do
      MAPS+=(-map "$f" "$ENTRIES/$(basename "$f")")
    done
  fi
else
  echo "warning: no systemd-boot entries found; the UEFI menu stays Arch's" >&2
fi

echo "==> repacking the live root"
mksquashfs "$WORK/root" "$WORK/airootfs.sfs" -noappend -comp zstd -all-root \
    "${XATTR[@]}" -no-progress >/dev/null
(cd "$WORK" && sha512sum airootfs.sfs > airootfs.sha512)

echo "==> writing $OUT"
rm -f "$OUT"
SFS_DIR="${SFS%/*}"
xorriso -indev "$BASE" -outdev "$OUT" \
    -map "$WORK/airootfs.sfs" "$SFS" \
    -map "$WORK/airootfs.sha512" "$SFS_DIR/airootfs.sha512" \
    ${MAPS[@]+"${MAPS[@]}"} \
    -boot_image any replay -commit

echo
echo "==> boot images on the result"
xorriso -indev "$OUT" -report_el_torito plain 2>/dev/null | sed 's/^/    /'
echo
echo "ISO written to $OUT"
echo "Boot it in VMware, or test it here: vm/test-boot.sh $OUT"