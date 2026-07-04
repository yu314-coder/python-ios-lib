# _build_config.py.in is converted into _build_config.py during the meson build process.

from __future__ import annotations


def build_config() -> dict[str, str]:
    """
    Return a dictionary containing build configuration settings.

    All dictionary keys and values are strings, for example ``False`` is
    returned as ``"False"``.

        .. versionadded:: 1.1.0
    """
    return dict(
        # Python settings
        python_version="3.14",
        python_install_dir=r"/opt/homebrew/lib/python3.14/site-packages/",
        python_path=r"/Volumes/D/OfflinAi/matplotlib_ios/buildenv/bin/python3",

        # Package versions
        contourpy_version="1.3.3",
        meson_version="1.10.1",
        mesonpy_version="0.20.0",
        pybind11_version="3.0.4",

        # Misc meson settings
        meson_backend="ninja",
        build_dir=r"/Volumes/D/OfflinAi/matplotlib_ios/src/contourpy-1.3.3/.mesonpy-v6xodsd3/lib/contourpy/util",
        source_dir=r"/Volumes/D/OfflinAi/matplotlib_ios/src/contourpy-1.3.3/lib/contourpy/util",
        cross_build="True",

        # Build options
        build_options=r"-Dbuildtype=release -Db_ndebug=if-release -Db_vscrt=md -Dvsenv=True --cross-file=/Volumes/D/OfflinAi/matplotlib_ios/ios-cross.ini --native-file=/Volumes/D/OfflinAi/matplotlib_ios/src/contourpy-1.3.3/.mesonpy-v6xodsd3/meson-python-native-file.ini",
        buildtype="release",
        cpp_std="c++17",
        debug="False",
        optimization="3",
        vsenv="True",
        b_ndebug="if-release",
        b_vscrt="from_buildtype",

        # C++ compiler
        compiler_name="clang",
        compiler_version="21.0.0",
        linker_id="ld64",
        compile_command="/Volumes/D/OfflinAi/Frameworks/Python.xcframework/ios-arm64/bin/arm64-apple-ios-clang++",

        # Host machine
        host_cpu="aarch64",
        host_cpu_family="aarch64",
        host_cpu_endian="little",
        host_cpu_system="darwin",

        # Build machine, same as host machine if not a cross_build
        build_cpu="aarch64",
        build_cpu_family="aarch64",
        build_cpu_endian="little",
        build_cpu_system="darwin",
    )
