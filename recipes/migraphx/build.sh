#!/bin/bash

set -xeuo pipefail

# Step 1: Build CK JIT static library.
# MIGraphX needs the jit_library component which only exists on CK's migraphx
# branch (https://github.com/ROCm/rocm-libraries#4245).
# We build and install it into $PREFIX so MIGraphX's
# find_package(composable_kernel COMPONENTS jit_library) succeeds.
cmake -GNinja -S ck-jit -B ck-jit/build \
    ${CMAKE_ARGS} \
    -DCK_BUILD_JIT_LIB=ON \
    -DBUILD_TESTING=OFF

cmake --build ck-jit/build -j ${CPU_COUNT}
cmake --install ck-jit/build

# Step 2: Build MIGraphX
# cpp-half installs to half_float/half.hpp but MIOpen expects half/half.hpp
mkdir -p ${PREFIX}/include/half
ln -sf ${PREFIX}/include/half_float/half.hpp ${PREFIX}/include/half/half.hpp

cmake -GNinja -S migraphx -B migraphx/build \
    ${CMAKE_ARGS} \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_TESTING=OFF \
    -DMIGRAPHX_ENABLE_PYTHON=ON \
    -DMIGRAPHX_USE_MIOPEN=ON \
    -DMIGRAPHX_USE_ROCBLAS=ON \
    -DMIGRAPHX_USE_HIPBLASLT=ON \
    -DMIGRAPHX_USE_COMPOSABLEKERNEL=ON \
    -DMIGRAPHX_ENABLE_GPU=ON \
    -DMIGRAPHX_ENABLE_CPU=OFF \
    -DMIGRAPHX_ENABLE_FPGA=OFF

cmake --build migraphx/build -j ${CPU_COUNT}

cmake --install migraphx/build
