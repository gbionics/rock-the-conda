mkdir build
cd build

:: I am not sure if this is actually required or not, but doing that fixes the build, see
:: https://github.com/conda-forge/librealsense-feedstock/pull/76#issuecomment-3241165148 for more details
copy %SRC_DIR%\src\win7\drivers\IntelRealSense_D400_series_win7.inf %SRC_DIR%

if not "%cuda_compiler_version%" == "None" (
  set "CMAKE_ARGS=%CMAKE_ARGS% -DBUILD_WITH_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=all"
) else (
  set "CMAKE_ARGS=%CMAKE_ARGS% -DBUILD_WITH_CUDA=OFF"
)

cmake %CMAKE_ARGS% -GNinja ^
    -DCMAKE_INSTALL_PREFIX=%LIBRARY_PREFIX% ^
    -DCMAKE_PREFIX_PATH=%LIBRARY_PREFIX% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_LIBDIR=lib ^
    -DBUILD_SHARED_LIBS=ON ^
    -DENABLE_CCACHE=OFF ^
    -DBUILD_WITH_OPENMP=OFF ^
    -DFORCE_RSUSB_BACKEND=ON ^
    -DBUILD_PYTHON_BINDINGS=ON ^
    -DPYTHON_INSTALL_DIR="%SP_DIR%\pyrealsense2" ^
    -DPYTHON_EXECUTABLE="%PYTHON%" ^
    -DPython_EXECUTABLE="%PYTHON%" ^
    -DBUILD_EXAMPLES=OFF ^
    -DBUILD_UNIT_TESTS=OFF ^
    -DLIBUSB_LIB=%LIBRARY_LIB%\libusb-1.0.lib ^
    -DCHECK_FOR_UPDATES=OFF ^
    -DBUILD_LEGACY_PYBACKEND=OFF ^
    -DBUILD_WITH_STATIC_CRT=OFF ^
    %SRC_DIR%
if errorlevel 1 exit 1

:: Build.
cmake --build . --config Release
if errorlevel 1 exit 1

:: Install.
cmake --build . --config Release --target install
if errorlevel 1 exit 1
