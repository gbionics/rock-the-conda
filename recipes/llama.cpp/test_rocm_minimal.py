#!/usr/bin/env python
"""
Minimal ROCm GPU detection and llama.cpp inference test for conda-forge recipe testing.

This script:
1. Checks if AMD GPUs are available on the system using rocm_agent_enumerator
2. If available, downloads a minimal GGML model and runs actual HIP inference
3. If no GPU is found, prints a message and exits gracefully
"""

import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


# Tiny stories model from ggml-org/tiny-llamas (~27MB, Q8_0 quantized)
# Pinned to a specific commit for reproducibility
MODEL_URL = f"https://huggingface.co/ggml-org/tiny-llamas/resolve/6e091d820cbe8f22eeb604d136403eca290b8c1e/stories15M-q8_0.gguf"
MODEL_FILENAME = "stories15M-q8_0.gguf"


def check_amd_gpu_available():
    """
    Check if AMD GPUs are available using rocm_agent_enumerator.

    rocm_agent_enumerator lists GPU agent IDs (e.g. gfx1100, gfx90a).
    It is more robust than rocminfo for simple presence detection
    because it only outputs GPU identifiers and does not require
    the full HSA runtime to enumerate device properties.

    Returns:
        tuple: (list of GPU agent names, error_message or None)
    """
    try:
        result = subprocess.run(
            ["rocm_agent_enumerator"],
            capture_output=True,
            text=True,
            timeout=10,
        )

        if result.returncode != 0:
            return [], f"rocm_agent_enumerator failed: {result.stderr}"

        # Each line is a GPU agent name (e.g. "gfx1100") or "gfx000" for the CPU agent.
        # Filter out the CPU placeholder "gfx000" and blank lines.
        agents = [
            line.strip()
            for line in result.stdout.splitlines()
            if line.strip() and line.strip() != "gfx000"
        ]

        if not agents:
            return [], "No AMD GPU agents detected by rocm_agent_enumerator"

        return agents, None

    except FileNotFoundError:
        return [], "rocm_agent_enumerator command not found"
    except subprocess.TimeoutExpired:
        return [], "rocm_agent_enumerator command timed out"
    except Exception as e:
        return [], f"Error checking for AMD GPUs: {e}"


def download_model(model_path):
    """
    Download a minimal GGML model for testing.

    Args:
        model_path: Path where to save the model

    Returns:
        bool: True if download successful, False otherwise
    """
    try:
        print(f"Downloading minimal GGML model (~27MB)...\n  {MODEL_URL}")

        def download_progress(block_num, block_size, total_size):
            downloaded = block_num * block_size
            if downloaded > total_size:
                downloaded = total_size
            percent = min(100, (downloaded * 100) // total_size)
            print(f"\r  Progress: {percent}%", end="", flush=True)

        urllib.request.urlretrieve(MODEL_URL, model_path, download_progress)
        print("\n✓ Model downloaded successfully")
        return True

    except Exception as e:
        print(f"\n⚠ Failed to download model: {e}", file=sys.stderr)
        return False


def run_hip_inference_test(model_path):
    """
    Run actual HIP inference with llama.cpp on the downloaded model using llama-bench.

    Uses JSON output (-o json) to parse structured results and verify
    that the HIP backend is actually being used for inference.

    This ensures that:
    1. The HIP backend is properly linked
    2. GPU code is actually executed (not CPU fallback)
    3. The model can be loaded and inference works

    Args:
        model_path: Path to the GGML model file

    Returns:
        bool: True if inference successful, False otherwise
    """
    try:
        import json

        # Print available devices for debugging
        print("Querying llama-bench --list-devices ...\n")
        try:
            dev_result = subprocess.run(
                ["llama-bench", "--list-devices"],
                capture_output=True,
                text=True,
                timeout=15,
            )
            print(dev_result.stdout)
            if dev_result.stderr:
                print(dev_result.stderr)
        except Exception as e:
            print(f"⚠ Could not list devices: {e}")

        print("Running HIP inference benchmark with llama-bench (JSON output)...\n")

        cmd = [
            "llama-bench",
            "-m", str(model_path),
            "-t", "1",     # Use 1 thread for consistency
            "-ngl", "99",  # Offload 99 layers to GPU (all of them)
            "-n", "20",    # Generate only 20 tokens for speed
            "-o", "json",  # Structured JSON output
        ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,  # 2 minute timeout for inference
        )

        if result.returncode != 0:
            print(f"⚠ llama-bench inference failed:\n{result.stderr}", file=sys.stderr)
            return False

        raw_output = result.stdout
        if not raw_output.strip():
            print("⚠ llama-bench produced no output", file=sys.stderr)
            return False

        # Parse JSON output
        try:
            bench_results = json.loads(raw_output)
        except json.JSONDecodeError as e:
            print(f"⚠ Failed to parse llama-bench JSON output: {e}", file=sys.stderr)
            print("Raw output:")
            print(raw_output)
            return False

        # Dump the full JSON for CI logs
        print("llama-bench JSON output:")
        print("-" * 70)
        print(json.dumps(bench_results, indent=2))
        print("-" * 70)

        if not bench_results:
            print("⚠ llama-bench returned empty results array", file=sys.stderr)
            return False

        # Validate backend information from the first result entry
        entry = bench_results[0]

        backends = entry.get("backends", "")
        gpu_info = entry.get("gpu_info", "")
        n_gpu_layers = entry.get("n_gpu_layers", 0)

        print(f"\n  backends:     {backends}")
        print(f"  gpu_info:     {gpu_info}")
        print(f"  n_gpu_layers: {n_gpu_layers}")

        # Verify HIP backend is active
        ok = True

        if "HIP" not in backends.upper():
            print(f"\n⚠ Expected 'HIP' in backends, got: '{backends}'", file=sys.stderr)
            ok = False
        else:
            print("\n✓ HIP backend is active")

        if n_gpu_layers == 0:
            print("⚠ n_gpu_layers is 0 — model not offloaded to GPU", file=sys.stderr)
            ok = False
        else:
            print(f"✓ {n_gpu_layers} layer(s) offloaded to GPU")

        if gpu_info:
            print(f"✓ GPU detected: {gpu_info}")
        else:
            print("⚠ gpu_info is empty — no GPU reported", file=sys.stderr)
            ok = False

        # Check that timing data is present (avg_ts = tokens/second)
        avg_ts = entry.get("avg_ts", 0)
        if avg_ts > 0:
            print(f"✓ Inference speed: {avg_ts:.2f} tokens/s")
        else:
            print("⚠ avg_ts is 0 — benchmark may not have run", file=sys.stderr)
            ok = False

        if ok:
            print("\n✓ HIP inference benchmark completed successfully")

        return ok

    except FileNotFoundError:
        print("⚠ llama-bench command not found", file=sys.stderr)
        return False
    except subprocess.TimeoutExpired:
        print("⚠ llama-bench inference timed out (120s timeout)", file=sys.stderr)
        return False
    except Exception as e:
        print(f"⚠ Error running inference test: {e}", file=sys.stderr)
        return False


def main():
    """
    Main entry point for the test script.
    """
    print("=" * 70)
    print("llama.cpp ROCm GPU Inference Test")
    print("=" * 70)

    # Check for AMD GPUs
    agents, error_msg = check_amd_gpu_available()

    if not agents:
        print(f"\n⚠ No AMD GPU detected: {error_msg}")
        print("\nTest will skip GPU inference testing.")
        print("This is normal on CPU-only or non-AMD-GPU systems.\n")
        return 0

    print(f"\n✓ Found {len(agents)} AMD GPU(s): {', '.join(agents)}")

    # Use a temporary directory for the model
    with tempfile.TemporaryDirectory() as tmpdir:
        model_path = Path(tmpdir) / MODEL_FILENAME

        # Download the model
        print("\n" + "=" * 70)
        if not download_model(str(model_path)):
            print("\n✗ Failed to download model")
            return 1

        # Run inference test
        print("\n" + "=" * 70)
        if run_hip_inference_test(model_path):
            print("\n" + "=" * 70)
            print("✓ llama.cpp ROCm HIP inference test PASSED")
            return 0
        else:
            print("\n" + "=" * 70)
            print("✗ llama.cpp ROCm HIP inference test FAILED")
            return 1


if __name__ == "__main__":
    sys.exit(main())
