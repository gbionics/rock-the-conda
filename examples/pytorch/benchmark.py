"""
benchmark.py — Matrix multiplication benchmark with PyTorch.

Measures TFLOPS for FP32 and FP16 square matrix multiplications at several
sizes on the selected device (GPU via ROCm by default, CPU with --device cpu),
giving a quick indication of whether GPU acceleration is working as expected.

Usage:
  python benchmark.py              # GPU (ROCm)
  python benchmark.py --device cpu # CPU
"""
import argparse
import sys
import time
import torch


def benchmark_matmul(
    size: int, dtype: torch.dtype, device: str = "cuda", warmup: int = 5, iters: int = 20
) -> float:
    """Return achieved TFLOPS for a (size x size) matrix multiplication."""
    a = torch.randn(size, size, dtype=dtype, device=device)
    b = torch.randn(size, size, dtype=dtype, device=device)

    # Warm up
    for _ in range(warmup):
        torch.mm(a, b)
    if device == "cuda":
        torch.cuda.synchronize()

    start = time.perf_counter()
    for _ in range(iters):
        torch.mm(a, b)
    if device == "cuda":
        torch.cuda.synchronize()
    elapsed = time.perf_counter() - start

    # FLOPs for a single matmul: 2 * N^3
    flops = 2.0 * size**3 * iters
    tflops = flops / elapsed / 1e12
    return tflops


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--device",
        default="cuda",
        choices=["cuda", "cpu"],
        help="Device to benchmark (default: cuda)",
    )
    args = parser.parse_args()
    device = args.device

    if device == "cuda" and not torch.cuda.is_available():
        print(
            "No GPU visible to PyTorch.  "
            "Make sure the ROCm drivers are installed and that you are running "
            "on a supported AMD GPU."
        )
        sys.exit(1)

    if device == "cuda":
        device_label = torch.cuda.get_device_name(0)
    else:
        device_label = "CPU"

    print(f"PyTorch version : {torch.__version__}")
    print(f"Device          : {device_label}\n")

    sizes = [1024, 2048, 4096]
    # FP16 on CPU is typically not accelerated; skip it for CPU runs
    dtypes = [
        ("FP32", torch.float32),
    ] + ([("FP16", torch.float16)] if device == "cuda" else [])

    header = f"{'Size':>6}  " + "  ".join(f"{name:>10}" for name, _ in dtypes)
    print(header)
    print("-" * len(header))

    for size in sizes:
        row = f"{size:>6}  "
        for name, dtype in dtypes:
            try:
                tflops = benchmark_matmul(size, dtype, device=device)
                row += f"{tflops:>8.2f} T  "
            except Exception as exc:  # noqa: BLE001
                row += f"{'ERROR':>10}  "
                print(f"  Warning ({name}, size={size}): {exc}")
        print(row)

    print("\nBenchmark complete.")


if __name__ == "__main__":
    main()
