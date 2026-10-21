#!/bin/bash
# FinnOS x86_64 install: archboot live env -> /dev/sda
#
# The payload comes from the FINNOS install disc, which the VM has attached
# as a second CD-ROM. If the disc is not attached the script falls back to
# the host HTTP server, which is how the old workflow worked.
exec > >(tee /tmp/finn-install.log) 2>&1
set -x
DISK=/dev/sda
HOST=http://192.168.44.1:8765
ISO_MNT=/finnos-iso
SRC=""
post() { curl -s -X POST --data-binary @/tmp/finn-install.log "$HOST/log" -o /dev/null 2>/dev/null || true; }

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
printf 'label: gpt\n,512M,U\n,,L\n' | sfdisk --wipe=always "$DISK"
sync; partprobe "$DISK" 2>/dev/null || true; sleep 3
lsblk "$DISK"
post

echo "===== [3/8] FORMAT ====="
mkfs.vfat -F32 "${DISK}1"
mkfs.ext4 -F -L finnos "${DISK}2"
post

echo "===== [4/8] MOUNT ====="
mkdir -p /mnt
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot
findmnt -o TARGET,SOURCE /mnt /mnt/boot
post

echo "===== [5/8] PACSTRAP ====="
# The toolchain is in the base install, because the chroot builds the
# compositor: the disc carries the sources, and the machine they land on is
# the one that can build them. The dev loop builds there too, so removing
# the compiler again would only mean putting it back.
yes | pacstrap /mnt base linux linux-firmware \
  systemd sudo openssh networkmanager \
  grub efibootmgr \
  mesa wayland wayland-protocols libdrm libinput seatd \
  fontconfig ttf-dejavu git python vim nano \
  base-devel pkgconf libdrm libwebp freetype2 alsa-lib
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
  curl -sLo /mnt/root/finn-chroot.sh "$HOST/vm/finn-chroot.sh"
  echo "payload taken from $HOST"
fi
chmod +x /mnt/root/finn-chroot.sh
arch-chroot /mnt /root/finn-chroot.sh
post

echo "===== [8/8] COMPLETE ====="
curl -s -X POST --data-binary @/tmp/finn-install.log "$HOST/log" -o /dev/null 2>/dev/null || true
echo "FINN_INSTALL_COMPLETE"