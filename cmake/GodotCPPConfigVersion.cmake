#[=======================================================================[.rst:

GodotCPPConfigVersion.cmake
---------------------------

``find_package(GodotCPP <版本>)`` 的版本匹配规则。

包版本就是 Godot API 版本，且直接取自包所在目录名（如 ``install/4.7``），
因此同一安装前缀下并存多个 API 版本时，各版本的版本文件互不覆盖。

]=======================================================================]

set(PACKAGE_VERSION "0.0.0")
get_filename_component(_godotcpp_api_dir "${CMAKE_CURRENT_LIST_DIR}" NAME)
if(_godotcpp_api_dir MATCHES "^[0-9]+(\\.[0-9]+)+$")
    set(PACKAGE_VERSION "${_godotcpp_api_dir}")
endif()

if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)
    set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
    set(PACKAGE_VERSION_COMPATIBLE TRUE)
    if(PACKAGE_VERSION VERSION_EQUAL PACKAGE_FIND_VERSION)
        set(PACKAGE_VERSION_EXACT TRUE)
    endif()
endif()