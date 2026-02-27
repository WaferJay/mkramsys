# mkramsys

English | [中文](README.zh.md)

Build RAM-based Debian systems. Debootstrap a minimal rootfs, package it as
squashfs, and boot it entirely from RAM using overlayfs.

The system runs read-only from squashfs with a writable tmpfs overlay — all
changes live in RAM and disappear on reboot.

## Quick Start

```bash
# Build a base image
sudo ./mkramsys init -o base.sqfs

# Open a session to customize
sudo ./mkramsys open base.sqfs
sudo ./mkramsys install vim curl openssh-server
sudo ./mkramsys driver          # auto-detect and install firmware

# Produce final squashfs and close session
sudo ./mkramsys commit -o system.sqfs
```

Boot the result with a kernel and initramfs from `boot/`:

```
linux /vmlinuz boot=ramsys ramsys.src=/dev/sda1 ramsys.dir=system.sqfs
initrd /initrd.img
```

## Requirements

- Root privileges
- `debootstrap`, `mksquashfs` (squashfs-tools), `bash`
- For `open`: `unsquashfs` (squashfs-tools)
- For `driver`: `modinfo`, `modprobe`

## Commands

```
mkramsys [-w DIR] <command> [options]
```

| Command   | Description                                        |
|-----------|----------------------------------------------------|
| `init`    | Create a standalone Debian squashfs image           |
| `open`    | Start a session on an existing squashfs             |
| `driver`  | Detect host firmware and install matching packages  |
| `install` | Install packages into the image                    |
| `shell`   | Chroot into the image                              |
| `build`   | Snapshot current state as squashfs (non-destructive)|
| `commit`  | Finalize: cleansys + squashfs + close session      |
| `reset`   | Discard overlay changes (keep session)             |
| `close`   | Delete session entirely                            |

Global option `-w DIR` overrides automatic session discovery with an explicit
session directory.

### init

```bash
sudo ./mkramsys init -o <output.sqfs> [--boot-dir DIR] [--mirror URL] [--codename NAME] [--comp-level N]
```

Creates a standalone Debian squashfs image via debootstrap. Installs a kernel,
generates an initramfs with the ramsys boot script, extracts boot files, then
purges the kernel and cleans the rootfs to minimize image size.

No session is created — this is a pure image builder.

| Option         | Description                                            |
|----------------|--------------------------------------------------------|
| `-o FILE`      | Output squashfs path (required)                        |
| `--boot-dir`   | Directory for kernel + initramfs (default: `boot/` alongside output) |
| `--mirror`     | Debian mirror (default: `https://deb.debian.org/debian/`) |
| `--codename`   | Debian release (default: `trixie`)                     |
| `--comp-level` | zstd compression level (default: `15`)                 |

### open

```bash
sudo ./mkramsys open <sqfs-path> [--force]
```

Starts a session on an existing squashfs file. Creates a session directory
(in `/tmp` by default, override with `-w`) and writes `.mkramsys-session` in
the current directory so subsequent commands find the session automatically.

| Option    | Description                          |
|-----------|--------------------------------------|
| `--force` | Overwrite an existing active session |

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

Installs packages through the overlay. Changes accumulate in the session
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
sudo ./mkramsys build -o <output.sqfs> [--comp-level N]
```

Snapshots the current overlay state as a squashfs image without running
cleansys. The session remains active for further modifications.

| Option         | Description                            |
|----------------|----------------------------------------|
| `-o FILE`      | Output squashfs path (required)        |
| `--comp-level` | zstd compression level (default: `15`) |

### commit

```bash
sudo ./mkramsys commit -o <output.sqfs> [--comp-level N]
```

Runs `cleansys --full` inside the chroot and from the host, creates the final
squashfs image, then closes the session. This is a terminal operation — the
session directory and `.mkramsys-session` are deleted.

| Option         | Description                            |
|----------------|----------------------------------------|
| `-o FILE`      | Output squashfs path (required)        |
| `--comp-level` | zstd compression level (default: `15`) |

### reset

```bash
sudo ./mkramsys reset [--force]
```

Deletes the overlay upper directory, discarding all changes made since `open`.
The source image and session are not affected. `--force` skips the confirmation
prompt.

### close

```bash
sudo ./mkramsys close [--force]
```

Deletes the session directory and `.mkramsys-session` marker, discarding all
overlay changes. `--force` skips the confirmation prompt.

## Session

Image creation (`init`) and image modification (`open`/`commit`/`close`) are
separate concerns:

```bash
# Create → open → modify → finalize
sudo ./mkramsys init -o base.sqfs
sudo ./mkramsys open base.sqfs
sudo ./mkramsys install vim
sudo ./mkramsys commit -o final.sqfs

# Or: snapshot without closing, keep working
sudo ./mkramsys open base.sqfs
sudo ./mkramsys install vim
sudo ./mkramsys build -o snapshot.sqfs    # session stays active
sudo ./mkramsys install curl
sudo ./mkramsys commit -o final.sqfs      # cleansys + close
```

Session discovery: `open` writes `.mkramsys-session` in the current directory.
Subsequent commands read this file to find the session. Use `-w DIR` to
override with an explicit path.

Session directory layout:

```
/tmp/mkramsys-session.XXXXXX/
├── .mkramsys        # Session marker
├── .source          # Absolute path to source squashfs
├── .lock            # flock target
├── upper/           # Overlay changes (persistent across commands)
└── .work/           # Overlay workdir
```

A lockfile prevents concurrent access to the same session.

## Boot Parameters

The initramfs boot script (`boot=ramsys`) copies a squashfs file into RAM and
mounts it with overlayfs as the root filesystem.

| Parameter            | Description                              |
|----------------------|------------------------------------------|
| `ramsys.src=`        | Source device (e.g. `/dev/sda1`, `UUID=`) |
| `ramsys.dir=`        | Path to squashfs file on the source      |
| `ramsys.src.fstype=` | Filesystem type (auto-detected if omitted) |
| `ramsys.src.flags=`  | Additional mount flags for source device |

## Distribution

```bash
./build.sh              # produces dist/mkramsys (single file, ~42KB)
./build.sh output.sh    # custom output path
```

The build script bundles all sources into one self-contained script with
embedded resource files. No external files needed at runtime.

## License

[GPLv3](LICENSE)
