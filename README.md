# DaVinci Resolve 21 on Kubuntu 24.04 with AMD

Docker/Distrobox setup for **DaVinci Resolve Studio 21.0 build 48** on
Kubuntu/Ubuntu 24.04 with AMD ROCm/OpenCL.

Validated target:

- Kubuntu/Ubuntu 24.04 on Xorg/X11
- AMD Radeon RX 7900 XT, 20 GB VRAM
- 64 GB system RAM
- Fedora 39 container, Docker-backed through Distrobox
- Docker `/dev/shm` set to 16 GB

The container supplies Fedora userspace libraries. The AMD GPU stack stays on
the host: Resolve uses the host `amdgpu` kernel driver, `/dev/kfd`,
`/dev/dri`, and ROCm OpenCL library.

## Quick Start

Install host tools. If you already use Docker CE from `download.docker.com`,
keep that package family and install only the missing tools:

```bash
sudo apt install distrobox clinfo curl unzip
sudo usermod -aG docker,render,video "$USER"
```

If Docker is not installed yet, Ubuntu's Docker package is fine:

```bash
sudo apt install docker.io distrobox clinfo curl unzip
sudo usermod -aG docker,render,video "$USER"
```

Log out and back in after changing groups, then check the host GPU stack:

```bash
groups
ls -l /dev/kfd /dev/dri/renderD*
clinfo | grep -E 'Platform Name|Device Name|Board Name|Device Vendor|Device Type|Driver Version'
```

Set up and launch Resolve:

```bash
./scripts/setup-and-launch-davinci-resolve-docker.sh
```

Launch later with:

```bash
davinci-resolve-docker
```

## Upgrade From Resolve 20

For an existing Resolve 20 or native `/opt/resolve` install, replace the tree and
recreate the container so the 16 GB shared-memory setting applies:

```bash
docker rm -f davincibox-docker
OVERWRITE_RESOLVE=1 RESOLVE_SHM_SIZE=16g ./scripts/setup-and-launch-davinci-resolve-docker.sh
```

To keep Resolve 20 and Resolve 21 side by side, use separate values for
`RESOLVE_DIR`, `RESOLVE_HOME`, and `RESOLVE_CONTAINER`.

## What Setup Does

- Uses `vendor/blackmagic/DaVinci_Resolve_Studio_21.0_Linux.zip` if present.
- Otherwise downloads the pinned Resolve Studio 21.0 Linux archive from
  Blackmagic Design.
- Refuses unvalidated Resolve versions unless `ALLOW_UNSUPPORTED_RESOLVE=1`.
- Installs Resolve to `/opt/resolve`.
- Moves Resolve's bundled GLib/GIO libraries aside for Fedora compatibility.
- Creates the Docker-backed Distrobox container `davincibox-docker`.
- Adds `/dev/kfd`, `/dev/dri`, and the host `render`/`video` group IDs.
- Sets Docker `/dev/shm` to `16g` by default.
- Writes the container OpenCL ICD to the host ROCm OpenCL library.
- Creates an isolated Resolve state tree at
  `~/.local/share/davinci-resolve-21-box-home`.
- Uses the container ALSA/Pulse defaults for normal audio output. Optional
  launcher audio modes can fall back to ALSA null output if Pulse/PipeWire is
  unavailable or being isolated during crash troubleshooting.
- Installs the `davinci-resolve-docker` launcher and desktop entry.

The launcher also creates a single-instance lock at
`$RESOLVE_HOME/.davinci-resolve-docker.lock`. A second launch against the same
state tree exits instead of starting another Resolve process. The lock is
removed when Resolve exits, when `docker exec` returns after a Resolve crash, or
when a stale launcher PID is detected on the next run.

## Common Options

Set these before running setup when needed:

| Variable | Default | Use |
| --- | --- | --- |
| `RESOLVE_CONTAINER` | `davincibox-docker` | Container name |
| `RESOLVE_IMAGE` | `fedora:39` | Container image |
| `RESOLVE_DIR` | `/opt/resolve` | Resolve install path on the host |
| `RESOLVE_HOME` | `~/.local/share/davinci-resolve-21-box-home` | Isolated Resolve HOME/XDG state |
| `RESOLVE_LOCK_DIR` | `$RESOLVE_HOME/.davinci-resolve-docker.lock` | Single-instance lock |
| `RESOLVE_AUDIO_MODE` | `system` | `system`, `auto`, `pulse`, or `null` audio mode |
| `RESOLVE_SHM_SIZE` | `16g` | Docker `/dev/shm` size at container creation |
| `RESOLVE_ZIP` | unset | Local official Resolve zip |
| `RESOLVE_DOWNLOAD_ID` | pinned 21.0 ID | Blackmagic download ID |
| `OVERWRITE_RESOLVE` | `0` | Replace an existing `/opt/resolve` tree |
| `ROCM_OPENCL_LIB` | auto-detected | Host `libamdocl64.so` path |
| `PATCH_RESOLVE_LIBS` | `1` | Move bundled GLib/GIO libraries aside |
| `ALLOW_UNSUPPORTED_RESOLVE` | `0` | Try a non-pinned Resolve version |

The default download cache is:

```text
~/.cache/davinci-resolve-docker/DaVinci_Resolve_Studio_21.0_Linux.zip
```

`RESOLVE_SHM_SIZE` is host RAM-backed IPC space, not GPU VRAM. It is not fully
reserved unless used, and changing it requires recreating the container.

Audio defaults to `RESOLVE_AUDIO_MODE=system`, which uses the container
`/etc/asound.conf` Pulse setup. For one launch, you can also use:

```bash
davinci-resolve-docker --audio=system
davinci-resolve-docker --audio=auto
davinci-resolve-docker --audio=null
```

`--audio=null` intentionally disables audible output with a temporary ALSA null
device and is meant only for isolating audio-related crashes.

## Recreate The Container

Recreate the container whenever the host GPU/runtime surface changes, or when a
Docker creation-time option needs to change.

Do this after:

- Kernel, Mesa, AMDGPU, ROCm, or OpenCL package updates.
- Changing `RESOLVE_SHM_SIZE`, `RESOLVE_IMAGE`, device mappings, or group IDs.
- Adding yourself to `docker`, `render`, or `video`.
- Verifier output shows `/dev/shm` below 16 GiB.
- Resolve sees the AMD OpenCL platform but no GPU device.
- Rare crashes start after a host graphics/runtime update.

Command:

```bash
docker rm -f davincibox-docker
RESOLVE_SHM_SIZE=16g ./scripts/setup-davinci-resolve-docker.sh
./scripts/verify-davinci-resolve-docker.sh
```

Use the same `RESOLVE_CONTAINER`, `RESOLVE_HOME`, `RESOLVE_DIR`, and
`RESOLVE_SHM_SIZE` values you used for setup if you customized them.

## Verify

Run:

```bash
./scripts/verify-davinci-resolve-docker.sh
```

Expected results:

- `/dev/kfd` is readable inside the container.
- At least one `/dev/dri/renderD*` node is readable inside the container.
- Docker `/dev/shm` is at least 16 GiB.
- `clinfo` inside the container shows an AMD GPU device.
- `ldd /opt/resolve/bin/resolve` reports no missing libraries.
- HOME/XDG paths point at the isolated Resolve 21 state tree.
- Audio reports a Pulse/PipeWire socket and ALSA `default` opens cleanly. The
  default `RESOLVE_AUDIO_MODE=system` matches the container ALSA/Pulse defaults.
  Use `davinci-resolve-docker --audio=null` only when isolating audio from a
  crash.
- The launcher lock is absent, active, or stale as expected.

## AMD GPU Notes

This repo does not install AMD drivers or ROCm. Fix host `clinfo` first; if the
host cannot see an AMD OpenCL GPU, the container cannot either.

Practical guidance for the RX 7900 XT and similar AMD GPUs:

- Resolve needs AMD's ROCm OpenCL ICD, usually `libamdocl64.so`. Mesa OpenCL
  alone is not enough for this setup.
- In Resolve preferences, use OpenCL and manually select only the RX 7900 XT if
  another AMD GPU or iGPU appears.
- Rare crashes on a 20 GB RX 7900 XT are less likely to be simple VRAM pressure
  and more likely to involve host/container runtime drift, `/dev/shm`, project
  state, permissions, or GPU reset behavior.
- Keep the host `amdgpu` kernel layer and ROCm/OpenCL userspace aligned. After a
  driver or ROCm change, recreate the container and rerun the verifier.
- The container user must have access to the host `render` and `video` group
  IDs. Log out and back in after group changes.
- Keep `RESOLVE_SHM_SIZE=16g` for this 64 GB RAM system. Larger values are
  reasonable on a 128 GB RAM configuration if verifier output or crash logs point
  at shared-memory pressure.
- Avoid `HSA_OVERRIDE_GFX_VERSION` unless you are deliberately testing an
  unsupported GPU.
- Xorg/X11 is the compatibility target. Wayland may work, but it is not the
  validated path here.

Useful AMD references:

- ROCm Linux install guide:
  <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/>
- ROCm Linux system requirements:
  <https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html>
- ROCm compatibility matrix:
  <https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html>

## Crash Troubleshooting

First run the verifier and inspect the host kernel log:

```bash
./scripts/verify-davinci-resolve-docker.sh
journalctl -k -b --no-pager | grep -Ei 'amdgpu|kfd|gpu reset|ring|vm fault|oom|segfault'
```

If `/dev/shm` is below 16 GiB, recreate the container with `RESOLVE_SHM_SIZE=16g`.

Force Resolve to rescan the GPU:

```bash
./scripts/reset-davinci-resolve-gpu-cache.sh
```

Capture the next crash from a terminal:

```bash
davinci-resolve-docker 2>&1 | tee "$HOME/davinci-resolve-crash-$(date +%Y%m%d-%H%M%S).log"
```

If OpenCL shows an AMD platform but no GPU devices, the container usually cannot
read `/dev/kfd` or the render node. Confirm host group membership, log out and
back in if needed, then recreate the container.

## Project Libraries

Before opening existing projects in Resolve 21, make a full project library
backup and export important projects individually.

After a hard crash, do not delete `*-wal`, `*-shm`, or `*-journal` files. Check
project database integrity with:

```bash
./scripts/check-davinci-resolve-project-dbs.sh
```

To check a project library stored somewhere else:

```bash
./scripts/check-davinci-resolve-project-dbs.sh /path/to/resolve/project/library
```

Keep project libraries on local SSD/NVMe storage. Avoid sync folders, network
filesystems, FUSE mounts, container overlay storage, and opening the same
library from native Resolve and container Resolve at the same time.

## Bundled Installer

This checkout may include:

```text
vendor/blackmagic/DaVinci_Resolve_Studio_21.0_Linux.zip
vendor/blackmagic/SHA256SUMS
```

The Resolve installer is proprietary Blackmagic Design software. Be careful
before pushing or publishing archives under `vendor/blackmagic/`.
