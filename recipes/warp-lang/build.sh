#!/bin/bash
set -euxo pipefail

export WP_CXX11_ABI=1

BUILD_ARGS="--no-cuda --no-use-libmathdx --mode release --verbose --llvm-path ${PREFIX}"

if [ "${hip_compiler_version:-None}" != "None" ]; then
    export ROCM_PATH="${BUILD_PREFIX}"
    export HIP_LIB_PATH="${PREFIX}/lib"
    export HIP_INCLUDE_PATH="${PREFIX}/include"
    export AMDGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
    BUILD_ARGS="${BUILD_ARGS} --hip --ck"
fi

$PYTHON build_lib.py ${BUILD_ARGS}
$PYTHON -m pip install . --no-deps --no-build-isolation -vv
