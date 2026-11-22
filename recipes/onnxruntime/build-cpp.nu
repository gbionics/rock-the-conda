let is_win = ($env.target_platform | str starts-with "win")
let is_linux = ($env.target_platform | str starts-with "linux")
let is_osx = ($env.target_platform | str starts-with "osx")

let cuda_version = ($env.cuda_compiler_version? | default "None")
let cuda_enabled = ($cuda_version != "None")
let hip_enabled = (($env.hip_compiler_version? | default "None") != "None")
let cross_compiling = ($env.CONDA_BUILD_CROSS_COMPILATION? | default "0") == "1"

let build_unit_tests = if $cross_compiling or $cuda_enabled or $hip_enabled { "OFF" } else { "ON" }
let dont_vectorize = if ($env.suffix? | default "") == "-novec" { "ON" } else { "OFF" }
let prefix = if $is_win { $env.LIBRARY_PREFIX } else { $env.PREFIX }

if $is_win {
    # onnxruntime_flatbuffers includes .pb.h without linking protobuf, so without
    # PROTOBUF_USE_DLLS it emits inline protobuf symbols that clash at link time.
    $env.CL = $"/DPROTOBUF_USE_DLLS ($env.CL? | default '')"
}

# protobuf, abseil and re2 come from conda-forge, but onnx stays vendored. Its
# protobuf-lite generated code registers nothing in protobuf's global
# descriptor pool, so it cannot clash with a separately imported onnx package.
mut cmake_defines = [
    "EIGEN_MPL2_ONLY=ON"
    "FLATBUFFERS_BUILD_FLATC=OFF"
    $"onnxruntime_DONT_VECTORIZE=($dont_vectorize)"
    "onnxruntime_BUILD_SHARED_LIB=ON"
    $"onnxruntime_BUILD_UNIT_TESTS=($build_unit_tests)"
    $"CMAKE_PREFIX_PATH=($prefix)"
    "CMAKE_CXX_STANDARD=20"
    "CMAKE_INSTALL_LIBDIR=lib"
    "CMAKE_DISABLE_FIND_PACKAGE_onnx=ON"
    # Vendored dependencies such as psimd require CMake versions that CMake 4 rejects.
    "CMAKE_POLICY_VERSION_MINIMUM=3.5"
]

if $is_linux {
    # https://github.com/conda-forge/ctng-compiler-activation-feedstock/issues/143
    # Explicitly force non-executable stack to fix compatibility with glibc 2.41, due to:
    # onnxruntime/capi/onnxruntime_pybind11_state.so: cannot enable executable stack as shared object requires: Invalid argument
    $env.LDFLAGS = $"($env.LDFLAGS? | default '') -Wl,-z,noexecstack"

    # onnxruntime looks for Threads before re2's CMake config sets this, so the first
    # configure links -lpthread but a re-run uses the cached -pthread check.
    # build-python.nu re-runs CMake, which would then rebuild everything using
    # Threads::Threads.
    $cmake_defines ++= ["THREADS_PREFER_PTHREAD_FLAG=ON"]

    # The first configure links CUDA targets with
    # -Wl,--dependency-file.  Later builds lose these flags
    # (invalidating the cache) somehow if the below is enabled.
    $cmake_defines ++= ["CMAKE_LINK_DEPENDS_USE_LINKER=OFF"]
}

# build.py ignores CMAKE_ARGS, so pass conda-forge's defines (toolchain, find
# root, archiver for LTO, ...) through --cmake_extra_defines.
$cmake_defines ++= ($env.CMAKE_ARGS
    | split row " "
    | where {|a| $a | str starts-with "-D"}
    | each {|a| $a | str substring 2..})

if $cross_compiling {
    # The host python cannot run, so point CMake at the target's headers.
    # https://conda-forge.org/docs/how-to/advanced/cross-compilation/#finding-numpy-in-cross-compiled-python-packages-using-cmake
    let python_include_dir = (python -c "import sysconfig; print(sysconfig.get_path('include'))" | str trim)
    let numpy_include_dir = (python -c "import numpy; print(numpy.get_include())" | str trim)
    $cmake_defines ++= [
        $"Python_EXECUTABLE:PATH=($env.BUILD_PREFIX)/bin/python"
        $"Python_INCLUDE_DIR:PATH=($python_include_dir)"
        $"Python_NumPy_INCLUDE_DIR=($numpy_include_dir)"
    ]
    if $is_linux {
        # glibc has iconv built in, but FindIconv's try_compile can't run when
        # cross-compiling and picks the wrong-arch libiconv from BUILD_PREFIX.
        $cmake_defines ++= ["Iconv_IS_BUILT_IN=TRUE"]
    }
} else {
    # onnx runs gen_proto.py with FindPython3's interpreter, which otherwise
    # caches a versioned path (e.g. bin/python3.13). build-python.nu keeps
    # the cached interpreter, which would then not exist; a changed path would
    # regenerate the ONNX protobuf sources and rebuild everything including
    # them. Pin the versionless path instead.
    let python_exe = (python -c "import sys; print(sys.executable)" | str trim)
    $cmake_defines ++= [$"Python3_EXECUTABLE:FILEPATH=($python_exe)"]
}

# --build_wheel enables the pybind11 target that build-python.nu builds.
mut build_py_args = [
    "--build_dir" "build-ci"
    "--config" "Release"
    "--update"
    "--cmake_generator" "Ninja"
    "--compile_no_warning_as_error"
    "--skip_pip_install"
    "--skip_submodule_sync"
    "--no_telemetry"
    "--build_wheel"
]

if $is_win {
    $build_py_args ++= ["--path_to_protoc_exe" $"($env.BUILD_PREFIX)/Library/bin/protoc.exe"]
} else {
    $build_py_args ++= ["--enable_lto" "--path_to_protoc_exe" $"($env.BUILD_PREFIX)/bin/protoc"]
}

if $is_osx {
    # conda-forge's libcxx provides symbols that the macOS SDK marks unavailable
    # for our deployment target, e.g. std::to_chars used by onnx.
    # https://conda-forge.org/docs/maintainer/knowledge_base/#newer-c-features-with-old-sdk
    $env.CXXFLAGS = $"($env.CXXFLAGS? | default '') -D_LIBCPP_DISABLE_AVAILABILITY"
    # Use CoreML for all osx builds
    $build_py_args ++= ["--osx_arch" "arm64" "--use_coreml"]
}

if $hip_enabled {
    $cmake_defines ++= [
        "onnxruntime_USE_MIGRAPHX=ON"
        $"onnxruntime_MIGRAPHX_HOME=($prefix)"
        "onnxruntime_DISABLE_RTTI=OFF"
    ]
}

if $cuda_enabled {
    let cuda_major = ($cuda_version | split row "." | first)
    let cuda_arch_list = if $cuda_version == "12.9" {
        if $is_win {
            # SM 100+ (Blackwell) triggers a broken asm in CUDA 12.9 clusterlaunchcontrol.h on Windows, fixed in 13.0
            "70-real;75-real;80-real;86-real;89-real;90-real"
        } else {
            "70-real;75-real;80-real;86-real;89-real;90-real;100-real;120"
        }
    } else if $cuda_major == "13" {
        if $is_win {
            # SM 110 (Thor) is Linux-only.
            "75-real;80-real;86-real;89-real;90-real;100-real;120"
        } else {
            "75-real;80-real;86-real;89-real;90-real;100-real;110-real;120"
        }
    } else {
        error make {msg: $"no CUDA architecture list exists for CUDA v($cuda_version); add one to 'build-cpp.nu'"}
    }
    # Silence nvcc's deprecation warning for architectures prior to sm_75.
    $cmake_defines ++= [
        $"CMAKE_CUDA_ARCHITECTURES=($cuda_arch_list)"
        "CMAKE_CUDA_FLAGS=-Wno-deprecated-gpu-targets"
    ]

    # The fpA_intB_gemm/gemv and moe_gemm cutlass kernels need several GB of RAM per
    # architecture in nvcc. More than one nvcc thread per translation unit runs the
    # runners out of memory.
    if $is_win {
        # nvcc must be on PATH for 'cmake --build'. Nushell exposes it as the list
        # 'Path'; assigning to 'PATH' would shadow it and lose cl.exe.
        $env.Path = ($env.Path | prepend $"($env.BUILD_PREFIX)/Library/bin")
        $build_py_args ++= [
            "--use_cuda" "--nvcc_threads=1"
            "--cuda_home" $env.LIBRARY_PREFIX
            "--cudnn_home" $env.LIBRARY_PREFIX
        ]
    } else {
        let cuda_target = match $env.target_platform {
            "linux-64" => "x86_64-linux"
            "linux-aarch64" => "sbsa-linux"
            _ => { error make {msg: $"unknown CUDA target for `($env.target_platform)`"} }
        }
        # nvcc is at $BUILD_PREFIX/bin, not $CUDA_HOME/bin in conda-forge CUDA 12
        $env.CUDA_HOME = $"($env.BUILD_PREFIX)/targets/($cuda_target)"
        $build_py_args ++= [
            "--use_cuda" "--nvcc_threads=1"
            "--cuda_home" $env.CUDA_HOME
            "--cudnn_home" $env.PREFIX
        ]
        $cmake_defines ++= [$"CMAKE_CUDA_COMPILER=($env.BUILD_PREFIX)/bin/nvcc"]
    }

    # recipe.yaml decides which variants get TensorRT. The builtin parser links
    # conda-forge's libnvonnxparser instead of vendoring onnx-tensorrt.
    if ($"($prefix)/include/NvInfer.h" | path exists) {
        $cmake_defines ++= [
            "onnxruntime_USE_TENSORRT=ON"
            "onnxruntime_USE_TENSORRT_BUILTIN_PARSER=ON"
            $"onnxruntime_TENSORRT_HOME=($prefix)"
        ]
    }
}

python tools/ci_build/build.py ...$build_py_args --cmake_extra_defines ...$cmake_defines

# Limit the parallelism to avoid running out of memory.
let build_jobs = [($env.CPU_COUNT | into int) 8] | math min
cmake --build build-ci/Release --config Release --parallel $build_jobs

if $build_unit_tests == "ON" {
    # onnxruntime_cuda_contrib_sources_test checks upstream's CMake source
    # selection, not the build, and needs a build tool for CMake's default generator.
    (ctest --test-dir build-ci/Release --build-config Release --output-on-failure --parallel $build_jobs
        --exclude-regex onnxruntime_cuda_contrib_sources_test)
}

# Install the C++ library for onnxruntime-cpp. 'cmake --install' provides the
# exported CMake targets and the public headers, flattened into
# include/onnxruntime as in upstream's release archives. The exported
# onnxruntime::onnxruntime target points at that directory, so consumers write
# '#include <onnxruntime_cxx_api.h>'.
cmake --install build-ci/Release --prefix install-ci
mkdir $"($prefix)/include" $"($prefix)/lib/cmake"
cp -r install-ci/lib/cmake/onnxruntime $"($prefix)/lib/cmake/"
cp -r install-ci/include/onnxruntime $"($prefix)/include/"

let libs = if $cuda_enabled {
    ["onnxruntime" "onnxruntime_providers_shared" "onnxruntime_providers_cuda"]
} else {
    ["onnxruntime"]
}
if $is_win {
    mkdir $"($prefix)/bin"
    # The library is renamed by 0001-avoid-conflicting-with-onnxruntime.dll-in-system32.patch.
    for lib in ($libs | str replace --regex '^onnxruntime$' "onnxruntime_conda") {
        cp $"build-ci/Release/($lib).lib" $"($prefix)/lib/"
        cp $"build-ci/Release/($lib).dll" $"($prefix)/bin/"
    }
} else {
    let ext = if $is_osx { "*dylib" } else { "so*" }
    for lib in $libs {
        # Keep the versioned symlinks instead of copying the library once per name.
        ^cp -P ...(glob $"build-ci/Release/lib($lib).($ext)") $"($prefix)/lib/"
    }
}

# MIGraphX may be built as a loadable provider. Preserve its shared objects
# alongside libonnxruntime when that layout is selected by upstream CMake.
if $hip_enabled {
    for provider in ["shared" "migraphx"] {
        for lib in (glob $"build-ci/Release/libonnxruntime_providers_($provider).so*") {
            ^cp -P $lib $"($prefix)/lib/"
        }
    }
}
