#!/bin/bash

cd amd/device-libs

mkdir build
cd build

export AMD_DEVICE_LIBS_LLVM_MAJOR_VER=22

cmake \
  -DLLVM_DIR=$PREFIX \
  $CMAKE_ARGS \
  -DROCM_DEVICE_LIBS_BITCODE_INSTALL_LOC_NEW:STRING=lib/clang/${AMD_DEVICE_LIBS_LLVM_MAJOR_VER}/lib/amdgcn \
  ..

make VERBOSE=1 -j${CPU_COUNT}
make install

# We create a symlink from $PREFIX/amdgcn to $PREFIX/lib/clang/${AMD_DEVICE_LIBS_LLVM_MAJOR_VER}/lib/amdgcn for compatibility with
# the upstream packaging (see https://rocm.docs.amd.com/en/docs-6.0.0/about/release-notes.html#compiler-location-change)
# and because otherwise hipcc would not find the rocm-device-libs, see https://github.com/ROCm/llvm-project/blob/rocm-7.0.2/amd/hipcc/src/hipBin_amd.h#L323
ln -sf $PREFIX/lib/clang/${AMD_DEVICE_LIBS_LLVM_MAJOR_VER}/lib/amdgcn $PREFIX/amdgcn
