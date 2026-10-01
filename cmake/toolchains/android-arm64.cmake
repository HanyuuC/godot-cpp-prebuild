#[=======================================================================[.rst:

android-arm64.cmake
-------------------

Android arm64 交叉编译工具链模板，转交给 NDK 自带的 android.toolchain.cmake。

godot-cpp 的 cmake/android.cmake 明确建议使用 NDK 提供的工具链文件，而不是 CMake
内建的 Android 流程，本文件遵循该建议。

NDK 位置取自 -DANDROID_NDK=<路径>，未提供时读 ANDROID_NDK 环境变量。

]=======================================================================]

if(NOT DEFINED ANDROID_NDK)
    if(DEFINED ENV{ANDROID_NDK})
        set(ANDROID_NDK "$ENV{ANDROID_NDK}")
    else()
        message(FATAL_ERROR
            "未找到 Android NDK。请设置 ANDROID_NDK 环境变量，或用 -DANDROID_NDK=<路径> 指定。")
    endif()
endif()

if(NOT EXISTS "${ANDROID_NDK}/build/cmake/android.toolchain.cmake")
    message(FATAL_ERROR "ANDROID_NDK='${ANDROID_NDK}' 下没有 build/cmake/android.toolchain.cmake。")
endif()

# 先给出 ABI 与 API level，NDK 工具链文件用 set(... CACHE ...) 读取，预置值优先。
set(ANDROID_ABI "arm64-v8a" CACHE STRING "Android ABI")
set(ANDROID_PLATFORM "android-24" CACHE STRING "Android API level")
set(ANDROID_STL "c++_static" CACHE STRING "Android C++ 标准库")

# NDK 工具链会设置 CMAKE_SYSTEM_NAME=Android、CMAKE_SYSTEM_PROCESSOR=aarch64。
include("${ANDROID_NDK}/build/cmake/android.toolchain.cmake")