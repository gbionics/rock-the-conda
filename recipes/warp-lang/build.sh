#!/bin/bash
set -euxo pipefail

BUILD_ARGS="--no-cuda --no-standalone --no-use-libmathdx --mode release --verbose"

if [ "${hip_compiler_version:-None}" != "None" ]; then
    export ROCM_PATH="${BUILD_PREFIX}"
    export HIP_LIB_PATH="${PREFIX}/lib"
    BUILD_ARGS="${BUILD_ARGS} --hip --ck"
fi

$PYTHON build_lib.py ${BUILD_ARGS}
$PYTHON -m pip install . --no-deps --no-build-isolation -vv
