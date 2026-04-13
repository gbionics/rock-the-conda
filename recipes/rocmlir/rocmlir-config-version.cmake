# Version compatibility file for find_package(rocMLIR ...).
# The upstream rocMLIR project version is 2.0.0; MIGraphX requires >= 1.0.0.
set(PACKAGE_VERSION "2.0.0")

if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
    set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
    set(PACKAGE_VERSION_COMPATIBLE TRUE)
    if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
        set(PACKAGE_VERSION_EXACT TRUE)
    endif()
endif()
