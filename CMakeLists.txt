cmake_minimum_required(VERSION 3.25)

#[=======================================================================[.rst:
godot-cpp-prebuild
==================

把 godot-cpp 编译成一组可长期共存、可整体迁移的预编译包，供多个 GDExtension
插件工程共用，避免每个插件工程各自重编译一次 godot-cpp。

产物布局（相对 ``CMAKE_INSTALL_PREFIX``，默认为 ``<本工程>/install``）::

    <API>/GodotCPPConfig.cmake                find_package(GodotCPP) 读取的包配置文件
    <API>/GodotCPPConfigVersion.cmake
    <API>/GodotCPPPlatform.cmake              平台归一化，构建侧与消费侧共用同一份实现
    <API>/GodotCPPDoc.cmake                   文档生成支持，定义 target_doc_sources()
    <API>/doc_source_generator.py
    <API>/<platform>-<arch>/<target>/<precision>-<withthreads|nothreads>/
        GodotCPPVariant.cmake                 记录本变体的配置项与工具链信息
        GodotCPPTargets.cmake                 导出的 GodotCPP::cpp 目标
        GodotCPPTargets-<config>.cmake
        include/                              静态头 + 构建期生成的绑定头
        lib/                                  godot-cpp 静态库

一个变体指这四组配置的一次具体取值：API 版本、平台与架构、target、精度与线程。
其中任何一项取新值就会多安装出一个新目录，因此任意多个配置天然共存、互不覆盖。
平台与架构由工具链决定，没有单独的开关可以手工指定。

构建与安装::

    cmake --workflow --preset windows-x86_64-debug     # 配置 + 构建 + 安装
    cmake --workflow --preset windows-x86_64-release

CMakePresets.json 为每个平台按 target 各备一个 preset；精度与线程沿用
GODOTCPP_PRECISION（single）与 GODOTCPP_THREADS（ON）的默认值，需要非默认组合时在
configure 时用 -D 追加，例如::

    cmake --preset windows-x86_64-debug "-DGODOTCPP_PRECISION=double"
    cmake --build --preset windows-x86_64-debug
    cmake --build --preset windows-x86_64-debug-install

消费端用法::

    set(GodotCPP_DIR "<本工程>/install/4.7" CACHE PATH "")
    find_package(GodotCPP CONFIG REQUIRED)
    target_link_libraries(my_extension PRIVATE GodotCPP::cpp)

]=======================================================================]

project(
    godot_cpp_prebuilt
    DESCRIPTION "Prebuilt godot-cpp packages for GDExtension projects."
    LANGUAGES CXX
)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(GodotCPPPlatform)
include(GodotCPPPrebuilt)

godotcpp_prebuilt_options()

find_package(Python3 3.4 REQUIRED COMPONENTS Interpreter)

# godot-cpp 保持上游原样，只作为普通子目录引入，不改动其源码与脚本。
set(GODOTCPP_VENDOR_BINARY_DIR "${CMAKE_BINARY_DIR}/godot-cpp")
add_subdirectory("${GODOTCPP_VENDOR_DIR}" "${GODOTCPP_VENDOR_BINARY_DIR}" SYSTEM)

# 上游把 godot-cpp 的 PDB 写到 ${CMAKE_SOURCE_DIR}/bin，把它收进构建目录，保持源码树干净。
set_target_properties(godot-cpp PROPERTIES PDB_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")

godotcpp_prebuilt_install()