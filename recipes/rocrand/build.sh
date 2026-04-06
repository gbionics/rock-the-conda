#!/bin/bash

set -xeuo pipefail

mkdir -p build
cd build

cmake -GNinja \
    ${CMAKE_ARGS} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=${PREFIX} \
    -DCMAKE_INSTALL_PREFIX=${PREFIX} \
    -DGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" \
    -DAMDGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" \
    -DBUILD_TEST=OFF \
    -DBUILD_BENCHMARK=OFF \
    -DBUILD_EXAMPLE=OFF \
    -DBUILD_FORTRAN_WRAPPER=OFF \
    ..

cmake --build . -j${CPU_COUNT}
cmake --install .
