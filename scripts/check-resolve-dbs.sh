#!/usr/bin/env bash
set -euo pipefail

gpu_backend="${RESOLVE_GPU:-auto}"
case "${gpu_backend,,}" in
  nvidia|cuda) gpu_backend="nvidia" ;;
  amd|rocm|opencl) gpu_backend="amd" ;;
  auto)
    if docker container inspect davincibox-docker >/dev/null 2>&1; then
      gpu_backend="amd"
    elif docker container inspect davincibox-nvidia-docker >/dev/null 2>&1; then
      gpu_backend="nvidia"
    elif command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
      gpu_backend="nvidia"
    else
      gpu_backend="amd"
    fi
    ;;
  *) echo "Invalid RESOLVE_GPU value: ${gpu_backend}. Use auto, amd, or nvidia." >&2; exit 1 ;;
esac

if [ "${gpu_backend}" = "nvidia" ]; then
  container="${RESOLVE_CONTAINER:-davincibox-nvidia-docker}"
  resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-21-nvidia-box-home}"
else
  container="${RESOLVE_CONTAINER:-davincibox-docker}"
  resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-21-box-home}"
fi
container_user="${RESOLVE_USER:-$(id -un)}"
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

roots=("$@")
if [ "${#roots[@]}" -eq 0 ]; then
  roots=("${resolve_home}")
fi

docker exec -u "${container_user}" \
  -e HOME="${resolve_home}" \
  -e XDG_CONFIG_HOME="${resolve_xdg_config_home}" \
  -e XDG_DATA_HOME="${resolve_xdg_data_home}" \
  -e XDG_CACHE_HOME="${resolve_xdg_cache_home}" \
  "${container}" bash -lc '
    set -euo pipefail

    if ! command -v sqlite3 >/dev/null 2>&1; then
      echo "sqlite3 is not installed in the container. Rerun setup to install the sqlite package." >&2
      exit 1
    fi

    found=0
    status=0

    for root in "$@"; do
      if [ ! -e "${root}" ] && [ -e "/run/host${root}" ]; then
        root="/run/host${root}"
      fi

      if [ ! -e "${root}" ]; then
        echo "Skipping missing path: ${root}" >&2
        continue
      fi

      while IFS= read -r -d "" db; do
        found=1
        printf "\n== %s ==\n" "${db}"
        if output="$(sqlite3 "${db}" "PRAGMA integrity_check;" 2>&1)"; then
          printf "%s\n" "${output}"
          [ "${output}" = "ok" ] || status=1
        else
          printf "%s\n" "${output}"
          status=1
        fi
      done < <(
        find "${root}" -type f -name "Project.db" -print0 2>/dev/null
      )
    done

    if [ "${found}" -eq 0 ]; then
      echo "No Resolve Project.db files found under the checked path(s)."
    fi

    exit "${status}"
  ' check-resolve-dbs "${roots[@]}"
