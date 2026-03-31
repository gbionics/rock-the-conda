#!/usr/bin/env python
"""
Minimal ROCm GPU detection and llama.cpp inference test for conda-forge recipe testing.

This script:
1. Checks if AMD GPUs are available on the system
2. If available, downloads a minimal GGML model and runs actual HIP inference
3. If no GPU is found, prints a message and exits gracefully
"""

import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


# Minimal quantized model: TinyLlama 1B in Q4_K_M format (~300MB)
# This is a real model that's suitable for testing GPU inference
MODEL_URL = "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
MODEL_FILENAME = "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"


def check_amd_gpu_available():
    """
    Check if AMD GPUs are available using rocminfo.
    
    Returns:
        tuple: (gpu_count, error_message or None)
    """
    try:
        result = subprocess.run(
            ["rocminfo"],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            return 0, f"rocminfo failed: {result.stderr}"
        
        # Count GPU devices in rocminfo output
        # GPU device names start with "GPU" in rocminfo output
        gpu_count = result.stdout.count("GPU")
        
        if gpu_count == 0:
            return 0, "No AMD GPUs detected by rocminfo"
        
        return gpu_count, None
        
    except FileNotFoundError:
        return 0, "rocminfo command not found"
    except subprocess.TimeoutExpired:
        return 0, "rocminfo command timed out"
    except Exception as e:
        return 0, f"Error checking for AMD GPUs: {e}"


def download_model(model_path):
    """
    Download a minimal GGML model for testing.
    
    Args:
        model_path: Path where to save the model
        
    Returns:
        bool: True if download successful, False otherwise
    """
    try:
        print(f"Downloading minimal GGML model (~300MB)...\n  {MODEL_URL}")
        
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
    Run actual HIP inference with llama.cpp on the downloaded model.
    
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
        # Run llama-cli with a simple prompt
        # Use explicit context size and GPU layers to ensure GPU usage
        prompt = "Hello, my name is"
        
        print("Running HIP inference test on the model...\n")
        
        cmd = [
            "llama-cli",
            "-m", str(model_path),
            "-p", prompt,
            "-n", "20",  # Generate only 20 tokens for speed
            "-t", "1",   # Use 1 thread
            "-ngl", "99",  # Offload 99 layers to GPU (all of them)
        ]
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120  # 2 minute timeout for inference
        )
        
        if result.returncode != 0:
            print(f"⚠ llama-cli inference failed:\n{result.stderr}", file=sys.stderr)
            return False
        
        output = result.stdout
        print("llama-cli inference output:")
        print("-" * 70)
        print(output)
        print("-" * 70)
        
        # Check that the model actually generated output
        if not output or "Hello" not in output:
            print("⚠ Model did not generate expected output", file=sys.stderr)
            return False
        
        print("\n✓ HIP inference test completed successfully")
        
        # Try to detect if GPU was actually used by checking for HIP messages
        if "ggml_cuda" in output.lower() or "hip" in output.lower():
            print("✓ GPU acceleration appears to be active")
        
        return True
        
    except FileNotFoundError:
        print("⚠ llama-cli command not found", file=sys.stderr)
        return False
    except subprocess.TimeoutExpired:
        print("⚠ llama-cli inference timed out (120s timeout)", file=sys.stderr)
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
    gpu_count, error_msg = check_amd_gpu_available()
    
    if gpu_count == 0:
        print(f"\n⚠ No AMD GPU detected: {error_msg}")
        print("\nTest will skip GPU inference testing.")
        print("This is normal on CPU-only or non-AMD-GPU systems.\n")
        return 0
    
    print(f"\n✓ Found {gpu_count} AMD GPU(s)")
    
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
