#!/bin/bash

set -xeuo pipefail

# rocThrust checks for a clang++ name even with native HIP language support.
# Use HIPCXX's companion C++ driver while keeping the host C/C++ compilers.
cmake -S . -B build -G Ninja \
    ${CMAKE_ARGS} \
    -DUSE_HIPCXX=ON \
    -DCMAKE_HIP_COMPILER="${CXX}" \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DAMDGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_TEST=OFF \
    -DBUILD_BENCHMARK=OFF \
    -DBUILD_EXAMPLE=OFF \
    -DBUILD_FILE_REORG_BACKWARD_COMPATIBILITY=OFF \
    -DBUILD_HIPSTDPAR_TEST=OFF

cmake --build build -j${CPU_COUNT}

cmake --install build
