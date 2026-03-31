export HIPCXX_CONDA_BACKUP=${HIPCXX:-}
export HIPCXX=$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-clang

# This env variable specified the default ROCM GPU targets used
# by conda-forge packages, downstream packages can override it if needed.
# The variable is not read automatically by CMake, but it needs to be 
# passed to the CMake explicitly in recipes with
# -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} or
# -DAMDGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} (for packages taht still do not support GPU_TARGETS) or
# -DCMAKE_HIP_ARCHITECTURES=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS}
# depending on the project
# See https://github.com/traversaro/rock-the-conda/issues/3#issuecomment-3317381230
# gfx1010 and gfx1012 were removed are not in for a problem in hipblaslt, see https://github.com/traversaro/rock-the-conda/issues/3#issuecomment-3419274585
# This list only contain the architectures, if a project needs to build for xnack- and xnack+ separetely
# for performance reason, the downstream recipe needs to expand the related element, i.e. change gfx908 to gfx908:xnack+;gfx908:xnack-
export CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS_CONDA_BACKUP=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS:-}
if [ -n "${ROCK_THE_CONDA_ROCM_GPU_TARGETS:-}" ]; then
    export CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS="${ROCK_THE_CONDA_ROCM_GPU_TARGETS}"
else
    export CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS="gfx908;gfx90a;gfx942;gfx950;gfx1030;gfx1100;gfx1101;gfx1102;gfx1150;gfx1151;gfx1200;gfx1201"
fi


