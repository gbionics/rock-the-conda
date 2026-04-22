# SPDX-License-Identifier: BSD-3-Clause
"""Detect ROCm version and GPU architectures on the system.

Detection strategies (in order of preference):

For __rocm_arch (GPU architecture):
  1. KFD sysfs topology (/sys/class/kfd/kfd/topology/nodes/*/properties)
  2. rocm_agent_enumerator -name
  3. rocminfo output parsing

  The version string is the raw gfx architecture identifier (e.g., "1151"
  for gfx1151, "942" for gfx942). This preserves the architecture name
  as-is since these are hardware identifiers, not semantic versions.

For __rocm (ROCm userspace version):
  1. /opt/rocm/.info/version (or $ROCM_PATH/.info/version)
  2. rocminfo output parsing

Both support CONDA_OVERRIDE_ROCM_ARCH and CONDA_OVERRIDE_ROCM environment
variable overrides.
"""

from __future__ import annotations

import functools
import logging
import os
import re
import shutil
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)

# Known gfx architectures for validation in rocminfo/agent_enumerator fallbacks.
_KNOWN_GFX: set[str] = {
    "gfx900", "gfx906", "gfx908", "gfx90a",
    "gfx940", "gfx941", "gfx942", "gfx950",
    "gfx1030",
    "gfx1100", "gfx1101", "gfx1102",
    "gfx1150", "gfx1151",
    "gfx1200", "gfx1201",
}

_GFX_REGEX = re.compile(r"\b(gfx[0-9a-f]+)\b")
_ROCM_VERSION_REGEX = re.compile(
    r"ROCm(?:\s+Version)?[:\s]*(\d+)\.(\d+)\.(\d+)", re.IGNORECASE
)


def _parse_gfx_target_version(value: int) -> str:
    """Parse the KFD gfx_target_version integer into a gfx name suffix.

    The kernel encodes this as a decimal value: major * 10000 + minor * 100 + stepping.
    For example, gfx1150 is encoded as 110500, gfx942 as 90402, gfx90a as 90010.
    See: /sys/class/kfd/kfd/topology/nodes/*/properties

    Returns the gfx suffix string, e.g. "1150" for gfx1150, "90a" for gfx90a.
    """
    major = value // 10000
    minor = (value % 10000) // 100
    stepping = value % 100
    # Stepping >= 10 uses hex digits (e.g., stepping=10 → 'a')
    stepping_str = f"{stepping:x}" if stepping >= 10 else str(stepping)
    return f"{major}{minor}{stepping_str}"


def _get_visible_devices() -> set[int] | None:
    """Parse ROCR_VISIBLE_DEVICES or HIP_VISIBLE_DEVICES to get allowed device indices."""
    for env_var in ("ROCR_VISIBLE_DEVICES", "HIP_VISIBLE_DEVICES"):
        val = os.environ.get(env_var, "").strip()
        if val:
            try:
                return {int(x.strip()) for x in val.split(",") if x.strip()}
            except ValueError:
                continue
    return None


def _get_arch_from_kfd() -> list[str]:
    """Read GPU architectures from KFD sysfs topology.

    Each KFD node with a nonzero gfx_target_version is a usable GPU.
    Returns a list of gfx suffix strings (e.g., ["1151"]).
    """
    topology = Path("/sys/class/kfd/kfd/topology/nodes")
    if not topology.is_dir():
        return []

    visible = _get_visible_devices()
    archs: list[str] = []
    gpu_index = 0

    for node_dir in sorted(topology.iterdir()):
        props_file = node_dir / "properties"
        if not props_file.is_file():
            continue
        try:
            props = props_file.read_text(encoding="utf-8")
        except (IOError, OSError):
            continue

        for line in props.splitlines():
            if line.startswith("gfx_target_version"):
                parts = line.split()
                if len(parts) < 2:
                    continue
                try:
                    val = int(parts[1])
                except ValueError:
                    continue
                if val == 0:
                    # Node is CPU, not GPU
                    continue
                if visible is not None and gpu_index not in visible:
                    gpu_index += 1
                    continue
                arch = _parse_gfx_target_version(val)
                archs.append(arch)
                gpu_index += 1

    return archs


def _get_arch_from_agent_enumerator() -> list[str]:
    """Get GPU architectures from rocm_agent_enumerator.

    Returns a list of gfx suffix strings (e.g., ["1151"]).
    """
    exec_path = shutil.which("rocm_agent_enumerator")
    if not exec_path:
        return []
    try:
        proc = subprocess.run(
            [exec_path, "-name"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        archs = []
        for line in proc.stdout.splitlines():
            m = _GFX_REGEX.search(line)
            if m:
                name = m.group(1).lower()
                if name == "gfx000":
                    continue
                if name in _KNOWN_GFX:
                    # Strip the "gfx" prefix to get the arch suffix
                    archs.append(name[3:])
        return archs
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return []


def _get_arch_from_rocminfo() -> list[str]:
    """Parse rocminfo output for gfx architecture strings.

    Returns a list of gfx suffix strings (e.g., ["1151"]).
    """
    exec_path = shutil.which("rocminfo")
    if not exec_path:
        return []
    try:
        output = subprocess.check_output(
            [exec_path],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=7,
        )
        archs = []
        for m in _GFX_REGEX.finditer(output):
            name = m.group(1).lower()
            if name == "gfx000":
                continue
            if name in _KNOWN_GFX:
                archs.append(name[3:])
        return archs
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return []


def _get_rocm_version_from_dir() -> str | None:
    """Read ROCm version from the version file in the ROCm install directory."""
    rocm_path_str = os.environ.get("ROCM_PATH")
    rocm_path = Path(rocm_path_str) if rocm_path_str else Path("/opt/rocm")

    version_file = rocm_path / ".info" / "version"
    if not version_file.is_file():
        return None
    try:
        content = version_file.read_text(encoding="utf-8").strip()
        # Version file contains "M.m.p" or "M.m.p-hash"
        parts = re.split(r"[.-]", content)
        if len(parts) >= 3:
            major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
            return f"{major}.{minor}.{patch}"
        elif len(parts) >= 2:
            major, minor = int(parts[0]), int(parts[1])
            return f"{major}.{minor}.0"
    except (ValueError, IOError, OSError):
        pass
    return None


def _get_rocm_version_from_rocminfo() -> str | None:
    """Parse rocminfo output for the ROCm version string."""
    exec_path = shutil.which("rocminfo")
    if not exec_path:
        return None
    try:
        output = subprocess.check_output(
            [exec_path],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=7,
        )
        m = _ROCM_VERSION_REGEX.search(output)
        if m:
            return f"{m.group(1)}.{m.group(2)}.{m.group(3)}"
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return None


@functools.cache
def get_rocm_arch() -> str | None:
    """Detect the minimum ROCm GPU architecture on the system.

    Returns the gfx architecture suffix (e.g., "1151" for gfx1151,
    "942" for gfx942) or None if no GPU is detected.
    """
    override = os.environ.get("CONDA_OVERRIDE_ROCM_ARCH", "").strip()
    if override:
        # Accept "1151", "gfx1151", "90a", "gfx90a", etc.
        cleaned = override.lower().removeprefix("gfx")
        if re.fullmatch(r"[0-9a-f]+", cleaned):
            return cleaned
        logger.warning(
            "Invalid CONDA_OVERRIDE_ROCM_ARCH='%s'. "
            "Expected a gfx architecture like 1151 or gfx1151. "
            "The __rocm_arch virtual package will not be created.",
            override,
        )
        return None

    # Try detection strategies in order of preference
    for detect_fn in (_get_arch_from_kfd, _get_arch_from_agent_enumerator, _get_arch_from_rocminfo):
        try:
            archs = detect_fn()
        except Exception:
            logger.debug("Detection via %s failed", detect_fn.__name__, exc_info=True)
            continue
        if archs:
            return min(archs)

    return None


@functools.cache
def get_rocm_version() -> str | None:
    """Detect the installed ROCm userspace version.

    Returns a version string like "7.0.2" or None if ROCm is not found.
    """
    override = os.environ.get("CONDA_OVERRIDE_ROCM", "").strip()
    if override:
        if re.fullmatch(r"\d+\.\d+(\.\d+)?", override):
            parts = override.split(".")
            if len(parts) == 2:
                return f"{override}.0"
            return override
        logger.warning(
            "Invalid CONDA_OVERRIDE_ROCM='%s'. "
            "Expected format: M.m.p (e.g., 7.0.2). "
            "The __rocm virtual package will not be created.",
            override,
        )
        return None

    for detect_fn in (_get_rocm_version_from_dir, _get_rocm_version_from_rocminfo):
        try:
            version = detect_fn()
        except Exception:
            logger.debug("Detection via %s failed", detect_fn.__name__, exc_info=True)
            continue
        if version:
            return version

    return None
