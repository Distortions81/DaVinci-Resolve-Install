#!/usr/bin/env bash
set -euo pipefail

gpu_backend="${RESOLVE_GPU:-auto}"
case "${gpu_backend,,}" in
  nvidia|cuda) gpu_backend="nvidia" ;;
  amd|rocm|opencl) gpu_backend="amd" ;;
  auto)
    if [ -d "${HOME}/.local/share/davinci-resolve-21-box-home" ]; then
      gpu_backend="amd"
    elif [ -d "${HOME}/.local/share/davinci-resolve-21-nvidia-box-home" ]; then
      gpu_backend="nvidia"
    elif command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
      gpu_backend="nvidia"
    else
      gpu_backend="amd"
    fi
    ;;
  *) printf 'reset-gpu-cache: ERROR: invalid RESOLVE_GPU value: %s\n' "${gpu_backend}" >&2; exit 1 ;;
esac

if [ "${gpu_backend}" = "nvidia" ]; then
  resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-21-nvidia-box-home}"
else
  resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-21-box-home}"
fi
resolve_xdg_data_home="${RESOLVE_XDG_DATA_HOME:-${resolve_home}/.local/share}"

die() {
  printf 'reset-gpu-cache: ERROR: %s\n' "$*" >&2
  exit 1
}

need_absolute_path() {
  case "$2" in
    /*) ;;
    *) die "$1 must be an absolute path: $2" ;;
  esac
}

need_absolute_path "RESOLVE_HOME" "${resolve_home}"
need_absolute_path "RESOLVE_XDG_DATA_HOME" "${resolve_xdg_data_home}"

roots=(
  "${resolve_xdg_data_home}/DaVinciResolve"
  "${resolve_home}/.local/share/DaVinciResolve"
)

removed=0
seen_roots=""

for root in "${roots[@]}"; do
  case "
${seen_roots}
" in
    *"
${root}
"*) continue ;;
  esac
  seen_roots="${seen_roots}${root}
"

  [ -d "${root}" ] || continue
  while IFS= read -r -d "" file; do
    rm -f -- "${file}"
    printf 'removed %s\n' "${file}"
    removed=1
  done < <(find "${root}" -type f -name gpudetect.bin -print0 2>/dev/null)
done

if [ "${removed}" -eq 0 ]; then
  printf 'no gpudetect.bin cache files found under %s\n' "${resolve_xdg_data_home}/DaVinciResolve"
fi
