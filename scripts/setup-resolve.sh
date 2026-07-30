#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"

container="${RESOLVE_CONTAINER:-davincibox-docker}"
image="${RESOLVE_IMAGE:-fedora:39}"
resolve_dir="${RESOLVE_DIR:-/opt/resolve}"
container_user="${RESOLVE_USER:-$(id -un)}"
resolve_home="${RESOLVE_HOME:-${HOME}/.local/share/davinci-resolve-21-box-home}"
resolve_shm_size="${RESOLVE_SHM_SIZE:-16g}"
install_launcher="${INSTALL_LAUNCHER:-1}"
patch_resolve_libs="${PATCH_RESOLVE_LIBS:-1}"
download_resolve="${DOWNLOAD_RESOLVE:-auto}"
overwrite_resolve="${OVERWRITE_RESOLVE:-0}"
launch_after_setup="${LAUNCH_AFTER_SETUP:-0}"
resolve_edition="${RESOLVE_EDITION:-Studio}"

supported_resolve_version="21.0.3"
supported_resolve_build="7"
supported_image="fedora:39"
recommended_shm_bytes=$((16 * 1024 * 1024 * 1024))
studio_download_id="60c57e20c37d488882dfea5b8d15355a"
free_download_id="a77754710e824036a6d77cd344df1be1"

resolve_version="${supported_resolve_version}"
resolve_build="${supported_resolve_build}"
resolve_product_name=""
resolve_archive_name=""
resolve_zip_name=""
resolve_run_name=""
resolve_download_id=""
resolve_download_dir="${RESOLVE_DOWNLOAD_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/davinci-resolve-docker}"

launcher_path="${HOME}/.local/bin/davinci-resolve-docker"
desktop_path="${HOME}/.local/share/applications/com.blackmagicdesign.resolve-docker.desktop"

packages=(
  alsa-lib
  alsa-plugins-pulseaudio
  clinfo
  libXi
  libXinerama
  libXrandr
  libXtst
  libXxf86vm
  libglvnd-glx
  libglvnd-opengl
  librsvg2
  libxcrypt-compat
  libxkbcommon
  libxkbcommon-x11
  mesa-dri-drivers
  mesa-libGLU
  mesa-vulkan-drivers
  mtdev
  numactl-libs
  ocl-icd
  pulseaudio-libs
  sqlite
  vulkan-loader
  xcb-util
  xcb-util-cursor
  xcb-util-image
  xcb-util-keysyms
  xcb-util-renderutil
  xcb-util-wm
)

log() {
  printf '[resolve-setup] %s\n' "$*" >&2
}

die() {
  printf '[resolve-setup] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_sudo_or_write_access() {
  local path="$1"
  if [ -w "${path}" ]; then
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die "need write access to ${path}, and sudo is not installed"
}

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

group_gid() {
  getent group "$1" | awk -F: '{ print $3 }'
}

resolve_marker_path() {
  printf '%s/.davinci-resolve-docker-target\n' "${resolve_dir}"
}

configure_resolve_edition() {
  case "${resolve_edition,,}" in
    studio|resolve-studio|resolve_studio|resolve\ studio|davinci\ resolve\ studio)
      resolve_edition="Studio"
      resolve_product_name="DaVinci Resolve Studio"
      resolve_archive_name="DaVinci_Resolve_Studio"
      resolve_download_id="${studio_download_id}"
      ;;
    resolve|free|davinci\ resolve)
      resolve_edition="Resolve"
      resolve_product_name="DaVinci Resolve"
      resolve_archive_name="DaVinci_Resolve"
      resolve_download_id="${free_download_id}"
      ;;
    *)
      die "invalid RESOLVE_EDITION value: ${resolve_edition}. Use Studio or Resolve."
      ;;
  esac

  resolve_zip_name="${resolve_archive_name}_${resolve_version}_Linux.zip"
  resolve_run_name="${resolve_archive_name}_${resolve_version}_Linux.run"
}

validate_supported_target() {
  if [ "${image}" != "${supported_image}" ]; then
    log "warning: default compatibility target uses ${supported_image}; RESOLVE_IMAGE=${image} is unvalidated"
  fi
}

validate_shm_size() {
  if ! [[ "${resolve_shm_size}" =~ ^[0-9]+([kKmMgG])?$ ]]; then
    die "invalid RESOLVE_SHM_SIZE value: ${resolve_shm_size}. Use a Docker size such as 16g or 17179869184."
  fi
}

check_host_session() {
  if [ -n "${XDG_SESSION_TYPE:-}" ] && [ "${XDG_SESSION_TYPE}" != "x11" ]; then
    log "warning: XDG_SESSION_TYPE=${XDG_SESSION_TYPE}; this setup is validated on Xorg/X11"
  fi
}

check_host_amd_opencl() {
  log "checking host AMD OpenCL visibility"

  local output
  if ! output="$(clinfo 2>&1)"; then
    printf '%s\n' "${output}" >&2
    die "host clinfo failed. Install and fix AMD ROCm/OpenCL on the host before creating the container."
  fi

  if ! printf '%s\n' "${output}" | awk '
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
  '; then
    printf '%s\n' "${output}" | grep -E 'Number of platforms|Platform Name|Number of devices|Device Name|Board Name|Device Vendor|Device Type|Driver Version' | sed -n '1,80p' >&2 || true
    die "host clinfo does not show an AMD OpenCL GPU. Fix the host ROCm/OpenCL stack first."
  fi

  printf '%s\n' "${output}" | grep -E 'Platform Name|Device Name|Board Name|Device Vendor|Device Type|Driver Version' | sed -n '1,16p' >&2 || true
}

write_resolve_install_marker() {
  local marker
  marker="$(resolve_marker_path)"

  if [ -w "${resolve_dir}" ]; then
    {
      printf 'installed_by=davinci-resolve-docker\n'
      printf 'resolve_product=%s\n' "${resolve_product_name}"
      printf 'resolve_version=%s\n' "${resolve_version}"
      printf 'resolve_build=%s\n' "${resolve_build}"
      printf 'container_image=%s\n' "${image}"
    } > "${marker}"
  else
    {
      printf 'installed_by=davinci-resolve-docker\n'
      printf 'resolve_product=%s\n' "${resolve_product_name}"
      printf 'resolve_version=%s\n' "${resolve_version}"
      printf 'resolve_build=%s\n' "${resolve_build}"
      printf 'container_image=%s\n' "${image}"
    } | run_root tee "${marker}" >/dev/null
    run_root chown "$(id -u):$(id -g)" "${marker}" || true
  fi
}

check_existing_resolve_marker() {
  local marker
  marker="$(resolve_marker_path)"

  if [ ! -f "${marker}" ]; then
    die "existing Resolve install has no ${marker}, so setup cannot verify it is ${resolve_product_name} ${resolve_version} build ${resolve_build}. Set OVERWRITE_RESOLVE=1 to replace it."
  fi

  if grep -qx "resolve_product=${resolve_product_name}" "${marker}" && grep -qx "resolve_version=${resolve_version}" "${marker}" && grep -qx "resolve_build=${resolve_build}" "${marker}"; then
    return 0
  fi

  die "existing Resolve marker does not match ${resolve_product_name} ${resolve_version} build ${resolve_build}: ${marker}. Set OVERWRITE_RESOLVE=1 to replace it with the selected edition."
}

get_blackmagic_download_url() {
  local payload
  payload='{"country":"us","origin":"www.blackmagicdesign.com"}'

  curl -fsSL \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Origin: https://www.blackmagicdesign.com' \
    -H 'Referer: https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion' \
    -H 'User-Agent: Mozilla/5.0' \
    --data-binary "${payload}" \
    "https://www.blackmagicdesign.com/api/register/us/download/${resolve_download_id}"
}

download_resolve_zip() {
  if [ -n "${RESOLVE_ZIP:-}" ]; then
    [ -f "${RESOLVE_ZIP}" ] || die "RESOLVE_ZIP does not exist: ${RESOLVE_ZIP}"
    printf '%s\n' "${RESOLVE_ZIP}"
    return 0
  fi

  local bundled_zip="${repo_dir}/vendor/blackmagic/${resolve_zip_name}"
  if [ -f "${bundled_zip}" ]; then
    if [ -f "${repo_dir}/vendor/blackmagic/SHA256SUMS" ]; then
      need_cmd sha256sum
      log "verifying bundled Resolve archive checksum"
      (
        cd "${repo_dir}/vendor/blackmagic"
        sha256sum -c SHA256SUMS --ignore-missing >&2
      )
    fi
    log "using bundled Resolve archive: ${bundled_zip}"
    printf '%s\n' "${bundled_zip}"
    return 0
  fi

  local downloads_zip="${HOME}/Downloads/${resolve_zip_name}"
  if [ -f "${downloads_zip}" ]; then
    log "using Resolve archive from Downloads: ${downloads_zip}"
    printf "%s\n" "${downloads_zip}"
    return 0
  fi

  mkdir -p "${resolve_download_dir}"
  local zip_path="${resolve_download_dir}/${resolve_zip_name}"

  if [ -s "${zip_path}" ]; then
    log "using cached Resolve archive: ${zip_path}"
    printf '%s\n' "${zip_path}"
    return 0
  fi

  if [ "${resolve_edition}" = "Resolve" ]; then
    die "Blackmagic requires personal registration for the free edition. Download ${resolve_zip_name} from https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion, then rerun with RESOLVE_ZIP=/path/to/${resolve_zip_name}."
  fi

  local url
  log "requesting official ${resolve_product_name} ${resolve_version} Linux download URL"
  url="$(get_blackmagic_download_url)"
  [ -n "${url}" ] || die "Blackmagic download API returned an empty URL"

  log "downloading ${resolve_zip_name} to ${zip_path}"
  curl -fL --continue-at - --output "${zip_path}" "${url}"
  printf '%s\n' "${zip_path}"
}

install_resolve_tree() {
  local source_dir="$1"
  local target_parent
  target_parent="$(dirname "${resolve_dir}")"

  if [ -e "${resolve_dir}" ] && [ "${overwrite_resolve}" != "1" ]; then
    die "${resolve_dir} already exists but ${resolve_dir}/bin/resolve is missing. Set OVERWRITE_RESOLVE=1 to replace it."
  fi

  log "installing ${resolve_product_name} ${resolve_version} to ${resolve_dir}"
  if [ -d "${resolve_dir}" ] && [ -w "${resolve_dir}" ]; then
    find "${resolve_dir}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    cp -a "${source_dir}/." "${resolve_dir}/"
  elif [ -w "${target_parent}" ]; then
    rm -rf "${resolve_dir}"
    mkdir -p "${resolve_dir}"
    cp -a "${source_dir}/." "${resolve_dir}/"
  else
    need_sudo_or_write_access "${target_parent}"
    run_root rm -rf "${resolve_dir}"
    run_root mkdir -p "${resolve_dir}"
    run_root cp -a "${source_dir}/." "${resolve_dir}/"
    run_root chown -R "$(id -u):$(id -g)" "${resolve_dir}"
  fi

  [ -x "${resolve_dir}/bin/resolve" ] || die "Resolve install did not produce ${resolve_dir}/bin/resolve"
  write_resolve_install_marker
}

extract_and_install_resolve() {
  local zip_path="$1"
  local work_dir="${resolve_download_dir}/extract-${resolve_version}"
  local run_file source_dir

  rm -rf "${work_dir}"
  mkdir -p "${work_dir}"

  log "extracting ${zip_path}"
  unzip -q "${zip_path}" -d "${work_dir}"

  run_file="$(find "${work_dir}" -maxdepth 2 -type f -name "${resolve_run_name}" -print -quit)"
  [ -n "${run_file}" ] || die "could not find ${resolve_run_name} inside ${zip_path}"
  chmod +x "${run_file}"

  log "extracting AppImage payload from ${resolve_run_name}"
  (
    cd "${work_dir}"
    "./$(basename "${run_file}")" --appimage-extract >/dev/null
  )

  source_dir="${work_dir}/squashfs-root"
  [ -x "${source_dir}/bin/resolve" ] || die "extracted Resolve payload is missing bin/resolve"
  install_resolve_tree "${source_dir}"
}

ensure_resolve_installed() {
  if [ -x "${resolve_dir}/bin/resolve" ]; then
    if [ "${overwrite_resolve}" = "1" ]; then
      log "OVERWRITE_RESOLVE=1; replacing existing Resolve install at ${resolve_dir}"
    else
      check_existing_resolve_marker
      log "Resolve already installed at ${resolve_dir}"
      return 0
    fi
  fi

  case "${download_resolve}" in
    1|yes|true|auto)
      need_cmd curl
      need_cmd unzip
      extract_and_install_resolve "$(download_resolve_zip)"
      ;;
    0|no|false)
      die "Resolve binary not found at ${resolve_dir}/bin/resolve, and DOWNLOAD_RESOLVE=0"
      ;;
    *)
      die "invalid DOWNLOAD_RESOLVE value: ${download_resolve}"
      ;;
  esac
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

patch_resolve_glib_libs() {
  [ "${patch_resolve_libs}" = "1" ] || return 0

  local libs_dir="${resolve_dir}/libs"
  [ -d "${libs_dir}" ] || die "Resolve libs directory not found: ${libs_dir}"

  shopt -s nullglob
  local files=(
    "${libs_dir}"/libglib-2.0.so*
    "${libs_dir}"/libgio-2.0.so*
    "${libs_dir}"/libgmodule-2.0.so*
    "${libs_dir}"/libgobject-2.0.so*
  )
  shopt -u nullglob

  if [ "${#files[@]}" -eq 0 ]; then
    log "Resolve GLib/GIO libraries already patched or absent"
    return 0
  fi

  local disabled_dir="${libs_dir}/disabled-by-davinci-docker-setup"
  log "moving bundled Resolve GLib/GIO libraries to ${disabled_dir}"

  if [ -w "${libs_dir}" ]; then
    mkdir -p "${disabled_dir}"
    mv -n -- "${files[@]}" "${disabled_dir}/"
  else
    command -v sudo >/dev/null 2>&1 || die "need write access to ${libs_dir}, and sudo is not installed"
    sudo bash -c 'disabled_dir="$1"; shift; mkdir -p "$disabled_dir"; mv -n -- "$@" "$disabled_dir/"' _ "${disabled_dir}" "${files[@]}"
  fi
}

create_container() {
  if docker container inspect "${container}" >/dev/null 2>&1; then
    local current_shm
    current_shm="$(docker inspect -f '{{.HostConfig.ShmSize}}' "${container}" 2>/dev/null || true)"
    log "container already exists: ${container}"
    if [[ "${current_shm}" =~ ^[0-9]+$ ]]; then
      log "container shared memory: ${current_shm} bytes"
      if [ "${current_shm}" -lt "${recommended_shm_bytes}" ]; then
        log "warning: container /dev/shm is below the recommended 16 GiB. Recreate the container to apply RESOLVE_SHM_SIZE=${resolve_shm_size}."
      fi
    else
      log "warning: could not inspect container shared memory size"
    fi
    return 0
  fi

  local render_gid video_gid flags
  render_gid="$(group_gid render)"
  [ -n "${render_gid}" ] || die "host group 'render' does not exist"
  video_gid="$(group_gid video || true)"

  flags="--device /dev/kfd --device /dev/dri --group-add ${render_gid} --shm-size=${resolve_shm_size}"
  if [ -n "${video_gid}" ] && [ "${video_gid}" != "${render_gid}" ]; then
    flags="${flags} --group-add ${video_gid}"
  fi

  log "creating Docker-backed Distrobox '${container}' from ${image} with /dev/shm=${resolve_shm_size}"
  if ! DBX_CONTAINER_MANAGER=docker distrobox create \
    --image "${image}" \
    --name "${container}" \
    --additional-flags "${flags}" \
    --yes; then
    docker container inspect "${container}" >/dev/null 2>&1 || die "Distrobox create failed"
    log "Distrobox create returned non-zero after creating the Docker container; continuing"
  fi
}

initialize_container() {
  log "initializing Distrobox user and mounts"
  if ! DBX_CONTAINER_MANAGER=docker distrobox enter "${container}" -- true; then
    log "Distrobox enter returned non-zero during initialization; continuing if Docker can exec"
  fi

  if [ "$(docker inspect -f '{{.State.Running}}' "${container}")" != "true" ]; then
    docker start "${container}" >/dev/null
  fi
}

install_container_packages() {
  log "installing Fedora runtime packages"
  docker exec -u root "${container}" dnf install -y --setopt=install_weak_deps=False "${packages[@]}"
}

configure_container() {
  local host_opencl="$1"
  local container_opencl="/run/host${host_opencl}"
  local container_resolve="/run/host${resolve_dir}"

  log "configuring /opt/resolve symlink, AMD OpenCL ICD, and ALSA defaults"
  docker exec -u root \
    -e HOST_USER="${container_user}" \
    -e CONTAINER_OPENCL="${container_opencl}" \
    -e CONTAINER_RESOLVE="${container_resolve}" \
    "${container}" bash -lc '
      set -e
      if [ -e /opt/resolve ] && [ ! -L /opt/resolve ]; then
        echo "/opt/resolve exists in the container and is not a symlink" >&2
        exit 1
      fi
      ln -sfn "${CONTAINER_RESOLVE}" /opt/resolve
      mkdir -p /etc/OpenCL/vendors
      printf "%s\n" "${CONTAINER_OPENCL}" > /etc/OpenCL/vendors/amdocl64-host.icd
      rm -f "/var/tmp/.${HOST_USER}.passwd.initialize"
    '

  docker exec -i -u root "${container}" tee /etc/asound.conf >/dev/null < "${repo_dir}/config/asound.conf"
  docker exec -u root "${container}" chmod 0644 /etc/asound.conf
}

install_launcher_files() {
  [ "${install_launcher}" = "1" ] || return 0

  local template="${repo_dir}/templates/com.blackmagicdesign.resolve-docker.desktop.in"

  log "installing launcher to ${launcher_path}"
  install -D -m 0755 "${repo_dir}/bin/launch-resolve.sh" "${launcher_path}"
  mkdir -p "$(dirname "${desktop_path}")"
  sed "s|@LAUNCHER@|${launcher_path}|g" "${template}" > "${desktop_path}"
  chmod 0644 "${desktop_path}"
  update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
}

verify_container() {
  log "verifying Resolve dependencies and AMD OpenCL device"
  docker exec -u "${container_user}" "${container}" bash -lc '
    set -e
    test -r /dev/kfd
    readable_render_node=0
    for node in /dev/dri/renderD*; do
      [ -e "${node}" ] || continue
      if [ -r "${node}" ]; then
        readable_render_node=1
        break
      fi
    done
    [ "${readable_render_node}" -eq 1 ] || {
      echo "no readable /dev/dri/renderD* node found" >&2
      ls -ln /dev/dri 2>/dev/null || true
      exit 1
    }
    if ldd /opt/resolve/bin/resolve 2>&1 | grep -q "not found"; then
      ldd /opt/resolve/bin/resolve 2>&1 | grep "not found"
      exit 1
    fi
    clinfo_output="$(clinfo)"
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
    '"'"'
    printf "%s\n" "${clinfo_output}" | grep -E "Platform Name|Device Name|Board Name|Device Vendor|Device Type|Driver Version" | sed -n "1,32p"
  '
}

configure_resolve_edition
validate_supported_target
validate_shm_size
check_host_session
need_cmd docker
need_cmd distrobox
need_cmd getent
need_cmd ldconfig
need_cmd clinfo

[ -e /dev/kfd ] || die "/dev/kfd is missing. ROCm/HSA is not available on this host."
[ -d /dev/dri ] || die "/dev/dri is missing."

docker info >/dev/null 2>&1 || die "Docker is not usable by this user. Install Docker and add the user to the docker group, then log out/in."

check_host_amd_opencl
ensure_resolve_installed

host_opencl="$(resolve_amd_opencl_lib)"
log "host AMD OpenCL library: ${host_opencl}"

patch_resolve_glib_libs
create_container
initialize_container
install_container_packages
configure_container "${host_opencl}"
install_launcher_files
verify_container

log "done"
cat <<EOF

Resolve Docker setup complete.

Version:       ${resolve_product_name} ${resolve_version} build ${resolve_build}
Resolve path:  ${resolve_dir}
Resolve HOME:  ${resolve_home}
Container:     ${container}
Requested shm: ${resolve_shm_size}
Launcher:      ${launcher_path}
Desktop file:  ${desktop_path}

Launch from terminal:
  davinci-resolve-docker

Launch from app menu:
  DaVinci Resolve (Docker)

Verify later:
  ${repo_dir}/scripts/verify-resolve.sh
EOF

case "${launch_after_setup}" in
  1|yes|true)
    log "launching Resolve"
    exec "${launcher_path}"
    ;;
  0|no|false)
    ;;
  *)
    die "invalid LAUNCH_AFTER_SETUP value: ${launch_after_setup}"
    ;;
esac
