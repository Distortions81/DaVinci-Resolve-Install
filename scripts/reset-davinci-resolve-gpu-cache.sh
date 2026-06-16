#!/usr/bin/env bash
set -euo pipefail

resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-21-box-home}"
resolve_xdg_data_home="${RESOLVE_XDG_DATA_HOME:-${resolve_home}/.local/share}"

die() {
  printf 'reset-davinci-resolve-gpu-cache: ERROR: %s\n' "$*" >&2
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
