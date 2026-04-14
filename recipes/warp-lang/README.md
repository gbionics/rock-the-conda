# warp-lang (ROCm/HIP)

AMD GPU build of [NVIDIA Warp](https://github.com/NVIDIA/warp) using HIP and CK (Composable Kernel) for MFMA-accelerated `tile_matmul`.

## Patch maintenance

The patch `01-hip-backend.patch` is maintained in
[flferretti/warp-hip](https://github.com/flferretti/warp-hip) on the `feat/hip-backend` branch.

To regenerate the patch after making changes:

```bash
cd /path/to/warp-hip
git format-patch --stdout upstream/main..feat/hip-backend \
  > /path/to/rock-the-conda/recipes/warp-lang/01-hip-backend.patch
```

