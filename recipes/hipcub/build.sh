#!/bin/bash
set -euxo pipefail

# hipCUB's compiler check requires a clang++ name even in native HIP mode.
# HIPCXX points to clang; CXX is the clang++ driver from compiler('clangxx').
cmake ${CMAKE_ARGS} \
    -DUSE_HIPCXX=ON \
    -DCMAKE_HIP_COMPILER="${CXX}" \
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
