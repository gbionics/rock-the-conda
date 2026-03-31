#!/usr/bin/env bash
set -euo pipefail

# Same test present in https://github.com/ROCm/rocm-systems/blob/rocm-7.2.0/projects/rocminfo/rocminfo.cc#L1217
if [ -d /sys/module/amdgpu ]; then
  echo "AMDGPU kernel module detected, assuming AMD GPU is present"
  export AMDGPU_AVAILABLE=1
else
  echo "AMDGPU kernel module not detected, skipping tests that require AMD GPU"
  export AMDGPU_AVAILABLE=0
fi

if [ "$AMDGPU_AVAILABLE" = "0" ]; then
    if ! rocminfo | grep -q "ROCk module is NOT loaded, possibly no GPU devices"; then
        echo "ERROR: rocminfo did not report that no GPU devices are found"
        exit 1
    fi
    echo "OK: rocminfo detected that no GPU is present"
fi

if [ "$AMDGPU_AVAILABLE" = "1" ]; then
    if ! rocminfo | grep -q "Device Type:.*GPU"; then
        echo "ERROR: rocminfo did not report any GPU agent"
        exit 1
    fi
    echo "OK: rocminfo detected at least one GPU agent"

    if ! rocm_agent_enumerator | grep -q "gfx"; then
        echo "ERROR: rocm_agent_enumerator did not list any gfx ISA"
        exit 1
    fi
    echo "OK: rocm_agent_enumerator listed at least one gfx ISA"
fi
