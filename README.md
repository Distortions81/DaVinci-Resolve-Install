# DaVinci Resolve 20 on Kubuntu 24.04 with AMD

This repo captures the container workaround that got DaVinci Resolve Studio 20.3.3 running on Kubuntu 24.04/X11 with an AMD Radeon RX 7900 XT.

It uses a Docker-backed Fedora 39 Distrobox so Resolve gets Fedora userspace libraries while still using the host AMD ROCm OpenCL stack and `/dev/kfd`.

## Compatibility Target

This is intentionally pinned for DaVinci Resolve Studio 20.3.3 build 10. The
tested host is Kubuntu/Ubuntu 24.04 on Xorg/X11 with an AMD Radeon RX 7900 XT.

The default `fedora:39` container is also deliberate: it has a new enough
userspace for the Ubuntu 24.04 AMD ROCm OpenCL library while still working with
this Resolve release after the bundled GLib/GIO libraries are moved aside.

For another Resolve release, use a separate `RESOLVE_HOME`, preferably a
separate `RESOLVE_CONTAINER`, and set `ALLOW_UNSUPPORTED_RESOLVE=1` along with
the exact official `RESOLVE_ZIP`, `RESOLVE_DOWNLOAD_URL`, or
`RESOLVE_DOWNLOAD_ID` for that release. The built-in download ID and archive
names are for 20.3.3 Studio.

## Prerequisites

- Kubuntu/Ubuntu 24.04 on Xorg/X11.
- Host AMD ROCm/OpenCL already working. `clinfo` on the host must show an AMD
  platform and at least one AMD GPU device before setup will continue.
- Docker and Distrobox installed, with your user able to run Docker.

  Use one Docker package family. If you already have Docker CE from
  `download.docker.com` (`docker-ce`, `docker-ce-cli`, `containerd.io`), keep it
  and install only the remaining host tools:

```bash
sudo apt install distrobox clinfo curl unzip
sudo usermod -aG docker,render,video "$USER"
```

  If you do not already have Docker installed, Ubuntu's packaged Docker is fine:

```bash
sudo apt install docker.io distrobox clinfo curl unzip
sudo usermod -aG docker,render,video "$USER"
```

Log out and back in after changing groups.

Check the host before running setup:

```bash
groups
ls -l /dev/kfd /dev/dri/renderD*
clinfo | grep -E 'Platform Name|Device Name|Board Name|Device Vendor|Device Type|Driver Version'
```

## Setup

Run:

```bash
./scripts/setup-davinci-resolve-docker.sh
```

Or do setup and launch Resolve immediately:

```bash
./scripts/setup-and-launch-davinci-resolve-docker.sh
```

The setup script:

- Uses the bundled `vendor/blackmagic/DaVinci_Resolve_Studio_20.3.3_Linux.zip` if present.
- Otherwise downloads the official pinned `DaVinci_Resolve_Studio_20.3.3_Linux.zip` from Blackmagic Design if Resolve is not already installed.
- Refuses unvalidated Resolve versions unless `ALLOW_UNSUPPORTED_RESOLVE=1` is set.
- Checks host `clinfo` before container creation and fails if AMD OpenCL is not visible.
- Extracts the `.run` AppImage payload and installs it at `/opt/resolve`.
- Finds the host AMD OpenCL library from `/etc/OpenCL/vendors` or `/opt/rocm*`.
- Moves Resolve's bundled `libglib`, `libgio`, `libgmodule`, and `libgobject` files into `disabled-by-davinci-docker-setup`.
- Creates a Docker-backed Distrobox named `davincibox-docker`.
- Adds `/dev/kfd`, `/dev/dri`, and the host `render`/`video` group IDs.
- Installs Fedora runtime libraries required by Resolve.
- Writes the container OpenCL ICD to use the host ROCm library.
- Launches Resolve with a dedicated HOME/XDG state directory at `~/.local/share/davinci-resolve-box-home`.
- Installs `davinci-resolve-docker` into `~/.local/bin`.
- Installs a desktop launcher named `DaVinci Resolve (Docker)`.
- Prints the Resolve install path, container name, launcher path, desktop file path, and launch command at the end.
- Optionally launches Resolve immediately with `LAUNCH_AFTER_SETUP=1`.

Launch:

```bash
davinci-resolve-docker
```

## Layout

- `scripts/`: setup and verification entrypoints.
- `bin/`: installed launcher source.
- `config/`: container config files.
- `templates/`: desktop entry templates.
- `vendor/blackmagic/`: optional bundled Blackmagic installer archive.

## Options

Set environment variables before running setup if needed:

```bash
RESOLVE_CONTAINER=davincibox-docker
RESOLVE_IMAGE=fedora:39
RESOLVE_DIR=/opt/resolve
RESOLVE_VERSION=20.3.3
RESOLVE_BUILD=10
ALLOW_UNSUPPORTED_RESOLVE=0
DOWNLOAD_RESOLVE=auto
RESOLVE_ZIP=/path/to/DaVinci_Resolve_Studio_20.3.3_Linux.zip
RESOLVE_DOWNLOAD_URL=https://example.invalid/DaVinci_Resolve_Studio_20.3.3_Linux.zip
ROCM_OPENCL_LIB=/opt/rocm/lib/libamdocl64.so
RESOLVE_HOME=$HOME/.local/share/davinci-resolve-box-home
PATCH_RESOLVE_LIBS=1
INSTALL_LAUNCHER=1
LAUNCH_AFTER_SETUP=0
```

The default download path is `~/.cache/davinci-resolve-docker/DaVinci_Resolve_Studio_20.3.3_Linux.zip`.

Use `RESOLVE_ZIP` to avoid downloading when you already have the official zip.
Use `RESOLVE_DIR` carefully if you also keep a native Resolve install. If
`/opt/resolve/bin/resolve` already exists, setup assumes it is the intended
20.3.3 Studio install. Installs created by this setup include
`.davinci-resolve-docker-target`; future setup runs use that marker to catch a
version/build mismatch. To keep multiple Resolve versions, use separate
`RESOLVE_DIR`, `RESOLVE_HOME`, and `RESOLVE_CONTAINER` values.
Use `PATCH_RESOLVE_LIBS=0` if you do not want setup to move Resolve's bundled GLib/GIO libraries.

The launcher forces Resolve's `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and
`XDG_CACHE_HOME` into the dedicated `RESOLVE_HOME` tree. This keeps container
Resolve state separate from native Resolve installs, other containers, and other
Resolve versions.

## AMD GPU Notes

This repo does not install AMD drivers or ROCm. It shares the host AMD OpenCL
runtime with the container, so the host must be healthy first. If host `clinfo`
does not show an AMD GPU device, Resolve in the container will not either.

Prefer AMD's package-manager ROCm install path for current systems. For Radeon
and Ryzen graphics workloads, AMD points users to its "Use ROCm on Radeon and
Ryzen" documentation from the ROCm Linux install guide. Also check AMD's ROCm
Linux system requirements and compatibility matrix for your exact GPU; AMD notes
that GPUs missing from the supported table are not officially supported by the
current ROCm release.

Useful AMD references:

- ROCm Linux install guide: <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/>
- ROCm Linux system requirements: <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html>
- ROCm compatibility matrix: <https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html>

Practical AMD guidance:

- The RX 7900 XT is the tested card here. Other RDNA2/RDNA3/RDNA4 cards depend
  on the ROCm release and AMD's support table for that release.
- Resolve needs the ROCm OpenCL ICD, typically `libamdocl64.so`. Mesa OpenCL
  providers alone are not a substitute for this setup.
- The user needs access to `/dev/kfd` and at least one `/dev/dri/renderD*` node.
  If you change `render` or `video` group membership, log out and back in, then
  recreate the Distrobox container.
- Multiple AMD GPUs are allowed, but test with `verify-davinci-resolve-docker.sh`
  before trusting project work. AMD documents that some multi-GPU ROCm systems
  may need `iommu=pt` to avoid hangs.
- Avoid `HSA_OVERRIDE_GFX_VERSION` unless you already understand the tradeoff for
  your exact card. It can make unsupported GPUs appear to work and then fail
  under Resolve load.
- Xorg/X11 is the validated display session. Wayland may work for some users, but
  it is outside this repo's compatibility target.

## Bundled Installer

This checkout can include the exact working installer at:

```text
vendor/blackmagic/DaVinci_Resolve_Studio_20.3.3_Linux.zip
```

That file is proprietary Blackmagic Design software. Keep that in mind before pushing or publishing this repo.

The bundled archive checksum is recorded in:

```text
vendor/blackmagic/SHA256SUMS
```

## Verify

Run:

```bash
./scripts/verify-davinci-resolve-docker.sh
```

Expected results:

- `/dev/kfd` is readable inside the container.
- At least one `/dev/dri/renderD*` node is readable inside the container.
- `clinfo` inside the container shows at least one AMD GPU device.
- `ldd /opt/resolve/bin/resolve` reports no missing libraries.
- The printed `HOME` and XDG paths point at the dedicated Resolve state tree.

## Project Database Integrity

After a hard crash, do not delete `*-wal`, `*-shm`, or `*-journal` files. Check
project database integrity with:

```bash
./scripts/check-davinci-resolve-project-dbs.sh
```

By default this checks the isolated `RESOLVE_HOME`. To check a project library
stored elsewhere, pass the path:

```bash
./scripts/check-davinci-resolve-project-dbs.sh /path/to/resolve/project/library
```

Keep Resolve project libraries on local SSD/NVMe storage. Avoid sync folders,
network filesystems, FUSE mounts, container overlay storage, and opening the same
library from native Resolve and container Resolve at the same time.

## Troubleshooting

After a Resolve crash, inspect the verifier output and the host kernel log for
AMD GPU resets, VM faults, ring failures, OOM kills, or segfaults:

```bash
./scripts/verify-davinci-resolve-docker.sh
journalctl -k -b --no-pager | grep -Ei 'amdgpu|kfd|gpu reset|ring|vm fault|oom|segfault'
```

If OpenCL shows an AMD platform but zero devices, the container usually cannot
read `/dev/kfd` or the render node. Recreate the container after confirming your
host has `render` and `video` groups:

```bash
docker rm -f davincibox-docker
./scripts/setup-davinci-resolve-docker.sh
```

If the launcher cannot find ROCm OpenCL, set `ROCM_OPENCL_LIB` to the host `libamdocl64.so` path and rerun setup.

To restore Resolve's bundled GLib/GIO libraries:

```bash
sudo mv /opt/resolve/libs/disabled-by-davinci-docker-setup/* /opt/resolve/libs/
```
