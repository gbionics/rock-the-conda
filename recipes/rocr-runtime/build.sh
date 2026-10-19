#!/bin/bash

set -xeo pipefail

mkdir build
cd build

# ROCr automatically links rocprofiler-register when CMake finds it, including
# system ROCm installations. It is not a recipe dependency, so disable discovery
# to avoid shipping an HSA runtime that needs an unprovided shared library.
cmake ${CMAKE_ARGS} \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_rocprofiler-register=ON \
  ..

make VERBOSE=1 -j${CPU_COUNT}
make install
