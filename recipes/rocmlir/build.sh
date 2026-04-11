#!/bin/bash

set -xeuo pipefail

# Initialize git submodules for bundled LLVM and MLIR-HAL
git submodule update --init --recursive external/llvm-project
git submodule update --init --recursive external/mlir-hal

cmake -S . -B build -GNinja \
    ${CMAKE_ARGS} \
    -DROCM_PATH=${PREFIX} \
    -DBUILD_FAT_LIBROCKCOMPILER=OFF \
    -DROCMLIR_GEN_CPP_FILES=OFF \
    -DMLIR_ENABLE_ROCM_RUNNER=OFF \
    -DMLIR_INCLUDE_INTEGRATION_TESTS=OFF \
    -DROCMLIR_DRIVER_E2E_TEST_ENABLED=OFF \
    -DROCMLIR_DRIVER_PR_E2E_TEST_ENABLED=OFF \
    -DROCK_E2E_TEST_ENABLED=OFF

cmake --build build -j${CPU_COUNT}
cmake --install build

# rocMLIR only installs headers in BUILD_FAT_LIBROCKCOMPILER mode,
# but downstream packages like MIGraphX need the C API headers
cp -r mlir/include/mlir-c "${PREFIX}/include/"

# Also install build-generated headers
if [ -d build/mlir/include/mlir-c ]; then
    cp -rn build/mlir/include/mlir-c "${PREFIX}/include/" 2>/dev/null || true
fi
