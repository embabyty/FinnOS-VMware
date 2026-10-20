# FinnOS dev VM

A working Arch Linux x86_64 install that boots FinnOS, running in VMware
Workstation. It is the build machine: the compositor needs the DRM headers,
GBM, EGL and FreeType, and this is where the shell is actually run.

## The VM

| | |
|---|---|
| Name | `FinnOS-dev` |
| Guest | Arch Linux x86_64 |
| Resources | 4 GB RAM, 2 vCPU, 32 GB disk - the i3-4130 / 4 GB target |
| Disk | `/dev/sda1` 512M EFI (vfat) + `/dev/sda2` 31.5G root (ext4, label `finnos`) |
| Bootloader | GRUB `x86_64-efi`, bootloader-id `FinnOS` (removable) |
| Console | VMware console, autologin `finn` on tty1 |
| Network | VMware NAT, DHCP. The guest IP is assigned by VMware; read it with `ip addr` |
| GPU | Intel HD Graphics (Mesa) - the accelerated path, GBM + EGL 1.5 |

## Credentials

- `finn` / `finn` (passwordless sudo), `root` / `finn`
- SSH: `ssh finn@<guest-ip>` (port 22, password auth enabled).
- Root SSH is publickey-only (the Arch default, `prohibit-password`).

Override the address used by the scripts with `FINN_HOST`:

```sh
FINN_HOST=finn@192.168.44.128 vm/deploy.sh
```

## The day-to-day loop

```sh
make deploy                  # build, install, restart
vm/shot.sh /tmp/shot.png     # look at it
```

`vm/deploy.sh` sends the tree over as a tar stream - the VM has no
`rsync` - builds it in `~/finnos`, installs it to `/usr/local/bin` and
restarts `finn-comp` and `finnd`.

To drive the shell from a script:

```sh
ssh finn@<guest-ip> '
  sudo finnctl pointer.move x=1196 y=1506
  sudo finnctl pointer.click
  sleep 1
  sudo finnctl screen.shell
'
```

## Installing a fresh VM

The repository is supplied to the guest as an install disc, so no host
HTTP server is needed. The VM has two CD-ROMs: the stock Arch Linux
installer, and the FinnOS disc that carries the tree, the assets and the
installer scripts.

1. Build the FinnOS ISO on the host or any Linux machine:

   ```sh
   vm/build-iso.sh
   ```

   The disc is labelled `FINNOS`, which is how the installer finds it.

2. Create the VMware VM, with both discs attached:

   ```sh
   vm/create-dev-vm.sh
   ```

   The Arch installer ISO is expected in `~/Downloads`; pass a path as the
   third argument to override it.

3. Boot the VM, log in on the installer, and run the installer:

   ```sh
   mkdir -p /finnos-iso
   mount /dev/sr1 /finnos-iso        # the disc labelled FINNOS
   bash /finnos-iso/vm/finn-install.sh
   ```

   `vm/finn-install.sh` finds the disc itself, partitions, formats,
   pacstraps and runs `vm/finn-chroot.sh`, which configures the machine,
   installs the fonts and the payload, and sets up the bootloader.

   If no disc is attached the installer falls back to the host HTTP
   server, which is how the old workflow worked.

4. Build the compositor on the machine and install it:

   ```sh
   cd /opt/finnos && make && sudo make install
   sudo systemctl restart finn-comp finnd
   ```

## What is on the machine

- `/usr/local/bin/finn-comp` - the compositor
- `/usr/local/bin/finnd`, `finnctl` - the control plane and its client
- `/usr/local/bin/finnpkg` - the package manager
- `/usr/share/finn/wallpaper/default.webp` - the wallpaper
- `/usr/share/finn/icons/*.svg` - the icon set
- `/usr/share/finn/apps.registry` - the catalogue of apps
- `/usr/share/fonts/OTF/FixelDisplay-*.otf` - `fc-match "Fixel Display"` resolves
- `/run/finn/` - the IPC namespace: `control.sock`, `comp.sock`, `state/`

## The services

```sh
systemctl status finn-comp finnd
sudo journalctl -u finn-comp -f
sudo tail -f /var/log/finn/control.log
```

The compositor writes to the journal, never to the TTY it is painting on.
Every control-plane call is audited with the peer uid.

## Making one

`vm/create-dev-vm.sh` creates an empty VMware VM with the right shape
for the target. Both discs are attached by the script.