# DaVinci Resolve on Linux with AMD GPUs

This project runs **DaVinci Resolve Studio 21.0.2** on Linux by default,
or the free **DaVinci Resolve 21.0.2** when selected, using a Docker-backed
Distrobox container.

The container provides the Linux userspace that Resolve expects. Your AMD GPU
driver, `/dev/kfd`, `/dev/dri`, and ROCm/OpenCL runtime stay on the host.

## Requirements

- A recent Linux desktop. Debian/Ubuntu-based, Arch-based, and Fedora-based
  hosts are the easiest paths.
- An AMD GPU with working ROCm/OpenCL support on the host.
- Docker, Distrobox, `clinfo`, `curl`, and `unzip`.
- Xorg/X11 is recommended. Wayland may work, but X11 is the tested path.

This repo does not install AMD drivers or ROCm. Make sure the host can see your
AMD OpenCL device before setting up Resolve.

## Quick Start

Install the host tools with your distro package manager.

Debian/Ubuntu-based:

```bash
sudo apt update
sudo apt install docker.io distrobox clinfo curl unzip
sudo systemctl enable --now docker
sudo usermod -aG docker,render,video "$USER"
```

If you already use Docker CE from Docker official packages, keep that package
family and install only the missing tools:

```bash
sudo apt install distrobox clinfo curl unzip
sudo usermod -aG docker,render,video "$USER"
```

Arch-based:

```bash
sudo pacman -Syu
sudo pacman -S docker distrobox clinfo curl unzip
sudo systemctl enable --now docker
sudo usermod -aG docker,render,video "$USER"
```

Fedora-based:

```bash
sudo dnf install moby-engine distrobox clinfo curl unzip
sudo systemctl enable --now docker
sudo usermod -aG docker,render,video "$USER"
```

Other distros need the same host pieces: Docker Engine, Distrobox, `clinfo`,
`curl`, `unzip`, and user access to the `docker`, `render`, and `video` groups.

Log out and back in after changing groups.

Check that the host can see the AMD GPU through OpenCL:

```bash
groups
ls -l /dev/kfd /dev/dri/renderD*
clinfo | grep -E 'Platform Name|Device Name|Board Name|Device Vendor|Device Type|Driver Version'
```

Then set up and launch Resolve Studio, which is the default:

```bash
./quickstart.sh
```

To install the free Resolve edition instead:

```bash
RESOLVE_EDITION=Resolve ./quickstart.sh
```

Launch it later with:

```bash
davinci-resolve-docker
```

## Scripts

Start with `./quickstart.sh`. Helper scripts are named by workflow:

| Path | Use |
| --- | --- |
| `quickstart.sh` | Set up and launch the selected Resolve edition |
| `scripts/setup-resolve.sh` | Set up or update without launching |
| `scripts/verify-resolve.sh` | Verify container, GPU, OpenCL, audio, and libraries |
| `scripts/reset-gpu-cache.sh` | Force Resolve to rescan GPU settings |
| `scripts/check-resolve-dbs.sh` | Check project library database files |
| `bin/launch-resolve.sh` | Launcher installed as `davinci-resolve-docker` |

## What Setup Does

- Installs DaVinci Resolve Studio by default, or free DaVinci Resolve when
  `RESOLVE_EDITION=Resolve` is set.
- Otherwise downloads the selected 21.0.2 Linux installer from Blackmagic
  Design.
- Installs Resolve to `/opt/resolve`.
- Creates the Docker-backed Distrobox container `davincibox-docker`.
- Gives the container access to `/dev/kfd`, `/dev/dri`, and the host
  `render`/`video` groups.
- Sets Docker `/dev/shm` to 16 GB.
- Points the container OpenCL ICD at the host AMD OpenCL library.
- Keeps Resolve's settings and project-library state in an isolated home at
  `~/.local/share/davinci-resolve-21-box-home`.
- Installs the `davinci-resolve-docker` launcher and desktop entry.

The launcher prevents two copies of Resolve from using the same isolated state
tree at the same time.

## Verify The Install

Run:

```bash
./scripts/verify-resolve.sh
```

Expected results:

- `/dev/kfd` is readable inside the container.
- At least one `/dev/dri/renderD*` node is readable inside the container.
- Docker `/dev/shm` is at least 16 GiB.
- `clinfo` inside the container shows an AMD GPU device.
- `ldd /opt/resolve/bin/resolve` reports no missing libraries.
- Resolve's HOME/XDG paths point at the isolated state tree.
- Audio opens through the system Pulse/PipeWire setup.

If the verifier fails, fix that before troubleshooting Resolve itself.

## Common Fixes

If host `clinfo` does not show an AMD GPU, fix the host AMD driver and
ROCm/OpenCL install first. The container cannot expose a GPU that the host cannot
use.

If `/dev/kfd` or `/dev/dri/renderD*` is not readable, confirm your user is in
the `render` and `video` groups, log out and back in, then recreate the
container.

If Resolve sees an AMD OpenCL platform but no GPU device, recreate the
container:

```bash
docker rm -f davincibox-docker
RESOLVE_SHM_SIZE=16g ./scripts/setup-resolve.sh
./scripts/verify-resolve.sh
```

Recreate the container after kernel, Mesa, AMDGPU, ROCm, OpenCL, Docker device
mapping, group, or `RESOLVE_SHM_SIZE` changes.

If Resolve crashes after a graphics or runtime update, run the verifier and
check the kernel log:

```bash
./scripts/verify-resolve.sh
journalctl -k -b --no-pager | grep -Ei 'amdgpu|kfd|gpu reset|ring|vm fault|oom|segfault'
```

To force Resolve to rescan the GPU:

```bash
./scripts/reset-gpu-cache.sh
```

To capture a crash log from a terminal:

```bash
davinci-resolve-docker 2>&1 | tee "$HOME/davinci-resolve-crash-$(date +%Y%m%d-%H%M%S).log"
```

To test whether audio is involved in a crash:

```bash
davinci-resolve-docker --audio=null
```

`--audio=null` intentionally disables audible output and is only for crash
testing.

## Reinstall Or Switch Editions

To replace the current Resolve install with the selected edition from this repo:

```bash
docker rm -f davincibox-docker
OVERWRITE_RESOLVE=1 RESOLVE_SHM_SIZE=16g ./quickstart.sh
```

To switch to the free Resolve edition:

```bash
docker rm -f davincibox-docker
RESOLVE_EDITION=Resolve OVERWRITE_RESOLVE=1 RESOLVE_SHM_SIZE=16g ./quickstart.sh
```

## Project Libraries

Before opening existing projects in Resolve 21, make a full project-library
backup and export important projects individually.

Keep project libraries on local SSD/NVMe storage. Avoid sync folders, network
filesystems, FUSE mounts, container overlay storage, and opening the same
library from native Resolve and container Resolve at the same time.

After a hard crash, do not delete `*-wal`, `*-shm`, or `*-journal` files. Check
project database integrity with:

```bash
./scripts/check-resolve-dbs.sh
```

To check a project library stored somewhere else:

```bash
./scripts/check-resolve-dbs.sh /path/to/resolve/project/library
```

## Advanced Options

Set these before running setup when needed:

| Variable | Default | Use |
| --- | --- | --- |
| `RESOLVE_CONTAINER` | `davincibox-docker` | Container name |
| `RESOLVE_IMAGE` | `fedora:39` | Container image |
| `RESOLVE_EDITION` | `Studio` | `Studio` or `Resolve` |
| `RESOLVE_DIR` | `/opt/resolve` | Resolve install path on the host |
| `RESOLVE_HOME` | `~/.local/share/davinci-resolve-21-box-home` | Isolated Resolve HOME/XDG state |
| `RESOLVE_AUDIO_MODE` | `system` | `system`, `auto`, `pulse`, or `null` audio mode |
| `RESOLVE_SHM_SIZE` | `16g` | Docker `/dev/shm` size at container creation |
| `RESOLVE_ZIP` | unset | Local official zip for the selected edition |
| `OVERWRITE_RESOLVE` | `0` | Replace an existing `/opt/resolve` tree |
| `ROCM_OPENCL_LIB` | auto-detected | Host `libamdocl64.so` path |

The default download cache is edition-specific:

```text
~/.cache/davinci-resolve-docker/DaVinci_Resolve_Studio_21.0.2_Linux.zip
~/.cache/davinci-resolve-docker/DaVinci_Resolve_21.0.2_Linux.zip
```

Useful AMD references:

- ROCm Linux install guide:
  <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/>
- ROCm Linux system requirements:
  <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html>
- ROCm compatibility matrix:
  <https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html>
