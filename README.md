# rock-the-conda

Experiments related to conda-forge packaging of ROCm.

This repository is just a container of experiments, it is not in any way a container of useful way of using ROCm in conda-forge.

If you are interested in ROCm support in conda-forge, please monitor official issues in conda-forge organizations like:
* https://github.com/conda-forge/conda-forge.github.io/issues/1923
* https://github.com/conda-forge/staged-recipes/issues/10123

## Features

### Conda-forge Feedstock Building

As a playground for official conda-forge PRs, this repo contains a way to build conda-forge feedstocks for ROCm packages:

~~~bash
pixi run build-packages
~~~

#### Environments

The workspace defines two pixi environments for targeting different channels:

| Environment | Channel | Description |
|---|---|---|
| `default` (includes `strix-archs` feature) | [`rock-the-conda-strix`](https://prefix.dev/channels/rock-the-conda-strix) | Builds targeting Strix (gfx1150/gfx1151) architectures. This is the active development channel. |
| `all-archs` | [`rock-the-conda`](https://prefix.dev/channels/rock-the-conda) | Builds targeting all ROCm GPU architectures. **Currently halted.** |

By default, `pixi run build-packages` builds and publishes to the `rock-the-conda-strix` channel. To build for all architectures instead (once work resumes), use:

~~~bash
pixi run -e all-archs build-packages
~~~

Each environment sets `CONDA_BUILD_ARGS`, `RATTLER_BUILD_ARGS`, and `ROCK_THE_CONDA_TARGET_CHANNEL` automatically.

The recipe to build are configured in `recipes` folder and build in order the following feedstocks:
- `rocm-core`
- `rocm-cmake`
- `rocm-devices-libs`
- `rocm-comgr`
- `rocr-runtime`
- `rocminfo`
- `hip`
- `rocm-smi`
- `rocprim`
- `rocfft`
- `hipfft`
- `roctracer`
- `hipblas-common`
- `hiblaslt`
- `rocblas`
- `rocsolver`
- `hipblas`
- `rocrand`
- `composable-kernel`
- `miopen-hip`

And the following downstream packages that uses `rocm`:
- `llama.cpp`

Built packages will be placed in the `output/` subdirectory of the folder. For simplify the debugging, some built packages are available in https://prefix.dev/channels/rock-the-conda . A simple example of using `rocm`-powered llama.cpp (to verify if GPU is actually used) is available in `examples/llama.cpp`:

~~~
cd examples/llama.cpp
pixi run benchmark
~~~


### TheRock Dependency Analysis

One functionality of this repo is some tooling to extract dependencies information of rocm packages from [`TheRock`](https://github.com/ROCm/TheRock):

~~~bash
pixi run download-therock
pixi run extract-deps
~~~

This generates a `the_rock_deps.png` file showing the dependency graph, see https://github.com/conda-forge/conda-forge.github.io/issues/1923#issuecomment-3074199892 for an example of such image.

### Build TheRock with conda-forge compilers

[`TheRock`](https://github.com/ROCm/TheRock) is a cmake-based superbuild/virtual monorepo infrastructure to build all the ROCm packages, including their dependencies. To compile it with conda-forge dependencies, run:

~~~
pixi run download-therock-all
pixi run build-therock
~~~

