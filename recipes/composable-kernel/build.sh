#!/bin/bash
set -euo pipefail

mkdir -p build
cd build

# gfx1150/gfx1151 (RDNA 3.5) use the WMMA pipeline, so DL and DPP kernel
# instances are unnecessary paths.
EXTRA_CMAKE_ARGS=""
ONLY_RDNA35=true
IFS=';' read -ra TARGETS <<< "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
for target in "${TARGETS[@]}"; do
    if [[ "$target" != "gfx1150" && "$target" != "gfx1151" ]]; then
        ONLY_RDNA35=false
        break
    fi
done

if [[ "$ONLY_RDNA35" == "true" ]]; then
    EXTRA_CMAKE_ARGS="-DDISABLE_DL_KERNELS=ON -DDISABLE_DPP_KERNELS=ON"
fi

# Configure CMake
cmake -GNinja \
    -DBUILD_SHARED_LIBS:BOOL=ON \
    ${CMAKE_ARGS} \
    -DGPU_ARCHS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DBUILD_DEV=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_CLANG_CPP_CHECKS=OFF \
    ${EXTRA_CMAKE_ARGS} \
    ..

# Depending on the specific machine you are running this in, you may need to
# change the number of threads to avoid out of memory issues, it is possible to do that with "--parallel 4",
# where 4  is the number of threads
cmake --build .  --parallel 6
cmake --install .
