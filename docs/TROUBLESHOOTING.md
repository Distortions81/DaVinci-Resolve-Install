# Troubleshooting and Maintenance

Start with the verifier. It gives a more useful failure surface than launching
Resolve repeatedly:

```bash
./scripts/verify-resolve.sh
```

Use `RESOLVE_GPU=nvidia` on a mixed-GPU host when checking the NVIDIA container.

## What Verification Checks

- Container image, device mappings, limits, IPC mode, and shared memory.
- Readable `/dev/kfd` and `/dev/dri/renderD*` devices for AMD.
- `nvidia-smi` and `libcuda.so.1` for NVIDIA.
- An AMD or NVIDIA GPU reported through OpenCL.
- Missing libraries in `/opt/resolve/bin/resolve`.
- Resolve's isolated HOME and XDG paths.
- Pulse/PipeWire and ALSA audio access.
- Recent AMD, NVIDIA, GPU reset, fault, OOM, and segmentation-fault messages.

## Update or Rebuild

AMD:

```bash
git pull
docker rm -f davincibox-docker
RESOLVE_SHM_SIZE=1g ./scripts/setup-resolve.sh
./scripts/verify-resolve.sh
```

NVIDIA:

```bash
git pull
docker rm -f davincibox-nvidia-docker
RESOLVE_GPU=nvidia RESOLVE_SHM_SIZE=1g ./scripts/setup-resolve.sh
RESOLVE_GPU=nvidia ./scripts/verify-resolve.sh
```

Removing a container does not remove Resolve's isolated settings or project
state. Omit `git pull` to rebuild from the current checkout.

To reinstall Resolve itself, add `OVERWRITE_RESOLVE=1` and run `quickstart.sh`:

```bash
docker rm -f davincibox-docker
OVERWRITE_RESOLVE=1 RESOLVE_SHM_SIZE=1g ./quickstart.sh
```

## AMD GPU Is Missing

If host `clinfo` does not show an AMD GPU, fix the host driver and ROCm/OpenCL
installation first. The container cannot expose a GPU the host cannot use.

If `/dev/kfd` or `/dev/dri/renderD*` is not readable, confirm the user belongs
to the `render` and `video` groups, log out and back in, and recreate the AMD
container.

If Resolve sees an AMD OpenCL platform but no GPU, recreate the container after
any kernel, Mesa, AMDGPU, ROCm, OpenCL, device-mapping, or group change.

## NVIDIA GPU Is Missing

Confirm the host driver and Docker runtime:

```bash
nvidia-smi
docker info --format '{{json .Runtimes}}'
```

If the runtime does not contain `nvidia`, install NVIDIA Container Toolkit, then:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker rm -f davincibox-nvidia-docker
RESOLVE_GPU=nvidia ./scripts/setup-resolve.sh
```

Recreate the NVIDIA container after host driver or Container Toolkit changes.

## Resolve Is Slow or Unresponsive

Recreate the selected container after a graphics or runtime change. On Xorg,
the launcher enables Qt's MIT-SHM display path by default; this substantially
improved UI responsiveness on the tested AMD system.

Disable it for one launch if it causes corruption or crashes:

```bash
QT_X11_NO_MITSHM=1 davinci-resolve-docker
```

For cache-heavy timelines, use a fast SSD or NVMe separate from source media:

```bash
docker rm -f davincibox-docker
RESOLVE_CACHE_DIR=/path/on/separate/nvme/ResolveCache \
RESOLVE_SHM_SIZE=1g \
./scripts/setup-resolve.sh
./scripts/verify-resolve.sh
```

Select `/var/cache/davinci-resolve` inside Resolve for cache files, proxies, and
optimized media. Treat that directory as disposable cache storage.

## Reset GPU Detection

```bash
./scripts/reset-gpu-cache.sh
```

For NVIDIA on a mixed-GPU host:

```bash
RESOLVE_GPU=nvidia ./scripts/reset-gpu-cache.sh
```

## Test Audio

Run Resolve without audible output to determine whether audio initialization is
involved in a crash:

```bash
davinci-resolve-docker --audio=null
```

`--audio=null` is for diagnosis only. The normal `system` mode uses the host
Pulse/PipeWire setup.

## Capture a Crash

```bash
davinci-resolve-docker 2>&1 | tee "$HOME/davinci-resolve-crash-$(date +%Y%m%d-%H%M%S).log"
journalctl -k -b --no-pager | grep -Ei 'amdgpu|kfd|nvidia|nvrm|xid|gpu reset|ring|vm fault|oom|segfault'
```

Attach the relevant output and `scripts/verify-resolve.sh` output to a bug
report. Remove license keys, usernames, media names, and other private data
before posting logs.

## Project Database Problems

Do not delete `*-wal`, `*-shm`, or `*-journal` files after a crash. Check the
isolated project library:

```bash
./scripts/check-resolve-dbs.sh
```

Or check another location:

```bash
./scripts/check-resolve-dbs.sh /path/to/resolve/project/library
```
