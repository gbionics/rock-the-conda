# rock-the-conda

Experiments related to conda-forge packaging of ROCm.

This repository is just a container of experiments, it is not in any way a container of useful way of using ROCm in conda-forge.

If you are interested in ROCm support in conda-forge, please monitor official issues in conda-forge organizations like:
* https://github.com/conda-forge/conda-forge.github.io/issues/1923
* https://github.com/conda-forge/staged-recipes/issues/10123

## Conda-forge Feedstock Building

As a playground for official conda-forge PRs, this repo contains a way to build conda-forge feedstocks for ROCm packages:

~~~bash
pixi run build-packages
~~~

## Environments

The workspace defines two pixi environments for targeting different channels:

| Environment | Channel | Description |
|---|---|---|
| `default` (includes `strix-archs` feature) | [`rock-the-conda-strix`](https://prefix.dev/channels/rock-the-conda-strix) | Builds targeting Strix (gfx1150/gfx1151) architectures. |
| `all-archs` | [`rock-the-conda`](https://prefix.dev/channels/rock-the-conda) | Builds targeting all ROCm GPU architectures.  |

By default, `pixi run build-packages` builds and publishes to the `rock-the-conda-strix` channel. To build for all architectures instead (this is not currently tested in CI, so it may fail), use:

~~~bash
pixi run -e all-archs build-packages
~~~


Built packages will be placed in the `output/` subdirectory of the folder. For simplify the debugging, some built packages are available in the following channels:

|    Channel                                            |  Supported architectures    |  Description |  Status     |
|:----------------------------------------------------:|:---------------------------:|:--------------:|:-------------:| 
| https://prefix.dev/channels/rock-the-conda-strix     | `gfx1150;gfx1151`           | Channel that contains packages that target Strix Halo and Strix Point systems. | Active. | 
| https://prefix.dev/channels/rock-the-conda     | `gfx908;gfx90a;gfx942;gfx950;gfx1030;gfx1100;gfx1101;gfx1102;gfx1150;gfx1151;gfx1200;gfx1201`  | Channel that contains packages that target all ROCm-supported architectures. | Active. | 

## Examples

Examples of using `rocm`-powered llama.cpp or pytorch  targeting AMD systems (to verify if GPU is actually used) are available in the  `examples` folder.

### llama.cpp

To run llama.cpp using `all-archs`:

~~~
cd examples/llama.cpp
pixi run benchmark
~~~

to run llama.cpp just for Strix Point/Strix Halo (gfx1150/gfx1151), using the more lightweight `rock-the-conda-strix` packages, run:

~~~
cd examples/llama.cpp
pixi run -e strix benchmark
~~~

### PyTorch

To run pytorch using `all-archs`:

~~~
cd examples/pytorch
pixi run benchmark
~~~

to run pytorch just for Strix Point/Strix Halo (gfx1150/gfx1151), using the more lightweight `rock-the-conda-strix` packages, run:

~~~
cd examples/pytorch
pixi run -e strix benchmark
~~~
