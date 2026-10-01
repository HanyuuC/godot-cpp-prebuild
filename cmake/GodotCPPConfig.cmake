#[=======================================================================[.rst:

GodotCPPConfig.cmake
--------------------

godot-cpp 预编译包的入口，由 ``find_package(GodotCPP CONFIG)`` 加载。

定位::

    set(GodotCPP_DIR "<prebuild>/install/4.7" CACHE PATH "")
    find_package(GodotCPP CONFIG REQUIRED)

变体选择
--------

命名约定：``GODOTCPP_*``（全大写）是使用者在选变体，``GodotCPP_*`` 是包在报告事实。

* API 版本由 ``GodotCPP_DIR`` 指向的目录决定（例如 ``install/4.6`` 与 ``install/4.7``
  各自独立），也可以用 ``find_package(GodotCPP 4.7)`` 约束。
* 平台与架构由工具链推导，不提供手工开关，避免选中 ABI 不匹配的变体。
* 以下三项在多个已安装变体之间切换，未设置时取与 Godot 官方模板一致的默认值：

  - ``GODOTCPP_TARGET``     template_debug | template_release | editor（默认 template_debug）
  - ``GODOTCPP_PRECISION``  single | double（默认 single）
  - ``GODOTCPP_THREADS``    ON | OFF（默认 ON）

结果变量
--------

* ``GodotCPP_FOUND``        是否找到
* ``GodotCPP_API_VERSION``  包对应的 Godot API 版本，如 4.7，可直接用作
  .gdextension 的 ``compatibility_minimum``
* ``GodotCPP_VARIANT_DIR``  实际命中的变体目录
* ``GodotCPP_SUFFIX``       库文件名后缀，如 ``.windows.template_debug.x86_64``
* ``GodotCPP_PLATFORM`` / ``GodotCPP_ARCH`` / ``GodotCPP_TARGET`` /
  ``GodotCPP_PRECISION`` / ``GodotCPP_THREADS``  实际命中的变体坐标

导入目标
--------

``GodotCPP::cpp`` —— 静态库、头文件搜索路径，以及全部 ABI 相关编译宏与链接选项
（``GDEXTENSION``、``DEBUG_ENABLED``、``THREADS_ENABLED``、``REAL_T_IS_DOUBLE``、
``WINDOWS_ENABLED``、``NOMINMAX``、Linux 上的 ``-static-libgcc -static-libstdc++`` 等）。
同时兼容按目标属性读取：``GODOTCPP_PLATFORM`` / ``GODOTCPP_TARGET`` /
``GODOTCPP_ARCH`` / ``GODOTCPP_PRECISION`` / ``GODOTCPP_SUFFIX``。

另外本文件会加载 ``GodotCPPDoc.cmake``，因此在消费端可直接调用
``target_doc_sources(<target> <xml 列表>)`` 生成编辑器内嵌文档。

]=======================================================================]

if(TARGET GodotCPP::cpp)
    set(GodotCPP_FOUND TRUE)
    return()
endif()

include("${CMAKE_CURRENT_LIST_DIR}/GodotCPPPlatform.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/GodotCPPDoc.cmake")

# ---- 1. 解析变体坐标 ----
godotcpp_target_platform(_platform)
godotcpp_target_arch(_arch)

if(NOT DEFINED GODOTCPP_TARGET OR GODOTCPP_TARGET STREQUAL "")
    set(GODOTCPP_TARGET "template_debug")
endif()
if(NOT DEFINED GODOTCPP_PRECISION OR GODOTCPP_PRECISION STREQUAL "")
    set(GODOTCPP_PRECISION "single")
endif()
if(NOT DEFINED GODOTCPP_THREADS OR GODOTCPP_THREADS STREQUAL "")
    set(GODOTCPP_THREADS ON)
endif()

if(GODOTCPP_THREADS)
    set(_threads "threads")
else()
    set(_threads "nothreads")
endif()

set(GodotCPP_VARIANT_DIR
    "${CMAKE_CURRENT_LIST_DIR}/${_platform}-${_arch}/${GODOTCPP_TARGET}/${GODOTCPP_PRECISION}-${_threads}")

# ---- 2. 命中检查 ----
if(NOT EXISTS "${GodotCPP_VARIANT_DIR}/GodotCPPVariant.cmake"
        OR NOT EXISTS "${GodotCPP_VARIANT_DIR}/GodotCPPTargets.cmake")
    godotcpp_variant_list(_available "${CMAKE_CURRENT_LIST_DIR}")
    string(REPLACE ";" "\n    " _available "${_available}")
    if(_available STREQUAL "")
        set(_available "<无，install 目录尚未安装任何变体>")
    endif()

    set(GodotCPP_FOUND FALSE)
    set(GodotCPP_NOT_FOUND_MESSAGE
        "预编译包中没有 ${_platform}-${_arch}/${GODOTCPP_TARGET}/${GODOTCPP_PRECISION}-${_threads} 变体。\n"
        "已安装的变体：\n    ${_available}\n"
        "补齐方式：在 godot-cpp-prebuild 中用对应的 CMakePreset 构建并安装。")
    return()
endif()

include("${GodotCPP_VARIANT_DIR}/GodotCPPVariant.cmake")
include("${GodotCPP_VARIANT_DIR}/GodotCPPTargets.cmake")

# ---- 3. 一致性检查 ----
if(GodotCPP_COMPILER_ID AND NOT GodotCPP_COMPILER_ID STREQUAL CMAKE_CXX_COMPILER_ID)
    message(WARNING
        "godot-cpp 预编译包由 ${GodotCPP_COMPILER_ID} ${GodotCPP_COMPILER_VERSION} 构建，"
        "当前工程使用 ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}。"
        "静态链接要求两者 ABI 兼容，请确认这一点。")
endif()

# MSVC 运行库不是可选项：godot-cpp 默认把 C/C++ 运行库静态链接（/MT），
# 而 CMake 对未显式设置的工程默认给 /MD，两者混用会在链接期报 LNK2038。
# 消费端通常不会自己设置这一项，这里替它补上与预编译包一致的取值。
if(GodotCPP_MSVC_RUNTIME_LIBRARY)
    if(NOT CMAKE_MSVC_RUNTIME_LIBRARY)
        set(CMAKE_MSVC_RUNTIME_LIBRARY "${GodotCPP_MSVC_RUNTIME_LIBRARY}" CACHE STRING
            "MSVC 运行库。由 GodotCPP 预编译包写入，与 godot-cpp 保持一致")
    elseif(NOT CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL GodotCPP_MSVC_RUNTIME_LIBRARY)
        message(WARNING
            "MSVC 运行库不一致：godot-cpp 预编译包为 '${GodotCPP_MSVC_RUNTIME_LIBRARY}'，"
            "当前工程为 '${CMAKE_MSVC_RUNTIME_LIBRARY}'。\n"
            "静态链接要求两者相同，否则链接期报 LNK2038；"
            "请移除对 CMAKE_MSVC_RUNTIME_LIBRARY 的设置以沿用预编译包的取值。")
    endif()
endif()

# ---- 4. 回填目标属性 ----
# godot::cpp 时代按目标属性读取的做法在这里继续可用。
set_target_properties(GodotCPP::cpp PROPERTIES
    GODOTCPP_PLATFORM "${GodotCPP_PLATFORM}"
    GODOTCPP_TARGET "${GodotCPP_TARGET}"
    GODOTCPP_ARCH "${GodotCPP_ARCH}"
    GODOTCPP_PRECISION "${GodotCPP_PRECISION}"
    GODOTCPP_SUFFIX "${GodotCPP_SUFFIX}"
)

set(GodotCPP_FOUND TRUE)