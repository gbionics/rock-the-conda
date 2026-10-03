#!/bin/bash

set -xeuo pipefail

: "${ROCM_LIBPATCH_VERSION:=${PKG_VERSION//\./0}}"
export ROCM_LIBPATCH_VERSION
export HIP_CLANG_PATH=${PREFIX}/bin

pushd hipcc/amd/hipcc
mkdir build
cd build
cmake ${CMAKE_ARGS} -DCMAKE_REQUIRE_FIND_PACKAGE_ROCM=TRUE -DCMAKE_DISABLE_FIND_PACKAGE_Git=ON ..
make VERBOSE=1 -j${CPU_COUNT}
make install
popd

pushd clr
mkdir build
cd build

export CXXFLAGS="$CXXFLAGS -I$SRC_DIR/clr/opencl/khronos/headers/opencl2.2 -I$SRC_DIR/clr/opencl/khronos/headers/opencl2.2/CL"

install $SRC_DIR/clr/rocclr/platform/prof_protocol.h $PREFIX/include

cmake -LAH \
  ${CMAKE_ARGS} \
  -DCLR_BUILD_HIP=ON \
  -DCLR_BUILD_OCL=ON \
  -DHIPCC_BIN_DIR=$PREFIX/bin \
  -DHIP_COMMON_DIR=$SRC_DIR/hip \
  -DPython_EXECUTABLE=$BUILD_PREFIX/bin/python \
  -DPython3_EXECUTABLE=$BUILD_PREFIX/bin/python \
  -DROCM_PATH=$PREFIX \
  -DAMD_OPENCL_INCLUDE_DIR=$SRC_DIR/clr/opencl/amdocl/ \
  -DHIP_ENABLE_ROCPROFILER_REGISTER=OFF \
  -DHIP_CLANG_PATH=$PREFIX/bin \
  -DCMAKE_DISABLE_FIND_PACKAGE_Git=ON \
  ..

make VERBOSE=1 -j${CPU_COUNT}
make install

FILES_TO_REMOVE="
    lib/libOpenCL.so
    lib/libOpenCL.so.1
    lib/libOpenCL.so.1.0.0
    lib/libcltrace.so
    include/CL/cl.hpp
    include/CL/cl2.hpp
    include/prof_protocol.h
    bin/roc-obj-extract.bat
    bin/roc-obj-ls.bat
    share/doc/hip-asan/LICENSE.md
    share/doc/opencl-asan/LICENSE.md
    bin/clinfo"

DIRS_TO_REMOVE="
    share/doc/hip-asan
    share/doc/opencl-asan"

for FILE in $FILES_TO_REMOVE
do
  rm -f "$PREFIX/$FILE"
done

for DIR in $DIRS_TO_REMOVE
do 
  rmdir "$PREFIX/$DIR" || true
done

popd

# Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d.
# This will allow them to be run on environment activation.
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/activate/hip_${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/hip_${CHANGE}.sh"
done

# register the opencl implementation
mkdir -p $PREFIX/etc/OpenCL/vendors
echo "$PREFIX/lib/libamdocl64.so" >> $PREFIX/etc/OpenCL/vendors/amdocl64.icd
