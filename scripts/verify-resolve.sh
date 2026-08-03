#!/usr/bin/env bash
set -euo pipefail

container="${RESOLVE_CONTAINER:-davincibox-docker}"
container_user="${RESOLVE_USER:-$(id -un)}"
uid="$(id -u)"
resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-21-box-home}"
resolve_xdg_config_home="${RESOLVE_XDG_CONFIG_HOME:-${resolve_home}/.config}"
resolve_xdg_data_home="${RESOLVE_XDG_DATA_HOME:-${resolve_home}/.local/share}"
resolve_xdg_cache_home="${RESOLVE_XDG_CACHE_HOME:-${resolve_home}/.cache}"
resolve_lock_dir="${RESOLVE_LOCK_DIR:-${resolve_home}/.davinci-resolve-docker.lock}"
pulse_server="${PULSE_SERVER:-unix:/run/user/${uid}/pulse/native}"
recommended_shm_bytes=$((1 * 1024 * 1024 * 1024))

audio_socket_path() {
  case "${pulse_server}" in
    unix:/*) printf '%s\n' "${pulse_server#unix:}" ;;
    unix:path=*) printf '%s\n' "${pulse_server#unix:path=}" ;;
    *) return 1 ;;
  esac
}

if ! docker container inspect "${container}" >/dev/null 2>&1; then
  echo "Container '${container}' does not exist." >&2
  exit 1
fi

if [ "$(docker inspect -f '{{.State.Running}}' "${container}")" != "true" ]; then
  docker start "${container}" >/dev/null
fi

echo "Container:"
container_ipc="$(docker inspect -f '{{.HostConfig.IpcMode}}' "${container}")"
requested_shm="$(docker inspect -f '{{.HostConfig.ShmSize}}' "${container}")"
actual_shm="$(docker exec "${container}" df -B1 --output=size /dev/shm | awk 'NR == 2 { print $1 }')"
docker inspect -f '  name={{.Name}} running={{.State.Running}} image={{.Config.Image}} groups={{json .HostConfig.GroupAdd}} devices={{json .HostConfig.Devices}}' "${container}"
docker inspect -f '  ipc={{.HostConfig.IpcMode}} security={{json .HostConfig.SecurityOpt}} ulimits={{json .HostConfig.Ulimits}}' "${container}"
echo "  requested_shm=${requested_shm} bytes"
echo "  actual_shm=${actual_shm} bytes"
if [ "${container_ipc}" = "host" ]; then
  echo "  note: host IPC is active, so /dev/shm uses the host tmpfs rather than the requested private size"
elif [[ "${actual_shm}" =~ ^[0-9]+$ ]] && [ "${actual_shm}" -lt "${recommended_shm_bytes}" ]; then
  echo "  warning: /dev/shm is below the recommended 1 GiB. Recreate the container with RESOLVE_SHM_SIZE=1g."
fi

cache_source="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/cache/davinci-resolve"}}{{.Source}}{{end}}{{end}}' "${container}")"
if [ -n "${cache_source}" ]; then
  echo "  resolve_cache=${cache_source} -> /var/cache/davinci-resolve"
  if docker exec -u "${container_user}" "${container}" test -w /var/cache/davinci-resolve; then
    echo "  resolve_cache_writable=yes"
  else
    echo "  error: Resolve user cannot write /var/cache/davinci-resolve" >&2
    exit 1
  fi
else
  echo "  resolve_cache=not configured"
fi

echo
echo "Host session:"
echo "  XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-unknown}"
if [ "${XDG_SESSION_TYPE:-}" != "x11" ]; then
  echo "  warning: this setup is expected to be most reliable from an X11 session"
fi

echo
echo "Host GPU groups:"
getent group render video || true

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
echo "Audio:"
echo "  RESOLVE_AUDIO_MODE=${RESOLVE_AUDIO_MODE:-system}"
echo "  PULSE_SERVER=${pulse_server}"
if pulse_socket="$(audio_socket_path)"; then
  if [ -S "${pulse_socket}" ]; then
    echo "  host pulse socket=present (${pulse_socket})"
  else
    echo "  host pulse socket=missing (${pulse_socket})"
  fi
else
  echo "  host pulse socket=not a unix socket path"
fi
if [ -f "${resolve_home}/.davinci-resolve-docker-audio-mode" ]; then
  echo "  last launcher mode=$(cat "${resolve_home}/.davinci-resolve-docker-audio-mode")"
else
  echo "  last launcher mode=unknown (launch Resolve once to record audio mode)"
fi
if [ -f "${resolve_home}/.asoundrc" ]; then
  echo "  asoundrc=${resolve_home}/.asoundrc"
else
  echo "  asoundrc=missing"
fi
if [ -f "${resolve_xdg_config_home}/pulse/client.conf" ]; then
  echo "  pulse client=${resolve_xdg_config_home}/pulse/client.conf"
else
  echo "  pulse client=missing"
fi
docker exec -u "${container_user}" \
  -e HOME="${resolve_home}" \
  -e XDG_CONFIG_HOME="${resolve_xdg_config_home}" \
  -e XDG_DATA_HOME="${resolve_xdg_data_home}" \
  -e XDG_CACHE_HOME="${resolve_xdg_cache_home}" \
  -e XDG_RUNTIME_DIR="/run/user/${uid}" \
  -e PULSE_SERVER="${pulse_server}" \
  "${container}" bash -lc '
  if [ -S "${XDG_RUNTIME_DIR}/pulse/native" ]; then
    echo "  container pulse socket=present (${XDG_RUNTIME_DIR}/pulse/native)"
  else
    echo "  container pulse socket=missing (${XDG_RUNTIME_DIR}/pulse/native)"
  fi
  python3 - <<'"'"'PY'"'"'
import ctypes
import sys

alsa = ctypes.CDLL("libasound.so.2")
pcm = ctypes.c_void_p()
err = alsa.snd_pcm_open(ctypes.byref(pcm), b"default", 0, 0)
print(f"  alsa pcm default open={err}")
if err == 0:
    alsa.snd_pcm_close(pcm)

ctl = ctypes.c_void_p()
err = alsa.snd_ctl_open(ctypes.byref(ctl), b"default", 0)
print(f"  alsa ctl default open={err}")
if err == 0:
    alsa.snd_ctl_close(ctl)

sys.exit(0)
PY
'

echo
echo "Launcher lock:"
echo "  path=${resolve_lock_dir}"
if [ -d "${resolve_lock_dir}" ]; then
  lock_pid="$(cat "${resolve_lock_dir}/pid" 2>/dev/null || true)"
  echo "  pid=${lock_pid:-unknown}"
  if [[ "${lock_pid}" =~ ^[0-9]+$ ]] && kill -0 "${lock_pid}" 2>/dev/null; then
    echo "  status=active"
  else
    echo "  status=stale"
  fi
else
  echo "  status=absent"
fi

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
  if ls /dev/dri/renderD* >/dev/null 2>&1; then
    ls -ln /dev/kfd /dev/dri/renderD*
  else
    ls -ln /dev/kfd /dev/dri 2>/dev/null || true
  fi
  test -r /dev/kfd && echo "kfd: readable" || echo "kfd: not readable"
  readable_render_node=0
  for node in /dev/dri/renderD*; do
    [ -e "${node}" ] || continue
    if [ -r "${node}" ]; then
      readable_render_node=1
      echo "$(basename "${node}"): readable"
    else
      echo "$(basename "${node}"): not readable"
    fi
  done
  [ "${readable_render_node}" -eq 1 ] || echo "render node: no readable /dev/dri/renderD* node found"
'

echo
echo "Shared memory:"
docker exec -u "${container_user}" "${container}" bash -lc '
  df -h /dev/shm
'

echo
echo "OpenCL:"
docker exec -u "${container_user}" "${container}" bash -lc '
  clinfo_output="$(clinfo 2>&1)" || {
    printf "%s\n" "${clinfo_output}"
    exit 1
  }
  printf "%s\n" "${clinfo_output}" | grep -E "Number of platforms|Platform Name|Number of devices|Device Name|Board Name|Device Vendor|Device Type|Driver Version" | sed -n "1,60p" || true
  printf "%s\n" "${clinfo_output}" | awk '"'"'
    function flush_device() {
      if (device_vendor_amd && device_gpu) {
        found = 1
      }
      device_vendor_amd = 0
      device_gpu = 0
    }
    /^[[:space:]]*Device Name/ { flush_device() }
    /Device Vendor/ && ($0 ~ /AMD|Advanced Micro Devices/) { device_vendor_amd = 1 }
    /Device Type/ && ($0 ~ /GPU/) { device_gpu = 1 }
    END { flush_device(); exit !found }
  '"'"' || {
    echo "OpenCL check failed: no AMD GPU device was reported."
    exit 1
  }
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
