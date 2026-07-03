#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_AFTER_SETUP=1 exec "${repo_dir}/scripts/setup-resolve.sh" "$@"
