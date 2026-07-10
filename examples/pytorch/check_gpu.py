"""
check_gpu.py — Verify PyTorch can see the ROCm GPU.

Prints device count, device name(s), and a quick sanity-check tensor round-trip.
"""
import sys
import torch

print(f"PyTorch version : {torch.__version__}")
print(f"CUDA (ROCm) available: {torch.cuda.is_available()}")

if not torch.cuda.is_available():
    print(
        "\nNo GPU visible to PyTorch.  "
        "Make sure the ROCm drivers are installed and that you are running "
        "on a supported AMD GPU."
    )
    sys.exit(1)

device_count = torch.cuda.device_count()
print(f"Device count    : {device_count}")
for i in range(device_count):
    props = torch.cuda.get_device_properties(i)
    print(
        f"  [{i}] {props.name}  "
        f"total_memory={props.total_memory / 1024**3:.1f} GiB"
    )

# Quick round-trip sanity check
x = torch.tensor([1.0, 2.0, 3.0], device="cuda")
result = (x * x).sum().item()
assert abs(result - 14.0) < 1e-5, f"Unexpected result: {result}"
print("\nSanity check passed: tensor round-trip on GPU is correct.")
