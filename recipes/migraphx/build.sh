#!/bin/bash

set -xeuo pipefail

# cpp-half installs to half_float/half.hpp but MIOpen expects half/half.hpp
mkdir -p ${PREFIX}/include/half
ln -sf ${PREFIX}/include/half_float/half.hpp ${PREFIX}/include/half/half.hpp

# Configure with CMake
cmake -GNinja -S . -B build \
    ${CMAKE_ARGS} \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_TESTING=OFF \
    -DMIGRAPHX_ENABLE_PYTHON=ON \
    -DMIGRAPHX_USE_MIOPEN=ON \
    -DMIGRAPHX_USE_ROCBLAS=ON \
    -DMIGRAPHX_USE_HIPBLASLT=ON \
    -DMIGRAPHX_USE_COMPOSABLEKERNEL=OFF \
    -DMIGRAPHX_ENABLE_GPU=ON \
    -DMIGRAPHX_ENABLE_CPU=OFF \
    -DMIGRAPHX_ENABLE_FPGA=OFF

cmake --build build -j ${CPU_COUNT}

cmake --install build
