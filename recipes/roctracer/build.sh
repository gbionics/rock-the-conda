#!/bin/bash

# The backtrace header probe enables a library search that can find a system
# libbacktrace, which is not supplied by the recipe.
cmake -GNinja ${CMAKE_ARGS} \
    -DROCM_PATH=$BUILD_PREFIX \
    -DBUILD_TESTING:BOOL=OFF \
    -DBACKTRACE_H=OFF \
    -DBACKTRACE_LIB= \
    -Bbuild -S.
cmake --build ./build
cmake --install ./build
