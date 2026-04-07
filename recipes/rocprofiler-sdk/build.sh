#!/bin/bash

set -xeuo pipefail

# Initialize git submodules
git submodule update --init --recursive

# Create symlink for hip headers
ln -s $BUILD_PREFIX/include/hip $PREFIX/include/hip

cmake -S . -B build -G Ninja \
    ${CMAKE_ARGS} \
    -DROCPROFILER_BUILD_TESTS=OFF \
    -DROCPROFILER_BUILD_GTESTS=OFF \
    -DROCPROFILER_BUILD_SAMPLES=OFF \
    -DROCPROFILER_BUILD_GHC_FS=OFF \
    -DROCPROFILER_BUILD_FMT=OFF \
    -DROCPROFILER_BUILD_GLOG=OFF \
    -DROCPROFILER_BUILD_PYBIND11=OFF \
    -DROCPROFILER_BUILD_GOTCHA=OFF \
    -DROCPROFILER_BUILD_SQLITE3=OFF \
    -DROCPROFILER_BUILD_BENCHMARK=OFF

cmake --build build -j${CPU_COUNT}
cmake --install build
