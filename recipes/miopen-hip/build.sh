#!/bin/bash

set -xeuo pipefail

# Composable Kernel only provides XDL instances (for gfx9* / CDNA GPUs).
# When building for RDNA-only targets (no gfx9*), CK's device_conv_operations
# library is empty, causing undefined symbols at runtime. Disable CK in that case.
USE_CK=ON
if ! echo "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" | grep -q 'gfx9'; then
    echo "No gfx9* targets found — disabling Composable Kernel in MIOpen"
    USE_CK=OFF
fi

# MIOpen needs a database directory at install prefix
mkdir -p ${PREFIX}/share/miopen/db

# cpp-half installs to half_float/half.hpp but MIOpen expects half/half.hpp
mkdir -p ${PREFIX}/include/half
ln -sf ${PREFIX}/include/half_float/half.hpp ${PREFIX}/include/half/half.hpp

mkdir -p build
cd build

cmake -GNinja \
    ${CMAKE_ARGS} \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=${PREFIX} \
    -DCMAKE_INSTALL_PREFIX=${PREFIX} \
    -DHALF_INCLUDE_DIR=${PREFIX}/include \
    -DMIOPEN_BACKEND=HIP \
    -DMIOPEN_USE_ROCBLAS=ON \
    -DMIOPEN_USE_COMPOSABLEKERNEL=${USE_CK} \
    -DMIOPEN_USE_MIOPENGEMM=OFF \
    -DMIOPEN_USE_HIPBLASLT=ON \
    -DMIOPEN_USE_MLIR=OFF \
    -DMIOPEN_ENABLE_AI_KERNEL_TUNING=OFF \
    -DMIOPEN_ENABLE_AI_IMMED_MODE_FALLBACK=OFF \
    -DBoost_USE_STATIC_LIBS=OFF \
    -DGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" \
    -DAMDGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" \
    -DMIOPEN_INSTALL_CXX_HEADERS=ON \
    -DBUILD_TESTS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_DEV=OFF \
    -DBUILD_FILE_REORG_BACKWARD_COMPATIBILITY=OFF \
    -DMIOPEN_BUILD_DRIVER=OFF \
    ..

cmake --build . -j${CPU_COUNT}
cmake --install .

# Clean up the symlink created for the build to avoid shipping it
rm -f -- "${PREFIX}/include/half/half.hpp"
rmdir -- "${PREFIX}/include/half" 2>/dev/null || true
