#!/bin/bash

set -xeuo pipefail

cmake -S . -B build -G Ninja \
	${CMAKE_ARGS} \
	-DFETCHCONTENT_FULLY_DISCONNECTED=ON \
	-DCMAKE_CXX_COMPILER="${BUILD_PREFIX}/bin/hipcc" \
	-DGPU_TARGETS="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}" \
	-DROCWMMA_BUILD_TESTS=OFF \
	-DROCWMMA_BUILD_SAMPLES=OFF

cmake --build build --parallel "${CPU_COUNT}"
cmake --install build
