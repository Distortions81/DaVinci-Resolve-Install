#!/usr/bin/env bash
set -euo pipefail

container="${RESOLVE_CONTAINER:-davincibox-docker}"
container_user="${RESOLVE_USER:-$(id -un)}"
resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-box-home}"
resolve_xdg_config_home="${RESOLVE_XDG_CONFIG_HOME:-${resolve_home}/.config}"
resolve_xdg_data_home="${RESOLVE_XDG_DATA_HOME:-${resolve_home}/.local/share}"
resolve_xdg_cache_home="${RESOLVE_XDG_CACHE_HOME:-${resolve_home}/.cache}"

if ! docker container inspect "${container}" >/dev/null 2>&1; then
  echo "Container '${container}' does not exist." >&2
  exit 1
fi

if [ "$(docker inspect -f '{{.State.Running}}' "${container}")" != "true" ]; then
  docker start "${container}" >/dev/null
fi

echo "Container:"
docker inspect -f '  name={{.Name}} running={{.State.Running}} image={{.Config.Image}} groups={{json .HostConfig.GroupAdd}} devices={{json .HostConfig.Devices}}' "${container}"

echo
echo "Host session:"
echo "  XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}"
if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
  echo "  warning: this setup is expected to be most reliable from an X11 session"
fi

echo
echo "Resolve isolated state:"
echo "  HOME=${resolve_home}"
echo "  XDG_CONFIG_HOME=${resolve_xdg_config_home}"
echo "  XDG_DATA_HOME=${resolve_xdg_data_home}"
echo "  XDG_CACHE_HOME=${resolve_xdg_cache_home}"
for path in "${resolve_home}" "${resolve_xdg_config_home}" "${resolve_xdg_data_home}" "${resolve_xdg_cache_home}"; do
  if [ -d "${path}" ]; then
    echo "  exists: ${path}"
  else
    echo "  missing: ${path} (created by the launcher on first run)"
  fi
done

echo
echo "Device permissions:"
docker exec -u "${container_user}" \
  -e HOME="${resolve_home}" \
  -e XDG_CONFIG_HOME="${resolve_xdg_config_home}" \
  -e XDG_DATA_HOME="${resolve_xdg_data_home}" \
  -e XDG_CACHE_HOME="${resolve_xdg_cache_home}" \
  "${container}" bash -lc '
  id
  printf "HOME=%s\n" "$HOME"
  printf "XDG_CONFIG_HOME=%s\n" "$XDG_CONFIG_HOME"
  printf "XDG_DATA_HOME=%s\n" "$XDG_DATA_HOME"
  printf "XDG_CACHE_HOME=%s\n" "$XDG_CACHE_HOME"
  ls -ln /dev/kfd /dev/dri/renderD128
  test -r /dev/kfd && echo "kfd: readable" || echo "kfd: not readable"
  test -r /dev/dri/renderD128 && echo "renderD128: readable" || echo "renderD128: not readable"
'

echo
echo "OpenCL:"
docker exec -u "${container_user}" "${container}" bash -lc '
  clinfo | grep -E "Number of platforms|Platform Name|Number of devices|Device Name|Board Name|Driver Version" | sed -n "1,40p"
'

echo
echo "Resolve missing libraries:"
docker exec -u "${container_user}" "${container}" bash -lc '
  missing="$(ldd /opt/resolve/bin/resolve 2>&1 | grep "not found" || true)"
  if [ -n "${missing}" ]; then
    printf "%s\n" "${missing}"
    exit 1
  fi
  echo "none"
'

echo
echo "Recent AMD/GPU kernel messages:"
if command -v journalctl >/dev/null 2>&1; then
  gpu_log="$(journalctl -k -b --no-pager 2>/dev/null | grep -Ei "amdgpu|kfd|gpu reset|ring|vm fault|oom|segfault" | tail -n 80 || true)"
  if [ -n "${gpu_log}" ]; then
    printf "%s\n" "${gpu_log}"
  else
    echo "none found in this boot"
  fi
else
  echo "journalctl is not installed on the host"
fi
