include_guard(GLOBAL)

include(CMakePackageConfigHelpers)
include(GNUInstallDirs)

# Fails fast if the current project has not called package_create() before other PackageBuilder
# entry points. Each project's package is its own, so another project's call does not count.
function(_package_check_initialized)
    get_property(package_initialized GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_CREATED)
    if(NOT package_initialized)
        message(FATAL_ERROR "package_create() must be called in project ${PROJECT_NAME} before all "
                            "other PackageBuilder functions.")
    endif()
endfunction()

# Converts caller-provided header root paths to absolute paths before storing them as install
# metadata.
function(_package_make_paths_absolute out_var)
    set(absolute_paths)
    foreach(path IN LISTS ARGN)
        get_filename_component(path "${path}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
        list(APPEND absolute_paths "${path}")
    endforeach()
    set(${out_var}
        "${absolute_paths}"
        PARENT_SCOPE)
endfunction()

# Records an existing target for install/export handling and optionally tracks public header roots
# for header installation. Accepts DISPLAY_NAME, ICON, LINUX_DESKTOP_FILE, LINUX_ICON_THEME_DIR,
# and COMPONENT to store per-target packaging metadata. This helper must not mutate target build
# settings.
function(_package_register_target_impl target)
    cmake_parse_arguments(
        PARSE_ARGV 1 PACKAGE_REGISTER ""
        "DISPLAY_NAME;ICON;LINUX_DESKTOP_FILE;LINUX_ICON_THEME_DIR;COMPONENT" "PUBLIC_HEADER_DIRS")

    if(NOT TARGET ${target})
        message(FATAL_ERROR "Target '${target}' does not exist and cannot be registered.")
    endif()

    # Every runtime target records its install component, Runtime unless COMPONENT names another,
    # so the consumer's own install rules can read it rather than restate it.
    _package_collect_runtime_targets(_runtime_target ${target})
    if(_runtime_target)
        if(NOT PACKAGE_REGISTER_COMPONENT)
            set(PACKAGE_REGISTER_COMPONENT Runtime)
        endif()
        set_target_properties(${target} PROPERTIES PACKAGE_BUILDER_COMPONENT
                                                   "${PACKAGE_REGISTER_COMPONENT}")
    elseif(PACKAGE_REGISTER_COMPONENT)
        message(FATAL_ERROR "Target '${target}' installs no runtime artifacts, "
                            "so it cannot take a COMPONENT.")
    endif()

    # External targets may already be fully configured, so registration only records packaging
    # metadata and must not mutate build properties such as include paths or sources.
    set_property(GLOBAL APPEND PROPERTY ${PROJECT_NAME}_TARGETS ${target})

    if(PACKAGE_REGISTER_PUBLIC_HEADER_DIRS)
        _package_make_paths_absolute(public_header_dirs ${PACKAGE_REGISTER_PUBLIC_HEADER_DIRS})
        set_property(GLOBAL APPEND PROPERTY ${PROJECT_NAME}_PUBLIC_HEADER_PATHS
                                            ${public_header_dirs})
    endif()

    if(PACKAGE_REGISTER_DISPLAY_NAME)
        set_target_properties(${target} PROPERTIES PACKAGE_BUILDER_DISPLAY_NAME
                                                   "${PACKAGE_REGISTER_DISPLAY_NAME}")
    endif()

    if(PACKAGE_REGISTER_ICON)
        _package_make_paths_absolute(_icon_abs "${PACKAGE_REGISTER_ICON}")
        set_target_properties(${target} PROPERTIES PACKAGE_BUILDER_ICON "${_icon_abs}")
    endif()

    if(PACKAGE_REGISTER_LINUX_DESKTOP_FILE)
        _package_make_paths_absolute(_desktop_abs "${PACKAGE_REGISTER_LINUX_DESKTOP_FILE}")
        set_target_properties(${target} PROPERTIES PACKAGE_BUILDER_LINUX_DESKTOP_FILE
                                                   "${_desktop_abs}")
    endif()

    if(PACKAGE_REGISTER_LINUX_ICON_THEME_DIR)
        _package_make_paths_absolute(_desktop_icon_dir_abs
                                     "${PACKAGE_REGISTER_LINUX_ICON_THEME_DIR}")
        set_target_properties(${target} PROPERTIES PACKAGE_BUILDER_LINUX_ICON_THEME_DIR
                                                   "${_desktop_icon_dir_abs}")
    endif()
endfunction()

# Filters a target list down to runtime-bearing targets that should contribute executable/shared
# artifacts to installers and runtime dependency collection.
function(_package_collect_runtime_targets out_var)
    set(runtime_targets)
    foreach(target IN LISTS ARGN)
        if(TARGET ${target})
            get_target_property(target_type ${target} TYPE)
            if(target_type STREQUAL "EXECUTABLE"
               OR target_type STREQUAL "SHARED_LIBRARY"
               OR target_type STREQUAL "MODULE_LIBRARY")
                list(APPEND runtime_targets ${target})
            endif()
        endif()
    endforeach()
    set(${out_var}
        "${runtime_targets}"
        PARENT_SCOPE)
endfunction()

# Returns the effective output name for a target: OUTPUT_NAME property if set, otherwise the target
# name itself.
function(_package_get_output_name out_var target)
    get_target_property(_name ${target} OUTPUT_NAME)
    if(NOT _name)
        set(_name "${target}")
    endif()
    set(${out_var}
        "${_name}"
        PARENT_SCOPE)
endfunction()

# Returns the shortcut label for a target: PACKAGE_BUILDER_DISPLAY_NAME property if set, otherwise
# the effective output name.
function(_package_get_shortcut_label out_var target)
    _package_get_output_name(_base ${target})
    get_target_property(_label ${target} PACKAGE_BUILDER_DISPLAY_NAME)
    if(NOT _label)
        set(_label "${_base}")
    endif()
    set(${out_var}
        "${_label}"
        PARENT_SCOPE)
endfunction()

# Validates that the project has the minimum metadata needed for packaging and records its package,
# once per project. Accepts optional package-level metadata: PRIMARY_TARGET designates the
# executable that represents the package's Windows identity (display name, installer icon, ARP
# icon); DISPLAY_NAME overrides the package name derived from PRIMARY_TARGET; ICON overrides the
# installer/ARP icon; DESKTOP_LINKS controls which GUI executables receive desktop shortcuts;
# MENU_LINKS adds Windows Start Menu links as <path> <label> pairs, the path relative to the install
# directory or a URL; VERSION overrides the package version, which defaults to PROJECT_VERSION, with
# that version plus a SemVer pre-release or build suffix (1.0.0-alpha); VENDOR names the publisher,
# which also becomes the parent folder of the Windows install directory.
function(package_create)
    cmake_parse_arguments(
        PARSE_ARGV 0 PACKAGE_CREATE "" "PRIMARY_TARGET;DISPLAY_NAME;ICON;VERSION;VENDOR"
        "DESKTOP_LINKS;MENU_LINKS")

    # A project describes one package, so it states its identity once.
    get_property(_package_created GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_CREATED)
    if(_package_created)
        message(FATAL_ERROR "package_create() was already called in project ${PROJECT_NAME}.")
    endif()

    list(LENGTH PACKAGE_CREATE_MENU_LINKS _menu_link_count)
    math(EXPR _menu_link_unpaired "${_menu_link_count} % 2")
    if(_menu_link_unpaired)
        message(FATAL_ERROR "package_create(MENU_LINKS) must be <path> <label> pairs: "
                            "${PACKAGE_CREATE_MENU_LINKS}")
    endif()

    # A project's package is its own: every package-level property is keyed by the project, as its
    # registered targets are, so nothing another project's package_create() passed reaches it.
    # DESKTOP_LINKS alone is set only when passed, since an empty list (no desktop shortcuts)
    # differs from none given (the PRIMARY_TARGET's).
    set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_MENU_LINKS "${PACKAGE_CREATE_MENU_LINKS}")
    set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_VENDOR "${PACKAGE_CREATE_VENDOR}")
    set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_PRIMARY_TARGET
                                 "${PACKAGE_CREATE_PRIMARY_TARGET}")
    set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_DISPLAY_NAME
                                 "${PACKAGE_CREATE_DISPLAY_NAME}")
    _package_make_paths_absolute(_icon_abs "${PACKAGE_CREATE_ICON}")
    set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_ICON "${_icon_abs}")
    if(DEFINED PACKAGE_CREATE_DESKTOP_LINKS)
        set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_DESKTOP_LINKS
                                     "${PACKAGE_CREATE_DESKTOP_LINKS}")
    endif()

    if(NOT PROJECT_VERSION)
        message(FATAL_ERROR "PROJECT_VERSION is not set. Add a VERSION to your project() call, "
                            "e.g. project(MyProject VERSION 1.0.0)")
    endif()

    # project() and the numeric platform version fields (VERSIONINFO's FILEVERSION, Apple plists)
    # accept integers only, so a suffixed package version must keep PROJECT_VERSION as its numeric
    # core: the installers and version text carry the whole string while everything numeric keeps
    # reading project().
    if(NOT PACKAGE_CREATE_VERSION)
        set(PACKAGE_CREATE_VERSION "${PROJECT_VERSION}")
    else()
        string(REPLACE "." "\\." _numeric_pattern "${PROJECT_VERSION}")
        if(NOT PACKAGE_CREATE_VERSION MATCHES
           "^${_numeric_pattern}(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$")
            message(
                FATAL_ERROR
                    "package_create(VERSION ${PACKAGE_CREATE_VERSION}) must be PROJECT_VERSION "
                    "(${PROJECT_VERSION}) plus an optional SemVer pre-release or build suffix.")
        endif()
    endif()
    set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_VERSION "${PACKAGE_CREATE_VERSION}")

    if(NOT PROJECT_DESCRIPTION)
        message(
            FATAL_ERROR "PROJECT_DESCRIPTION is not set. Add a DESCRIPTION to your project() call, "
                        "e.g. project(MyProject DESCRIPTION \"A short summary\")")
    endif()

    if(NOT EXISTS "${PROJECT_SOURCE_DIR}/LICENSE")
        message(
            FATAL_ERROR "A LICENSE file is required at ${PROJECT_SOURCE_DIR}/LICENSE for packaging."
        )
    endif()

    set_property(GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_CREATED TRUE)
endfunction()

# Registers a target created outside PackageBuilder so it participates in install/export/CPack
# generation.
function(package_register_target target)
    _package_check_initialized()
    # This is the low-level integration point for targets created outside PackageBuilder.
    _package_register_target_impl(${target} ${ARGN})
endfunction()

# Writes the Windows resource script of a registered target and returns its path in out_var: the
# version information, and the target's icon when one was registered. FILEVERSION and
# PRODUCTVERSION are four 16-bit integers, so they carry the numeric PROJECT_VERSION; the text
# Explorer shows carries the full package version and the target's display name.
# package_add_executable() compiles it into every executable it creates; a target whose own tooling
# writes its resource script (JUCE's juce_add_gui_app, through JUCE_USER_DEFINED_RC_FILE) can
# include it instead. Call it after the target is registered, so the display name and icon are
# known. The file is rewritten only when its content changes, so a configure does not relink the
# executable.
function(package_write_resource_script out_var target)
    _package_check_initialized()

    get_property(_package_version GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_VERSION)
    set(_numeric_version)
    foreach(_part IN ITEMS MAJOR MINOR PATCH TWEAK)
        if("${PROJECT_VERSION_${_part}}" STREQUAL "")
            list(APPEND _numeric_version 0)
        else()
            list(APPEND _numeric_version "${PROJECT_VERSION_${_part}}")
        endif()
    endforeach()
    list(JOIN _numeric_version "," _numeric_version)

    # A resource script string escapes a quote by doubling it.
    _package_get_shortcut_label(_display_name ${target})
    string(REPLACE "\"" "\"\"" _display_name "${_display_name}")

    string(
        CONCAT _rc_content
               "1 VERSIONINFO\n"
               "FILEVERSION ${_numeric_version}\n"
               "PRODUCTVERSION ${_numeric_version}\n"
               "FILEOS 0x40004\n" # VOS_NT_WINDOWS32
               "FILETYPE 0x1\n" # VFT_APP
               "BEGIN\n"
               "    BLOCK \"StringFileInfo\"\n"
               "    BEGIN\n"
               "        BLOCK \"040904B0\"\n"
               "        BEGIN\n"
               "            VALUE \"FileDescription\", \"${_display_name}\"\n"
               "            VALUE \"FileVersion\", \"${_package_version}\"\n"
               "            VALUE \"ProductName\", \"${_display_name}\"\n"
               "            VALUE \"ProductVersion\", \"${_package_version}\"\n"
               "        END\n"
               "    END\n"
               "    BLOCK \"VarFileInfo\"\n"
               "    BEGIN\n"
               "        VALUE \"Translation\", 0x409, 1200\n"
               "    END\n"
               "END\n")
    # Registration already made the icon path absolute. CMake learns a resource script's dependencies
    # by preprocessing it, so it records the files the script #includes and never one an ICON
    # statement names. The icon is therefore a configure dependency and its hash is written into the
    # script: a changed icon rewrites the script, which both kinds of consumer rebuild on, the one
    # that compiles it and the one that includes it.
    get_target_property(_icon ${target} PACKAGE_BUILDER_ICON)
    if(_icon)
        set_property(
            DIRECTORY
            APPEND
            PROPERTY CMAKE_CONFIGURE_DEPENDS "${_icon}")
        file(SHA256 "${_icon}" _icon_hash)
        string(APPEND _rc_content "// Icon SHA-256: ${_icon_hash}\n"
               "IDI_ICON1 ICON \"${_icon}\"\n")
    endif()
    set(_rc_file "${CMAKE_CURRENT_BINARY_DIR}/${target}_resources.rc")
    file(CONFIGURE OUTPUT "${_rc_file}" CONTENT "${_rc_content}" @ONLY)
    set(${out_var}
        "${_rc_file}"
        PARENT_SCOPE)
endfunction()

# Creates and registers an executable target using PackageBuilder's conventional private include
# defaults for application-style layouts. Accepts DISPLAY_NAME, ICON, LINUX_DESKTOP_FILE,
# LINUX_ICON_THEME_DIR, and COMPONENT as packaging metadata; all other arguments are forwarded to
# add_executable(): the sources, and WIN32 for a GUI executable. On Windows, PackageBuilder also
# compiles in the target's resource script (package_write_resource_script()): its version
# information and, when ICON is provided, that icon.
function(package_add_executable target)
    _package_check_initialized()

    set(_one_value_keywords DISPLAY_NAME ICON LINUX_DESKTOP_FILE LINUX_ICON_THEME_DIR COMPONENT)
    cmake_parse_arguments(PARSE_ARGV 1 PACKAGE_EXEC "" "${_one_value_keywords}" "")

    add_executable(${target} ${PACKAGE_EXEC_UNPARSED_ARGUMENTS})

    # Executables don't need a public header surface, but adding the project root keeps app-style
    # layouts working without extra include boilerplate.
    target_include_directories(
        ${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/include
                          ${CMAKE_CURRENT_SOURCE_DIR}/src)

    set(_register_args)
    foreach(_keyword ${_one_value_keywords})
        if(PACKAGE_EXEC_${_keyword})
            list(APPEND _register_args ${_keyword} ${PACKAGE_EXEC_${_keyword}})
        endif()
    endforeach()

    _package_register_target_impl(${target} ${_register_args})

    # Registered first, so the resource script carries the target's display name and icon.
    if(WIN32)
        package_write_resource_script(_rc_file ${target})
        target_sources(${target} PRIVATE "${_rc_file}")
    endif()
endfunction()

# Creates and registers a library target, wiring conventional public/private include paths and the
# default public header installation root.
function(package_add_library target)
    _package_check_initialized()

    add_library(${target} ${ARGN})

    target_include_directories(
        ${target}
        PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
               $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
        # The source-tree root is a build-time convenience only. Consumers still see just the
        # installed public include directory.
        PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/src)

    # Libraries created by PackageBuilder use the conventional include/ directory as installable
    # public headers without requiring a separate registration call.
    _package_register_target_impl(${target} PUBLIC_HEADER_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include)

    add_library(${PROJECT_NAME}::${target} ALIAS ${target})
endfunction()

# Generates install rules, package config files, and CPack configuration for all registered targets
# and public header roots in the current project.
#
# HOW CPack COMPONENTS WORK
# --------------------------
# CPack uses "components" to categorize install() rules. CPACK_COMPONENTS_ALL lists the components
# a package carries. NSIS honours that list on its own; the archive and DEB generators honour it
# only in component mode, and install every rule otherwise, so package_install() switches them to
# component mode with all listed components grouped into one package. Rules that belong to a
# component not listed are then excluded from every generated package.
#
# PackageBuilder defines two components. The Runtime component holds executables, macOS app bundles,
# shared libraries, the transitive runtime dependencies of every packaged target, and with MSVC the
# C++ runtime — everything an end user needs to run the application. The Development component
# holds static libraries, public headers, CMake exported target definitions, and generated package
# config files — everything needed to compile against this project as a library. A runtime target
# registered with COMPONENT <name> puts its runtime artifacts and its Linux launcher entry in that
# component instead of Runtime; its dependencies follow it there only while that component is not
# packaged.
#
# By default, CPACK_COMPONENTS_ALL is Runtime plus every registered COMPONENT, so generated
# installers ship what end users need. To choose the list, set PACKAGE_BUILDER_CPACK_COMPONENTS
# before calling package_install(): "Runtime Development" also ships development files, and leaving
# a COMPONENT out keeps that target's files out of every package while it still builds. A packaged
# target's runtime dependencies ship in Runtime, so a list that packages a COMPONENT must name
# Runtime too.
function(package_install)
    _package_check_initialized()

    get_property(targets GLOBAL PROPERTY ${PROJECT_NAME}_TARGETS)
    _package_collect_runtime_targets(runtime_targets ${targets})

    # The components the generated packages carry. The install rules below read the list too: a
    # packaged target's runtime dependencies go to Runtime.
    if(NOT DEFINED PACKAGE_BUILDER_CPACK_COMPONENTS)
        set(PACKAGE_BUILDER_CPACK_COMPONENTS Runtime)
        foreach(rt_target IN LISTS runtime_targets)
            get_target_property(_component ${rt_target} PACKAGE_BUILDER_COMPONENT)
            list(APPEND PACKAGE_BUILDER_CPACK_COMPONENTS ${_component})
        endforeach()
        list(REMOVE_DUPLICATES PACKAGE_BUILDER_CPACK_COMPONENTS)
    endif()

    # Set the install destination and namespace
    set(install_destination "${CMAKE_INSTALL_LIBDIR}/cmake/${PROJECT_NAME}")

    if(targets)
        # -------------------------------------------------------------------
        # Separate registered targets into two groups.
        #
        # Runtime targets (EXECUTABLE, SHARED_LIBRARY, MODULE_LIBRARY) each need their own
        # per-target install() call with a unique RUNTIME_DEPENDENCY_SET, explained in Group B.
        # Non-runtime targets (STATIC_LIBRARY, OBJECT_LIBRARY, INTERFACE_LIBRARY) share one
        # install() call with no dependency set, but still contribute to the export so
        # find_package() consumers can link against them.
        # -------------------------------------------------------------------
        set(non_runtime_targets ${targets})
        list(REMOVE_ITEM non_runtime_targets ${runtime_targets})

        # -------------------------------------------------------------------
        # Group A: Non-runtime targets (static/object/interface libraries).
        #
        # ARCHIVE installs the .a / .lib file into the Development component. INCLUDES DESTINATION
        # annotates the export entry with the public include path so downstream consumers get the
        # right INTERFACE_INCLUDE_DIRECTORIES from find_package() without needing a separate
        # target_include_directories().
        # -------------------------------------------------------------------
        if(non_runtime_targets)
            install(
                TARGETS ${non_runtime_targets}
                EXPORT ${PROJECT_NAME}Targets
                ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR} COMPONENT Development
                INCLUDES
                DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})
        endif()

        if(runtime_targets)
            # ---------------------------------------------------------------
            # Pre-build the exclude regex lists used by every runtime dependency set install. These
            # filters prevent bundling OS-provided libraries that are guaranteed to exist on the
            # target machine.
            #
            # PRE_EXCLUDE_REGEXES match against the unresolved dependency name (fast: no disk lookup
            # required).
            # ---------------------------------------------------------------
            set(_pre_exclude_regexes
                [=[api-ms-]=] # Windows API sets
                [=[ext-ms-]=] # Windows extension sets
                [=[kernel32\.dll]=]
                [=[ntdll\.dll]=]
                [=[libc\.so\.]=] # Linux glibc
                [=[libgcc_s\.so\.]=]
                [=[libm\.so\.]=]
                [=[libstdc\+\+\.so\.]=]
                [=[libpthread\.so\.]=] # no-op on glibc 2.34+ (merged into libc)
                [=[libdl\.so\.]=] # same
                [=[librt\.so\.]=] # same
                [=[ld-linux.*\.so\.]=] # dynamic linker
            )

            # POST_EXCLUDE_REGEXES match against the resolved absolute path (catch-all safety net
            # for paths that slipped past pre-exclude).
            set(_post_exclude_regexes
                [=[.*[/\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\][Ss][Yy][Ss][Tt][Ee][Mm]32[/\\].*]=]
                [=[^/lib]=] # Linux system libs
                [=[^/usr/lib]=] # Linux multiarch + macOS system libs
                [=[^/System/Library]=] # macOS system frameworks
            )

            foreach(rt_target IN LISTS runtime_targets)
                # -----------------------------------------------------------
                # Group B: Per-runtime-target install call.
                #
                # WHY ONE CALL PER TARGET? CMake's install(TARGETS ...) accepts exactly one
                # RUNTIME_DEPENDENCY_SET name per call. On macOS, a runtime dependency set may be
                # associated with at most one app bundle executable. If two bundle targets share one
                # set, CMake fails: "install A runtime dependency set may only have one bundle
                # executable"
                #
                # The fix is to give each runtime target its own uniquely named dependency set. All
                # per-target calls still contribute to the same EXPORT name — CMake merges them into
                # one targets file — so the exported package remains project-wide.
                #
                # Archive files (ARCHIVE) go to Development since they are only needed at link time.
                # App bundles (BUNDLE), shared library binaries (LIBRARY), and other executables
                # (RUNTIME) go to the target's component, Runtime unless it was registered with
                # COMPONENT. Shared library version symlinks (NAMELINK) go to Development since only
                # the compiler needs them.
                # -----------------------------------------------------------
                set(_dep_set "${PROJECT_NAME}_${rt_target}_RuntimeDeps")
                get_target_property(_component ${rt_target} PACKAGE_BUILDER_COMPONENT)

                install(
                    TARGETS ${rt_target} RUNTIME_DEPENDENCY_SET ${_dep_set}
                    EXPORT ${PROJECT_NAME}Targets
                    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR} COMPONENT Development
                    BUNDLE DESTINATION . COMPONENT ${_component}
                    INCLUDES
                    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
                    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
                            COMPONENT ${_component}
                            NAMELINK_COMPONENT Development
                    RESOURCE DESTINATION ${CMAKE_INSTALL_BINDIR} COMPONENT ${_component}
                    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR} COMPONENT ${_component})

                # -----------------------------------------------------------
                # Group C: Per-runtime-target dependency set install.
                #
                # Each RUNTIME_DEPENDENCY_SET declared in Group B must have a matching
                # install(RUNTIME_DEPENDENCY_SET ...) call. CMake resolves the transitive shared
                # library dependencies of the target at install time and copies them to DESTINATION,
                # applying the exclude filters to skip system-provided libraries.
                #
                # A packaged target's dependencies go to Runtime. CPack stages each component on its
                # own, so a library two packaged executables both need, left in each executable's
                # component, would be a file of both: written by two NSIS sections, and deleted
                # by either one's removal while the other still needs it. An unpackaged target's
                # dependencies stay in its own component, so none of them ship.
                # -----------------------------------------------------------
                set(_dependency_component ${_component})
                if(_component IN_LIST PACKAGE_BUILDER_CPACK_COMPONENTS)
                    if(NOT "Runtime" IN_LIST PACKAGE_BUILDER_CPACK_COMPONENTS)
                        message(
                            FATAL_ERROR
                                "PackageBuilder: '${rt_target}' is packaged in ${_component} and "
                                "its runtime dependencies ship in Runtime, which "
                                "PACKAGE_BUILDER_CPACK_COMPONENTS lacks: "
                                "${PACKAGE_BUILDER_CPACK_COMPONENTS}")
                    endif()
                    set(_dependency_component Runtime)
                endif()
                install(
                    RUNTIME_DEPENDENCY_SET
                    ${_dep_set}
                    DESTINATION
                    ${CMAKE_INSTALL_BINDIR}
                    COMPONENT
                    ${_dependency_component}
                    PRE_EXCLUDE_REGEXES
                    ${_pre_exclude_regexes}
                    POST_EXCLUDE_REGEXES
                    ${_post_exclude_regexes})
            endforeach()

            # -----------------------------------------------------------
            # The MSVC C++ runtime. A runtime target that links it dynamically (/MD, the default)
            # loads DLLs that Windows does not carry, and the dependency sets above cannot bundle
            # them: they exclude everything resolved from System32, where an installed
            # redistributable puts them. InstallRequiredSystemLibraries installs the
            # redistributable's whole C++ runtime set instead, so a newly used library feature never
            # needs a DLL the package lacks; the Universal CRT it builds on ships with Windows 10 and
            # later and stays out. Every runtime target shares it, so it is installed once, in
            # Runtime, beside the packaged targets' dependencies. A project that links the runtime
            # statically (/MT) or deploys it another way sets CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP,
            # which the module honours by installing nothing.
            # -----------------------------------------------------------
            if(MSVC)
                set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION ${CMAKE_INSTALL_BINDIR})
                set(CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT Runtime)
                include(InstallRequiredSystemLibraries)
            endif()
        endif()

        # Export metadata is a development artifact: it is the generated <ProjectName>Targets.cmake
        # file that downstream find_package() calls include to get target definitions. It must not
        # appear in runtime-only installers, so it is tagged COMPONENT Development.
        install(
            EXPORT ${PROJECT_NAME}Targets
            FILE ${PROJECT_NAME}Targets.cmake
            NAMESPACE ${PROJECT_NAME}::
            DESTINATION ${install_destination}
            COMPONENT Development)
    endif()

    # Public headers are consumed at compile time by downstream projects, not at runtime by end
    # users. Tag them Development so they stay out of release packages.
    get_property(public_header_paths GLOBAL PROPERTY ${PROJECT_NAME}_PUBLIC_HEADER_PATHS)
    foreach(public_header_path IN LISTS public_header_paths)
        install(
            DIRECTORY ${public_header_path}/
            DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
            COMPONENT Development
            FILES_MATCHING
            PATTERN "*.h*")
    endforeach()

    # Custom CMake modules (cmake/*.cmake) are consumed by downstream CMake projects via
    # CMAKE_MODULE_PATH after find_package(). They are build-system metadata, not runtime artifacts,
    # and belong in the Development component.
    install(
        DIRECTORY ${PROJECT_SOURCE_DIR}/cmake/
        DESTINATION ${install_destination}
        COMPONENT Development
        FILES_MATCHING
        PATTERN "*.cmake"
        PATTERN "*.in")

    # Generate a package configuration file
    set(config_content "@PACKAGE_INIT@\n")

    string(APPEND config_content
           "\nlist(APPEND CMAKE_MODULE_PATH \"\${CMAKE_CURRENT_LIST_DIR}\")\n")

    # Include targets file if we have targets installed
    if(targets)
        string(APPEND config_content
               "\ninclude(\${CMAKE_CURRENT_LIST_DIR}/${PROJECT_NAME}Targets.cmake)")
    endif()

    file(WRITE ${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake.in "${config_content}")
    configure_package_config_file(
        ${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake.in
        ${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake
        INSTALL_DESTINATION ${install_destination})

    # Generate a package version file. The absolute path avoids a subtle bug: write_basic_package_version_file
    # resolves relative paths against CMAKE_CURRENT_BINARY_DIR, which is the caller's binary dir
    # inside a function — not necessarily PROJECT_BINARY_DIR.
    write_basic_package_version_file(
        "${PROJECT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake"
        VERSION ${PROJECT_VERSION}
        COMPATIBILITY SameMajorVersion)

    # The generated Config and ConfigVersion files are consumed by find_package() in downstream
    # projects. They are CMake package metadata — development artifacts — and must not appear in
    # runtime-only release installers.
    install(
        FILES "${PROJECT_BINARY_DIR}/${PROJECT_NAME}Config.cmake"
              "${PROJECT_BINARY_DIR}/${PROJECT_NAME}ConfigVersion.cmake"
        DESTINATION ${install_destination}
        COMPONENT Development)

    # -------------------------------------------------------------------
    # CPack configuration
    #
    # CPack reads the CPACK_* variables set below and generates platform-native installers (ZIP,
    # NSIS, DEB, DragNDrop, etc.) from the install() rules defined above. Only install() rules whose
    # COMPONENT is listed in CPACK_COMPONENTS_ALL are included in the generated package.
    # -------------------------------------------------------------------
    # CPack's defaults read the top-level project's CMAKE_PROJECT_*; a package reads its own
    # PROJECT_*. CPack installs the package by running the install script of the project's binary
    # directory, which includes the scripts of the directories below it and no other, so a project
    # packages what its own directory installs; the component field ALL names CPACK_COMPONENTS_ALL
    # as the components to install. The configuration files are written beside that script.
    set(CPACK_PACKAGE_NAME "${PROJECT_NAME}")
    set(CPACK_PACKAGE_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}")
    set(CPACK_PACKAGE_VERSION_MINOR "${PROJECT_VERSION_MINOR}")
    set(CPACK_PACKAGE_VERSION_PATCH "${PROJECT_VERSION_PATCH}")
    set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PROJECT_DESCRIPTION}")
    set(CPACK_PACKAGE_HOMEPAGE_URL "${PROJECT_HOMEPAGE_URL}")
    set(CPACK_INSTALL_CMAKE_PROJECTS "${PROJECT_BINARY_DIR};${PROJECT_NAME};ALL;/")
    set(CPACK_OUTPUT_CONFIG_FILE "${PROJECT_BINARY_DIR}/CPackConfig.cmake")
    set(CPACK_SOURCE_OUTPUT_CONFIG_FILE "${PROJECT_BINARY_DIR}/CPackSourceConfig.cmake")

    get_property(_package_version GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_VERSION)
    get_property(_vendor GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_VENDOR)
    # Always set, so a package without a VENDOR names no publisher instead of CPack's default
    # "Humanity": the Windows Publisher entry is skipped when empty.
    set(CPACK_PACKAGE_VENDOR "${_vendor}")
    set(CPACK_PACKAGE_VERSION "${_package_version}")
    set(CPACK_RESOURCE_FILE_LICENSE "${PROJECT_SOURCE_DIR}/LICENSE")

    # Normalize system name: linux-x86_64, macos-arm64, windows-x86_64, etc.
    string(TOLOWER "${CMAKE_SYSTEM_NAME}" _os)
    if(_os STREQUAL "darwin")
        set(_os "macos")
    endif()
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _arch)
    if(_arch MATCHES "amd64")
        set(_arch "x86_64")
    elseif(_arch MATCHES "arm64|aarch64")
        set(_arch "arm64")
    endif()
    set(CPACK_SYSTEM_NAME "${_os}-${_arch}")
    set(CPACK_PACKAGE_FILE_NAME "${PROJECT_NAME}-${_package_version}-${_os}-${_arch}")

    if(NOT runtime_targets)
        message(
            STATUS
                "No runtime targets found for ${PROJECT_NAME}; skipping CPack package generation.")
        return()
    endif()

    # CPACK_COMPONENTS_ALL tells CPack which component buckets to include in the generated
    # installer. Only install() rules tagged with one of these components will be packaged.
    set(CPACK_COMPONENTS_ALL ${PACKAGE_BUILDER_CPACK_COMPONENTS})
    # Runtime holds the dependencies every packaged executable loads, so no installer may drop it.
    set(CPACK_COMPONENT_RUNTIME_REQUIRED TRUE)

    # The archive and DEB generators install every component unless they run in component mode;
    # grouping all listed components into one package keeps one package per generator, named
    # CPACK_PACKAGE_FILE_NAME as before. The project configuration file keeps the archives' top-level
    # directory, which component mode would drop. CPack reads only one such file, so a file the
    # caller named in CPACK_PROJECT_CONFIG_FILE moves to CPACK_PACKAGE_BUILDER_PROJECT_CONFIG_FILE,
    # which PackageBuilder's file includes after its own settings.
    set(CPACK_ARCHIVE_COMPONENT_INSTALL ON)
    set(CPACK_DEB_COMPONENT_INSTALL ON)
    set(CPACK_COMPONENTS_GROUPING ALL_COMPONENTS_IN_ONE)
    if(CPACK_PROJECT_CONFIG_FILE)
        set(CPACK_PACKAGE_BUILDER_PROJECT_CONFIG_FILE "${CPACK_PROJECT_CONFIG_FILE}")
    endif()
    set(CPACK_PROJECT_CONFIG_FILE
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/PackageBuilderCPackOptions.cmake")

    get_property(
        _desktop_links_defined GLOBAL
        PROPERTY ${PROJECT_NAME}_PACKAGE_DESKTOP_LINKS
        SET)
    get_property(_desktop_link_targets GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_DESKTOP_LINKS)

    if(WIN32)
        set(CPACK_GENERATOR "ZIP;NSIS")
        set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
        if(NOT DEFINED PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER)
            set(PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER ON)
        endif()
        # The bin directory as the installer spells it under $INSTDIR, for the shortcuts, the
        # installed icon and the PATH entry.
        string(REPLACE "/" "\\" CPACK_PACKAGE_BUILDER_NSIS_BINDIR "${CMAKE_INSTALL_BINDIR}")

        # -------------------------------------------------------------------
        # Collect packaged executables: those whose component is listed. An unlisted executable
        # ships in no package, so it takes no part in the package's identity or shortcuts.
        # -------------------------------------------------------------------
        set(_exe_targets)
        foreach(rt_target IN LISTS runtime_targets)
            get_target_property(_target_type ${rt_target} TYPE)
            get_target_property(_component ${rt_target} PACKAGE_BUILDER_COMPONENT)
            if(_target_type STREQUAL "EXECUTABLE" AND _component IN_LIST CPACK_COMPONENTS_ALL)
                list(APPEND _exe_targets ${rt_target})
            endif()
        endforeach()

        # -------------------------------------------------------------------
        # Resolve primary executable:
        # PRIMARY_TARGET is explicit and must be packaged; single-exe packages infer it
        # automatically. Multi-exe packages without PRIMARY_TARGET emit a warning.
        # -------------------------------------------------------------------
        get_property(_primary_target GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_PRIMARY_TARGET)
        if(_primary_target AND NOT _primary_target IN_LIST _exe_targets)
            message(
                FATAL_ERROR
                    "PackageBuilder: PRIMARY_TARGET '${_primary_target}' is not a packaged "
                    "executable. Register it, and list its component in "
                    "PACKAGE_BUILDER_CPACK_COMPONENTS when that list is set.")
        endif()
        if(NOT _primary_target)
            list(LENGTH _exe_targets _exe_count)
            if(_exe_count EQUAL 1)
                set(_primary_target "${_exe_targets}")
            elseif(_exe_count GREATER 1)
                message(
                    WARNING
                        "PackageBuilder: Multiple executables packaged but PRIMARY_TARGET is not set. "
                        "Package display name will fall back to PROJECT_NAME and icon fields will be "
                        "left unset. Call package_create(PRIMARY_TARGET <target>) to designate a "
                        "primary executable, or use DISPLAY_NAME and ICON to override explicitly.")
            endif()
        endif()

        # -------------------------------------------------------------------
        # Resolve package display name:
        # Explicit DISPLAY_NAME > PRIMARY_TARGET's display name > PROJECT_NAME
        # -------------------------------------------------------------------
        get_property(_pkg_display_name GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_DISPLAY_NAME)
        if(NOT _pkg_display_name AND _primary_target)
            _package_get_shortcut_label(_pkg_display_name ${_primary_target})
        endif()
        if(NOT _pkg_display_name)
            set(_pkg_display_name "${PROJECT_NAME}")
        endif()
        set(CPACK_NSIS_DISPLAY_NAME "${_pkg_display_name}")
        set(CPACK_NSIS_PACKAGE_NAME "${_pkg_display_name}")

        # The install directory ([<vendor>\]<display name>) and registry key (<display name>) carry
        # no version, so a new version installs over the last one rather than beside it.
        if(_vendor)
            set(CPACK_PACKAGE_INSTALL_DIRECTORY "${_vendor}\\${_pkg_display_name}")
        else()
            set(CPACK_PACKAGE_INSTALL_DIRECTORY "${_pkg_display_name}")
        endif()
        set(CPACK_PACKAGE_INSTALL_REGISTRY_KEY "${_pkg_display_name}")

        # -------------------------------------------------------------------
        # Resolve installer and ARP icons:
        # Package-level ICON overrides target-level icon. If PRIMARY_TARGET has no icon, leave
        # fields unset.
        # -------------------------------------------------------------------
        get_property(_pkg_icon GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_ICON)
        if(_pkg_icon)
            set(CPACK_NSIS_MUI_ICON "${_pkg_icon}")
            set(CPACK_NSIS_MUI_UNIICON "${_pkg_icon}")
            get_filename_component(_pkg_icon_filename "${_pkg_icon}" NAME)
            set(CPACK_NSIS_INSTALLED_ICON_NAME
                "${CPACK_PACKAGE_BUILDER_NSIS_BINDIR}\\${_pkg_icon_filename}")
            install(
                FILES "${_pkg_icon}"
                DESTINATION "${CMAKE_INSTALL_BINDIR}"
                COMPONENT Runtime)
        elseif(_primary_target)
            get_target_property(_primary_icon ${_primary_target} PACKAGE_BUILDER_ICON)
            if(_primary_icon)
                set(CPACK_NSIS_MUI_ICON "${_primary_icon}")
                set(CPACK_NSIS_MUI_UNIICON "${_primary_icon}")
                _package_get_output_name(_primary_output_name ${_primary_target})
                set(CPACK_NSIS_INSTALLED_ICON_NAME
                    "${CPACK_PACKAGE_BUILDER_NSIS_BINDIR}\\${_primary_output_name}.exe")
            endif()
        endif()

        # -------------------------------------------------------------------
        # Collect the packaged GUI executables, the only ones that get shortcuts. An executable
        # whose WIN32_EXECUTABLE is not true is a command-line tool: a shortcut would only open a
        # console window, so it gets none, as on Linux an executable without a .desktop file gets no
        # launcher entry. A generator expression cannot be evaluated here and
        # counts as true, the usual one keeping a console for Debug builds alone.
        # -------------------------------------------------------------------
        set(_gui_exe_targets)
        set(_has_command_line_tool OFF)
        foreach(rt_target IN LISTS _exe_targets)
            get_target_property(_win32_executable ${rt_target} WIN32_EXECUTABLE)
            if(_win32_executable)
                list(APPEND _gui_exe_targets ${rt_target})
            else()
                set(_has_command_line_tool ON)
            endif()
        endforeach()

        # -------------------------------------------------------------------
        # PATH: the one-click installer has no page to ask on, so the package decides. A
        # command-line tool is run by name from a console, so a package holding one adds its bin
        # directory to the machine PATH; a GUI-only package leaves PATH alone. The classic wizard's
        # options page lets the user choose.
        # -------------------------------------------------------------------
        if(PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER)
            set(CPACK_NSIS_MODIFY_PATH ${_has_command_line_tool})
        else()
            set(CPACK_NSIS_MODIFY_PATH ON)
        endif()

        # -------------------------------------------------------------------
        # Build the Start Menu: CPACK_PACKAGE_EXECUTABLES gives each packaged GUI executable an
        # entry (label = DISPLAY_NAME), and CPACK_NSIS_MENU_LINKS carries the package's MENU_LINKS
        # beside them. The uninstaller removes both. package_create(MENU_LINKS) is the one source of
        # the links, so a value the caller set itself would be dropped silently; it is an error
        # instead.
        # -------------------------------------------------------------------
        set(_cpack_executables)
        foreach(rt_target IN LISTS _gui_exe_targets)
            _package_get_output_name(_output_name ${rt_target})
            _package_get_shortcut_label(_label ${rt_target})
            list(APPEND _cpack_executables "${_output_name}" "${_label}")
        endforeach()

        if(DEFINED CPACK_NSIS_MENU_LINKS)
            message(
                FATAL_ERROR
                    "PackageBuilder: pass Start Menu links to package_create(MENU_LINKS) instead "
                    "of setting CPACK_NSIS_MENU_LINKS.")
        endif()
        get_property(CPACK_NSIS_MENU_LINKS GLOBAL PROPERTY ${PROJECT_NAME}_PACKAGE_MENU_LINKS)

        # -------------------------------------------------------------------
        # Resolve desktop shortcut targets:
        # DESKTOP_LINKS not set  → primary target only (if resolved and a GUI executable)
        # DESKTOP_LINKS empty    → no shortcuts
        # DESKTOP_LINKS <list>   → those targets whose component is listed; a listed command-line
        #                          tool gets none and draws a warning, since dropping it silently
        #                          would hide the change from a project that listed it
        # -------------------------------------------------------------------
        if(NOT _desktop_links_defined AND _primary_target IN_LIST _gui_exe_targets)
            set(_desktop_link_targets "${_primary_target}")
        endif()
        set(_cpack_desktop_links)
        set(_cpack_desktop_link_labels)
        foreach(_link_target IN LISTS _desktop_link_targets)
            get_target_property(_link_component ${_link_target} PACKAGE_BUILDER_COMPONENT)
            if(NOT _link_component IN_LIST CPACK_COMPONENTS_ALL)
                continue()
            endif()
            if(NOT _link_target IN_LIST _gui_exe_targets)
                message(
                    WARNING "PackageBuilder: DESKTOP_LINKS names '${_link_target}', which is a "
                            "command-line tool (its WIN32_EXECUTABLE is not true), so it gets no "
                            "desktop shortcut: one would only open a console window. Drop it from "
                            "DESKTOP_LINKS, or build it WIN32 if it is a GUI program.")
                continue()
            endif()
            _package_get_output_name(_output_name ${_link_target})
            _package_get_shortcut_label(_label ${_link_target})
            list(APPEND _cpack_desktop_links "${_output_name}")
            list(APPEND _cpack_desktop_link_labels "${_label}")
        endforeach()

        # -------------------------------------------------------------------
        # Wire up CPack shortcut variables:
        # One-click: inject CreateShortCut commands unconditionally.
        # Classic:   CPACK_CREATE_DESKTOP_LINKS drives the checkbox flow; .lnk names come from
        #            CPACK_PACKAGE_EXECUTABLES automatically.
        # -------------------------------------------------------------------
        set(CPACK_PACKAGE_EXECUTABLES ${_cpack_executables})
        if(PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER)
            foreach(_exe_name _label IN ZIP_LISTS _cpack_desktop_links _cpack_desktop_link_labels)
                string(APPEND CPACK_NSIS_CREATE_ICONS_EXTRA
                       "CreateShortCut \"$DESKTOP\\${_label}.lnk\""
                       " \"$INSTDIR\\${CPACK_PACKAGE_BUILDER_NSIS_BINDIR}\\${_exe_name}.exe\"\n  ")
                string(APPEND CPACK_NSIS_DELETE_ICONS_EXTRA
                       "Delete \"$DESKTOP\\${_label}.lnk\"\n  ")
            endforeach()
        else()
            set(CPACK_CREATE_DESKTOP_LINKS ${_cpack_desktop_links})
        endif()

        # -------------------------------------------------------------------
        # Remove the vendor folder once the vendor's last product is uninstalled. The one-click
        # template and CMake's classic one both run CPACK_NSIS_DELETE_ICONS_EXTRA after removing the
        # install directory, the only hook either places there, so the removal rides on it. RMDir
        # removes the folder only when it is empty, and the suffix check only where the installer
        # created it: the parent of a folder the user chose on the classic Directory page stays.
        # -------------------------------------------------------------------
        if(_vendor)
            set(_nsis_install_suffix "\\${CPACK_PACKAGE_INSTALL_DIRECTORY}")
            string(APPEND CPACK_NSIS_DELETE_ICONS_EXTRA "StrLen $0 \"${_nsis_install_suffix}\"\n  "
                   "StrCpy $0 \"$INSTDIR\" \"\" -$0\n  "
                   "StrCmp $0 \"${_nsis_install_suffix}\" 0 +2\n  " "  RMDir \"$INSTDIR\\..\"\n  ")
        endif()

        # -------------------------------------------------------------------
        # Choose the NSIS template by prepending directories to CMAKE_MODULE_PATH, where CPack's
        # NSIS generator looks before CMake's built-in template. Precedence (highest to lowest):
        #   1. PACKAGE_BUILDER_NSIS_TEMPLATE_DIR (caller override, in either mode)
        #   2. PackageBuilder's own cmake/NSIS/ directory (one-click mode only)
        #   3. CMake's built-in template (the classic wizard)
        #
        # CMAKE_CURRENT_FUNCTION_LIST_DIR resolves to the directory containing PackageBuilder.cmake
        # regardless of where package_install() is called from (requires CMake 3.17+). The
        # one-click template loads its NSIS plugins from the plugin directory beside it.
        # -------------------------------------------------------------------
        if(PACKAGE_BUILDER_WINDOWS_ONE_CLICK_INSTALLER)
            list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/NSIS")
            file(TO_NATIVE_PATH "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/NSIS/Plugins"
                 CPACK_PACKAGE_BUILDER_NSIS_PLUGIN_DIR)
        endif()
        if(DEFINED PACKAGE_BUILDER_NSIS_TEMPLATE_DIR)
            list(PREPEND CMAKE_MODULE_PATH "${PACKAGE_BUILDER_NSIS_TEMPLATE_DIR}")
        endif()
    elseif(APPLE)
        set(CPACK_GENERATOR "ZIP;DragNDrop")
        # macOS: DragNDrop bundles are self-contained; users drag .app to /Applications and
        # Launchpad handles discovery automatically. No desktop shortcut action needed.
    else()
        set(CPACK_GENERATOR "ZIP;DEB")
        # A Debian package must name a maintainer, which CPack takes from
        # CPACK_DEBIAN_PACKAGE_MAINTAINER, or else from CPACK_PACKAGE_CONTACT. Either one the
        # caller sets wins; without them the contact is the vendor. A package that names none of
        # the three fails with CPack's own error, which names both variables.
        if(NOT CPACK_PACKAGE_CONTACT AND _vendor)
            set(CPACK_PACKAGE_CONTACT "${_vendor}")
        endif()
        # dpkg reads '-' as the start of a Debian revision, which sorts AFTER the bare version;
        # '~' sorts before it, which is what a pre-release must do.
        string(REPLACE "-" "~" CPACK_DEBIAN_PACKAGE_VERSION "${_package_version}")

        # Install XDG .desktop files and icon theme assets for every executable that has them: the
        # launcher entry is the Linux Start Menu entry, which DESKTOP_LINKS (desktop shortcuts)
        # never governs. Uses the PACKAGE_BUILDER_LINUX_DESKTOP_FILE target property if set, and
        # warns when that file is missing; otherwise uses a <target>.desktop file in the same
        # directory as the target's CMakeLists.txt when there is one. An executable with neither is
        # a command-line tool, which has no launcher entry. Linux icon assets are installed from
        # LINUX_ICON_THEME_DIR, which is expected to contain a hicolor/... tree rooted at that
        # directory. Both ship in the executable's component, so they are packaged exactly when it
        # is.
        foreach(rt_target IN LISTS runtime_targets)
            get_target_property(_target_type ${rt_target} TYPE)
            if(_target_type STREQUAL "EXECUTABLE")
                get_target_property(_component ${rt_target} PACKAGE_BUILDER_COMPONENT)
                get_target_property(_desktop_file ${rt_target} PACKAGE_BUILDER_LINUX_DESKTOP_FILE)
                if(NOT _desktop_file)
                    get_target_property(_source_dir ${rt_target} SOURCE_DIR)
                    set(_desktop_file "")
                    if(EXISTS "${_source_dir}/${rt_target}.desktop")
                        set(_desktop_file "${_source_dir}/${rt_target}.desktop")
                    endif()
                endif()
                if(EXISTS "${_desktop_file}")
                    install(
                        FILES "${_desktop_file}"
                        DESTINATION "${CMAKE_INSTALL_DATADIR}/applications"
                        COMPONENT ${_component})
                elseif(_desktop_file)
                    message(
                        WARNING "PackageBuilder: The LINUX_DESKTOP_FILE of '${rt_target}' does not "
                                "exist at ${_desktop_file}. Skipping Linux desktop integration for "
                                "this target.")
                endif()

                get_target_property(_desktop_icon_dir ${rt_target}
                                    PACKAGE_BUILDER_LINUX_ICON_THEME_DIR)
                if(_desktop_icon_dir)
                    if(EXISTS "${_desktop_icon_dir}")
                        install(
                            DIRECTORY "${_desktop_icon_dir}/"
                            DESTINATION "${CMAKE_INSTALL_DATADIR}/icons"
                            COMPONENT ${_component}
                            FILES_MATCHING
                            PATTERN "*.png"
                            PATTERN "*.svg")
                    else()
                        message(
                            WARNING "PackageBuilder: Desktop icon directory for '${rt_target}' "
                                    "does not exist at ${_desktop_icon_dir}. Skipping Linux icon "
                                    "installation for this target.")
                    endif()
                endif()
            endif()
        endforeach()
    endif()

    # Ensure backslashes and other special characters in CPACK variable values are properly escaped
    # when written to CPackConfig.cmake. Without this, backslashes in paths (e.g. bin\appname) would
    # be interpreted as CMake escape sequences when the file is re-read, corrupting values.
    set(CPACK_VERBATIM_VARIABLES TRUE)

    include(CPack)
endfunction()
