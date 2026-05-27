#!/bin/bash
set -euo pipefail

mkdir -p build
cd build

# gfx1150/gfx1151 (RDNA 3.5) use the WMMA pipeline, so DL and DPP kernel
# instances are unnecessary paths.
EXTRA_CMAKE_ARGS=""
ONLY_RDNA35=true
# This is dimensioned on a Strix Halo with ~123 GB  of available RAM + 128 GB of cache
NUMBER_OF_THREADS=8
IFS=';' read -ra TARGETS <<< "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
for target in "${TARGETS[@]}"; do
    if [[ "$target" != "gfx1150" && "$target" != "gfx1151" ]]; then
        ONLY_RDNA35=false
        break
    fi
done

if [[ "$ONLY_RDNA35" == "true" ]]; then
    EXTRA_CMAKE_ARGS="-DDISABLE_DL_KERNELS=ON -DDISABLE_DPP_KERNELS=ON"
    CK_ACTUALLY_USED_GPU_ARCHS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}
else
    EXTRA_CMAKE_ARGS="-DMIOPEN_REQ_LIBS_ONLY:BOOL=ON -DHIPTENSOR_REQ_LIBS_ONLY:BOOL=ON"
    # To keep the compilation time and memory usage down, we prefer to use the generic target
    # used by default in composable-kernel, i.e. in 7.2.3 : gfx10-3-generic;gfx11-generic;gfx12-generic
    # see https://github.com/ROCm/rocm-libraries/blob/rocm-7.2.3/projects/composablekernel/CMakeLists.txt#L203C29-L203C100
    # So if any target among the following (from https://llvm.org/docs/AMDGPUUsage.html#amdgpu-generic-processor-table):
    # gfx10-3-generic: gfx1030, gfx1031, gfx1032, gfx1033, gfx1034,gfx1035, gfx1036 (regex: gfx103[0-6])
    # gfx11-generic: gfx1100, gfx1101, gfx1102, gfx1103, gfx1150, gfx1151, gfx1152, gfx1153 (regex: gfx11[0-5][0-3])
    # gfx12-generic: gfx1200,gfx1201 (regex: gfx120[0-1])
    # is included, it is substituted with the corresponding generic target, and then the duplicates are removed
    
    # Convert targets to generic and remove duplicates
    declare -a processed_targets
    declare -A seen_targets
    
    IFS=';' read -ra TARGETS <<< "${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}"
    for target in "${TARGETS[@]}"; do
        generic_target="$target"
        if [[ "$target" =~ ^gfx103[0-6]$ ]]; then
            generic_target="gfx10-3-generic"
        elif [[ "$target" =~ ^gfx11[0-5][0-3]$ ]]; then
            generic_target="gfx11-generic"
        elif [[ "$target" =~ ^gfx120[0-1]$ ]]; then
            generic_target="gfx12-generic"
        fi
        
        if [[ -z "${seen_targets[$generic_target]:-}" ]]; then
            processed_targets+=("$generic_target")
            seen_targets["$generic_target"]=1
        fi
    done
    
    # Join targets with semicolons
    CK_ACTUALLY_USED_GPU_ARCHS=$(IFS=';'; echo "${processed_targets[*]}")
fi

echo "Configuring for GPU targets: ${CK_ACTUALLY_USED_GPU_ARCHS}"

# Configure CMake
cmake -GNinja \
    -DBUILD_SHARED_LIBS:BOOL=ON \
    ${CMAKE_ARGS} \
    -DGPU_ARCHS=${CK_ACTUALLY_USED_GPU_ARCHS} \
    -DBUILD_DEV=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_CLANG_CPP_CHECKS=OFF \
    ${EXTRA_CMAKE_ARGS} \
    ..

# Depending on the specific machine you are running this in, you may need to
# change the number of threads to avoid out of memory issues, it is possible to do that with "--parallel 4",
# where 4  is the number of threads
cmake --build .  --parallel ${NUMBER_OF_THREADS}
cmake --install .
