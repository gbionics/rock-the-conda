#!/bin/bash

set -xeuo pipefail

# This output alone varies with ROCM_GPU_TARGETS. Keeping activation-script
# generation out of the staging build lets all other HIP packages reuse the
# same compiled artifacts and remain independent of the target list.
for CHANGE in activate deactivate
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    sed -e "s/@rocm_gpu_targets@/${ROCM_GPU_TARGETS}/g" \
        "${RECIPE_DIR}/activate/hip-rocm-clang_${CHANGE}.sh" \
        > "${PREFIX}/etc/conda/${CHANGE}.d/hip-rocm-clang_${CHANGE}.sh"
done
