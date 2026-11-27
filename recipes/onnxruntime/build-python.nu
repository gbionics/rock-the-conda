# Rebuilds the Python bindings in the staging output's build tree for the
# current Python version. Everything else is up to date and is not rebuilt.

let is_win = ($env.target_platform | str starts-with "win")
let cuda_enabled = (($env.cuda_compiler_version? | default "None") != "None")
let hip_enabled = (($env.hip_compiler_version? | default "None") != "None")
let cross_compiling = ($env.CONDA_BUILD_CROSS_COMPILATION? | default "0") == "1"

# Same environment as in build-cpp.nu. The re-run of CMake ignores LDFLAGS,
# but cl.exe reads CL on every invocation.
if $is_win {
    $env.CL = $"/DPROTOBUF_USE_DLLS ($env.CL? | default '')"
    if $cuda_enabled {
        $env.Path = ($env.Path | prepend $"($env.BUILD_PREFIX)/Library/bin")
    }
}

# The staging output's commands, to explain unexpected rebuilds below.
let commands_before = (ninja -C build-ci/Release -t commands onnxruntime_pybind11_state | lines)

# Make CMake detect the current Python instead of the staging output's. The
# interpreter paths cached by build-cpp.nu are the same for every Python
# version; the entries removed here are derived from the interpreter's version.
let python_defines = if $cross_compiling {
    # Same as in build-cpp.nu, for the current Python.
    let python_include_dir = (python -c "import sysconfig; print(sysconfig.get_path('include'))" | str trim)
    let numpy_include_dir = (python -c "import numpy; print(numpy.get_include())" | str trim)
    [$"-DPython_INCLUDE_DIR:PATH=($python_include_dir)" $"-DPython_NumPy_INCLUDE_DIR=($numpy_include_dir)"]
} else {
    []
}
# build.py passes --compile-no-warning-as-error on the command line, which the
# cache does not record.
(cmake --compile-no-warning-as-error
    -U "_Python*" -U "FIND_PACKAGE_MESSAGE_DETAILS_Python*" -U "pybind11_INCLUDE_DIRS"
    ...$python_defines build-ci/Release)

# `-d explain` makes ninja log why each step is out of date.
let build_jobs = [($env.CPU_COUNT | into int) 8] | math min
let ninja_log = (cmake --build build-ci/Release --target onnxruntime_pybind11_state --config Release --parallel $build_jobs -- -d explain
    | tee { print --raw }
    | collect)

# Any step besides the Python bindings means that this output's build
# environment differs from the staging output's, typically because their
# requirements in recipe.yaml are out of sync.
let unexpected_steps = ($ninja_log
    | lines
    | parse --regex '^\[\d+/\d+\] (?<step>.*)$'
    | get step
    | where {|step| $step !~ 'onnxruntime_pybind11_state|^Re-checking globbed directories|^Re-running CMake'})
if ($unexpected_steps | is-not-empty) {
    let steps = ($unexpected_steps | first 20 | str join "\n")
    # Ninja's explanation "command line changed" doesn't say how it changed.
    let commands_after = (ninja -C build-ci/Release -t commands onnxruntime_pybind11_state | lines)
    let changed_before = ($commands_before | where {|c| $c not-in $commands_after})
    let changed_after = ($commands_after | where {|c| $c not-in $commands_before})
    # Paths in step descriptions use backslashes on Windows.
    let normalize = {|s| $s | str replace --all '\' '/'}
    let command_diff = ($unexpected_steps
        | each {|step|
            # A step's description ends with its output, which its command contains.
            let output = (do $normalize ($step | split row " " | last))
            let before = ($changed_before | where {|c| do $normalize $c | str contains $output})
            let after = ($changed_after | where {|c| do $normalize $c | str contains $output})
            if ($before | is-empty) or ($after | is-empty) {
                null
            } else {
                let words_before = ($before.0 | split row " ")
                let words_after = ($after.0 | split row " ")
                let removed = ($words_before | where {|w| $w not-in $words_after} | str join " ")
                let added = ($words_after | where {|w| $w not-in $words_before} | str join " ")
                $"\nThe command line of `($output)` changed.\nRemoved: ($removed)\nAdded: ($added)"
            }
        }
        | compact
        | first 1
        | str join)
    error make {msg: $"rebuilt ($unexpected_steps | length) steps of the staging output's build tree; check that the requirements of the 'onnxruntime' output match the staging output's. Steps rebuilt, e.g.:\n($steps)($command_diff)"}
}

cd build-ci/Release

if not $cross_compiling and not $cuda_enabled and not $hip_enabled {
    # The Python tests that 'build.py --test' runs without onnx installed, in the
    # same working directory.
    for test in [
        "onnxruntime_test_python.py"
        "onnxruntime_test_python_global_threadpool.py"
        "onnxruntime_test_python_autoep.py"
        "onnxruntime_test_python_sparse_matmul.py"
        "onnxruntime_test_python_mlops.py"
    ] {
        python $test
    }
}

# With --use_cuda, upstream names the wheel onnxruntime-gpu, the name of the separate
# CUDA project on PyPI. See build.py's build_python_wheel.
let wheel_args = if $cuda_enabled { ["--wheel_name_suffix=gpu"] } else { [] }
let plat_args = if $cross_compiling {
    let plat_name = match $env.target_platform {
        "linux-aarch64" => "linux_aarch64"
        _ => { error make {msg: $"unknown wheel platform for `($env.target_platform)`"} }
    }
    ["--plat-name" $plat_name]
} else {
    []
}
rm -rf dist
python $"($env.SRC_DIR)/setup.py" bdist_wheel ...$wheel_args ...$plat_args
python -m pip install --no-deps --no-build-isolation ...(glob "dist/onnxruntime*.whl")

# The wheel bundles libonnxruntime, which the statically linked Python bindings
# don't use; onnxruntime-cpp ships it. onnxruntime-ep-tensorrt ships the
# TensorRT provider.
# 'glob' would parse the backslashes of Windows paths as part of the pattern.
let capi = $"($env.SP_DIR)/onnxruntime/capi"
for f in (ls $capi | get name | where {|f| ($f | path basename) =~ '^libonnxruntime(_providers_tensorrt)?\.'}) {
    rm $f
}

# On conda-forge both variants are the onnxruntime package, so add an onnxruntime
# alias dist-info: packages requiring either PyPI name are satisfied.
if $cuda_enabled {
    let alias_dir = $"($env.SP_DIR)/onnxruntime-($env.PKG_VERSION).dist-info"
    if ($alias_dir | path exists) {
        error make {msg: $"`($alias_dir)` already exists"}
    }
    mkdir $alias_dir
    $"Metadata-Version: 2.1\nName: onnxruntime\nVersion: ($env.PKG_VERSION)\n" | save $"($alias_dir)/METADATA"
    "conda\n" | save $"($alias_dir)/INSTALLER"
}

# Loadable providers must also be next to the Python extension, which uses
# its own directory when loading execution-provider shared libraries.
if $hip_enabled {
    for provider in ["shared" "migraphx"] {
        for lib in (glob $"libonnxruntime_providers_($provider).so*") {
            ^cp -P $lib $capi
        }
    }
}
