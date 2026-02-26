# mkramsys

English | [中文](README.zh.md)

Build RAM-based Debian systems. Debootstrap a minimal rootfs, package it as
squashfs, and boot it entirely from RAM using overlayfs.

The system runs read-only from squashfs with a writable tmpfs overlay — all
changes live in RAM and disappear on reboot.

## Quick Start

```bash
# Build a base image
sudo ./mkramsys init

# Customize
sudo ./mkramsys install vim curl openssh-server
sudo ./mkramsys driver          # auto-detect and install firmware

# Produce final squashfs
sudo ./mkramsys build -o system.sqfs
```

Boot the result with a kernel and initramfs from `build/boot/`:

```
linux /vmlinuz boot=ramsys ramsys.src=/dev/sda1 ramsys.dir=system.sqfs
initrd /initrd.img
```

## Requirements

- Root privileges
- `debootstrap`, `mksquashfs` (squashfs-tools), `bash`
- For `driver`: `modinfo`, `modprobe`

## Commands

```
mkramsys [-w WORKSPACE] <command> [options]
```

| Command   | Description                                        |
|-----------|----------------------------------------------------|
| `init`    | Debootstrap a base Debian system, create base.sqfs |
| `driver`  | Detect host firmware and install matching packages  |
| `install` | Install packages into the image                    |
| `shell`   | Chroot into the image                              |
| `build`   | Clean up and produce final squashfs                |
| `reset`   | Discard all overlay changes                        |

Global option `-w DIR` sets the workspace directory (default: `./build`).

### init

```bash
sudo ./mkramsys init [--force] [--mirror URL] [--codename NAME]
```

Creates a base Debian image via debootstrap. Installs a kernel, generates an
initramfs with the ramsys boot script, extracts boot files, then purges the
kernel and cleans the rootfs to minimize image size.

| Option       | Description                                            |
|--------------|--------------------------------------------------------|
| `--force`    | Re-initialize, discarding all previous state           |
| `--mirror`   | Debian mirror (default: `https://deb.debian.org/debian/`) |
| `--codename` | Debian release (default: `trixie`)                     |

### driver

```bash
sudo ./mkramsys driver
```

Scans the host for required firmware:

1. Loaded kernel modules (`/proc/modules`) — queries firmware dependencies
2. Hardware modaliases (`/sys/bus/*/devices/*/modalias`) — resolves to modules,
   queries firmware
3. CPU vendor — selects `amd64-microcode` or `intel-microcode`

Maps detected firmware files to Debian packages via `apt-file` and installs
them. Automatically enables the `non-free-firmware` repository.

### install

```bash
sudo ./mkramsys install [-f packages.txt] [PKG...]
```

Installs packages through the overlay. Changes accumulate in the workspace
upper directory.

`-f FILE` reads package names from a file (one per line, `#` comments
supported).

### shell

```bash
sudo ./mkramsys shell [-c CMD] [-l] [SCRIPT [ARGS...]]
```

| Form                  | Behavior                         |
|-----------------------|----------------------------------|
| `shell`               | Interactive bash                 |
| `shell -l`            | Login shell (sources /etc/profile) |
| `shell -c "cmd"`      | Execute command string           |
| `shell script.sh`     | Copy script into chroot, execute |
| `shell script.sh arg` | Execute script with arguments    |

### build

```bash
sudo ./mkramsys build [-o output.sqfs]
```

Runs `cleansys --full` inside the chroot and from the host, then creates a
squashfs image. Default output: `$WORKSPACE/output.sqfs`.

This is a terminal operation — cleansys deletions are written into the overlay
upper. Run `reset` before further modifications if needed.

### reset

```bash
sudo ./mkramsys reset [--force]
```

Deletes the overlay upper directory, discarding all changes made since `init`.
The base image is not affected. `--force` skips the confirmation prompt.

## Workspace

All state lives in a single directory (default `./build/`):

```
build/
├── base.sqfs        # Base image from init
├── boot/            # Kernel + initramfs
├── upper/           # Overlay changes (persistent across commands)
├── .work/           # Overlay workdir
└── .mkramsys        # Workspace marker
```

Overlay changes accumulate in `upper/` across `driver`, `install`, and `shell`
commands. Squashfs is only created twice: once at `init` (base) and once at
`build` (final). This avoids redundant compression during iterative
customization.

A lockfile prevents concurrent access to the same workspace.

## Boot Parameters

The initramfs boot script (`boot=ramsys`) copies a squashfs file into RAM and
mounts it with overlayfs as the root filesystem.

| Parameter            | Description                              |
|----------------------|------------------------------------------|
| `ramsys.src=`        | Source device (e.g. `/dev/sda1`, `UUID=`) |
| `ramsys.dir=`        | Path to squashfs file on the source      |
| `ramsys.src.fstype=` | Filesystem type (auto-detected if omitted) |
| `ramsys.src.flags=`  | Additional mount flags for source device |

## Environment Variables

| Variable                    | Default                          |
|-----------------------------|----------------------------------|
| `SQUASHFS_COMPRESSION_LEVEL`| `15` (zstd)                      |
| `EXTRA_PACKAGES`            | *(empty)*                        |

## Distribution

```bash
./build.sh              # produces dist/mkramsys (single file, ~34KB)
./build.sh output.sh    # custom output path
```

The build script bundles all sources into one self-contained script with
embedded resource files. No external files needed at runtime.

## License

[GPLv3](LICENSE)
