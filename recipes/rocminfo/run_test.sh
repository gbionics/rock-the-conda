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
    rocminfo_output="$(rocminfo)"
    if ! grep -q "ROCk module is NOT loaded, possibly no GPU devices" <<< "$rocminfo_output"; then
        echo "ERROR: rocminfo did not report that no GPU devices are found"
        exit 1
    fi
    echo "OK: rocminfo detected that no GPU is present"
fi

if [ "$AMDGPU_AVAILABLE" = "1" ]; then
    rocminfo_output="$(rocminfo)"
    if ! grep -q "Device Type:.*GPU" <<< "$rocminfo_output"; then
        echo "ERROR: rocminfo did not report any GPU agent"
        exit 1
    fi
    echo "OK: rocminfo detected at least one GPU agent"

    rocm_agent_enumerator_output="$(rocm_agent_enumerator)"
    if ! grep -q "gfx" <<< "$rocm_agent_enumerator_output"; then
        echo "ERROR: rocm_agent_enumerator did not list any gfx ISA"
        exit 1
    fi
    echo "OK: rocm_agent_enumerator listed at least one gfx ISA"
fi
