#!/bin/bash
set -euxo pipefail

cmake ${CMAKE_ARGS} \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DAMDGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TEST=OFF \
    -DBUILD_BENCHMARK=OFF \
    -DBUILD_EXAMPLE=OFF \
    -DBUILD_FILE_REORG_BACKWARD_COMPATIBILITY=OFF \
    -B build

cmake --build build
cmake --install build
