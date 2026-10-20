# Changelog

## Unreleased

- Dev VM workflow moved from Parallels Desktop to VMware Workstation.
- Added `vm/build-iso.sh`, which remasters the Arch Linux ISO into a
  bootable FinnOS install disc: the live root carries the tree at
  `/opt/finnos`, and the boot images and label are kept, so it boots
  under UEFI (VMware) and BIOS. The installer takes the payload from the
  live root; a data disc labelled `FINNOS` and the host HTTP server are
  fallbacks.
- The disc's boot menus no longer say Arch Linux. The default entry on
  both BIOS (syslinux) and UEFI (systemd-boot) is **Install FinnOS**,
  which hands over to the installer; **FinnOS live shell** stays in the
  live environment. The entries reuse the kernel, initrd and archiso
  parameters the base image ships.
- Added `vm/test-boot.sh`, which boots the disc under QEMU and waits for
  a login prompt, and the ISO workflow now runs it before uploading.
- The installer can be run from the disc again. The payload scripts were
  reaching the live root without their executable bit, so `finn-install`
  stopped with "Permission denied"; a file that starts with a shebang is
  now marked executable when the tree goes onto the disc, and the workflow
  checks that the payload can be run.
- Added `vm/menu-shot.sh`, which starts the disc under QEMU with the
  display off and asks the monitor for a frame of the boot menu, so the
  menu can be looked at rather than assumed.

The shape of this file is the shape of the project: the system is small,
and the changes to it are worth reading.

## Unreleased

### The Start Menu

The shell had a dock, a Control Center and a clock page, and no way in to
the system's apps at all. There is now a fourth surface.

- **The Start Menu** (`finnmenu`): a centred card holding the app grid,
  each app's own state, and the power row. It opens from the dock's
  launcher button, and the desktop dims behind it.
- **The application registry** (`finnapps`): the catalogue the OS ships
  and the install list the package manager owns, kept apart so that one
  can change without the other. The Start Menu draws the catalogue; the
  control plane launches what is installed.
- **Honest states.** An app that is not installed is a muted plate with
  "Not installed" under its name, and pressing it says so.
- **One way in.** The menu asks the control plane to launch a program; it
  never spawns anything itself.

### The control plane

- `app.list` and `app.launch <id>`. The control plane is the only place in
  the system that starts user programs, so the shell, a script and an
  agent all go through the same audit trail.
- `finnd` now gives its socket to the `finn` group itself, and runs in
  root's own group. systemd takes `CAP_SETUID` away from a service whose
  group it had to change, and the control plane needs that capability to
  start an app as the user rather than as root.

### The tree

- `src/core`, `src/compositor`, `src/control`, `src/pkg`, `src/tools`: the
  tree now says what it is. The core is a library and knows nothing about
  the two binaries that use it.
- `finncc` is now `finncontrol`. "cc" was an abbreviation, and the house
  rule is that a module is named for what it renders.
- `fvtest` is now `vgtest`, and it draws a sheet of the whole icon set.
- The build artefacts that were committed into the tree are gone, and so is
  `compositor/desktop.rules` — it described a Wayland compositor with
  damage regions and AVIF wallpapers, which is not the system that
  exists. `docs/architecture.md` replaces it.
