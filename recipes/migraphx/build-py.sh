#!/bin/bash

set -xeuo pipefail

# The staging cache restored the work directory with all compiled C++ objects.
# Re-configure cmake with Python enabled and do an incremental build:
# only the Python binding targets need compilation.

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
