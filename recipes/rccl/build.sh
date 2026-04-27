#!/bin/bash

set -xeuo pipefail

mkdir build
cd build

# RCCL's CMakeLists.txt uses ROCM_PATH for finding dependencies and
# sets CMAKE_INSTALL_PREFIX="${ROCM_PATH}" as a default (overridden by CMAKE_ARGS).
cmake \
    -GNinja \
    ${CMAKE_ARGS} \
    -DROCM_PATH="${BUILD_PREFIX}" \
    -DGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" \
    -DAMDGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" \
    -DBUILD_TESTS=OFF \
    -DBUILD_BFD=OFF \
    -DRCCL_ROCPROFILER_REGISTER=OFF \
    -DENABLE_MSCCLPP=OFF \
    ..

cmake --build . -j${CPU_COUNT}
cmake --install .
