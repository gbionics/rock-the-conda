#!/bin/bash

# A lot of internal mechanism in hipblaslt require the ROCM_PATH env variable to be defined,
# otherwise they default to /opt/rocm that is not correct in conda-forge packages
export ROCM_PATH=${PREFIX}

# Expand xnack variants for gfx908 and gfx90a if present in CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS.
# The variable is a ';'-separated list. Bare gfx908/gfx90a entries expand to
# '<arch>:xnack+;<arch>:xnack-'. Entries already with modifiers are preserved.
# This is done as the hipblaslt upstream mention that there is a performance benefit in compiling
# for xnack+ and xnack- separately for these architectures.
AMDGPU_TARGETS_EXPANDED=""
if [[ -n "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS:-}" ]]; then
    IFS=';' read -r -a _rocm_targets <<< "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
    _expanded_targets=()
    for _t in "${_rocm_targets[@]}"; do
        case "${_t}" in
            gfx908)
                _expanded_targets+=("gfx908:xnack+" "gfx908:xnack-")
                ;;
            gfx90a)
                _expanded_targets+=("gfx90a:xnack+" "gfx90a:xnack-")
                ;;
            gfx908:*|gfx90a:*)
                _expanded_targets+=("${_t}")
                ;;
            "")
                ;;
            *)
                _expanded_targets+=("${_t}")
                ;;
        esac
    done
    AMDGPU_TARGETS_EXPANDED=$(IFS=';'; echo "${_expanded_targets[*]}")
fi

echo "Original CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS: ${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
echo "AMDGPU_TARGETS option passed after adding xnack variants for gfx908 and gfx90a: ${AMDGPU_TARGETS_EXPANDED}"

# A lot of part of the build system hardcode amdclang++ as compiler and assume that is in $PREFIX, let's temporary
# add a symlink with this name, see https://github.com/ROCm/rocm-libraries/issues/944
env

ln -sf -- "$HIPCXX" "$PREFIX/bin/amdclang++"
ln -sf -- "$HIPCXX" "$PREFIX/bin/amdclang"

cmake -GNinja ${CMAKE_ARGS} -DGPU_TARGETS="${AMDGPU_TARGETS_EXPANDED}" -DPython_EXECUTABLE=$PYTHON -Bbuild -S.
cmake --build ./build
cmake --install ./build

# Remove amdclang++ symlink to avoid to ship it
rm -f -- "$PREFIX/bin/amdclang++"
rm -f -- "$PREFIX/bin/amdclang"
