#!/bin/bash
set -euxo pipefail

cd jax_rocm_plugin

$RECIPE_DIR/add_py_toolchain.sh

export JAXLIB_RELEASE=1

export LDFLAGS="${LDFLAGS} -lrt -Wl,-z,noexecstack"
export CFLAGS="${CFLAGS} -DNDEBUG -Dabsl_nullable= -Dabsl_nonnull="
export CXXFLAGS="${CXXFLAGS} -DNDEBUG -Dabsl_nullable= -Dabsl_nonnull= -fclang-abi-compat=17"

export ROCM_PATH="${PREFIX}"
export HIP_PATH="${PREFIX}"
export HIP_PLATFORM="amd"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
export RCCL_ROOT="${PREFIX}"
export RCCL_INCLUDE_DIR="${PREFIX}/include"
export RCCL_LIB_DIR="${PREFIX}/lib"

# Symlink compiler('hip') artifacts from BUILD_PREFIX into PREFIX
# so that rocm_configure.bzl finds them under ROCM_PATH.
mkdir -p "${PREFIX}/llvm/bin"
ln -sf "${BUILD_PREFIX}/bin/clang" "${PREFIX}/llvm/bin/clang"
for f in hipcc hipcc.bin hipconfig; do
    [[ ! -f "${PREFIX}/bin/${f}" && -f "${BUILD_PREFIX}/bin/${f}" ]] && \
        ln -sf "${BUILD_PREFIX}/bin/${f}" "${PREFIX}/bin/${f}" || true
done
for d in include/hip share/hip amdgcn; do
    [[ ! -e "${PREFIX}/${d}" && -e "${BUILD_PREFIX}/${d}" ]] && \
        ln -sf "${BUILD_PREFIX}/${d}" "${PREFIX}/${d}" || true
done
[[ ! -f "${PREFIX}/lib/.hipInfo" && -f "${BUILD_PREFIX}/lib/.hipInfo" ]] && \
    ln -sf "${BUILD_PREFIX}/lib/.hipInfo" "${PREFIX}/lib/.hipInfo" || true

cat >> .bazelrc <<EOF
build --verbose_failures
build --local_resources=cpu=${CPU_COUNT}
build --linkopt=-fuse-ld=lld
build --host_linkopt=-fuse-ld=lld
build --linkopt=-L${PREFIX}/lib
build --host_linkopt=-L${PREFIX}/lib
EOF
sed -i '/Qunused-arguments/d' .bazelrc

HOST_PY_VER=$($PYTHON -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
DIST_DIR="$(pwd)/dist"

BUILD_ARGS=(
    --python_version="${HOST_PY_VER}"
    --bazel_path="${BUILD_PREFIX}/bin/bazel"
    --use_clang=true
    --clang_path="${BUILD_PREFIX}/bin/clang"
    --rocm_path="${PREFIX}"
    --rocm_amdgpu_targets="${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS//;/,}"
    --output_path="${DIST_DIR}"
    --bazel_options="--action_env=LD_LIBRARY_PATH=${PREFIX}/lib:${BUILD_PREFIX}/lib"
    --bazel_options="--action_env=RCCL_ROOT=${PREFIX}"
    --bazel_options="--action_env=ROCM_PATH=${PREFIX}"
    --bazel_options="--action_env=HIP_PATH=${PREFIX}"
)

# Build wheels separately: build.py's subprocess inherits the CWD, and
# the first bazel run can invalidate it before the second starts.
python build/build.py build --wheels=jax-rocm-plugin "${BUILD_ARGS[@]}"
python build/build.py build --wheels=jax-rocm-pjrt "${BUILD_ARGS[@]}"

# Skip bazel clean to preserve cache across Python variant builds.
# The output base lives in BUILD_PREFIX and is discarded after the final variant.

pip install --no-deps --prefix="${PREFIX}" dist/*.whl

# Fix INSTALLER/RECORD (https://github.com/conda-forge/jaxlib-feedstock#293)
HOST_SP_DIR=$($PYTHON -c "import sysconfig; print(sysconfig.get_path('purelib'))")
for DIST_INFO in "${HOST_SP_DIR}"/jax_rocm*_{plugin,pjrt}-*.dist-info; do
    [[ -d "${DIST_INFO}" ]] || continue
    echo "conda" > "${DIST_INFO}/INSTALLER"
    rm -f "${DIST_INFO}/RECORD"
done

# Clean up build-only symlinks
rm -rf "${PREFIX}/llvm"
rm -f "${PREFIX}/include/hip" "${PREFIX}/share/hip" "${PREFIX}/amdgcn"
rm -f "${PREFIX}/bin/hipcc" "${PREFIX}/bin/hipcc.bin" "${PREFIX}/bin/hipconfig"
rm -f "${PREFIX}/lib/.hipInfo"
