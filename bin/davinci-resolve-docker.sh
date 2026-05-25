#!/usr/bin/env bash
set -euo pipefail

container="${RESOLVE_CONTAINER:-davincibox-docker}"
container_user="${RESOLVE_USER:-$(id -un)}"
resolve_dir="${RESOLVE_DIR:-/opt/resolve}"
uid="$(id -u)"
display="${DISPLAY:-:0}"
xauthority="${XAUTHORITY:-$HOME/.Xauthority}"
xdg_runtime="/run/user/${uid}"
pulse_server="${PULSE_SERVER:-unix:${xdg_runtime}/pulse/native}"
dbus_session="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${xdg_runtime}/bus}"

die() {
  echo "davinci-resolve-docker: $*" >&2
  exit 1
}

resolve_amd_opencl_lib() {
  if [ -n "${ROCM_OPENCL_LIB:-}" ]; then
    [ -e "${ROCM_OPENCL_LIB}" ] || die "ROCM_OPENCL_LIB does not exist: ${ROCM_OPENCL_LIB}"
    printf '%s\n' "${ROCM_OPENCL_LIB}"
    return 0
  fi

  local icd line path
  for icd in /etc/OpenCL/vendors/*.icd; do
    [ -e "${icd}" ] || continue
    while IFS= read -r line || [ -n "${line}" ]; do
      line="${line%%#*}"
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [ -n "${line}" ] || continue
      [[ "${line}" == *amd* || "${line}" == *amdocl* ]] || continue

      if [[ "${line}" = /* && -e "${line}" ]]; then
        printf '%s\n' "${line}"
        return 0
      fi

      path="$(ldconfig -p 2>/dev/null | awk -v lib="${line}" '$1 == lib { print $NF; exit }')"
      if [ -n "${path}" ] && [ -e "${path}" ]; then
        printf '%s\n' "${path}"
        return 0
      fi
    done < "${icd}"
  done

  for path in /opt/rocm*/lib/libamdocl64.so /opt/rocm*/core-*/lib/opencl/libamdocl64.so /opt/amdgpu*/lib*/libamdocl64.so; do
    [ -e "${path}" ] || continue
    printf '%s\n' "${path}"
    return 0
  done

  path="$(find -L /opt/rocm* /opt/amdgpu /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu \
    -type f -name 'libamdocl64.so*' -print -quit 2>/dev/null || true)"
  [ -n "${path}" ] && [ -e "${path}" ] || die "could not find AMD ROCm OpenCL library. Verify host clinfo shows an AMD GPU."
  printf '%s\n' "${path}"
}

host_opencl="$(resolve_amd_opencl_lib)"
container_opencl="/run/host${host_opencl}"

if ! docker container inspect "${container}" >/dev/null 2>&1; then
  die "container '${container}' does not exist. Run scripts/setup-davinci-resolve-docker.sh from the repo first."
fi

if [ "$(docker inspect -f '{{.State.Running}}' "${container}")" != "true" ]; then
  docker start "${container}" >/dev/null
fi

docker exec -u root \
  -e RESOLVE_DIR_IN_CONTAINER="/run/host${resolve_dir}" \
  -e CONTAINER_OPENCL="${container_opencl}" \
  "${container}" bash -lc '
  set -e
  if [ -e /opt/resolve ] && [ ! -L /opt/resolve ]; then
    echo "/opt/resolve exists in the container and is not a symlink" >&2
    exit 1
  fi
  ln -sfn "${RESOLVE_DIR_IN_CONTAINER}" /opt/resolve
  mkdir -p /etc/OpenCL/vendors
  printf "%s\n" "${CONTAINER_OPENCL}" > /etc/OpenCL/vendors/amdocl64-host.icd
'

exec docker exec -u "${container_user}" \
  -e DISPLAY="${display}" \
  -e XAUTHORITY="${xauthority}" \
  -e XDG_RUNTIME_DIR="${xdg_runtime}" \
  -e PULSE_SERVER="${pulse_server}" \
  -e DBUS_SESSION_BUS_ADDRESS="${dbus_session}" \
  -e QT_X11_NO_MITSHM="${QT_X11_NO_MITSHM:-1}" \
  -w /opt/resolve \
  "${container}" \
  /opt/resolve/bin/resolve "$@"
