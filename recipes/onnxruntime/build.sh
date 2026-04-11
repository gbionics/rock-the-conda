#!/bin/bash

set -xeuo pipefail

# cpp-half installs to half_float/half.hpp but onnxruntime expects half/half.hpp
mkdir -p ${PREFIX}/include/half
ln -sf ${PREFIX}/include/half_float/half.hpp ${PREFIX}/include/half/half.hpp

# ORT patches onnx; keep building it from source via FetchContent.
sed -i '/FIND_PACKAGE_ARGS NAMES ONNX onnx/d' cmake/external/onnxruntime_external_deps.cmake

# libre2-11 ships only the runtime .so.
# Create a cmake config shim so FetchContent's find_package(re2) succeeds
# and ORT links against conda's shared libre2 instead of building a static
# libre2.a from source (which causes abseil ABI mismatches).
_RE2_CMAKE_DIR="${PREFIX}/lib/cmake/re2"
mkdir -p "${_RE2_CMAKE_DIR}"
ln -sf "${PREFIX}/lib/libre2.so.11" "${PREFIX}/lib/libre2.so"
cat > "${_RE2_CMAKE_DIR}/re2Config.cmake" << 'RE2CFG'
if(NOT TARGET re2::re2)
  add_library(re2::re2 SHARED IMPORTED)
  set_target_properties(re2::re2 PROPERTIES
    IMPORTED_LOCATION "${CMAKE_INSTALL_PREFIX}/lib/libre2.so"
    IMPORTED_SONAME "libre2.so.11"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_INSTALL_PREFIX}/include"
  )
  find_package(absl QUIET)
  if(TARGET absl::strings AND TARGET absl::synchronization)
    set_property(TARGET re2::re2 APPEND PROPERTY
      INTERFACE_LINK_LIBRARIES absl::strings absl::synchronization)
  endif()
endif()
RE2CFG

# Install re2 headers from the same source ORT would download via FetchContent
_RE2_URL=$(grep '^re2;' cmake/deps.txt | cut -d';' -f2)
python -c "
import urllib.request, zipfile, shutil, os, glob
urllib.request.urlretrieve('${_RE2_URL}', '/tmp/re2-src.zip')
with zipfile.ZipFile('/tmp/re2-src.zip') as zf:
    zf.extractall('/tmp/re2-src')
os.makedirs('${PREFIX}/include/re2', exist_ok=True)
for d in glob.glob('/tmp/re2-src/*/re2'):
    for h in glob.glob(os.path.join(d, '*.h')):
        shutil.copy2(h, '${PREFIX}/include/re2/')
"
rm -rf /tmp/re2-src /tmp/re2-src.zip

# Conda's libabseil 20260107 reports cmake version 20250127 (LTS tag),
# but ORT requires 20250814. Lower the constraint so find_package succeeds.
sed -i 's/FIND_PACKAGE_ARGS 20250814 NAMES absl/FIND_PACKAGE_ARGS NAMES absl/' cmake/external/abseil-cpp.cmake

# Conda's abseil is missing 3 targets added in 20250814 (header-only).
# Create shim INTERFACE targets so ORT's cmake can link against them.
cat >> cmake/external/abseil-cpp.cmake << 'ABSL_SHIMS'

# Shims for abseil targets added after conda-forge's LTS (20250127)
if(NOT TARGET absl::hashtable_control_bytes)
  add_library(absl::hashtable_control_bytes INTERFACE IMPORTED)
  target_link_libraries(absl::hashtable_control_bytes INTERFACE absl::config absl::core_headers)
endif()
if(NOT TARGET absl::iterator_traits_internal)
  add_library(absl::iterator_traits_internal INTERFACE IMPORTED)
  target_link_libraries(absl::iterator_traits_internal INTERFACE absl::config absl::type_traits)
endif()
if(NOT TARGET absl::weakly_mixed_integer)
  add_library(absl::weakly_mixed_integer INTERFACE IMPORTED)
  target_link_libraries(absl::weakly_mixed_integer INTERFACE absl::config)
endif()
ABSL_SHIMS

# Let Boost::mp11 be found from CF's libboost-devel instead of
# downloading boostorg/mp11. Mirrors the logic from the vcpkg code path.
sed -i '/^if(NOT TARGET Boost::mp11)/i \
find_package(Boost QUIET)\
if(TARGET Boost::headers AND NOT TARGET Boost::mp11)\
  add_library(Boost::mp11 ALIAS Boost::headers)\
endif()' cmake/external/onnxruntime_external_deps.cmake

# Fix __builtin_ia32_tpause call for Clang 20+ (3-arg form: hint, hi32, lo32)
sed -i 's/__builtin_ia32_tpause(0x0, __rdtsc() + tpause_spin_delay_cycles)/{ uint64_t __tsc = __rdtsc() + tpause_spin_delay_cycles; __builtin_ia32_tpause(0x0, (uint32_t)(__tsc >> 32), (uint32_t)__tsc); }/' \
    onnxruntime/core/common/spin_pause.cc

# MIGraphX 7.0.2 lacks fp4x2_type added in newer MIGraphX.
# Map FLOAT4E2M1 to fp8e4m3fn as a reasonable fallback for the type size.
sed -i 's/mgx_type = migraphx_shape_fp4x2_type;/mgx_type = migraphx_shape_fp8e4m3fn_type; \/\/ fp4x2 not in MIGraphX 7.0.2/' \
    onnxruntime/core/providers/migraphx/migraphx_execution_provider.cc

# Remove flatbuffers version assertions from pre-generated headers.
# The checked-in headers assert FLATBUFFERS_VERSION_MAJOR == 23 but conda has 25.
# The wire format is backward-compatible; only the compile-time check fails.
find onnxruntime -name '*.fbs.h' -o -name '*_generated.h' | \
    xargs sed -i '/static_assert(FLATBUFFERS_VERSION_MAJOR/,/Non-compatible flatbuffers version/d'

cmake -S cmake -B build \
    -G Ninja \
    ${CMAKE_ARGS} \
    -DPython_EXECUTABLE="${BUILD_PREFIX}/bin/python" \
    --compile-no-warning-as-error \
    -Donnxruntime_BUILD_SHARED_LIB=ON \
    -Donnxruntime_BUILD_UNIT_TESTS=OFF \
    -Donnxruntime_ENABLE_PYTHON=OFF \
    -Donnxruntime_USE_MIGRAPHX=ON \
    -Donnxruntime_MIGRAPHX_HOME="${PREFIX}" \
    -Donnxruntime_DISABLE_RTTI=OFF \
    -Donnxruntime_USE_COREML=OFF \
    -Donnxruntime_USE_VCPKG=OFF \
    -DEIGEN_MPL2_ONLY=ON

cmake --build build -j${CPU_COUNT}
cmake --install build --prefix "${PREFIX}"

# Clean up symlink
rm -f -- "${PREFIX}/include/half/half.hpp"
rmdir -- "${PREFIX}/include/half" 2>/dev/null || true
