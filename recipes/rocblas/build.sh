#!/bin/bash

# Expand xnack variants for gfx908 if present in CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS.
# As of 7.0.2, rocBLAS explicitly supports gfx908:xnack-, even if it is not clear why,
# See https://github.com/ROCm/ROCm/issues/2358

GPU_TARGETS_EXPANDED=""
if [[ -n "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS:-}" ]]; then
    IFS=';' read -r -a _rocm_targets <<< "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
    _expanded_targets=()
    for _t in "${_rocm_targets[@]}"; do
        case "${_t}" in
            gfx908)
                _expanded_targets+=("gfx908:xnack+" "gfx908:xnack-")
                ;;
            "")
                ;;
            *)
                _expanded_targets+=("${_t}")
                ;;
        esac
    done
    GPU_TARGETS_EXPANDED=$(IFS=';'; echo "${_expanded_targets[*]}")
fi

echo "Original CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS: ${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
echo "GPU_TARGETS option passed after restricting xnack variants for gfx908: ${GPU_TARGETS_EXPANDED}"

# We clone locally tensile to patch it as a workaround for https://github.com/traversaro/rock-the-conda/issues/3#issuecomment-3317381230
git clone https://github.com/ROCm/Tensile.git tensile_local_copy
cd tensile_local_copy

# Do a git checkout of the commit contained in ../tensile_tag.txt
TENSILE_COMMIT=$(cat ../tensile_tag.txt)
git checkout "${TENSILE_COMMIT}"

# Copied from https://github.com/gentoo/gentoo/pull/42887
sed  's/ op_sel:\[0,0\] op_sel_hi:\[1,1\]//' -i Tensile/Components/MAC_I8X4.py

cd ..

# A lot of part of the build system hardcode amdclang++ as compiler, let's temporary
# add a symlink with this name, see https://github.com/ROCm/rocm-libraries/issues/944
ln -sf -- "$HIPCXX" "$BUILD_PREFIX/bin/amdclang++"
ln -sf -- "$HIPCXX" "$BUILD_PREFIX/bin/amdclang"

# CMAKE_C_COMPILER AND CMAKE_CXX_COMPILER is passed as a Workaround for hack check that requires the compiler to have a specific name:
# https://github.com/ROCm/Tensile/blob/e8a8999e0e7374aaae546a6d7cb703d9e06b0ebf/Tensile/Utilities/Toolchain.py#L147C58-L147C65
# and https://github.com/traversaro/rock-the-conda/issues/3#issuecomment-3315983823
cmake -GNinja ${CMAKE_ARGS} -DGPU_TARGETS=${GPU_TARGETS_EXPANDED} -DCMAKE_C_COMPILER="$BUILD_PREFIX/bin/amdclang" -DCMAKE_CXX_COMPILER="$BUILD_PREFIX/bin/amdclang++" -DTensile_TEST_LOCAL_PATH=$(pwd)/tensile_local_copy -Bbuild -S.
cmake --build ./build
cmake --install ./build

# Remove amdclang++ symlink to avoid to ship it
rm -f -- "$BUILD_PREFIX/bin/amdclang++"
rm -f -- "$BUILD_PREFIX/bin/amdclang"
