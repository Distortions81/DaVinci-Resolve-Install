#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_AFTER_SETUP=1 exec "${script_dir}/setup-davinci-resolve-docker.sh" "$@"
