#!/bin/bash

cd amd/comgr

mkdir build
cd build

# Fallback include paths: in some clangdev setups CLANG_INCLUDE_DIRS from
# find_package(Clang) does not include the monorepo headers used by comgr.
export CXXFLAGS="${CXXFLAGS} -I${SRC_DIR}/clang/include -I${SRC_DIR}/clang-tools-extra/include"

cmake \
  -DLLVM_DIR=$PREFIX \
  -DCMAKE_INSTALL_PREFIX=$PREFIX \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DBUILD_TESTING:BOOL=OFF \
  -G "Unix Makefiles" \
  ..

make VERBOSE=1 -j${CPU_COUNT}
ctest --output-on-failure
make install

# ln -sf $PREFIX/lib/libamd_comgr.so $PREFIX/lib/libamdcomgr64.so
