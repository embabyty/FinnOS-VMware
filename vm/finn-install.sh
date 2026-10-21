#!/bin/bash
# FinnOS x86_64 install: archboot live env -> /dev/sda
#
# The payload comes from the FINNOS install disc, which the VM has attached
# as a second CD-ROM. If the disc is not attached the script falls back to
# the host HTTP server, which is how the old workflow worked.
exec > >(tee /tmp/finn-install.log) 2>&1
set -x
DISK=/dev/sda
# The host server is the gateway of the NAT network, and VMware picks that
# subnet when the VM is made. A hardcoded address is a different network on
# the next machine, and a POST to it that nobody answers stalls the install
# at the first stage, before anything has been written. Ask the route
# instead, and never let the log outlive the install.
HOST="http://$(ip route show default 2>/dev/null | awk 'NR==1{print $3}'):8765"
ISO_MNT=/finnos-iso
SRC=""
post() { curl -s --connect-timeout 2 --max-time 4 -X POST --data-binary @/tmp/finn-install.log "$HOST/log" -o /dev/null 2>/dev/null || true; }

echo "===== [0/8] FIND THE PAYLOAD ====="
# The bootable disc carries the tree in the live root, which is where the
# installer normally runs from. A separate data disc labelled FINNOS still
# works for the two-disc flow, and the host server is the last resort.
if [ -f /opt/finnos/vm/finn-chroot.sh ]; then
  SRC=/opt/finnos
  echo "payload found in the live root: $SRC"
else
  if [ ! -d "$ISO_MNT" ]; then mkdir -p "$ISO_MNT"; fi
  for dev in /dev/sr0 /dev/sr1 /dev/sr2 /dev/sda2 /dev/sdb2; do
    [ -b "$dev" ] || continue
    if blkid "$dev" 2>/dev/null | grep -q 'LABEL="FINNOS"'; then
      mount "$dev" "$ISO_MNT" && break
    fi
  done
  if mountpoint -q "$ISO_MNT" && [ -f "$ISO_MNT/vm/finn-chroot.sh" ]; then
    SRC="$ISO_MNT"
    echo "install disc found on $ISO_MNT"
  else
    umount "$ISO_MNT" 2>/dev/null || true
    echo "no install disc; falling back to $HOST"
  fi
fi
post

echo "===== [1/8] PREREQS ====="
# The live environment ships a list of mirrors and the first one is not
# always the quickest for the machine that is installing; the geo mirror
# is anycast and picks one near the caller. The rest stay in the list for
# the machine that is installed.
if [ -f /etc/pacman.d/mirrorlist ]; then
  {
    echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
    grep -v '^Server = https://geo.mirror.pkgbuild.com' /etc/pacman.d/mirrorlist
  } > /etc/pacman.d/mirrorlist.new
  mv /etc/pacman.d/mirrorlist.new /etc/pacman.d/mirrorlist
fi
pacman -Sy --noconfirm arch-install-scripts dosfstools parted 2>&1 | tail -5 || {
  sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
  pacman -Sy --noconfirm arch-install-scripts dosfstools parted 2>&1 | tail -5
}
command -v pacstrap mkfs.vfat
post

echo "===== [2/8] PARTITION $DISK ====="
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
wipefs -a "$DISK" || true
# Three partitions: an EFI system partition for /boot, a one-megabyte BIOS
# boot partition, and the root. The BIOS boot partition is where GRUB puts
# its boot code on a GPT disk; without it a machine that starts with a BIOS
# has an install it cannot reach, and the firmware is not always willing
# to boot an EFI disk on its own.
#
# The type is the GUID, not the one-letter alias: sfdisk accepts "U" and
# "L" everywhere, but not every version knows "B" for a BIOS boot
# partition, and the one that does not rejects the whole entry.
printf 'label: gpt\n,512M,U\n,+1M,21686148-6449-6E6F-744E-656564454649\n,,L\n' \
  | sfdisk --wipe=always "$DISK"
sync; partprobe "$DISK" 2>/dev/null || true; sleep 3
lsblk "$DISK"
post

echo "===== [3/8] FORMAT ====="
mkfs.vfat -F32 "${DISK}1"
mkfs.ext4 -F -L finnos "${DISK}3"
post

echo "===== [4/8] MOUNT ====="
mkdir -p /mnt
mount "${DISK}3" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot
findmnt -o TARGET,SOURCE /mnt /mnt/boot
post

echo "===== [5/8] PACSTRAP ====="
# The toolchain is in the base install, because the chroot builds the
# compositor: the disc carries the sources, and the machine they land on is
# the one that can build them. The dev loop builds there too, so removing
# the compiler again would only mean putting it back.
PKGS="base linux linux-firmware systemd sudo openssh networkmanager
      grub efibootmgr mesa wayland wayland-protocols libdrm libinput seatd
      fontconfig ttf-dejavu git python vim nano
      base-devel pkgconf libwebp freetype2 alsa-lib"

# A mirror that stalls must not fail the install. pacman keeps what it has
# downloaded, so a retry only fetches what is missing, and it picks another
# mirror for it. Three tries, and then it is a real failure.
staged=0
for try in 1 2 3; do
  if yes | pacstrap /mnt $PKGS; then staged=1; break; fi
  echo "pacstrap failed on try $try; retrying"
done
[ "$staged" = 1 ] || {
  echo "FINN_INSTALL_FAILED: the base system did not install"
  exit 1
}
post

echo "===== [6/8] FSTAB ====="
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab
post

echo "===== [7/8] CHROOT ====="
mkdir -p /mnt/root
if [ -n "$SRC" ]; then
  # The disc carries the whole tree: the chroot script, the assets and the
  # sources, so nothing has to come over the network.
  cp "$SRC/vm/finn-chroot.sh" /mnt/root/finn-chroot.sh
  mkdir -p /mnt/root/finnos-src
  tar -C "$SRC" -cf - --exclude='.git' --exclude='*.o' --exclude='*.a' . \
    | tar -C /mnt/root/finnos-src -xf -
  echo "payload taken from the install disc"
else
  curl -s --connect-timeout 2 --max-time 60 -Lo /mnt/root/finn-chroot.sh "$HOST/vm/finn-chroot.sh"
  echo "payload taken from $HOST"
fi
chmod +x /mnt/root/finn-chroot.sh
# The chroot is where the machine is actually configured; if it fails, the
# install has failed, and saying otherwise would be a lie the reader acts on.
arch-chroot /mnt /root/finn-chroot.sh || {
  echo "FINN_INSTALL_FAILED: the machine could not be configured"
  exit 1
}
post

echo "===== [8/8] COMPLETE ====="
post
echo "FINN_INSTALL_COMPLETE"