#!/bin/bash

set -xeuo pipefail

# Step 1: Build CK JIT static library.
# MIGraphX needs the jit_library component which only exists on CK's migraphx
# branch (https://github.com/ROCm/rocm-libraries#4245).
# Install into a separate prefix to avoid overwriting the regular CK headers.
CK_JIT_PREFIX=${SRC_DIR}/ck-jit/install
cmake -GNinja -S ck-jit -B ck-jit/build \
    ${CMAKE_ARGS} \
    -DCMAKE_INSTALL_PREFIX=${CK_JIT_PREFIX} \
    -DCK_BUILD_JIT_LIB=ON \
    -DBUILD_TESTING=OFF

cmake --build ck-jit/build -j ${CPU_COUNT}
cmake --install ck-jit/build

# Merge the JIT cmake targets, library, and new headers into $PREFIX alongside
# the regular CK package. Use cp -rn (no-clobber) for headers to avoid
# overwriting regular CK headers while adding JIT-specific ones (ck/host/).
cp ${CK_JIT_PREFIX}/lib/cmake/composable_kernel/composable_kernelConfig.cmake \
    ${CK_JIT_PREFIX}/lib/cmake/composable_kernel/composable_kerneljit_libraryTargets*.cmake \
    ${PREFIX}/lib/cmake/composable_kernel/
find ${CK_JIT_PREFIX}/lib -maxdepth 1 -name '*.a' -exec cp {} ${PREFIX}/lib/ \;
cp -rn ${CK_JIT_PREFIX}/include/* ${PREFIX}/include/

# Step 2: Build MIGraphX (C++ only, no Python bindings)
# cpp-half installs to half_float/half.hpp but MIOpen expects half/half.hpp
mkdir -p ${PREFIX}/include/half
ln -sf ../half_float/half.hpp ${PREFIX}/include/half/half.hpp

cmake -GNinja -S migraphx -B migraphx/build \
    ${CMAKE_ARGS} \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_TESTING=OFF \
    -DMIGRAPHX_ENABLE_PYTHON=OFF \
    -DMIGRAPHX_USE_MIOPEN=ON \
    -DMIGRAPHX_USE_ROCBLAS=ON \
    -DMIGRAPHX_USE_HIPBLASLT=ON \
    -DMIGRAPHX_USE_COMPOSABLEKERNEL=ON \
    -DMIGRAPHX_ENABLE_GPU=ON \
    -DMIGRAPHX_ENABLE_CPU=OFF \
    -DMIGRAPHX_ENABLE_FPGA=OFF

cmake --build migraphx/build -j ${CPU_COUNT}

cmake --install migraphx/build
