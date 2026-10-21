#!/bin/bash

set -xeuo pipefail

# Use the bundled tracing headers for optional APIs absent from the recipe.
# Otherwise system installations silently change the SDK's compiled API tables.
cmake -S . -B build -G Ninja \
    ${CMAKE_ARGS} \
    -DCMAKE_DISABLE_FIND_PACKAGE_rccl=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_rocDecode=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_rocJPEG=ON \
    -DROCPROFILER_BUILD_TESTS=OFF \
    -DROCPROFILER_BUILD_GTESTS=OFF \
    -DROCPROFILER_BUILD_SAMPLES=OFF \
    -DROCPROFILER_BUILD_GHC_FS=OFF \
    -DROCPROFILER_BUILD_FMT=OFF \
    -DROCPROFILER_BUILD_GLOG=OFF \
    -DROCPROFILER_BUILD_PYBIND11=OFF \
    -DROCPROFILER_BUILD_GOTCHA=OFF \
    -DROCPROFILER_BUILD_ELFIO=OFF \
    -DROCPROFILER_BUILD_OTF2=OFF \
    -DROCPROFILER_BUILD_SQLITE3=OFF \
    -DROCPROFILER_BUILD_BENCHMARK=OFF

cmake --build build -j${CPU_COUNT}
cmake --install build
