#!/bin/bash

set -xeuo pipefail

export ROCM_LIBPATCH_VERSION=${PKG_VERSION//\./0}
export HIP_CLANG_PATH=${PREFIX}/bin

pushd hipcc/amd/hipcc
mkdir build
cd build
cmake ${CMAKE_ARGS} ..
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
  -DPython3_EXECUTABLE=$BUILD_PREFIX/bin/python \
  -DROCM_PATH=$PREFIX \
  -DAMD_OPENCL_INCLUDE_DIR=$SRC_DIR/clr/opencl/amdocl/ \
  -DHIP_ENABLE_ROCPROFILER_REGISTER=OFF \
  -DHIP_CLANG_PATH=$PREFIX/bin \
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
    share/doc/opencl-asan/LICENSE.txt
    bin/clinfo"

DIRS_TO_REMOVE="
    share/doc/opencl-asan"

for FILE in $FILES_TO_REMOVE
do
  rm "$PREFIX/$FILE"
done

for DIR in $DIRS_TO_REMOVE
do 
  rmdir "$PREFIX/$DIR"
done

popd

# Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d.
# This will allow them to be run on environment activation.
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/activate/hip_${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/hip_${CHANGE}.sh"
    cp "${RECIPE_DIR}/activate/hip-clang_${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/hip-clang_${CHANGE}.sh"
done

# register the opencl implementation
mkdir -p $PREFIX/etc/OpenCL/vendors
echo "$PREFIX/lib/libamdocl64.so" >> $PREFIX/etc/OpenCL/vendors/amdocl64.icd
