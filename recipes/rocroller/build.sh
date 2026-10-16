#!/bin/bash
set -euo pipefail

cmake -GNinja ${CMAKE_ARGS} \
    -DFETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS \
    -DROCROLLER_ENABLE_CLIENT=OFF \
    -DROCROLLER_BUILD_TESTING=OFF \
    -DROCROLLER_ENABLE_FETCH=OFF \
    -DROCROLLER_BUILD_SHARED_LIBS=ON \
    -Bbuild -S.
cmake --build ./build
cmake --install ./build
