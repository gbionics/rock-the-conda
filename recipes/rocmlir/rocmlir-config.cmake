# Custom rocmlir CMake config for conda-forge builds.
# Creates the rocMLIR::rockCompiler INTERFACE target that downstream
# packages (e.g. MIGraphX) expect from find_package(rocMLIR CONFIG).
# Instead of the upstream fat static archive, this links to the
# individual C-API shared libraries that the conda package ships.

get_filename_component(_rocmlir_prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

include(CMakeFindDependencyMacro)

find_library(_rocmlir_capi_migraphx MLIRCAPIMIGraphX
    HINTS "${_rocmlir_prefix}/lib" NO_DEFAULT_PATH)
find_library(_rocmlir_capi_rock MLIRCAPIRock
    HINTS "${_rocmlir_prefix}/lib" NO_DEFAULT_PATH)
find_library(_rocmlir_capi_register MLIRCAPIRegisterRocMLIR
    HINTS "${_rocmlir_prefix}/lib" NO_DEFAULT_PATH)

if(NOT _rocmlir_capi_migraphx OR NOT _rocmlir_capi_rock OR NOT _rocmlir_capi_register)
    set(rocMLIR_FOUND FALSE)
    set(rocMLIR_NOT_FOUND_MESSAGE
        "rocMLIR C-API libraries not found (looked in ${_rocmlir_prefix}/lib)")
    return()
endif()

if(NOT TARGET rocMLIR::rockCompiler)
    add_library(rocMLIR::rockCompiler INTERFACE IMPORTED)
    set_target_properties(rocMLIR::rockCompiler PROPERTIES
        INTERFACE_LINK_LIBRARIES
            "${_rocmlir_capi_migraphx};${_rocmlir_capi_rock};${_rocmlir_capi_register}"
        INTERFACE_INCLUDE_DIRECTORIES
            "${_rocmlir_prefix}/include"
    )
endif()

set(rocMLIR_FOUND TRUE)
