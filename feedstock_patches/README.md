# ROCm feedstock overlays

The download tasks check out the exact conda-forge commits in `pixi.toml` and
apply these patches with `recipes/prepare_feedstock.py`. Repeated downloads
recognize an applied patch. A conflicting local edit or a dirty checkout at a
different commit stops preparation and preserves the changes.

The snapshots were refreshed on 2026-11-22:

| Feedstock | Recipe version | Upstream commit | Local build number |
| --- | --- | --- | --- |
| PyTorch | 2.14.1 | `fd9eb8541c7ebe90639685b9bf88c48b4c71b149` | 7, plus upstream GPU/BLAS offsets |
| TorchCodec | 0.17.0 | `be638d73e4149b5a6d699454985a2e56c5dc80fa` | 4 |
| torchvision | 0.29.2 | `a89a7558ad23780c38b2493965566c0a066338e8` | 1 |
| Triton | 3.9.0 | `4f0f1b7d8fd2e4399546ced548dcf671dca1f132` | 2 |
| Triton for PyTorch | 3.7.1 | `8b8237668081e10534081839413146dd096563be` | 4 |
| libmagma | 2.10.0 | `fccc3688530114c35bd3fc7ce0f9e738c2ef54fb` | 3 |
| flash-attn | 2.8.3.post2 (package 2.8.3) | `2f0cc37aa25854ddb16e0f3e1e7ceee4a6412d6b` | 7 |

PyTorch's exact Triton 3.7.1 requirement is retained. Its build task builds that
compatible release alongside current Triton 3.9.0. The two tasks use separate
checkouts and version-specific artifact patterns.

The Triton 3.7.1 overlay updates the LLVM archive checksum after verifying the
download against commit `1f126a6dea50d185c0781743a667390037ae88bd`. Its file
tree matches that commit after accounting for archive metadata substitution
and line-ending conversion in six test fixtures.

PyTorch 2.14.1 uses CMake's native HIP language and C++20. The overlay supplies
the build environment's HIP compiler separately from the host ROCm prefix;
the old FindHIP patch no longer applies and has been removed. Both ROCm host
environments include `libamd-smi` for the distributed topology code's
`amd_smi/amdsmi.h` header and runtime library. The PyTorch task builds AMD SMI
first. The build dependency on sccache is pinned to 0.14.0 to match `pixi.lock`
and the CI action, keeping clients compatible with their shared server. The HIP
compiler launcher sets `SCCACHE_DIRECT=false` to bypass 0.14.0's include-path
parser failure on Flash Attention AOT preprocessor output; compilation caching
remains enabled, and the C/C++ launchers retain direct mode.

TorchCodec's ROCm package uses CPU media codecs with ROCm PyTorch. Its test
runner hides GPU devices and excludes NVIDIA-only tests, and isolates pytest's
configuration so the upstream Pillow/AVIF exclusions match their node IDs.
The C++ extension test loads Conda's `hip::host` target and uses C++20.
Twelve lossy AVI comparison cases are excluded with FFmpeg 9: the CLI and
library outputs pass the PSNR check but miss the upstream pixel tolerance.
Other CPU codec and extension tests remain enabled.

flash-attn retains the existing ROCm fork's disabled build while adopting the
current upstream v1 recipe and its source version. Its former ROCm-specific
2.8.4.1 source tag is replaced by conda-forge's sdist. Enabling and validating
the ROCm backend remains separate work.

The local ONNX Runtime recipe is synchronized with
`conda-forge/onnxruntime-feedstock` at
`2313412bb8d031f6990cb0849499ea623c0521fd` (1.32.0), including its upstream
patches and split Python/C++ build scripts, with MIGraphX support added.
All ONNX Runtime outputs are temporarily skipped while its upstream GitHub
repository is offline and the source archive returns HTTP 404.

For a future refresh, update the pinned commit, port the overlay onto that
snapshot, and regenerate the patch with `git diff --text --full-index` against
that commit. The `--text` option keeps added source patches reviewable even
when a feedstock marks `*.patch` as binary in `.gitattributes`. Check that the
patch applies to a clean snapshot and that a second preparation is a no-op.
