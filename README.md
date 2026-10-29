# PackageBuilder

[![Build - Windows](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/build-windows.yml/badge.svg)](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/build-windows.yml)
[![Build - Linux](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/build-linux.yml/badge.svg)](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/build-linux.yml)
[![Build - macOS](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/build-macos.yml/badge.svg)](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/build-macos.yml)
[![Docs](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/docs.yml/badge.svg)](https://github.com/tnt-music-studios/cmake-package-builder/actions/workflows/docs.yml)

**Tired of writing hundreds of lines of CMake boilerplate just to create a properly installable library?** Build sleek, professional C++ libraries and executables with a few simple function calls. Installation and package config generation all handled automatically.

> [!IMPORTANT]
> PackageBuilder assumes a [canonical CMake project structure](#project-structure) for its default behavior.

## Prerequisites

- CMake 3.24 or higher
- [NSIS](https://nsis.sourceforge.io/) to build the Windows installer

---

## Installation

### Method 1: Conan via cmake-conan (Preferred)

If your project uses [cmake-conan](https://github.com/tnt-music-studios/cmake-conan) (the TNT Music Studios fork), this is the recommended way to consume PackageBuilder. Dependencies are resolved automatically with no manual installation.

Add the following to your `conanfile.py`:

```python
def requirements(self):
    self.requires("cmake-package-builder/3.0.0") #recipe: https://github.com/tnt-music-studios/cmake-package-builder.git
```

Or in `conanfile.txt`:

```ini
[requires]
cmake-package-builder/3.0.0 #recipe: https://github.com/tnt-music-studios/cmake-package-builder.git

[generators]
CMakeDeps
CMakeToolchain
```

The `#recipe:` tag tells cmake-conan where to find the source for the package. If the package is not already present in your local Conan cache or any configured remote, cmake-conan will automatically clone the tagged version from the provided git URL and run `conan create` to build it locally. No manual recipe hosting or remote setup needed.

Then in your CMakeLists.txt:

```cmake
find_package(PackageBuilder REQUIRED)
include(PackageBuilder)
```

For full details on how cmake-conan and the recipe tag work, see the TNT Music Studios fork of the
[cmake-conan](https://github.com/tnt-music-studios/cmake-conan) repository.

### Method 2: FetchContent (Simplest)

The simplest way to get started. No installation or package manager required.

```cmake
cmake_minimum_required(VERSION 3.24)
project(MyProject LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(
    PackageBuilder
    GIT_REPOSITORY https://github.com/tnt-music-studios/cmake-package-builder
    GIT_TAG v3.0.0
)
FetchContent_MakeAvailable(PackageBuilder)

include(PackageBuilder)
```

Added this way, PackageBuilder contributes only its module: it packages nothing of its own and adds
no docs or lint targets to your build. `include(PackageBuilder)` finds the module because
`FetchContent_MakeAvailable()` runs in your scope; call it from your project's directory scope, not
from inside a function.

This allows you to immediately hit the ground running with professional quality install/package creation logic for your own project.

### Method 3: find_package (Classic)

Build and install PackageBuilder to your system, then find it like any other CMake package.

**Install:**

```
git clone https://github.com/tnt-music-studios/cmake-package-builder
cd cmake-package-builder
cmake -B build -DINCLUDE_PROJECT_CONFIG=OFF
cmake --install build
```

`INCLUDE_PROJECT_CONFIG=OFF` skips the repository's own docs and lint tooling, which lives in the
`project-config` submodule that a plain clone leaves empty.

**Consume:**

```cmake
cmake_minimum_required(VERSION 3.24)
project(MyProject LANGUAGES CXX)

find_package(PackageBuilder REQUIRED)
include(PackageBuilder)
```

---

## Usage

### Create The Package

**Required.** Must be called, once per project, before any other PackageBuilder function in that project.

```cmake
package_create()
```

This function performs essential validation before any targets are defined:

- **Version verification:** Verifies that `PROJECT_VERSION` is set and fails with a fatal error if it is not. `PROJECT_VERSION` is typically set by specifying the version in the `project()` command.
- **Package version:** The installers carry `PROJECT_VERSION` unless `VERSION` overrides it with that version plus an optional SemVer pre-release or build suffix, e.g. `package_create(VERSION 1.0.0-alpha)` under `project(MyProject VERSION 1.0.0)`; any other value is a fatal error. `project()` and the numeric platform version fields (Windows VERSIONINFO's `FILEVERSION` and `PRODUCTVERSION`, Apple plists) accept integers only, so they keep the numeric version while installer file names, displayed versions and the Windows version text fields carry the full one. Debian packages spell the suffix with `~` (`1.0.0~alpha`) so that a pre-release sorts before its final release.
- **Description verification:** Verifies that `PROJECT_DESCRIPTION` is set and fails with a fatal error if it is not. Set via the `DESCRIPTION` argument in the `project()` command.
- **License verification:** Verifies that a `LICENSE` file exists at the project root. This is required for CPack packaging.

It also takes the package's identity, all optional:

| Argument | Description |
|----------|-------------|
| `VENDOR` | The publisher: `CPACK_PACKAGE_VENDOR`, the Windows *Publisher* entry, the parent folder of the Windows install directory, and the Debian maintainer unless you name one, so a Linux package with neither fails to build its DEB (see [Packaging Behavior](#packaging-behavior)). Without it, the package names no publisher: the Windows install directory has no parent folder, *Apps & features* shows no publisher, and a DEB needs `CPACK_PACKAGE_CONTACT`. |
| `DISPLAY_NAME` | The package's name on Windows: the installer title, the *Apps & features* entry, the Start Menu folder, the install directory and the registry key. Defaults to the `PRIMARY_TARGET`'s display name, then `PROJECT_NAME`. |
| `ICON` | The installer, uninstaller and *Apps & features* icon, installed to `bin` in `Runtime` for the latter. Defaults to the `PRIMARY_TARGET`'s icon. |
| `PRIMARY_TARGET` | The executable that represents the package when `DISPLAY_NAME` or `ICON` is not given, and that gets the desktop shortcut by default when it is a [GUI executable](#desktop-shortcuts-and-launchers). It must be packaged (see [Install components](#install-components)). A package with one packaged executable infers it. |
| `DESKTOP_LINKS` | See [Desktop shortcuts and launchers](#desktop-shortcuts-and-launchers). |
| `MENU_LINKS` | See [Start Menu links](#start-menu-links). |
| `VERSION` | See above. |

A project's package is its own: what `package_create()` records is keyed by `PROJECT_NAME`, as the project's registered targets are, so every PackageBuilder function reads its own project's package and nothing another project's `package_create()` passed reaches it. An argument a project does not pass takes its default. A second `package_create()` in one project is a configure error. A workspace that configures several projects in one build tree gives each its own `package_create()`, and only one of them can package (see [Generate Package Install Logic](#generate-package-install-logic)).

The Windows install directory is `<VENDOR>\<DISPLAY_NAME>` under Program Files and the registry key is `<DISPLAY_NAME>`. Neither carries the version, so a new version installs over the last one rather than beside it. The one-click installer's *Apps & features* entry names the install directory as its `InstallLocation`, the standard value through which another program finds an installed one; the classic wizard, CMake's own template, stores it under `Software\<VENDOR>\<DISPLAY_NAME>` instead. The uninstaller removes the `<VENDOR>` folder once the vendor's last product is gone, in both installer modes:

```cmake
# Installs to "Program Files\My Company\My Suite"
package_create(VENDOR "My Company" DISPLAY_NAME "My Suite" ICON resources/my_suite.ico
               PRIMARY_TARGET my_app)
```

> [!TIP]
> **A repository that packages a single command-line tool should pass `DISPLAY_NAME`.** Its one packaged executable is the inferred `PRIMARY_TARGET`, and `DISPLAY_NAME` falls back to that target's display name, which is its output name, before `PROJECT_NAME`. Without `DISPLAY_NAME`, the install directory, registry key and *Apps & features* entry are therefore named after the executable, e.g. `Program Files\my-tool` for an `OUTPUT_NAME` of `my-tool`:
>
> ```cmake
> # Installs to "Program Files\My Company\My Tool" instead of "Program Files\my-tool"
> package_create(VENDOR "My Company" DISPLAY_NAME "My Tool")
> ```

### Add Targets

```cmake
# Create a library (automatically aliased as MyProject::mylib)
package_add_library(mylib src/mylib.cpp)

# Create an executable
package_add_executable(myapp src/main.cpp)

# Create a GUI executable with packaging metadata
package_add_executable(myapp WIN32 src/main.cpp
    ICON                 resources/myapp.ico
    LINUX_DESKTOP_FILE   resources/myapp.desktop
    LINUX_ICON_THEME_DIR resources/icons)

# Link them together using the namespaced alias
target_link_libraries(myapp PRIVATE MyProject::mylib)
```

Libraries created with `package_add_library` are automatically given a namespaced alias of `<PROJECT_NAME>::<target>`. This is the same alias that downstream consumers will use after `find_package()`.

Targets created with `package_add_library` and `package_add_executable` automatically receive
these private include directories:

- `${CMAKE_CURRENT_SOURCE_DIR}`
- `${CMAKE_CURRENT_SOURCE_DIR}/include`
- `${CMAKE_CURRENT_SOURCE_DIR}/src`

For libraries, only `${CMAKE_CURRENT_SOURCE_DIR}/include` is exposed publicly. The project root is
a build-time convenience only and is not exported to consumers.

`package_add_executable` accepts optional packaging arguments:

| Argument       | Description |
|----------------|-------------|
| `DISPLAY_NAME`         | Human-readable name for the executable: its shortcut label and, on Windows, its `File description` and `Product name`. Defaults to the executable's output name. |
| `ICON`                 | Path to an icon file (`.ico`). On Windows, `package_add_executable()` embeds this into the executable; the `PRIMARY_TARGET`'s icon is also the NSIS installer/uninstaller icon unless `package_create()` sets its own `ICON`. Changing the icon re-runs CMake; that is how the compiled resource learns of it. Paths may be relative to the calling `CMakeLists.txt`. |
| `LINUX_DESKTOP_FILE`   | Path to an XDG `.desktop` file. Installed to `share/applications` on Linux for desktop launcher integration. Paths may be relative to the calling `CMakeLists.txt`. |
| `LINUX_ICON_THEME_DIR` | Path to a directory containing a Linux icon theme subtree such as `hicolor/256x256/apps/myapp.png`. Installed to `share/icons` on Linux. Paths may be relative to the calling `CMakeLists.txt`. |
| `COMPONENT`            | The install component that carries the executable and its Linux launcher entry and icons. Defaults to `Runtime`. See [Install components](#install-components). |

All other arguments after the target name are forwarded to `add_executable()`: the source files, and `WIN32` for a GUI executable, which on Windows gets [shortcuts](#desktop-shortcuts-and-launchers) where a command-line tool gets none.

On Windows, every executable created with `package_add_executable` also gets version information, which Explorer shows under Properties → Details: the numeric `FILEVERSION` and `PRODUCTVERSION` carry `PROJECT_VERSION`, the `File version` and `Product version` text carries the full package version (`1.0.0-alpha`), and the `File description` and `Product name` carry the target's `DISPLAY_NAME` (or its output name when none is given).

A target created outside PackageBuilder can carry the same version information, and its registered `ICON`, through `package_write_resource_script(<out_var> <target>)`, which writes the resource script and returns its path. Call it after `package_register_target`, so the display name and icon are known. When the target's own tooling writes its resource script, include this one from it. For a JUCE app, JUCE's generated resource script includes `JUCE_USER_DEFINED_RC_FILE` in place of its own version block; leave JUCE's `ICON_BIG` and `ICON_SMALL` unset, so the icon comes from this script alone:

```cmake
juce_add_gui_app(my_app PRODUCT_NAME "My App" VERSION ${PROJECT_VERSION})
package_register_target(my_app DISPLAY_NAME "My App" ICON resources/my_app.ico)
if(WIN32)
    package_write_resource_script(_my_app_rc my_app)
    target_compile_definitions(my_app PRIVATE JUCE_USER_DEFINED_RC_FILE="${_my_app_rc}")
endif()
```

### Register Existing Targets

If your target is created outside PackageBuilder, such as by `add_executable` or another CMake
helper, register it for install, export, and CPack handling with `package_register_target`:

```cmake
add_executable(my_app WIN32 main.cpp)
target_include_directories(my_app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

package_register_target(my_app
    ICON                 resources/my_app.ico
    LINUX_DESKTOP_FILE   resources/my_app.desktop
    LINUX_ICON_THEME_DIR resources/icons)
```

For externally created libraries, use `PUBLIC_HEADER_DIRS` to tell PackageBuilder which public
header roots should be installed:

```cmake
add_library(my_lib)
target_sources(my_lib PRIVATE src/my_lib.cpp)
target_include_directories(
    my_lib
    PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
           $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

package_register_target(my_lib PUBLIC_HEADER_DIRS include)
```

`package_register_target` accepts the same `DISPLAY_NAME`, `ICON`, `LINUX_DESKTOP_FILE`,
`LINUX_ICON_THEME_DIR`, and `COMPONENT` arguments as `package_add_executable`; a `COMPONENT` on a
target without runtime artifacts (an executable, shared library or module library) is a configure
error. For externally created targets, `ICON` is packaging metadata: it serves as the installer icon
as above, but reaches the executable's own resources only through
[`package_write_resource_script`](#add-targets). `package_register_target` does not create the
target, add sources, add include directories, or create a namespaced build-tree alias. Those
details remain the responsibility of the project that created the target.

### Generate Package Install Logic

```cmake
package_install()
```

This single call handles everything:

- Installs all targets registered via `package_add_library`, `package_add_executable`, and
  `package_register_target`
- Installs public headers (files matching `*.h*`) from `include/` or any `PUBLIC_HEADER_DIRS`
  provided while registering external libraries
- Installs any custom CMake modules (`*.cmake` and `*.in` files) from `cmake/`
- With MSVC, installs the [C++ runtime](#msvc-c-runtime) beside any executable, shared library or
  module library
- Generates and installs `<ProjectName>Config.cmake` and `<ProjectName>ConfigVersion.cmake`

Downstream projects can then consume your package:

```cmake
find_package(MyProject REQUIRED)
target_link_libraries(myapp PRIVATE MyProject::mylib)
```

A build tree makes one package, so `package_install()` may be called once per build tree: a second
call, from any project, is a configure error naming both projects. CPack writes one
`CPackConfig.cmake` per build tree and a package installs every install rule of the tree, so a
second package would carry the first one's files. A repository of several products configures each
product in a build tree of its own, and a subproject that packages itself when built alone guards
its call:

```cmake
if(PROJECT_IS_TOP_LEVEL)
    package_install()
endif()
```

---

## Packaging Behavior

`package_install()` configures [CPack](https://cmake.org/cmake/help/latest/module/CPack.html) to generate platform-native installers:

| Platform | Generators     |
|----------|---------------|
| Windows  | ZIP, NSIS      |
| macOS    | ZIP, DragNDrop |
| Linux    | ZIP, DEB       |

A project with no executable, shared library or module library gets install rules but no CPack
configuration.

`package_install()` includes `CPack` itself, so other `CPACK_*` variables set before the call reach
CPack. The ones PackageBuilder sets from the package's identity, version, components, generators and
Windows shortcuts and icons overwrite any value you set; `CPACK_NSIS_CREATE_ICONS_EXTRA` and
`CPACK_NSIS_DELETE_ICONS_EXTRA` are appended to.

A Debian package must name a maintainer. Set `CPACK_PACKAGE_CONTACT` (or
`CPACK_DEBIAN_PACKAGE_MAINTAINER`, which takes precedence) before `package_install()`, in Debian's
`Name <email>` form. Without either, PackageBuilder uses the `VENDOR` passed to `package_create()`;
a package that names none of the three fails to build its DEB with CPack's error naming both
variables.

PackageBuilder uses CPack's project configuration file (`CPACK_PROJECT_CONFIG_FILE`) for its own
per-generator settings. A file you name in `CPACK_PROJECT_CONFIG_FILE` before `package_install()`
still runs: PackageBuilder's file includes it last, once per generator, so your settings override
PackageBuilder's.

Multiple registered applications — including macOS app bundles created by external CMake helpers —
are supported in a single package. Each registered runtime target gets its own runtime dependency
set, so CPack can correctly resolve and bundle the dependencies for every app.

### Install components

PackageBuilder assigns every install artifact to one of two CPack components:

| Component | Contents |
|-----------|----------|
| `Runtime` | Executables, macOS app bundles, shared libraries, the runtime dependencies of every packaged target, and with MSVC the [C++ runtime](#msvc-c-runtime) |
| `Development` | Static libraries, public headers, CMake package metadata (exported targets, config/version files, custom modules) |

A runtime target registered with `COMPONENT <name>` goes to that component instead of `Runtime`,
together with its Linux `.desktop` file and icons. Its runtime dependencies go to `Runtime` while
`<name>` is packaged, so a library two packaged executables both need is one file of `Runtime`
rather than a file of each executable's component; while `<name>` is not packaged they stay in
`<name>`, so none of them ship. Registration records
every runtime target's component, `Runtime` included, as its `PACKAGE_BUILDER_COMPONENT` property,
so a project's own install rules for files that belong to one executable can read it rather than
restate it:

```cmake
package_add_executable(my_game main.cpp DISPLAY_NAME "My Game" COMPONENT Game)

get_target_property(_game_component my_game PACKAGE_BUILDER_COMPONENT)
install(DIRECTORY levels/ DESTINATION ${CMAKE_INSTALL_BINDIR}/levels COMPONENT ${_game_component})
```

`PACKAGE_BUILDER_CPACK_COMPONENTS` lists the components the generated packages carry, and must
include `Runtime` whenever it lists the component of a runtime target registered with another
`COMPONENT`, since `Runtime` then carries that target's runtime dependencies. Every
generator honours it: the ZIP and DEB generators run in component mode with all listed components
grouped into one package, so each still produces one file named `<PROJECT_NAME>-<version>-<os>-<arch>`.
A component left off the list ships in no package, while its targets still build and its install
rules still run for `cmake --install`. On Windows, an executable whose component is not listed gets
no Start Menu entry or desktop shortcut, and cannot be the `PRIMARY_TARGET`.

`Runtime` is required in every installer, so it cannot be deselected: it holds what every packaged
executable loads, and the files of package-level features such as the [Start Menu
links](#start-menu-links) belong in it.

### Runtime-only installers

By default, `PACKAGE_BUILDER_CPACK_COMPONENTS` is `Runtime` plus every component a target was
registered with, so the generated installers carry executables, app bundles, and shared libraries.
Development-facing artifacts such as static libraries, public headers, exported CMake target
definitions, and package config files are excluded because [Conan](https://conan.io/) is the
preferred method for consuming packages as libraries during development.

To leave a finished-but-unreleased application out of every package, set the list without its
component before calling `package_install()`:

```cmake
# my_game (COMPONENT Game) keeps building and testing, but ships in no package until listed
set(PACKAGE_BUILDER_CPACK_COMPONENTS Runtime Tool)
package_install()
```

### Desktop shortcuts and launchers

Every packaged GUI executable gets a Start Menu entry (Windows), and every packaged executable with
a `.desktop` file an XDG launcher entry (Linux). On Windows, a GUI executable is one whose
`WIN32_EXECUTABLE` property is true, as `package_add_executable(my_app WIN32 ...)`,
`add_executable(my_app WIN32 ...)` and JUCE's `juce_add_gui_app` make it; a generator-expression
value counts as true. Any other executable is a command-line tool, for which a shortcut would only
open a console window, so it gets no Start Menu entry or desktop shortcut, as on Linux an executable
without a `.desktop` file gets no launcher entry. A GUI program that still links as a console
application (some SDL games) counts as one too: set its `WIN32_EXECUTABLE` to `TRUE`, with
`/ENTRY:mainCRTStartup` under MSVC to keep a plain `main()`, or keep its console and give it a
`MENU_LINKS` entry. A command-line tool that should still appear in the Start Menu takes a
[`MENU_LINKS`](#start-menu-links) entry, such as `MENU_LINKS "bin/my-tool.exe" "My Tool"`; a
one-click package with neither a GUI executable nor a `MENU_LINKS` entry gets no Start Menu
folder, and reaches its command-line tools through PATH instead (see
[Windows one-click installer](#windows-one-click-installer)). The one-click installer adds no
Uninstall shortcut: Windows uninstalls a package from *Apps & features*.

Desktop shortcuts (Windows) go to the package's `PRIMARY_TARGET` by default when it is a GUI
executable; pass `DESKTOP_LINKS` to `package_create()` to choose the GUI executables that receive
one, or an empty list for none. Targets in `DESKTOP_LINKS` whose component is not listed get none,
and a listed command-line tool gets none with a configure warning:

```cmake
# Both apps get a desktop shortcut
package_create(PRIMARY_TARGET my_app DESKTOP_LINKS my_app my_tool)

# The GUI primary target gets no desktop shortcut. Quote the empty list: a bare DESKTOP_LINKS
# counts as not given
package_create(PRIMARY_TARGET my_app DESKTOP_LINKS "")
```

| Platform | Behavior |
|----------|----------|
| Windows  | See [Windows one-click installer](#windows-one-click-installer) below for desktop shortcut behavior. The package's [`MENU_LINKS`](#start-menu-links) join the GUI executables' Start Menu entries. The NSIS installer icon is the package's `ICON`, else the `PRIMARY_TARGET`'s. |
| Linux    | Installs the `.desktop` file provided via `LINUX_DESKTOP_FILE` to `share/applications`, and installs the `.png` and `.svg` files of the icon theme tree provided via `LINUX_ICON_THEME_DIR` to `share/icons`. If `LINUX_DESKTOP_FILE` is omitted, PackageBuilder looks for a `<target>.desktop` file in the same directory as the target's `CMakeLists.txt`; an executable with neither is a command-line tool and gets no launcher entry. Only a `LINUX_DESKTOP_FILE` or `LINUX_ICON_THEME_DIR` that does not exist draws a configure warning. |
| macOS    | No action needed — DragNDrop bundles are self-contained and Launchpad discovers them automatically when dragged to `/Applications`. |

### Start Menu links

`package_create(MENU_LINKS <path> <label> ...)` adds Windows Start Menu links beside the GUI
executables' entries, such as a user guide or a website: `<path> <label>` pairs, where `<path>` is
relative to the install directory or is a URL. The uninstaller removes them with the rest of the
Start Menu folder. Install the files they point at in `Runtime`, which every installer carries:

```cmake
package_create(VENDOR "My Company" DISPLAY_NAME "My Suite"
               MENU_LINKS "bin/guide/index.html" "My Suite User Guide"
                          "https://example.com" "My Suite Website")

install(DIRECTORY "${guide_dir}/" DESTINATION "${CMAKE_INSTALL_BINDIR}/guide" COMPONENT Runtime)
```

PackageBuilder is the one source of the links: setting `CPACK_NSIS_MENU_LINKS` yourself is a
configure error, since `package_install()` would otherwise drop it silently.

### MSVC C++ runtime

With MSVC, an executable, shared library or module library that links the C++ runtime dynamically
(`/MD`, the default) needs DLLs that Windows does not carry, and the runtime dependency sets cannot
bundle them: they exclude everything resolved from `System32`, where an installed Visual C++
redistributable puts them. So whenever a package has an executable, shared library or module
library, `package_install()` installs the
redistributable's whole C++ runtime set (`msvcp140.dll`, `vcruntime140.dll`, and their siblings)
into `bin` in the `Runtime` component, through CMake's `InstallRequiredSystemLibraries`. The
Universal CRT it builds on ships with Windows 10 and later and stays out. A package of static or
header-only libraries ships no runtime, and other compilers install nothing.

A project that links the runtime statically (`/MT`) or deploys it another way opts out before
calling `package_install()`:

```cmake
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
package_install()
```

`InstallRequiredSystemLibraries`'s other inputs, such as `CMAKE_INSTALL_DEBUG_LIBRARIES` and
`CMAKE_INSTALL_UCRT_LIBRARIES`, apply as usual.

### Windows one-click installer

By default (`PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER ON`), the generated NSIS installer is
**zero-interaction**: the user double-clicks the installer, it installs the application, creates
the [desktop shortcuts](#desktop-shortcuts-and-launchers), and closes automatically. No wizard
pages, no "Next" buttons, no path or directory choices.

When set to `OFF`, the installer reverts to CMake's classic NSIS wizard: Welcome, License, an
options page (PATH and an opt-in desktop shortcut checkbox), Directory, Start Menu, Components
(`Runtime` cannot be deselected), Install and Finish pages.

In both modes, an installer that finds an earlier installation under the same registry key first
asks whether to uninstall it.

The one-click installer has no page to ask about PATH, so the package decides: when it holds a
[command-line tool](#desktop-shortcuts-and-launchers), the installer adds its `bin` directory to
the machine PATH, where a console finds the tool by name, and the uninstaller removes it again. A
package of GUI executables alone leaves PATH alone. PATH is edited with the
[EnVar](https://github.com/GsNSIS/EnVar) NSIS plugin (v0.3.1, zlib licence), which PackageBuilder
carries in `cmake/NSIS/Plugins/`.

```cmake
# Default: zero-interaction installer (user just double-clicks)
# set(PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER ON)

# Classic wizard with pages
set(PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER OFF)
package_install()
```

| Mode | Desktop shortcut | PATH modification | Wizard pages |
|------|-----------------|-------------------|--------------|
| `ON` (default) | Created for the `DESKTOP_LINKS` targets without asking | `bin` added to the machine PATH when the package holds a command-line tool | None, only install progress |
| `OFF` | Opt-in checkbox during install | User-controlled via installer page | Welcome, License, options, Directory, Start Menu, Components, Finish |

#### Providing a custom NSIS template

If your project needs a fully custom NSIS installer template, set `PACKAGE_BUILDER_NSIS_TEMPLATE_DIR`
to the directory containing your `NSIS.template.in` before calling `package_install()`. This
directory takes the highest priority in either installer mode:

```cmake
set(PACKAGE_BUILDER_NSIS_TEMPLATE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/packaging/nsis")
package_install()
```

PackageBuilder's lookup order for `NSIS.template.in` (highest to lowest priority):

1. `PACKAGE_BUILDER_NSIS_TEMPLATE_DIR` — caller-provided override
2. PackageBuilder's bundled `cmake/NSIS/` directory (one-click template, one-click mode only)
3. CMake's built-in NSIS template (classic wizard)

A custom template must expand `@CPACK_NSIS_DELETE_ICONS_EXTRA@` after its uninstaller removes
`$INSTDIR`, as PackageBuilder's template and CMake's both do: PackageBuilder removes the one-click
desktop shortcuts and the empty vendor folder through it. In one-click mode it must also expand
`@CPACK_NSIS_CREATE_ICONS_EXTRA@`, through which PackageBuilder creates the desktop shortcuts, and
add `$INSTDIR\@CPACK_PACKAGE_BUILDER_NSIS_BINDIR@` to PATH when `@CPACK_NSIS_MODIFY_PATH@` is `ON`,
and remove it again on uninstall;
`@CPACK_PACKAGE_BUILDER_NSIS_PLUGIN_DIR@` names the directory holding PackageBuilder's EnVar plugin
for `!addplugindir`, as its own template does.

### Including development components

If your project needs installers that also ship development files, set `PACKAGE_BUILDER_CPACK_COMPONENTS` before calling `package_install()`. Setting it replaces the default list, so name every component the packages should carry:

```cmake
set(PACKAGE_BUILDER_CPACK_COMPONENTS Runtime Development)
package_install()
```

---

## Project Structure

PackageBuilder is designed to work best with the following project layout:

```
MyProject/
|- CMakeLists.txt
|- cmake/              # Optional: custom CMake modules (auto-installed alongside config files)
|- include/            # Public headers (auto-installed to the system include directory)
`- src/                # Private source and header files
```

- Headers in `include/` are exposed publicly to consumers of your library.
- The project root is also added as a private include directory for targets created by
  `package_add_library` and `package_add_executable`.
- Files in `src/` are private to your project and are not installed.
- Any `.cmake` and `.in` files in `cmake/` are installed alongside the generated package config,
  which adds their directory to consumers' `CMAKE_MODULE_PATH`.

Projects with non-canonical layouts can still use PackageBuilder by creating targets themselves and
then registering them with `package_register_target(...)`.

---

## Complete Example

```cmake
cmake_minimum_required(VERSION 3.24)
project(MyAwesomeLib VERSION 1.0.0 DESCRIPTION "An awesome library" LANGUAGES CXX)

# Or use FetchContent if the package is not installed
find_package(PackageBuilder REQUIRED)
include(PackageBuilder)

# Create the package - validates version, description, and license
package_create()

# Create targets
package_add_library(awesome src/awesome.cpp)
package_add_executable(awesome_app WIN32 src/main.cpp
    ICON                 resources/awesome_app.ico
    LINUX_DESKTOP_FILE   resources/awesome_app.desktop
    LINUX_ICON_THEME_DIR resources/icons)

target_link_libraries(awesome_app PRIVATE MyAwesomeLib::awesome)

# Give awesome_app a Start Menu entry and desktop shortcut (Windows), install its
# .desktop file to share/applications (Linux), and install its icon theme
# assets to share/icons (Linux)
package_install()
```

---

## Example: JUCE Application

[JUCE](https://juce.com/) creates GUI app targets via `juce_add_gui_app` rather than
`add_executable`. Use `package_register_target` to hand the externally-created target off to
PackageBuilder:

```cmake
cmake_minimum_required(VERSION 3.24)
project(MyApp VERSION 1.0.0 DESCRIPTION "A JUCE-based application" LANGUAGES CXX)

find_package(PackageBuilder REQUIRED)
include(PackageBuilder)

package_create()

# JUCE creates and configures the target internally
juce_add_gui_app(my_app
    PRODUCT_NAME "My App"
    VERSION      ${PROJECT_VERSION})

target_sources(my_app PRIVATE main.cpp)
target_compile_definitions(my_app PRIVATE JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0)
target_link_libraries(my_app PRIVATE juce::juce_gui_basics juce::juce_recommended_warning_flags)

# Register the JUCE target so PackageBuilder includes it in install/CPack output
package_register_target(my_app
    DISPLAY_NAME         "My App"
    ICON                 resources/my_app.ico
    LINUX_DESKTOP_FILE   resources/my_app.desktop
    LINUX_ICON_THEME_DIR resources/icons)

# Give the executable its version information and icon through JUCE's own resource script
if(WIN32)
    package_write_resource_script(_my_app_rc my_app)
    target_compile_definitions(my_app PRIVATE JUCE_USER_DEFINED_RC_FILE="${_my_app_rc}")
endif()

# Give my_app a Start Menu entry and desktop shortcut (Windows), install its .desktop
# file to share/applications (Linux), and install its icon theme assets to
# share/icons (Linux)
package_install()
```

For Linux desktop icons, place PNG files under a standard icon theme layout rooted at the
directory passed to `LINUX_ICON_THEME_DIR`, for example:

```text
resources/icons/
`- hicolor/
   |- 32x32/apps/my_app.png
   |- 48x48/apps/my_app.png
   |- 64x64/apps/my_app.png
   |- 128x128/apps/my_app.png
   `- 256x256/apps/my_app.png
```

Then set `Icon=my_app` in your `.desktop` file, without a file extension.

---

## Versioning

From 2.0.0 on, every breaking change bumps the major version, so a pin to any 3.x release can move
to a later 3.x without changes to the consuming project. The installed
`PackageBuilderConfigVersion.cmake` uses `SameMajorVersion` to the same effect:
`find_package(PackageBuilder 3)` accepts any 3.x and no 2.x.

2.0.3 is a bug fix within that promise: a command-line (console) executable no longer gets a Windows
Start Menu entry or default desktop shortcut, which only opened a console window, and a
`DESKTOP_LINKS` entry that names one is dropped with a configure warning (see
[Desktop shortcuts and launchers](#desktop-shortcuts-and-launchers)).

2.0.4 is one too: a package without a `VENDOR` names no publisher, where it showed CPack's default
"Humanity" as its Windows publisher and registry folder, and the one-click installer no longer
writes a `Software\<vendor>\<DISPLAY_NAME>` registry key that nothing read.

2.0.5 changes no behavior: the project moved to the tnt-music-studios organization, so its
recipe URL, its project-config submodule and its CI now point there.

2.1.0 changes what the one-click installer does on Windows, with nothing to change in a consuming
project: a package that holds a command-line tool adds its `bin` directory to the machine PATH (see
[Windows one-click installer](#windows-one-click-installer)), and a package with no Start Menu
entry no longer leaves a Start Menu folder holding only an Uninstall shortcut, which the one-click
installer no longer creates. The one-click installer is now a Unicode NSIS installer.

3.0.0 makes a project's package its own and one package per build tree a rule. What
`package_create()` records is keyed by the project, so nothing another project's call passed reaches
it, where every call in a build tree had shared one identity. A second `package_create()` in one
project and a second `package_install()` in one build tree are configure errors. The one-click
installer's *Apps & features* entry now carries `InstallLocation`, the install directory (see
[Create The Package](#create-the-package)).

Before 2.0.0, two minor releases broke existing builds:

- **1.6.0** renamed `package_write_version_resource()`, added in 1.5.0, to
  `package_write_resource_script()`, which also writes the target's icon; and on Linux it began
  installing the `.desktop` file of every executable, independent of `DESKTOP_LINKS`.
- **1.7.0** dropped the version from the Windows install directory and registry key (CPack's default
  `<PROJECT_NAME> <version>` became `[<VENDOR>\]<DISPLAY_NAME>`), made the ZIP and DEB packages honour
  the component list (they had shipped every component, `Development` included), and made a
  `PRIMARY_TARGET` that is not packaged a configure error. It also added a per-executable
  `MENU_LINKS`, which 2.0.0 removes.

1.8.0 broke only a configuration 1.7.0 had just made possible: a component list that packages a
target's `COMPONENT` must name `Runtime` too.

### Upgrading to 3.0.0

A project that calls `package_create()` and `package_install()` once each needs no change. Otherwise:

- A build tree that called `package_install()` more than once now fails to configure. Its packages
  were never separate: each installed every install rule of the tree. Configure each package in a
  build tree of its own, or guard a subproject's call with `PROJECT_IS_TOP_LEVEL` (see
  [Generate Package Install Logic](#generate-package-install-logic)).
- A project's package is its own: nothing another project's `package_create()` passed reaches it.
  A project that calls a PackageBuilder function now calls `package_create()` itself; one that
  relied on another project's call fails to configure, where its targets went to a registry no
  `package_install()` read and its resource scripts carried the other project's version.
- A second `package_create()` in one project is a configure error: pass every value to the one
  call.

### Upgrading to 2.0.0

From 1.7.x or 1.8.x:

- Pass Start Menu links to `package_create(MENU_LINKS ...)`. The per-executable `MENU_LINKS` is
  gone, and setting `CPACK_NSIS_MENU_LINKS` yourself is now a configure error.
- With MSVC, the [C++ runtime](#msvc-c-runtime) now ships in `Runtime`. Remove your own
  `include(InstallRequiredSystemLibraries)`, which would install the same files a second time, or
  set `CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP` to keep deploying the runtime yourself.
- The Debian maintainer is no longer always `<PROJECT_NAME> maintainers`: it is
  `CPACK_PACKAGE_CONTACT` or `CPACK_DEBIAN_PACKAGE_MAINTAINER` when set, else the package's
  `VENDOR`. A Linux package with none of the three now fails to build its DEB, so set
  `CPACK_PACKAGE_CONTACT` or pass `VENDOR` (see [Packaging Behavior](#packaging-behavior)).
- A `CPACK_PROJECT_CONFIG_FILE` you set now runs, after PackageBuilder's own; 1.7 and 1.8 silently
  replaced it.
- Nothing to do for the rest: a Linux configure warns about a `.desktop` file only when
  `LINUX_DESKTOP_FILE` names one that does not exist, and the classic-wizard uninstaller now removes
  the empty vendor folder as the one-click one does.

From 1.2.0, all of the above, and:

- **Windows install identity.** 1.2.0 installed to `Program Files\<PROJECT_NAME> <version>` under
  the registry key `<PROJECT_NAME> <version>`; 2.0.0 installs to
  `Program Files\[<VENDOR>\]<DISPLAY_NAME>` under `<DISPLAY_NAME>`. A repository that packages one
  command-line tool and passes no `DISPLAY_NAME` is named after the executable (see the tip under
  [Create The Package](#create-the-package)), so pass `DISPLAY_NAME`, and `VENDOR` if the publisher
  should own a folder. The registry key changed, so a 2.0.0 installer does not offer to remove an
  installation a 1.2.0 one made: uninstall that one once by hand.
- **Archive contents.** The ZIP and DEB packages carry only `Runtime` by default; under 1.2.0 they
  also carried `Development` (headers, static libraries, CMake package files). Set
  `PACKAGE_BUILDER_CPACK_COMPONENTS` to `Runtime Development` before `package_install()` to keep
  shipping them.
- **Windows version information.** Every executable `package_add_executable` creates now carries a
  `VERSIONINFO` resource (see [Add Targets](#add-targets)), so such a target must not also compile
  one of its own.
- **Linux launcher entries.** Every executable with a `.desktop` file installs it; under 1.2.0,
  `DESKTOP_LINKS` chose which did. `DESKTOP_LINKS` now governs Windows desktop shortcuts only.
