# DaVinci Resolve on Linux with AMD GPUs

This project runs **DaVinci Resolve Studio 21.0.3** on Linux by default,
or the free **DaVinci Resolve 21.0.3** when selected, using a Docker-backed
Distrobox container.

The container provides the Linux userspace that Resolve expects. Your AMD GPU
driver, `/dev/kfd`, `/dev/dri`, and ROCm/OpenCL runtime stay on the host.

## Requirements

Blackmagic Design lists these minimum system requirements for DaVinci Resolve
21.0.3 on Linux:

- Rocky Linux 8.6.
- 32 GB of system memory.
- For monitoring, Blackmagic Design Desktop Video 12.9 or later.
- A discrete GPU with at least 4 GB of VRAM.
- At least 16 GB of VRAM for advanced AI tools.
- At least 32 GB of system memory and 12 GB of VRAM for background rendering.
- A GPU that supports OpenCL 1.2 or CUDA 12.8.
- Official AMD drivers from your GPU manufacturer.
- NVIDIA Studio driver 580.119.02 or newer.

This project supplies a Fedora 39 container userspace, so Rocky Linux 8.6 is
not required as the host operating system. The host still needs to meet the
hardware and driver requirements above. The tested path is AMD with OpenCL;
NVIDIA/CUDA is not currently validated by this project.

For this container workflow, the host also needs:

- A recent Linux desktop. Debian/Ubuntu-based, Arch-based, and Fedora-based
  hosts are the easiest paths.
- An AMD GPU with official drivers and working ROCm/OpenCL support on the host.
- Docker, Distrobox, `clinfo`, `curl`, and `unzip`.
- Xorg/X11 is recommended. Wayland may work, but X11 is the tested path.

This repo does not install AMD drivers or ROCm. Make sure the host can see your
AMD OpenCL device before setting up Resolve.

## Quick Start

### Install AMD Radeon Drivers And ROCm On Ubuntu/Kubuntu

Download the AMD installer package that exactly matches the host Ubuntu release
from the [AMD Linux driver page](https://www.amd.com/en/support/download/linux-drivers.html).
Then replace `VERSION` below with the version in the downloaded file name:

```bash
cd ~/Downloads
sudo apt update
sudo apt install ./amdgpu-install_VERSION.deb
sudo apt update
sudo amdgpu-install -y --usecase=graphics,rocm
sudo usermod -aG render,video "$USER"
sudo reboot
```

The `.deb` installs `amdgpu-install` into `PATH`, so run
`amdgpu-install`, not `./amdgpu-install`. The `-y` option makes the
installation non-interactive. Do not add `--no-dkms` when the goal is to
install AMD's host kernel driver. If Secure Boot is enabled, complete the MOK
enrollment during reboot so the driver module can load.

After rebooting, confirm that `clinfo` reports the AMD GPU before continuing.
These commands are for Ubuntu/Kubuntu; use AMD's package and instructions that
match the host distribution and release.

### Install Container Tools

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

The free Resolve edition requires personal registration with Blackmagic Design.
Register and download the official Linux ZIP from the
[Blackmagic support page](https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion),
then either leave it in `~/Downloads` or pass its path explicitly:

```bash
RESOLVE_EDITION=Resolve \
RESOLVE_ZIP="$HOME/Downloads/DaVinci_Resolve_21.0.3_Linux.zip" \
./quickstart.sh
```

Launch it later with:

```bash
davinci-resolve-docker
```

## Update Or Rebuild

From the repository directory, update the repository and rebuild the container
without launching Resolve:

```bash
git pull
docker rm -f davincibox-docker
RESOLVE_SHM_SIZE=1g ./scripts/setup-resolve.sh
./scripts/verify-resolve.sh
```

To rebuild from the current checkout without updating the repository, omit
`git pull`.

To also reinstall or update Resolve itself:

```bash
docker rm -f davincibox-docker
OVERWRITE_RESOLVE=1 RESOLVE_SHM_SIZE=1g ./quickstart.sh
```

Removing the container does not remove the isolated Resolve settings and
project state stored in `~/.local/share/davinci-resolve-21-box-home`.

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
- Uses an official archive supplied with `RESOLVE_ZIP`, bundled in the repo,
  cached from an earlier run, or placed in `~/Downloads`.
- Otherwise downloads the Studio 21.0.3 Linux installer from Blackmagic
  Design. The free edition must be downloaded after personal registration.
- Installs Resolve to `/opt/resolve`.
- Creates the Docker-backed Distrobox container `davincibox-docker`.
- Gives the container access to `/dev/kfd`, `/dev/dri`, and the host
  `render`/`video` groups.
- Sets Docker `/dev/shm` to 1 GB.
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
- Docker `/dev/shm` is at least 1 GiB.
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
RESOLVE_SHM_SIZE=1g ./scripts/setup-resolve.sh
./scripts/verify-resolve.sh
```

Recreate the container after kernel, Mesa, AMDGPU, ROCm, OpenCL, Docker device
mapping, group, or `RESOLVE_SHM_SIZE` changes.

### Improve UI Responsiveness

Rebuilding the container can help if Resolve became sluggish after a host
graphics, ROCm/OpenCL, group, or Docker configuration change. It refreshes the
GPU device mappings and runtime packages and applies the recommended 1 GiB
Docker shared-memory limit:

```bash
docker rm -f davincibox-docker
RESOLVE_SHM_SIZE=1g ./scripts/setup-resolve.sh
./scripts/verify-resolve.sh
```

The shared-memory size is a limit, not memory reserved immediately. Rebuilding
does not remove the isolated Resolve settings and project state in
`~/.local/share/davinci-resolve-21-box-home`.

On Xorg/X11, the Qt MIT-SHM display path can also be tested for one launch:

```bash
QT_X11_NO_MITSHM=0 davinci-resolve-docker
```

The launcher disables MIT-SHM by default for compatibility. If enabling it
causes visual corruption, crashes, or no improvement, return to the default by
launching normally:

```bash
davinci-resolve-docker
```

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
OVERWRITE_RESOLVE=1 RESOLVE_SHM_SIZE=1g ./quickstart.sh
```

To switch to the free Resolve edition:

```bash
docker rm -f davincibox-docker
RESOLVE_EDITION=Resolve OVERWRITE_RESOLVE=1 RESOLVE_SHM_SIZE=1g ./quickstart.sh
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
| `RESOLVE_SHM_SIZE` | `1g` | Docker `/dev/shm` size at container creation |
| `RESOLVE_ZIP` | unset | Local official zip for the selected edition |
| `OVERWRITE_RESOLVE` | `0` | Replace an existing `/opt/resolve` tree |
| `ROCM_OPENCL_LIB` | auto-detected | Host `libamdocl64.so` path |

The default download cache is edition-specific:

```text
~/.cache/davinci-resolve-docker/DaVinci_Resolve_Studio_21.0.3_Linux.zip
~/.cache/davinci-resolve-docker/DaVinci_Resolve_21.0.3_Linux.zip
```

Useful AMD references:

- ROCm Linux install guide:
  <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/>
- ROCm Linux system requirements:
  <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html>
- ROCm compatibility matrix:
  <https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html>
