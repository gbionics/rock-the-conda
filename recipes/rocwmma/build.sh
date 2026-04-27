#!/bin/bash

set -xeuo pipefail

cmake -S . -B build -G Ninja \
	${CMAKE_ARGS} \
	-DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
	-DAMDGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
	-DROCWMMA_BUILD_TESTS=OFF \
	-DROCWMMA_BUILD_SAMPLES=OFF \
	-DThreads_FOUND=TRUE \
	-DCMAKE_THREAD_LIBS_INIT=-lpthread \
	-DCMAKE_USE_PTHREADS_INIT=1 \
	-DOpenMP_CXX_FLAGS=-fopenmp \
	-DOpenMP_CXX_LIB_NAMES=omp \
	-DOpenMP_omp_LIBRARY=${PREFIX}/lib/libomp.so

cmake --build build -j${CPU_COUNT}
cmake --install build
