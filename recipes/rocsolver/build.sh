#!/bin/bash

cmake -GNinja \
    -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    -DAMDGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} \
    ${CMAKE_ARGS} -Bbuild -S.
cmake --build ./build
cmake --install ./build
