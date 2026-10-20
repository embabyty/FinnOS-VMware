#!/bin/bash
# Create a FinnOS dev VM for VMware Workstation (x86_64), with the Arch
# Linux installer and the FinnOS install disc attached.
#
#   vm/create-dev-vm.sh [vm-name] [finnos-iso] [arch-iso]
#
# The FinnOS ISO is produced by vm/build-iso.sh. The Arch ISO is the stock
# installer: the machine is installed from it, with the FinnOS disc
# attached as the second CD-ROM. VMware Workstation is the target
# hypervisor; there is no Parallels dependency anywhere in this tree.
set -eux
VM="${1:-FinnOS-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ISO="${2:-$ROOT/finnos.iso}"
ARCH_ISO="${3:-$HOME/Downloads/archlinux-x86_64.iso}"
MEM=4096 # match i3-4130 4GB target
CPUS=2
HDD=32768
WORKDIR="${VMWARE_VM_DIR:-$HOME/Virtual Machines/$VM}"
mkdir -p "$WORKDIR"

for f in "$ISO" "$ARCH_ISO"; do
  if [ ! -f "$f" ]; then
    echo "not found: $f" >&2
    [ "$f" = "$ISO" ] && echo "Build it first: vm/build-iso.sh" >&2
    [ "$f" = "$ARCH_ISO" ] && echo "Download it from archlinux.org" >&2
    exit 1
  fi
done

cat > "$WORKDIR/$VM.vmx" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "$VM"
guestOS = "other5xlinux-64"
memsize = "$MEM"
numvcpus = "$CPUS"
firmware = "efi"
bios.bootOrder = "cdrom,hdd"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$VM.vmdk"
scsi0:0.deviceType = "disk"
ide1:0.present = "TRUE"
ide1:0.fileName = "$ARCH_ISO"
ide1:0.deviceType = "cdrom-image"
ide1:0.startConnected = "TRUE"
ide1:1.present = "TRUE"
ide1:1.fileName = "$ISO"
ide1:1.deviceType = "cdrom-image"
ide1:1.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000"
usb.present = "TRUE"
sound.present = "FALSE"
EOF

# Create an empty virtual disk if vmware-vdiskmanager is available.
if command -v vmware-vdiskmanager >/dev/null 2>&1; then
  vmware-vdiskmanager -c -s "${HDD}MB" -a lsilogic -t 0 \
    "$WORKDIR/$VM.vmdk" >/dev/null
else
  echo "vmware-vdiskmanager not found: create the disk in the VMware UI,"
  echo "or install VMware Workstation's CLI tools."
fi

echo "VM created at: $WORKDIR/$VM.vmx"
echo "Open it in VMware Workstation and power on."
echo "cdrom0 = the Arch installer, cdrom1 = the FinnOS install disc."