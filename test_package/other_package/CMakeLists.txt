# Another package's project in the sample's build tree. Its package_create() passes every
# package-level argument and runs before the sample's, which passes none of them in the bare
# configure: a value that reached the sample's package would show in its package configuration,
# which the root CMakeLists.txt checks. Its package_install() makes the build tree's second package,
# configured in this project's binary directory; conanfile.py checks that it holds this project's
# app and nothing of the sample's.
project(
    PackageBuilderOtherTest
    VERSION 2.0.0
    DESCRIPTION "PackageBuilder test package's other package"
    LANGUAGES CXX)

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
    2.0.0-other
    REQUIRE_LICENSE_ACCEPTANCE)

# A complete package of its own, the sample's app mirrored, so that its package_install() succeeds
# on every platform.
package_add_executable(other_app WIN32 ../main.cpp DISPLAY_NAME "Other App")
set_target_properties(other_app PROPERTIES OUTPUT_NAME other-app)
# The GUI subsystem defaults to a WinMain entry; keep the shared plain main() under MSVC.
target_link_options(other_app PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/ENTRY:mainCRTStartup>)

package_install()
