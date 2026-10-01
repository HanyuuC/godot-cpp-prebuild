#[=======================================================================[.rst:

GodotCPPPlatform.cmake
----------------------

把 CMake 的平台/架构标识归一化成 Godot 的 platform token 与 arch 名，并复现
godot-cpp 的库文件名后缀拼装规则。

预编译工程与安装后的 GodotCPPConfig.cmake 共用这一份实现，因此构建侧与消费侧对
变体目录名、库文件后缀的理解始终一致。文件只依赖 CMake 内建变量，不依赖 godot-cpp
源码树，可以独立安装与迁移。

]=======================================================================]

# --- godotcpp_target_platform ---
# 归一化平台名，得到 Godot 的 platform token。
# 依据 CMAKE_SYSTEM_NAME 判断，交叉编译时该变量由工具链文件提供；取不到时回退主机平台。
function(godotcpp_target_platform OUTVAR)
    set(_system "${CMAKE_SYSTEM_NAME}")
    if(_system STREQUAL "")
        set(_system "${CMAKE_HOST_SYSTEM_NAME}")
    endif()

    if(_system STREQUAL "Windows" OR _system STREQUAL "MSYS")
        set(_platform "windows")
    elseif(_system STREQUAL "Linux")
        set(_platform "linux")
    elseif(_system STREQUAL "Darwin")
        set(_platform "macos")
    elseif(_system STREQUAL "Android")
        set(_platform "android")
    elseif(_system STREQUAL "iOS")
        set(_platform "ios")
    elseif(_system STREQUAL "Emscripten")
        set(_platform "web")
    else()
        string(TOLOWER "${_system}" _platform)
    endif()

    set(${OUTVAR} "${_platform}" PARENT_SCOPE)
endfunction()

# --- godotcpp_target_arch ---
# 归一化架构名，得到 Godot 的 arch 名（x86_64 / arm64 / ...）。
# Visual Studio 生成器的 CMAKE_SYSTEM_PROCESSOR 不可靠，优先读 CMAKE_VS_PLATFORM_NAME。
function(godotcpp_target_arch OUTVAR)
    # macOS 通用二进制
    if(DEFINED CMAKE_OSX_ARCHITECTURES)
        if("x86_64" IN_LIST CMAKE_OSX_ARCHITECTURES AND "arm64" IN_LIST CMAKE_OSX_ARCHITECTURES)
            set(${OUTVAR} "universal" PARENT_SCOPE)
            return()
        endif()
    endif()

    # Visual Studio 生成器
    if(DEFINED CMAKE_VS_PLATFORM_NAME)
        if(CMAKE_VS_PLATFORM_NAME STREQUAL "Win32")
            set(${OUTVAR} "x86_32" PARENT_SCOPE)
            return()
        elseif(CMAKE_VS_PLATFORM_NAME STREQUAL "x64")
            set(${OUTVAR} "x86_64" PARENT_SCOPE)
            return()
        elseif(CMAKE_VS_PLATFORM_NAME STREQUAL "ARM64")
            set(${OUTVAR} "arm64" PARENT_SCOPE)
            return()
        endif()
    endif()

    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _arch)
    if(_arch STREQUAL "")
        string(TOLOWER "${CMAKE_HOST_SYSTEM_PROCESSOR}" _arch)
    endif()

    # 已归一化的名字直接返回
    set(_known "x86_32;x86_64;arm32;arm64;rv64;ppc32;ppc64;wasm32")
    if(_arch IN_LIST _known)
        set(${OUTVAR} "${_arch}" PARENT_SCOPE)
        return()
    endif()

    # 常见别名
    set(_x86_64 "amd64;w64;x86-64")
    set(_x86_32 "x86;i386;i486;i586;i686")
    set(_arm64 "arm64v8;aarch64;armv8;armv8-a")
    set(_arm32 "armv7;armv7-a")
    set(_rv64 "rv;riscv;riscv64")

    if(_arch IN_LIST _x86_64)
        set(_arch "x86_64")
    elseif(_arch IN_LIST _x86_32)
        set(_arch "x86_32")
    elseif(_arch IN_LIST _arm64)
        set(_arch "arm64")
    elseif(_arch IN_LIST _arm32)
        set(_arch "arm32")
    elseif(_arch IN_LIST _rv64)
        set(_arch "rv64")
    endif()

    set(${OUTVAR} "${_arch}" PARENT_SCOPE)
endfunction()

# --- godotcpp_variant_key ---
# 变体目录的最后一段，由精度与线程两个轴组成：<precision>-<threads>
function(godotcpp_variant_key OUTVAR)
    if(GODOTCPP_THREADS)
        set(_threads "threads")
    else()
        set(_threads "nothreads")
    endif()

    set(${OUTVAR} "${GODOTCPP_PRECISION}-${_threads}" PARENT_SCOPE)
endfunction()

# --- godotcpp_variant_path ---
# 变体相对路径：<API>/<platform>-<arch>/<target>/<precision>-<threads>
# 安装侧作为 install() 的 DESTINATION，也是消费端定位变体的路径。
function(godotcpp_variant_path OUTVAR)
    godotcpp_target_platform(_platform)
    godotcpp_target_arch(_arch)
    godotcpp_variant_key(_key)

    set(${OUTVAR} "${GODOTCPP_API_VERSION}/${_platform}-${_arch}/${GODOTCPP_TARGET}/${_key}" PARENT_SCOPE)
endfunction()

# --- godotcpp_library_suffix ---
# 复现 godot-cpp 的库文件后缀构成：
#   .<platform>.<target>[.dev][.double].<arch>[.nothreads]
# 与 godot-cpp 的 cmake/godotcpp.cmake 中 GODOTCPP_SUFFIX 的组合顺序保持一致，
# 该后缀同时用于扩展产物命名，因此两端必须算出同一个值。
function(godotcpp_library_suffix OUTVAR PLATFORM ARCH)
    set(_suffix ".${PLATFORM}.${GODOTCPP_TARGET}")

    if(GODOTCPP_DEV_BUILD)
        string(APPEND _suffix ".dev")
    endif()
    if(GODOTCPP_PRECISION STREQUAL "double")
        string(APPEND _suffix ".double")
    endif()

    string(APPEND _suffix ".${ARCH}")

    if(NOT GODOTCPP_THREADS)
        string(APPEND _suffix ".nothreads")
    endif()

    set(${OUTVAR} "${_suffix}" PARENT_SCOPE)
endfunction()

# --- godotcpp_variant_list ---
# 列出包内已安装的变体（相对包根目录的路径），用于失败时给出可选项。
function(godotcpp_variant_list OUTVAR ROOT)
    file(GLOB _variants RELATIVE "${ROOT}" "${ROOT}/*/*/*/GodotCPPVariant.cmake")
    list(TRANSFORM _variants REPLACE "/GodotCPPVariant.cmake$" "")

    set(${OUTVAR} "${_variants}" PARENT_SCOPE)
endfunction()