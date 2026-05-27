# DaVinci Resolve 20 on Kubuntu 24.04 with AMD

This repo captures the container workaround that got DaVinci Resolve Studio 20.3.3 running on Kubuntu 24.04/X11 with an AMD Radeon RX 7900 XT.

It uses a Docker-backed Fedora 39 Distrobox so Resolve gets Fedora userspace libraries while still using the host AMD ROCm OpenCL stack and `/dev/kfd`.

## Prerequisites

- Kubuntu/Ubuntu 24.04 on Xorg/X11.
- Host AMD ROCm/OpenCL already working. `clinfo` on the host should show an AMD platform and your GPU.
- Docker and Distrobox installed, with your user able to run Docker.

  Use one Docker package family. If you already have Docker CE from
  `download.docker.com` (`docker-ce`, `docker-ce-cli`, `containerd.io`), keep it
  and install only the remaining host tools:

```bash
sudo apt install distrobox clinfo curl unzip
sudo usermod -aG docker "$USER"
```

  If you do not already have Docker installed, Ubuntu's packaged Docker is fine:

```bash
sudo apt install docker.io distrobox clinfo curl unzip
sudo usermod -aG docker "$USER"
```

Log out and back in after adding the Docker group.

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
- Extracts the `.run` AppImage payload and installs it at `/opt/resolve`.
- Finds the host AMD OpenCL library from `/etc/OpenCL/vendors` or `/opt/rocm*`.
- Moves Resolve's bundled `libglib`, `libgio`, `libgmodule`, and `libgobject` files into `disabled-by-davinci-docker-setup`.
- Creates a Docker-backed Distrobox named `davincibox-docker`.
- Adds `/dev/kfd`, `/dev/dri`, and the host `render`/`video` group IDs.
- Installs Fedora runtime libraries required by Resolve.
- Writes the container OpenCL ICD to use the host ROCm library.
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
DOWNLOAD_RESOLVE=auto
RESOLVE_ZIP=/path/to/DaVinci_Resolve_Studio_20.3.3_Linux.zip
RESOLVE_DOWNLOAD_URL=https://example.invalid/DaVinci_Resolve_Studio_20.3.3_Linux.zip
ROCM_OPENCL_LIB=/opt/rocm/lib/libamdocl64.so
PATCH_RESOLVE_LIBS=1
INSTALL_LAUNCHER=1
LAUNCH_AFTER_SETUP=0
```

The default download path is `~/.cache/davinci-resolve-docker/DaVinci_Resolve_Studio_20.3.3_Linux.zip`.

Use `RESOLVE_ZIP` to avoid downloading when you already have the official zip.
Use `PATCH_RESOLVE_LIBS=0` if you do not want setup to move Resolve's bundled GLib/GIO libraries.

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
- `clinfo` inside the container shows one AMD GPU device.
- `ldd /opt/resolve/bin/resolve` reports no missing libraries.

## Troubleshooting

If OpenCL shows an AMD platform but zero devices, the container cannot read `/dev/kfd`. Recreate the container after confirming your host has `render` and `video` groups:

```bash
docker rm -f davincibox-docker
./scripts/setup-davinci-resolve-docker.sh
```

If the launcher cannot find ROCm OpenCL, set `ROCM_OPENCL_LIB` to the host `libamdocl64.so` path and rerun setup.

To restore Resolve's bundled GLib/GIO libraries:

```bash
sudo mv /opt/resolve/libs/disabled-by-davinci-docker-setup/* /opt/resolve/libs/
```
