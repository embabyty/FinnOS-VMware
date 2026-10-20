#!/bin/bash
# Create a FinnOS dev VM for VMware Workstation (x86_64), and attach the
# FinnOS install ISO as its CD-ROM.
#
#   vm/create-dev-vm.sh [vm-name] [iso-path]
#
# The ISO is produced by vm/build-iso.sh; build it first, or pass a path to
# an Arch Linux x86_64 installer ISO. VMware Workstation is the target
# hypervisor: there is no Parallels dependency anywhere in this tree.
set -eux
VM="${1:-FinnOS-dev}"
ISO="${2:-$(cd "$(dirname "$0")/.." && pwd)/finnos.iso}"
MEM=4096 # match i3-4130 4GB target
CPUS=2
HDD=32768
WORKDIR="${VMWARE_VM_DIR:-$HOME/Virtual Machines/$VM}"
mkdir -p "$WORKDIR"

if [ ! -f "$ISO" ]; then
  echo "ISO not found: $ISO" >&2
  echo "Build it first: vm/build-iso.sh" >&2
  exit 1
fi

cat > "$WORKDIR/$VM.vmx" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "20"
displayName = "$VM"
guestOS = "other5xlinux-64"
memsize = "$MEM"
numvcpus = "$CPUS"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$VM.vmdk"
scsi0:0.deviceType = "disk"
ide1:0.present = "TRUE"
ide1:0.fileName = "$ISO"
ide1:0.deviceType = "cdrom-image"
ide1:0.startConnected = "TRUE"
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
echo "Open it in VMware Workstation and power on. The ISO is attached as cdrom0."