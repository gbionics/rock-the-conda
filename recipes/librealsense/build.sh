#!/bin/bash

mkdir build && cd build

# Workaround for https://github.com/IntelRealSense/librealsense/issues/8250#issuecomment-768309524
if [[ "${target_platform}" == "osx-arm64" || "${target_platform}" == "linux-ppc64le" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_THREAD_LIBS_INIT=-lpthread -DCMAKE_HAVE_THREADS_LIBRARY=1 -DCMAKE_USE_WIN32_THREADS_INIT=0 -DCMAKE_USE_PTHREADS_INIT=1 -DTHREADS_PREFER_PTHREAD_FLAG=ON"
fi

# Enable exactly one GPU backend. HIP support is provided by the pinned upstream commit.
gpu_backend="${1:?expected one of: cpu, cuda, rocm}"
if [[ "${gpu_backend}" == "rocm" ]]
then
    echo "==> enabling CMake's HIP support"
    CMAKE_ARGS="${CMAKE_ARGS} -DBUILD_WITH_CUDA=OFF -DBUILD_WITH_HIP=ON"
    CMAKE_ARGS="${CMAKE_ARGS} -DROCM_PATH=${BUILD_PREFIX} -DCMAKE_HIP_COMPILER=${HIPCXX}"
    CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_HIP_ARCHITECTURES=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
elif [[ "${gpu_backend}" == "cuda" ]]
then
    echo "==> enabling CMake's CUDA support"
    if [[ "${target_platform}" == "linux-64" ]]
    then
        CUDA_TOOLKIT_ROOT_DIR="${PREFIX}/targets/x86_64-linux"
    elif [[ "${target_platform}" == "linux-aarch64" ]]
    then
        CUDA_TOOLKIT_ROOT_DIR="${PREFIX}/targets/sbsa-linux"
    elif [[ "${target_platform}" == "linux-ppc64le" ]]
    then
        CUDA_TOOLKIT_ROOT_DIR="${PREFIX}/targets/ppc64le-linux"
    else
        echo "Unknown CUDA version ${cuda_compiler_version} for target platform ${target_platform}"
        exit 1
    fi
    CMAKE_ARGS="${CMAKE_ARGS} -DBUILD_WITH_CUDA=ON -DBUILD_WITH_HIP=OFF -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR} -DCUDAToolkit_ROOT=${CUDA_TOOLKIT_ROOT_DIR} -DCUDA_CUDART_LIBRARY=$PREFIX/lib/libcudart.so"
    if [[ "${target_platform}" == "linux-aarch64" && "${arm_variant_type}" == "tegra" ]]
    then
        CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=$CUDAARCHS"
    else
        CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_CUDA_ARCHITECTURES=all"
    fi
    export CUDA_LIB_PATH="$PREFIX/lib"
elif [[ "${gpu_backend}" == "cpu" ]]
then
    echo "==> disabling GPU support"
    CMAKE_ARGS="${CMAKE_ARGS} -DBUILD_WITH_CUDA=OFF -DBUILD_WITH_HIP=OFF"
else
    echo "Unknown GPU backend: ${gpu_backend}" >&2
    exit 1
fi


cmake ${CMAKE_ARGS} -GNinja \
      -DCMAKE_INSTALL_PREFIX=$PREFIX \
      -DCMAKE_PREFIX_PATH=$PREFIX \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=ON \
      -DENABLE_CCACHE=OFF \
      -DBUILD_WITH_OPENMP=OFF \
      -DUSE_EXTERNAL_NLOHMANN_JSON=ON \
      -DFORCE_RSUSB_BACKEND=ON \
      -DBUILD_PYTHON_BINDINGS:bool=true \
      -DPYTHON_INSTALL_DIR="$SP_DIR/pyrealsense2" \
      -DPYTHON_EXECUTABLE="$PREFIX/bin/python" \
      -DPython_EXECUTABLE="$PREFIX/bin/python" \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_UNIT_TESTS=OFF \
      -DCHECK_FOR_UPDATES=OFF \
      -DENABLE_AI_ASSISTANT=OFF \
      -DENABLE_STATS=OFF \
      -DCMAKE_VERBOSE_MAKEFILE=ON \
      -DBUILD_LEGACY_PYBACKEND=OFF \
      $SRC_DIR

cmake --build . --config Release
cmake --install . --config Release
