# SPDX-License-Identifier: BSD-3-Clause
"""Conda plugin that exposes __rocm and __rocm_arch virtual packages.

__rocm: Reports the installed ROCm userspace version (e.g., 7.0.2).
__rocm_arch: Reports the minimum GPU architecture as a version string
    (e.g., 11.5.1 for gfx1151, 9.4.2 for gfx942). The presence of this
    package indicates that an amdgpu driver capable of running ROCm
    workloads is available.
"""

from __future__ import annotations

from conda import plugins

from rocm_virtual_packages.detect import get_rocm_arch, get_rocm_version


@plugins.hookimpl
def conda_virtual_packages():
    # __rocm_arch: GPU architecture detection
    arch = get_rocm_arch()
    if arch is not None:
        yield plugins.CondaVirtualPackage(
            name="rocm_arch",
            version=arch,
            build=None,
        )

    # __rocm: ROCm userspace version
    rocm_version = get_rocm_version()
    if rocm_version is not None:
        yield plugins.CondaVirtualPackage(
            name="rocm",
            version=rocm_version,
            build=None,
        )
