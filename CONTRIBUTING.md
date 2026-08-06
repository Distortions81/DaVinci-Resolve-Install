# Contributing

Bug reports, documentation fixes, GPU test results, and focused pull requests
are welcome.

## Before Opening an Issue

1. Update to the latest repository version.
2. Run `./scripts/verify-resolve.sh` with the same `RESOLVE_GPU` selection used
   for setup.
3. Search existing issues for the exact error and GPU model.
4. Remove license keys, usernames, media names, and private paths from logs.

Include:

- Host distribution and version.
- X11 or Wayland session.
- Resolve version and Free or Studio edition.
- GPU model and host driver version.
- AMD ROCm/OpenCL version or NVIDIA Container Toolkit version.
- Docker and Distrobox versions.
- Whether the failure happened during setup, verification, or launch.
- Complete error text and relevant verifier output.

## Pull Requests

Keep changes focused and preserve both GPU paths unless the change is explicitly
backend-specific.

Before submitting:

```bash
bash -n quickstart.sh bin/launch-resolve.sh scripts/*.sh
git diff --check
```

When hardware is available, also run:

```bash
./scripts/verify-resolve.sh
```

Use `RESOLVE_GPU=nvidia` for NVIDIA tests on a mixed-GPU host. Describe the host,
GPU, driver, desktop session, and commands tested in the pull request.

Do not commit Resolve installers, extracted Resolve files, license material,
project databases, crash dumps containing private data, or media files.
