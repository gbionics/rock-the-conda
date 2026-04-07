#!/bin/bash

set -xeuo pipefail

cmake -S . -B build -G Ninja \
    ${CMAKE_ARGS} \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DAMDGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_TEST=OFF \
    -DBUILD_BENCHMARK=OFF \
    -DBUILD_EXAMPLE=OFF \
    -DBUILD_HIPSTDPAR_TEST=OFF

cmake --build build -j${CPU_COUNT}
cmake --install build
