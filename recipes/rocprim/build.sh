#!/bin/bash

cmake -GNinja ${CMAKE_ARGS} -DGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} -DAMDGPU_TARGETS=${CONDA_FORGE_DEFAULT_ROCM_GPU_TARGETS} -Bbuild -S.
cmake --build ./build
cmake --install ./build
