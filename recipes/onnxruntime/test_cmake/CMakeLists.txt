cmake_minimum_required(VERSION 3.16)
project(onnxruntime_cmake_test CXX)

# Consume the library only through the exported target, as downstream CMake
# projects do: its include directory must provide the flat public headers.
find_package(onnxruntime CONFIG REQUIRED)
add_executable(test_cmake test_cmake.cpp)
target_compile_features(test_cmake PRIVATE cxx_std_17)
target_link_libraries(test_cmake PRIVATE onnxruntime::onnxruntime)
