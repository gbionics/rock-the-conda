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

## Managing conda-forge pins

`rock_the_conda_pinning.yaml` records an exact `conda-forge-pinning` package
version, an ordered set of selected migrations, and local `pinning_overrides`.
Regenerate the build configuration with:

~~~bash
pixi run rock-the-conda-pinning-render
~~~

The renderer downloads that package, applies migrations in `migrator_ts` order
using conda-forge's CFEP-9 variant algebra, then applies the overrides. Its output
is `conda_forge_pinnings/conda_build_config.yaml`, which the existing build tasks
already consume. Edit the specification instead of the generated file.
Shared ROCm build overrides are kept in `pinning_overrides` too. The workspace
fixes `c_stdlib_version` independently of the compiler/CUDA zip group, while
retaining the other zipped tuples. Recipe-specific variant files still apply.
Packages built here (`pytorch`, `libtorch`, `librealsense`, the three libmagma
outputs, and `magma`) have explicit null overrides to remove their global pins.

To update the base package and select completed migrations, then render:

~~~bash
pixi run rock-the-conda-pinning-update --render
~~~

Pixi runs `download-feedstock-all` first, downloading/checking out all configured
feedstocks. The updater collects dependencies from both `recipes/` and
`feedstocks/`, including v1 `recipe.yaml` and v0 `meta.yaml` files, output and test
requirements, and both branches of conditional requirements. It reads recipe
names and literal pin helpers without solving build environments; compiler and
stdlib helpers and unresolved template names are skipped. This conservative
union avoids overlooking dependencies used by another variant.

For each relevant active migration, the updater checks conda-forge's public
migration status and waits until all participating dependency feedstocks are
done. It skips paused migrations and migrations outside Linux/Windows by
default. Repeat `--platform` to select other platforms. Previously selected
migrations remain selected until they disappear from the base package's active
migrations; local overrides and their comments are preserved.

The updater always writes explicit `null` values and preserves their comments.
An override of `null` deletes a pin, including one added by a migration. Override
or delete every member of a `zip_keys` group together to preserve alignment.
An explicit `zip_keys` override can decouple an independently fixed variant
from a group; validation checks the groups that will be emitted:

~~~yaml
pinning_overrides:
  docker_image: null
~~~

Both tools accept `-d PATH` and `--config PATH`; the renderer also accepts
`--output PATH`. Paths are relative to `-d`. When updating another checkout,
download its feedstocks with `pixi run --manifest-path PATH/pixi.toml
download-feedstock-all` first. The commands can also be installed with
`python -m pip install -e .`; when using the installed updater directly, run
`pixi run download-feedstock-all` before it.

The pinning implementation and regression tests are adapted from
[Vinca PR #138](https://github.com/RoboStack/vinca/pull/138),
[PR #157](https://github.com/RoboStack/vinca/pull/157), and Vinca main at
`2cf366bed03d219cb379654efb0e7a858a0251f7`, including its selector and zip-key fixes.
Upstream license notices are retained in `rock_the_conda/LICENSE`.

Run the regression suite with `pixi run test-pinning`.


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
