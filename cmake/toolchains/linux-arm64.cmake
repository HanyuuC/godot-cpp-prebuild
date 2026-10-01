#[=======================================================================[.rst:

linux-arm64.cmake
-----------------

Linux arm64（aarch64）交叉编译工具链模板。

宿主为 Windows 时，Windows 原生环境不提供 aarch64-linux-gnu 工具链，需在 WSL2、
Docker 或 CI 中执行构建。工具链前缀可用 -DGODOTCPP_CROSS_PREFIX=<前缀> 覆盖。

]=======================================================================]

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(GODOTCPP_CROSS_PREFIX "aarch64-linux-gnu" CACHE STRING "交叉工具链前缀")

find_program(GODOTCPP_C_COMPILER "${GODOTCPP_CROSS_PREFIX}-gcc" REQUIRED)
find_program(GODOTCPP_CXX_COMPILER "${GODOTCPP_CROSS_PREFIX}-g++" REQUIRED)
find_program(GODOTCPP_AR "${GODOTCPP_CROSS_PREFIX}-ar" REQUIRED)
find_program(GODOTCPP_RANLIB "${GODOTCPP_CROSS_PREFIX}-ranlib" REQUIRED)

set(CMAKE_C_COMPILER "${GODOTCPP_C_COMPILER}")
set(CMAKE_CXX_COMPILER "${GODOTCPP_CXX_COMPILER}")
set(CMAKE_AR "${GODOTCPP_AR}")
set(CMAKE_RANLIB "${GODOTCPP_RANLIB}")

# 宿主程序（Python 等）用宿主侧，目标库与头文件只用目标系统侧。
set(CMAKE_FIND_ROOT_PATH "/usr/${GODOTCPP_CROSS_PREFIX}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)