#!/bin/bash
set -euxo pipefail

export ROCM_PATH="${PREFIX}"

python build_lib.py \
    --no-cuda \
    --hip \
    --no-standalone \
    --no-use-libmathdx \
    --mode release \
    --verbose

python -m pip install . --no-deps --no-build-isolation -vv
