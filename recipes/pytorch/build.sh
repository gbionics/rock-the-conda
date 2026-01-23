#!/bin/bash

set -ex

echo "#########################################################################"
echo "Building ${PKG_NAME} (py: ${PY_VER}) for ROCm"
echo "#########################################################################"

# This is used to detect if it's in the process of building pytorch
export IN_PYTORCH_BUILD=1

# https://github.com/conda-forge/pytorch-cpu-feedstock/issues/243
# https://github.com/pytorch/pytorch/blob/v2.3.1/setup.py#L341
export PACKAGE_TYPE=conda

# remove pyproject.toml to avoid installing deps from pip
rm -rf pyproject.toml

# uncomment to debug cmake build
# export CMAKE_VERBOSE_MAKEFILE=1

export USE_NUMA=0
export USE_ITT=0

#################### ADJUST COMPILER AND LINKER FLAGS #####################
# Pytorch's build system doesn't like us setting the c++ standard through CMAKE_CXX_FLAGS
# and will issue a warning. We need to use at least C++17 to match the abseil ABI, see
# https://github.com/conda-forge/abseil-cpp-feedstock/issues/45
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-std=c++[0-9][0-9]//g')"
# The below three lines expose symbols that would otherwise be hidden or
# optimised away.
export CFLAGS="$(echo $CFLAGS | sed 's/-fvisibility-inlines-hidden//g')"
export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-fvisibility-inlines-hidden//g')"
# Ignore warnings; blows up the logs for no benefit
export CXXFLAGS="$CXXFLAGS -w"

export LDFLAGS="$(echo $LDFLAGS | sed 's/-Wl,--as-needed//g')"

if [[ "$c_compiler" == "clang" ]]; then
    export CXXFLAGS="$CXXFLAGS -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-error=unused-command-line-argument -Wno-error=vla-cxx-extension"
    export CFLAGS="$CFLAGS -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-error=unused-command-line-argument -Wno-error=vla-cxx-extension"
else
    export CXXFLAGS="$CXXFLAGS -Wno-deprecated-declarations -Wno-error=maybe-uninitialized"
    export CFLAGS="$CFLAGS -Wno-deprecated-declarations -Wno-error=maybe-uninitialized"
fi

# This is not correctly found for linux-aarch64 since pytorch 2.0.0 for some reason
export _GLIBCXX_USE_CXX11_ABI=1

# Explicitly force non-executable stack to fix compatibility with glibc 2.41
LDFLAGS="${LDFLAGS} -Wl,-z,noexecstack"

# Dynamic libraries need to be lazily loaded so that torch
# can be imported on systems without a GPU
LDFLAGS="${LDFLAGS//-Wl,-z,now/-Wl,-z,lazy}"

################ CONFIGURE CMAKE FOR CONDA ENVIRONMENT ###################
export CMAKE_GENERATOR=Ninja
export CMAKE_LIBRARY_PATH=$PREFIX/lib:$PREFIX/include:$CMAKE_LIBRARY_PATH
export CMAKE_PREFIX_PATH=$PREFIX
export CMAKE_BUILD_TYPE=Release

for ARG in $CMAKE_ARGS; do
  if [[ "$ARG" == "-DCMAKE_"* ]]; then
    cmake_arg=$(echo $ARG | cut -d= -f1)
    cmake_arg=$(echo $cmake_arg| cut -dD -f2-)
    cmake_val=$(echo $ARG | cut -d= -f2-)
    printf -v $cmake_arg "$cmake_val"
    export ${cmake_arg}
  fi
done
CMAKE_FIND_ROOT_PATH+=";$SRC_DIR"
unset CMAKE_INSTALL_PREFIX
export PYTORCH_BUILD_VERSION=$PKG_VERSION
# Always pass 0 to avoid appending ".post" to version string.
export PYTORCH_BUILD_NUMBER=0

export INSTALL_TEST=0
export BUILD_TEST=0

#################### SYSTEM LIBRARIES ####################################
export USE_SYSTEM_SLEEF=1
# use our protobuf
export BUILD_CUSTOM_PROTOBUF=OFF
rm -rf $PREFIX/bin/protoc
export USE_SYSTEM_PYBIND11=1
export USE_SYSTEM_EIGEN_INSTALL=1
export USE_SYSTEM_FMT=1
export Python_ROOT_DIR=$PREFIX

# force using cblas_dot when cross-compiling
# (this matches the behavior to our patches)
export PYTORCH_BLAS_USE_CBLAS_DOT=ON

# workaround to stop setup.py from trying to check whether we checked out
# all submodules (we don't use all of them)
rm -f .gitmodules

# prevent six from being downloaded
> third_party/NNPACK/cmake/DownloadSix.cmake

if [[ "${target_platform}" != "${build_platform}" ]]; then
    sed -i.bak \
        "s,IMPORTED_LOCATION_RELEASE .*/bin/protoc,IMPORTED_LOCATION_RELEASE \"${BUILD_PREFIX}/bin/protoc," \
        ${PREFIX}/lib/cmake/protobuf/protobuf-targets-release.cmake
fi

if [[ "$CONDA_BUILD_CROSS_COMPILATION" == 1 ]]; then
    export COMPILER_WORKS_EXITCODE=0
    export COMPILER_WORKS_EXITCODE__TRYRUN_OUTPUT=""
fi

#################### PARALLELISM #########################################
if [[ "${CI}" == "github_actions" ]]; then
    export MAX_JOBS=4
elif [[ "${CI}" == "azure" ]]; then
    export MAX_JOBS=${CPU_COUNT}
else
    export MAX_JOBS=$((CPU_COUNT > 1 ? CPU_COUNT - 1 : 1))
fi

#################### BLAS ################################################
# OpenBLAS (generic)
export BLAS=OpenBLAS
export OpenBLAS_HOME=${PREFIX}

#################### ROCm CONFIGURATION ##################################
export USE_CUDA=0
export USE_CUDNN=0
export USE_XPU=0
export USE_ROCM=1
export USE_MKLDNN=1
export HIP_PLATFORM=amd
export ROCM_PATH=${PREFIX}
export ROCM_HOME=${PREFIX}
export PYTORCH_ROCM_ARCH="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"

# Enable distributed computing
export USE_DISTRIBUTED=1
export USE_GLOO=1
export USE_MPI=1
export USE_TENSORPIPE=1
# RCCL is the ROCm equivalent of NCCL; PyTorch detects it automatically
# when USE_ROCM=1. The rccl package is provided via host dependencies.
export USE_RCCL=1

#################### BUILD PACKAGE #######################################

if [[ "$PKG_NAME" == "pytorch" ]]; then
  # Trick Cmake into thinking python hasn't changed
  sed "s/3\.12/$PY_VER/g" build/CMakeCache.txt.orig > build/CMakeCache.txt
  sed -i.bak "s/3;12/${PY_VER%.*};${PY_VER#*.}/g" build/CMakeCache.txt
  sed -i.bak "s/cpython-312/cpython-${PY_VER%.*}${PY_VER#*.}/g" build/CMakeCache.txt
fi

echo '${CXX}'=${CXX}
echo '${PREFIX}'=${PREFIX}

case ${PKG_NAME} in
  libtorch)
    # Call setup.py directly to avoid spending time on unnecessarily
    # packing and unpacking the wheel.
    $PREFIX/bin/python setup.py -q build

    mv build/lib.*/torch/bin/* ${PREFIX}/bin/
    mv build/lib.*/torch/lib/* ${PREFIX}/lib/
    # need to merge these now because we're using system pybind11, meaning the destination directory is not empty
    rsync -a build/lib.*/torch/share/* ${PREFIX}/share/
    mv build/lib.*/torch/include/{ATen,caffe2,tensorpipe,torch,c10} ${PREFIX}/include/ 2>/dev/null || true
    rm -f ${PREFIX}/lib/libtorch_python.*

    # Keep the original backed up to sed later
    cp build/CMakeCache.txt build/CMakeCache.txt.orig

    # Install ROCm arch activation/deactivation scripts
    for CHANGE in "activate" "deactivate"
    do
        mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
        sed -e "s/@cf_torch_rocm_arch_list@/${PYTORCH_ROCM_ARCH}/g" \
        "${RECIPE_DIR}/${CHANGE}.sh" > "${PREFIX}/etc/conda/${CHANGE}.d/libtorch_${CHANGE}.sh"
    done
    ;;
  pytorch)
    $PREFIX/bin/python -m pip install . --no-deps --no-build-isolation -v --no-clean --config-settings=--global-option=-q \
        | sed "s,${CXX},\$\{CXX\},g" \
        | sed "s,${PREFIX},\$\{PREFIX\},g"
    # Keep this in ${PREFIX}/lib so that the library can be found by
    # TorchConfig.cmake.
    # NB: we are using cp rather than mv, so that the loop below symlinks it back.
    cp ${SP_DIR}/torch/lib/libtorch_python${SHLIB_EXT} ${PREFIX}/lib

    pushd $SP_DIR/torch
    # Make symlinks for libraries and headers from libtorch into $SP_DIR/torch
    # Also remove the vendorered libraries
    # https://github.com/conda-forge/pytorch-cpu-feedstock/issues/243
    for f in bin/* lib/* share/* include/*; do
      if [[ -e "$PREFIX/$f" ]]; then
        rm -rf $f
        # do not symlink include files back
        if [[ ${f} != include/* ]]; then
          ln -sf $PREFIX/$f $PWD/$f
        fi
      fi
    done
    popd
    ;;
  *)
    echo "Unknown package name, edit build.sh"
    exit 1
esac

# Clean up build artifacts to reduce package size
find ${SP_DIR}/torch -name "*.pyc" -delete 2>/dev/null || true
find ${SP_DIR}/torch -name "__pycache__" -type d -delete 2>/dev/null || true
