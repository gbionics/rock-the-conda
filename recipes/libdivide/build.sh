#!/bin/bash
set -euo pipefail

cmake -GNinja ${CMAKE_ARGS} \
    -DLIBDIVIDE_BUILD_TESTS=OFF \
    -DLIBDIVIDE_BUILD_FUZZERS=OFF \
    -Bbuild -S.
cmake --build ./build
cmake --install ./build
