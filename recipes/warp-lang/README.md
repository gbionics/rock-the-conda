# warp-lang (CPU + ROCm/HIP)

AMD GPU build of [NVIDIA Warp](https://github.com/NVIDIA/warp) using
HIP and CK (Composable Kernel) for MFMA-accelerated `tile_matmul`.
A CPU-only variant is also available.

## Source

The source is pulled directly from
[flferretti/warp-hip](https://github.com/flferretti/warp-hip),
branch `feat/hip-backend`.

To update the fork after a new upstream release:

```bash
cd /path/to/warp-hip
git fetch upstream
git rebase upstream/main
git push origin feat/hip-backend --force-with-lease
```

Then update the `version` in `recipe.yaml` to match.
