# Advanced Usage

The defaults are intended to work without customization. Set environment
variables only when the standard setup does not match the host or workflow.

## Options

| Variable             | Default          | Use                                                                           |
| -------------------- | ---------------- | ----------------------------------------------------------------------------- |
| `RESOLVE_GPU`        | `auto`           | `auto`, `amd`, or `nvidia`; `rocm`, `opencl`, and `cuda` aliases are accepted |
| `RESOLVE_CONTAINER`  | backend-specific | Override the AMD or NVIDIA container name                                     |
| `RESOLVE_IMAGE`      | `fedora:39`      | Override the container image                                                  |
| `RESOLVE_EDITION`    | `Studio`         | Select `Studio` or `Resolve` Free                                             |
| `RESOLVE_DIR`        | `/opt/resolve`   | Resolve installation path on the host                                         |
| `RESOLVE_HOME`       | backend-specific | Override the isolated Resolve HOME/XDG state                                  |
| `RESOLVE_AUDIO_MODE` | `system`         | `system`, `auto`, `pulse`, or `null` audio mode                               |
| `RESOLVE_SHM_SIZE`   | `1g`             | Requested Docker `/dev/shm` size at container creation                        |
| `RESOLVE_CACHE_DIR`  | unset            | Host directory mounted at `/var/cache/davinci-resolve`                        |
| `RESOLVE_ZIP`        | unset            | Local official ZIP for the selected edition                                   |
| `OVERWRITE_RESOLVE`  | `0`              | Replace the existing `/opt/resolve` tree                                      |
| `ROCM_OPENCL_LIB`    | auto-detected    | Override the host `libamdocl64.so` path for AMD                               |
| `QT_X11_NO_MITSHM`   | `0`              | Set to `1` at launch to disable Qt MIT-SHM                                    |

## Backend Defaults

| Backend | Container                  | Resolve state                                       |
| ------- | -------------------------- | --------------------------------------------------- |
| AMD     | `davincibox-docker`        | `~/.local/share/davinci-resolve-21-box-home`        |
| NVIDIA  | `davincibox-nvidia-docker` | `~/.local/share/davinci-resolve-21-nvidia-box-home` |

Both backends share `/opt/resolve` by default but use separate preferences,
project-library state, GPU caches, locks, and desktop entries.

## Installer Search Order

Setup looks for the selected edition's archive in this order:

1. `RESOLVE_ZIP`.
2. `vendor/blackmagic/` in the repository.
3. `~/Downloads`.
4. The edition-specific download cache.
5. Blackmagic Design's official Studio download endpoint.

The Free edition stops after the local/cache checks because Blackmagic Design
requires personal registration.

Default cache paths:

```text
~/.cache/davinci-resolve-docker/DaVinci_Resolve_Studio_21.0.4_Linux.zip
~/.cache/davinci-resolve-docker/DaVinci_Resolve_21.0.4_Linux.zip
```

## What Setup Changes

- Installs the selected Resolve edition to `/opt/resolve`.
- Creates a Docker-backed Fedora Distrobox container.
- Passes AMD devices and groups or requests NVIDIA GPUs through NVIDIA
  Container Toolkit.
- Requests a 1 GiB Docker `/dev/shm`. Distrobox may use host IPC, in which case
  Resolve sees the host shared-memory filesystem instead.
- Applies unconfined seccomp, unlimited locked memory, and a 1,048,576
  file-descriptor limit.
- Moves Resolve's bundled GLib/GIO libraries aside so the container can supply
  compatible versions.
- Configures the AMD or NVIDIA OpenCL ICD.
- Configures ALSA defaults for the system Pulse/PipeWire service.
- Installs `davinci-resolve-docker` and a backend-specific desktop entry.

The launcher prevents two Resolve processes from using the same isolated state
tree simultaneously.

## Switch Editions

Back up important projects before changing editions or versions.

Studio:

```bash
docker rm -f davincibox-docker
RESOLVE_EDITION=Studio OVERWRITE_RESOLVE=1 ./quickstart.sh
```

Free:

```bash
docker rm -f davincibox-docker
RESOLVE_EDITION=Resolve OVERWRITE_RESOLVE=1 ./quickstart.sh
```

Add `RESOLVE_GPU=nvidia` and use `davincibox-nvidia-docker` for NVIDIA.

## Project Libraries

Before opening existing projects in Resolve 21, create a full project-library
backup and export important projects individually.

Keep project libraries on a local native Linux filesystem. Avoid sync folders,
network filesystems, FUSE mounts, container overlay storage, and opening the
same library from native and containerized Resolve simultaneously.

After a hard crash, do not delete SQLite `*-wal`, `*-shm`, or `*-journal` files.
Use `scripts/check-resolve-dbs.sh` to check database integrity.

## Custom Cache Storage

Bind a writable absolute host path during container creation:

```bash
RESOLVE_CACHE_DIR=/path/on/fast/storage/ResolveCache ./scripts/setup-resolve.sh
```

Then select `/var/cache/davinci-resolve` inside Resolve. Cache, proxy, and
optimized-media files should be treated as disposable; do not store the only
copy of a project library there.
