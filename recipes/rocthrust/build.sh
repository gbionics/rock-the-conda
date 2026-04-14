#!/bin/bash
set -euxo pipefail

cmake ${CMAKE_ARGS} \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TEST=OFF \
    -DBUILD_BENCHMARKS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_FILE_REORG_BACKWARD_COMPATIBILITY=OFF \
    -B build

cmake --build build
cmake --install build
