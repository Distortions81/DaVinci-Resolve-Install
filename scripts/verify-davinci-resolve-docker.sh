#!/usr/bin/env bash
set -euo pipefail

container="${RESOLVE_CONTAINER:-davincibox-docker}"
container_user="${RESOLVE_USER:-$(id -un)}"

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
echo "Device permissions:"
docker exec -u "${container_user}" "${container}" bash -lc '
  id
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
