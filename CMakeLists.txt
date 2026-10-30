cmake_minimum_required(VERSION 3.24)

# Specify CXX as the language even though it is purely CMake to make cmake-conan happy
project(
    PackageBuilder
    VERSION 4.0.0
    DESCRIPTION "Tools to assist with CMake/C++ package development"
    LANGUAGES C CXX)

# Our own modules
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

# A project that adds PackageBuilder as a subproject (as FetchContent does) needs only the module,
# which it includes itself, as it would after find_package(). Everything below packages
# PackageBuilder itself. FetchContent_MakeAvailable() is a macro, so the parent scope is the scope
# that called it.
if(NOT PROJECT_IS_TOP_LEVEL)
    set(CMAKE_MODULE_PATH
        "${CMAKE_MODULE_PATH}"
        PARENT_SCOPE)
    return()
endif()

# Add project config (disabled for Conan builds where project-config is not exported)
option(INCLUDE_PROJECT_CONFIG "Include project-config for docs, linting, and CMake presets" ON)
if(INCLUDE_PROJECT_CONFIG)

    # Set project-config specific options
    option(PROJECT_CONFIG_ENABLE_DOCS "Enable docs target when Doxygen is available" ON)
    # The README is the whole reference for the CMake functions, so it is all the docs document.
    set(PROJECT_CONFIG_DOCS_INPUT README.md)
    option(PROJECT_CONFIG_ENABLE_CLANG_TIDY
           "Enable clang-tidy target when run-clang-tidy is available" OFF)

    add_subdirectory(project-config)
endif()

# Use our own functions to create/export the package
include(PackageBuilder)
package_create()
package_install()

# package_install() installs the modules and templates of cmake/; the NSIS plugins the one-click
# template loads are PackageBuilder's own.
install(
    DIRECTORY "${PROJECT_SOURCE_DIR}/cmake/NSIS/Plugins"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}/NSIS"
    COMPONENT Development)
