#[=======================================================================[.rst:

GodotCPPPrebuilt.cmake
----------------------

godot-cpp-prebuild 的构建侧逻辑：声明配置项、校验变体配置、把 godot-cpp 安装成
可被 ``find_package(GodotCPP)`` 发现的预编译包。

本文件与 GodotCPPPlatform.cmake 都只依赖 CMake 内建变量，不依赖调用者的目录作用域，
函数在任何位置调用都成立。

]=======================================================================]

# --- godotcpp_prebuilt_options ---
# 声明全部配置项。
#
# 这里刻意用 set(... CACHE ...) 逐个声明，而不是 option()：CMP0077 之下 option() 会
# 被同名普通变量屏蔽，行为不够可预期。逐个声明后，godot-cpp 自己的
# godotcpp_options() 会沿用同名的缓存条目，因此本工程声明的默认值即最终生效值。
function(godotcpp_prebuilt_options)
    godotcpp_prebuilt_root(_root)
    set(GODOTCPP_VENDOR_DIR "${_root}/godot-cpp" CACHE PATH
        "godot-cpp 源码目录（保持上游原样，不做修改）")

    # ---- 变体配置 ----
    # 前三项每取一个新值，install/ 下就多出一个可与之共存的目录。
    set(GODOTCPP_API_VERSION "" CACHE STRING
        "目标 Godot API 版本，对应 godot-cpp/gdextension/extension_api-<版本>.json")
    set(GODOTCPP_TARGET "template_debug" CACHE STRING
        "构建目标：template_debug（编辑器加载）| template_release（导出包加载）| editor")
    set_property(CACHE GODOTCPP_TARGET PROPERTY STRINGS "template_debug;template_release;editor")
    set(GODOTCPP_PRECISION "single" CACHE STRING
        "浮点精度：single | double。决定 real_t 的定义，与消费端 ABI 相关")
    set_property(CACHE GODOTCPP_PRECISION PROPERTY STRINGS "single;double")
    set(GODOTCPP_THREADS ON CACHE BOOL "启用多线程支持。GODOTCPP_THREADS=OFF 的产物带 .nothreads 段")

    godotcpp_prebuilt_validate()
endfunction()

# --- godotcpp_prebuilt_install ---
# 生成变体元数据、导出 GodotCPP::cpp 目标、安装头文件与静态库、安装包配置文件。
# 必须在 add_subdirectory(godot-cpp) 之后调用。
function(godotcpp_prebuilt_install)
    godotcpp_target_platform(_platform)
    godotcpp_target_arch(_arch)
    godotcpp_variant_key(_key)
    godotcpp_variant_path(_variant_rel)
    godotcpp_library_suffix(_suffix "${_platform}" "${_arch}")

    set(_api "${GODOTCPP_API_VERSION}")
    set(_vendor "${GODOTCPP_VENDOR_DIR}")
    set(_vendor_bin "${GODOTCPP_VENDOR_BINARY_DIR}")

    if(MSVC)
        set(_msvc_runtime "${CMAKE_MSVC_RUNTIME_LIBRARY}")
    else()
        set(_msvc_runtime "")
    endif()

    message(STATUS "godot-cpp 预编译变体：${_variant_rel}")
    message(STATUS "  平台/架构   : ${_platform} / ${_arch}")
    message(STATUS "  库文件后缀  : ${_suffix}")
    message(STATUS "  安装前缀    : ${CMAKE_INSTALL_PREFIX}")

    # ---- 变体元数据 ----
    configure_file(
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/GodotCPPVariant.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/GodotCPPVariant.cmake"
        @ONLY
    )

    # ---- 导出目标 ----
    # 上游的 add_library(godot::cpp ALIAS godot-cpp) 只在本工程内可用，
    # 安装侧通过 EXPORT_NAME 让消费端拿到 GodotCPP::cpp。
    set_target_properties(godot-cpp PROPERTIES EXPORT_NAME cpp)

    install(TARGETS godot-cpp
        EXPORT GodotCPPTargets
        ARCHIVE DESTINATION "${_variant_rel}/lib"
        # INCLUDES DESTINATION 会被写成 $<INSTALL_INTERFACE:>，相对安装前缀解析，
        # 而 GodotCPPTargets.cmake 位于变体目录内，相对安装前缀有 4 级子目录，_IMPORT_PREFIX 会回退到
        # 安装前缀，因此这里必须给出从安装前缀算起的完整相对路径。
        INCLUDES DESTINATION "${_variant_rel}/include"
    )

    install(EXPORT GodotCPPTargets
        NAMESPACE GodotCPP::
        FILE GodotCPPTargets.cmake
        DESTINATION "${_variant_rel}"
    )

    # ---- 头文件 ----
    # 静态头，随上游发布，与精度无关。整目录搬运而不按扩展名过滤：
    # 上游除 .hpp 外还有 math.compat.inc 这类被 include 的片段。
    install(DIRECTORY "${_vendor}/include/"
        DESTINATION "${_variant_rel}/include"
    )
    # 构建期由 Python 生成的头，内容随 API 版本与精度变化，必须随变体一起发布。
    install(DIRECTORY "${_vendor_bin}/gen/include/"
        DESTINATION "${_variant_rel}/include"
    )

    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/GodotCPPVariant.cmake"
        DESTINATION "${_variant_rel}"
    )

    # ---- 包配置文件 ----
    # 与变体目录同级，因此多个 API 版本共用同一个安装前缀也不会互相覆盖。
    install(FILES
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/GodotCPPConfig.cmake"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/GodotCPPConfigVersion.cmake"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/GodotCPPPlatform.cmake"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/GodotCPPDoc.cmake"
        "${_vendor}/doc_source_generator.py"
        DESTINATION "${_api}"
    )
endfunction()

# --- godotcpp_prebuilt_root ---
# 本工程根目录。由本文件所在目录（cmake/）的父目录得到，不读调用者作用域的变量，
# 因此函数在任意位置调用都指向同一个目录。
function(godotcpp_prebuilt_root OUTVAR)
    get_filename_component(_dir "${CMAKE_CURRENT_FUNCTION_LIST_DIR}" DIRECTORY)
    set(${OUTVAR} "${_dir}" PARENT_SCOPE)
endfunction()

# --- godotcpp_prebuilt_validate ---
# 尽早拦下拼错的取值，避免错误留到加载时才发现。
function(godotcpp_prebuilt_validate)
    if(NOT EXISTS "${GODOTCPP_VENDOR_DIR}/CMakeLists.txt")
        message(FATAL_ERROR
            "GODOTCPP_VENDOR_DIR='${GODOTCPP_VENDOR_DIR}' 不是有效的 godot-cpp 源码目录。")
    endif()

    # 可用 API 版本直接从 godot-cpp 自带的 gdextension 目录反推，godot-cpp 升级后自动跟随。
    file(GLOB _api_files
        RELATIVE "${GODOTCPP_VENDOR_DIR}/gdextension"
        "${GODOTCPP_VENDOR_DIR}/gdextension/extension_api-*.json"
    )
    list(TRANSFORM _api_files REPLACE "^extension_api-(.*)\\.json$" "\\1")
    list(TRANSFORM _api_files REPLACE "-" ".")

    if(GODOTCPP_API_VERSION STREQUAL "")
        message(FATAL_ERROR
            "GODOTCPP_API_VERSION 未设置。可用值：${_api_files}\n"
            "示例：cmake -S . -B build/x -DGODOTCPP_API_VERSION=4.7")
    elseif(NOT GODOTCPP_API_VERSION IN_LIST _api_files)
        message(FATAL_ERROR
            "GODOTCPP_API_VERSION='${GODOTCPP_API_VERSION}' 在 godot-cpp 中不存在。"
            "可用值：${_api_files}")
    endif()

    if(NOT GODOTCPP_TARGET MATCHES "^(template_debug|template_release|editor)$")
        message(FATAL_ERROR
            "GODOTCPP_TARGET='${GODOTCPP_TARGET}' 无效，只能是 template_debug、template_release 或 editor。")
    endif()

    if(NOT GODOTCPP_PRECISION MATCHES "^(single|double)$")
        message(FATAL_ERROR
            "GODOTCPP_PRECISION='${GODOTCPP_PRECISION}' 无效，只能是 single 或 double。")
    endif()

    # dev build 会让库文件名多出 .dev 段，而变体目录不含该信息，
    # dev 与非 dev 产物因此会安装到同一个目录里互相覆盖。
    if(GODOTCPP_DEV_BUILD)
        message(FATAL_ERROR
            "不支持 GODOTCPP_DEV_BUILD=ON：.dev 段无法体现在变体目录上，会与非 dev 产物互相覆盖。"
            "如需 dev 构建，请先把 dev 加入变体目录命名。")
    endif()
endfunction()