#!/bin/bash

set -xeuo pipefail

# The staging cache restored the work directory with all compiled C++ objects.
# Re-configure cmake with Python enabled and do an incremental build:
# only the Python binding targets need compilation.

# MIGraphX's cmake/PythonModules.cmake searches all Python versions 3.6-3.14 and
# may pick up system Python installs. Compute the version we are building for and
# disable all others so only the conda-managed Python is found.
CURRENT_PYTHON_VERSION=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
_disable_versions=""
for _v in 3.6 3.7 3.8 3.9 3.10 3.11 3.12 3.13 3.14; do
    if [ "$_v" != "$CURRENT_PYTHON_VERSION" ]; then
        _disable_versions="${_disable_versions:+${_disable_versions};}${_v}"
    fi
done

cmake -GNinja -S migraphx -B migraphx/build \
    ${CMAKE_ARGS} \
    -DPYTHON_DISABLE_VERSIONS="${_disable_versions}" \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_TESTING=OFF \
    -DMIGRAPHX_ENABLE_PYTHON=ON \
    -DPython_EXECUTABLE=$PYTHON \
    -DPython3_EXECUTABLE=$PYTHON \
    -DPYTHON_EXECUTABLE=$PYTHON \
    -DMIGRAPHX_USE_MIOPEN=ON \
    -DMIGRAPHX_USE_ROCBLAS=ON \
    -DMIGRAPHX_USE_HIPBLASLT=ON \
    -DMIGRAPHX_USE_COMPOSABLEKERNEL=ON \
    -DMIGRAPHX_ENABLE_GPU=ON \
    -DMIGRAPHX_ENABLE_CPU=OFF \
    -DMIGRAPHX_ENABLE_FPGA=OFF

cmake --build migraphx/build -j ${CPU_COUNT}

cmake --install migraphx/build
