# Another package's project in the sample's build tree, as a workspace configures its other product
# beside the sample. Its package_create() passes every package-level argument and runs before the
# sample's, which passes none of them in the bare configure: a value that reached the sample's
# package would show in its package configuration, which the root CMakeLists.txt checks. With
# PACKAGE_BUILDER_TEST_OTHER_INSTALLS it calls package_install() too, so the sample's own call is
# the build tree's second and must fail the configure, which conanfile.py checks.
project(
    PackageBuilderOtherTest
    VERSION 2.0.0
    DESCRIPTION "PackageBuilder test package's other package"
    LANGUAGES CXX)

option(PACKAGE_BUILDER_TEST_OTHER_INSTALLS "The other package calls package_install() too" OFF)

package_create(
    VENDOR
    "Other Vendor"
    DISPLAY_NAME
    "Other Product"
    ICON
    other.ico
    PRIMARY_TARGET
    other_app
    DESKTOP_LINKS
    ""
    MENU_LINKS
    "bin/other.html"
    "Other Guide"
    VERSION
    2.0.0-other)

# A complete package of its own, the sample's app mirrored, so that its package_install() succeeds
# on every platform and the sample's is the first call to fail.
package_add_executable(other_app WIN32 ../main.cpp DISPLAY_NAME "Other App")
set_target_properties(other_app PROPERTIES OUTPUT_NAME other-app)
# The GUI subsystem defaults to a WinMain entry; keep the shared plain main() under MSVC.
target_link_options(other_app PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/ENTRY:mainCRTStartup>)

if(PACKAGE_BUILDER_TEST_OTHER_INSTALLS)
    package_install()
endif()
