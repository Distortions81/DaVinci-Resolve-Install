# Installation and GPU Setup

This guide prepares a Linux host for DaVinci Resolve Container. Return to the
[Quick Start](../README.md#quick-start) once the host checks pass.

## Resolve Requirements

Blackmagic Design lists these minimum requirements for DaVinci Resolve 21.0.4
on Linux:

- Rocky Linux 8.6.
- 32 GB of system memory.
- Blackmagic Design Desktop Video 12.9 or later for monitoring.
- A discrete GPU with at least 4 GB of VRAM.
- At least 16 GB of VRAM for advanced AI tools.
- At least 32 GB of system memory and 12 GB of VRAM for background rendering.
- A GPU supporting OpenCL 1.2 or CUDA 12.8.
- Official AMD drivers from the GPU manufacturer, or NVIDIA Studio driver
  580.119.02 or newer.

The project supplies Fedora 39 as the container userspace, so Rocky Linux is not
required as the host operating system. The hardware and driver requirements
still apply.

## Host Tools

The host needs Docker Engine, Distrobox, `clinfo`, `curl`, and `unzip`.

Debian or Ubuntu:

```bash
sudo apt update
sudo apt install docker.io distrobox clinfo curl unzip
sudo systemctl enable --now docker
sudo usermod -aG docker,render,video "$USER"
```

If Docker CE is already installed from Docker's official repository, keep that
package family and install only the missing tools:

```bash
sudo apt install distrobox clinfo curl unzip
sudo usermod -aG docker,render,video "$USER"
```

Arch Linux:

```bash
sudo pacman -Syu
sudo pacman -S docker distrobox clinfo curl unzip
sudo systemctl enable --now docker
sudo usermod -aG docker,render,video "$USER"
```

Fedora:

```bash
sudo dnf install moby-engine distrobox clinfo curl unzip
sudo systemctl enable --now docker
sudo usermod -aG docker,render,video "$USER"
```

Log out and back in after changing groups. Confirm Docker works without `sudo`:

```bash
docker info
```

## AMD Radeon and ROCm/OpenCL

This repository does not install AMD drivers or ROCm. Download the AMD package
that exactly matches the host Ubuntu release from the
[AMD Linux driver page](https://www.amd.com/en/support/download/linux-drivers.html),
then replace `VERSION` with the version in its file name:

```bash
cd ~/Downloads
sudo apt update
sudo apt install ./amdgpu-install_VERSION.deb
sudo apt update
sudo amdgpu-install -y --usecase=graphics,rocm
sudo usermod -aG render,video "$USER"
sudo reboot
```

The `.deb` adds `amdgpu-install` to `PATH`; run `amdgpu-install`, not
`./amdgpu-install`. Do not add `--no-dkms` when the host kernel driver is
required. If Secure Boot is enabled, complete MOK enrollment during reboot.

After rebooting:

```bash
groups
ls -l /dev/kfd /dev/dri/renderD*
clinfo | grep -E 'Platform Name|Device Name|Board Name|Device Vendor|Device Type|Driver Version'
```

Do not continue until `clinfo` reports an AMD GPU device.

Useful references:

- [ROCm installation guide](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/)
- [ROCm system requirements](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html)
- [ROCm compatibility matrix](https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html)

## NVIDIA CUDA and OpenCL

Install NVIDIA Studio driver 580.119.02 or newer using the host distribution's
package manager. Then install
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html),
configure Docker, and restart it:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
nvidia-smi
docker info --format '{{json .Runtimes}}'
```

The Docker runtime output must contain `nvidia`. The setup script rejects an
older driver or an unconfigured runtime before creating the container.

NVIDIA Container Toolkit supplies the container with the driver capabilities
needed for CUDA/OpenCL compute, OpenGL/Vulkan graphics, X11 display, video, and
`nvidia-smi`.

Useful references:

- [NVIDIA Container Toolkit installation](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- [NVIDIA Docker GPU and driver capabilities](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html)
- [Distrobox GPU integration](https://distrobox.it/useful_tips/#using-the-gpu-inside-the-container)

## Install Resolve

Clone the repository and run setup:

```bash
git clone https://github.com/Distortions81/DaVinci-Resolve-Container.git
cd DaVinci-Resolve-Container
./quickstart.sh
```

`RESOLVE_GPU=auto` is the default. It prefers AMD when both vendors are present.
Select NVIDIA explicitly when needed:

```bash
RESOLVE_GPU=nvidia ./quickstart.sh
```

Studio is the default edition and can be downloaded automatically from
Blackmagic Design. For the Free edition, register and download the official
Linux ZIP, leave it in `~/Downloads`, and run:

```bash
RESOLVE_EDITION=Resolve ./quickstart.sh
```

Or pass an explicit path:

```bash
RESOLVE_EDITION=Resolve \
RESOLVE_ZIP="$HOME/Downloads/DaVinci_Resolve_21.0.4_Linux.zip" \
./quickstart.sh
```

## Next Step

Verify the completed installation:

```bash
./scripts/verify-resolve.sh
```

See [Troubleshooting and Maintenance](TROUBLESHOOTING.md) if verification fails.
