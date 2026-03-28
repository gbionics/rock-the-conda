#!/bin/bash
set -euo pipefail

mkdir -p build
cd build

# Configure CMake
cmake -GNinja \
    -DBUILD_SHARED_LIBS:BOOL=ON \
    ${CMAKE_ARGS} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DGPU_ARCHS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_DEV=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_CLANG_CPP_CHECKS=OFF \
    ..

# Depending on the specific machine you are running this in, you may need to
# change the number of threads to avoid out of memory issues, it is possible to do that with "--parallel 4",
# where 4  is the number of threads
cmake --build .  --parallel 8
cmake --install .
