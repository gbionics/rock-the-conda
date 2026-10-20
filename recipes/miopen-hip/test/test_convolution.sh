#!/bin/bash
set -euo pipefail

if [[ ! -e /dev/kfd ]]; then
    echo "Compiled MIOpen HIP/C++ smoke test; execution requires an AMD GPU (/dev/kfd)."
    exit 77
fi

db_dir=$(mktemp -d)
trap 'rm -r -- "$db_dir"' EXIT
MIOPEN_USER_DB_PATH="${db_dir}" MIOPEN_DEBUG_ENABLE_AI_IMMED_MODE_FALLBACK=1 "$1"
