export HIPCXX_CONDA_BACKUP=${HIPCXX:-}
export HIPCXX=$CONDA_PREFIX/bin/x86_64-conda-linux-gnu-clang

# ROCm GPU targets are selected by the ROCM_GPU_TARGETS build variant and
# embedded in this activation script when hip-rocm-clang is packaged.
export CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS_CONDA_BACKUP=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS:-}
export CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS="@rocm_gpu_targets@"
