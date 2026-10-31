import re
import sys
import zipfile
from io import StringIO
from pathlib import Path

from conan import ConanFile
from conan.errors import ConanException
from conan.tools.cmake import CMake, cmake_layout


class CMakePackageBuilderTestConan(ConanFile):
    settings = "os", "compiler", "build_type", "arch"
    generators = "CMakeDeps", "CMakeToolchain"

    def requirements(self):
        self.requires(self.tested_reference_str)

    def layout(self):
        cmake_layout(self)

    def build(self):
        # The bare sample checks the configuration of a package whose package_create() passes no
        # argument and that holds the GUI app alone. The cache keeps every variable a configure
        # sets, so each configure sets it.
        cmake = CMake(self)
        cmake.configure(variables={"PACKAGE_BUILDER_TEST_BARE": "ON"})

        # The full sample names the GUI app as its PRIMARY_TARGET, so the configure must not warn
        # that the package lacks one; nor, on Linux, that the app or the command-line tool has no
        # .desktop file. CMake writes warnings to stderr, which is captured to check and then
        # passed through.
        stderr = StringIO()
        cmake.configure(variables={"PACKAGE_BUILDER_TEST_BARE": "OFF"}, stderr=stderr)
        sys.stderr.write(stderr.getvalue())
        if "PRIMARY_TARGET is not set" in stderr.getvalue():
            raise ConanException("The configure warned that the package lacks a PRIMARY_TARGET.")
        if "desktop integration" in stderr.getvalue():
            raise ConanException("The configure warned about a .desktop file.")
        cmake.build()

    # The configure checks the package configuration; this checks the archive CPack stages from
    # it: one file named CPACK_PACKAGE_FILE_NAME, holding the listed app and tool and not the
    # unlisted game, and with a dynamically linked MSVC runtime, that runtime beside them; and the
    # archive of the other project's package. On Windows it also compiles both packages' one-click
    # installers and checks the scripts they compiled.
    def test(self):
        self.run(f"cpack -G ZIP -C {self.settings.build_type}", cwd=self.build_folder)
        archives = list(Path(self.build_folder).glob("*.zip"))
        if len(archives) != 1 or not re.fullmatch(
            r"PackageBuilderTest-1\.0\.0-[a-z]+-[a-z0-9_]+\.zip", archives[0].name
        ):
            raise ConanException(f"Expected one PackageBuilderTest archive, found {archives}.")
        with zipfile.ZipFile(archives[0]) as archive:
            names = archive.namelist()
        if not any(re.search(r"bin/test-tool(\.exe)?$", name) for name in names):
            raise ConanException(f"The archive lacks the listed tool: {names}")
        if not any(re.search(r"bin/test-app(\.exe)?$", name) for name in names):
            raise ConanException(f"The archive lacks the listed app: {names}")
        if any("test-game" in name for name in names):
            raise ConanException(f"The archive holds the unlisted game: {names}")
        if (
            self.settings.compiler == "msvc"
            and self.settings.get_safe("compiler.runtime") == "dynamic"
        ):
            for runtime in ("msvcp140.dll", "vcruntime140.dll"):
                if not any(name.endswith(f"bin/{runtime}") for name in names):
                    raise ConanException(f"The archive lacks the C++ runtime's {runtime}: {names}")
        if self.settings.os == "Windows" and not any(
            name.endswith("bin/LICENSE.txt") for name in names
        ):
            raise ConanException(f"The archive lacks the licence: {names}")

        # A project packages what its own directory installs, the directories below it included.
        # The other project's package is the build tree's second, configured in its own binary
        # directory: it holds its app and nothing of the sample's, whose rules lie outside that
        # directory. The other project's directory lies inside the sample's, so the sample's
        # package holds the other's app too. Each configuration names its own package.
        other_folder = Path(self.build_folder) / "other_package"
        identities = []
        for folder in (Path(self.build_folder), other_folder):
            config = folder / "CPackConfig.cmake"
            if not config.is_file():
                raise ConanException(f"No package configuration at {config}.")
            variables = dict(
                re.findall(r'^set\((CPACK_\w+) "(.*)"\)$', config.read_text(), flags=re.MULTILINE)
            )
            identities.append(
                tuple(
                    variables.get(f"CPACK_PACKAGE_{key}") for key in ("NAME", "VENDOR", "VERSION")
                )
            )
        if identities != [
            ("PackageBuilderTest", "Test Vendor", "1.0.0"),
            ("PackageBuilderOtherTest", "Other Vendor", "2.0.0-other"),
        ]:
            raise ConanException(f"The packages carry the wrong identities: {identities}")
        if not any(re.search(r"bin/other-app(\.exe)?$", name) for name in names):
            raise ConanException(f"The sample's archive lacks the nested project's app: {names}")

        self.run(f"cpack -G ZIP -C {self.settings.build_type}", cwd=str(other_folder))
        other_archives = list(other_folder.glob("*.zip"))
        if len(other_archives) != 1 or not re.fullmatch(
            r"PackageBuilderOtherTest-2\.0\.0-other-[a-z]+-[a-z0-9_]+\.zip", other_archives[0].name
        ):
            raise ConanException(
                f"Expected one PackageBuilderOtherTest archive, found {other_archives}."
            )
        with zipfile.ZipFile(other_archives[0]) as archive:
            other_names = archive.namelist()
        if not any(re.search(r"bin/other-app(\.exe)?$", name) for name in other_names):
            raise ConanException(f"The other archive lacks its app: {other_names}")
        if any(re.search(r"test-(app|game|tool)", name) for name in other_names):
            raise ConanException(f"The other archive holds the sample's files: {other_names}")

        # Only makensis checks the one-click installer's template and the PATH plugin it loads, so
        # the test compiles the installers.
        if self.settings.os == "Windows":
            installer = self._compile_installer(Path(self.build_folder), "PackageBuilderTest-1.0.0")

            # The uninstall entry carries the install directory as InstallLocation, through which
            # another program finds the installation.
            if not re.search(
                r'Push "InstallLocation"\s+Push "\$INSTDIR"\s+Call ConditionalAddToRegistry',
                installer,
            ):
                raise ConanException("The installer writes no InstallLocation.")

            # The sample's licence needs no acceptance, so its installer shows no licence page. The
            # other project's requires acceptance, so its installer shows the page before the
            # install progress.
            if "!insertmacro MUI_PAGE_LICENSE" in installer:
                raise ConanException("The installer shows a licence page nothing requires.")
            other_installer = self._compile_installer(
                other_folder, "PackageBuilderOtherTest-2.0.0-other"
            )
            if not re.search(
                r"!insertmacro MUI_PAGE_LICENSE [^\n]*\s+!insertmacro MUI_PAGE_INSTFILES",
                other_installer,
            ):
                raise ConanException("The other installer shows no licence page before installing.")

        # No executable links a library the resolver keeps, so the archive cannot show where their
        # dependencies go; the install script names the component of each dependency rule. Each
        # top-level block of it is one rule, guarded by the component it belongs to. The listed
        # app's and tool's dependencies go to Runtime, and the unlisted game's stay in Game.
        script = (Path(self.build_folder) / "cmake_install.cmake").read_text()
        rules = re.split(r'^if\(CMAKE_INSTALL_COMPONENT STREQUAL "', script, flags=re.MULTILINE)
        dependency_components = {
            executable: {
                rule.split('"', 1)[0]
                for rule in rules[1:]
                if "GET_RUNTIME_DEPENDENCIES" in rule and executable in rule
            }
            for executable in ("test-app", "test-game", "test-tool")
        }
        if dependency_components != {
            "test-app": {"Runtime"},
            "test-game": {"Game"},
            "test-tool": {"Runtime"},
        }:
            raise ConanException(
                f"Dependency rules are in the wrong components: {dependency_components}"
            )

    # Compiles the NSIS installer of the package configured in folder, checks that it is the one
    # installer named file_name_prefix there, and returns the script makensis compiled.
    def _compile_installer(self, folder, file_name_prefix):
        self.run(f"cpack -G NSIS -C {self.settings.build_type}", cwd=str(folder))
        installers = list(folder.glob(f"{file_name_prefix}-*.exe"))
        if len(installers) != 1:
            raise ConanException(f"Expected one {file_name_prefix} installer, found {installers}.")
        scripts = list(folder.glob("_CPack_Packages/*/NSIS/project.nsi"))
        if len(scripts) != 1:
            raise ConanException(f"Expected one installer script in {folder}, found {scripts}.")
        return scripts[0].read_text()
