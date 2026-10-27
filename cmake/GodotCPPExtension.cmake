#[=======================================================================[.rst:

GodotCPPExtension.cmake
-----------------------

消费端辅助模块：把扩展库产物命名与 ``.gdextension`` 声明收敛到一处。

``GodotCPPConfig.cmake`` 会自动加载本文件，消费端无需处理 ``CMAKE_MODULE_PATH``，
创建并链接扩展目标后直接调用::

    godotcpp_extension(my_extension)

完整参数::

    godotcpp_extension(<target>
        [NAME <name>]
        [OUTPUT_DIR <dir>]
        [ENTRY_SYMBOL <symbol>]
        [RELOADABLE <布尔值>]
        [COMPATIBILITY_MINIMUM <version>]
        [GODOT_PROJECT_DIR <dir>]
        [VARIANTS <platform|arch|extension>...]
    )

``NAME``
    扩展名，默认取 target 名。
``OUTPUT_DIR``
    输出根目录，默认 ``${PROJECT_SOURCE_DIR}/bin/<name>``。二进制按平台放入
    ``<OUTPUT_DIR>/<GodotCPP_PLATFORM>``。相对路径按调用处的当前源码目录解析。
``ENTRY_SYMBOL``
    ``.gdextension`` 的 ``entry_symbol``，默认 ``library_init``。
``RELOADABLE``
    ``.gdextension`` 的 ``reloadable`` 选项，按 CMake 布尔语义解析
    （``ON``/``OFF``、``TRUE``/``FALSE``、``YES``/``NO``、``1``/``0``），默认 ``OFF``。
``COMPATIBILITY_MINIMUM``
    ``compatibility_minimum``，默认取 ``GodotCPP_API_VERSION``。
``GODOT_PROJECT_DIR``
    给出时，构建完成后把 ``OUTPUT_DIR`` 复制到 ``<dir>/bin/<name>``。
    相对路径按调用处的``CMAKE_CURRENT_SOURCE_DIR``解析。
``VARIANTS``
    覆盖默认的库路径表，元素形如 ``platform|arch|extension``。默认覆盖
    windows / linux / android；需要 macOS、iOS、web 等平台时，传入完整表
    （例如 ``"macos|x86_64|dylib"``）。

结果变量（父作用域）::

    <target>_GDEXTENSION_FILE      生成的 .gdextension 路径
    <target>_GDEXTENSION_OUT_DIR   输出根目录

产物文件名由 ``GodotCPP_SUFFIX`` 决定，``.gdextension`` 内的路径由同一份规则
（``godotcpp_library_suffix``）生成，因此两者不会脱节。

``GODOTCPP_THREADS=OFF`` 时路径会带上 ``.nothreads`` 段；原生平台的 feature tag
里没有 ``nothreads``，因此同一个 ``.gdextension`` 只能指向其中一种线程配置的产物。

``GODOTCPP_TARGET=editor`` 时只生成 ``editor`` 条目；其余 target 生成
``debug`` / ``release`` 两条条目，编辑器会按 ``debug`` 命中 ``template_debug`` 产物。
]=======================================================================]

# include_guard 保证本文件被多次 include 时只定义一次函数。
# find_package(GodotCPP) 可能在多个子目录里被调用，函数只需要定义一次。
include_guard(GLOBAL)

# 本文件的主流程：
#   1. _godotcpp_extension_libraries() 生成 [libraries] 段文本；
#   2. godotcpp_extension() 设置扩展目标的输出目录与文件名；
#   3. 把文本交给 GodotCPPExtension.gdextension.in 生成 .gdextension；
#   4. 可选地在构建后把产物复制到 Godot 工程。
#
# 关键点：二进制文件名使用 GodotCPP_SUFFIX，.gdextension 里的路径使用
# godotcpp_library_suffix()。两者是同一套规则，所以不会出现“库叫一个名字、
# 声明里写另一个名字”的情况。


# --- _godotcpp_extension_libraries ---
# 私有辅助函数：把一个平台表转换成 .gdextension 的 [libraries] 段文本。
#
# 参数：
#   OUTVAR  输出变量名，函数结束时把文本写回调用者的这个变量
#   NAME    扩展名，用来拼 "./<平台>/<扩展名><后缀>.<扩展>"
#   ARGN    NAME 之后的平台表，每个元素形如 "platform|arch|extension"
#
# 这段文本必须跟着库文件名的后缀规则计算，手写模板无法保证长期一致。
function(_godotcpp_extension_libraries OUTVAR NAME)
    # ARGN 是 NAME 之后的所有参数。这里不加引号展开，让每个平台表项
    # 重新成为 CMake 列表的一个元素。
    set(_variants ${ARGN})

    # 没有传平台表时使用默认表。if() 里写变量名会自动取它的值；
    # 非空列表在这里视为真，空列表视为假。
    if(NOT _variants)
        # 默认覆盖原 hello_gdextension 模板的平台范围；其它平台由调用者
        # 通过 godotcpp_extension(... VARIANTS ...) 传入完整表。
        # 用 | 分隔三段，避免和 CMake 列表分隔符 ; 冲突。
        set(_variants
            "windows|x86_32|dll"
            "windows|x86_64|dll"
            "linux|x86_64|so"
            "linux|arm64|so"
            "linux|rv64|so"
            "android|x86_64|so"
            "android|arm64|so"
        )
    endif()

    # 逐行累积最终要写入模板的文本；换行符直接写在字符串里。
    set(_libraries "")
    # 记录上一个“平台.架构”分组，用来判断是否需要插入空行。
    set(_last_group "")

    # .gdextension 的 key 使用 feature tag：debug / release / editor。
    # 实际库文件名里的 target 段则是 template_debug / template_release / editor。
    #
    # editor 变体是特殊情况：它由 editor feature tag 命中，不存在 debug/release
    # 两条路径，所以只生成 editor 条目。其余 target 生成 debug/release 两条，
    # 编辑器按 debug 命中 template_debug，导出包按 release 命中 template_release。
    if(GodotCPP_TARGET STREQUAL "editor")
        set(_config_tags editor)
    else()
        set(_config_tags debug release)
    endif()

    # 遍历每个平台表项。
    foreach(_variant IN LISTS _variants)
        # 把 "windows|x86_64|dll" 拆成 CMake 列表 "windows;x86_64;dll"，
        # 存入 _variant_fields：平台、架构、扩展名三个字段。
        string(REPLACE "|" ";" _variant_fields "${_variant}")
        list(LENGTH _variant_fields _field_count)
        if(NOT _field_count EQUAL 3)
            message(FATAL_ERROR
                "godotcpp_extension: VARIANTS 元素 '${_variant}' 无效，"
                "应为 platform|arch|extension，例如 windows|x86_64|dll。")
        endif()
        # list(GET) 从 0 开始取三个字段：平台、架构、扩展名。
        list(GET _variant_fields 0 _platform)
        list(GET _variant_fields 1 _arch)
        list(GET _variant_fields 2 _extension)

        # 平台或架构变化时先插入空行；第一组前面不需要空行。
        if(NOT _last_group STREQUAL "" AND
                NOT _last_group STREQUAL "${_platform}.${_arch}")
            string(APPEND _libraries "\n")
        endif()
        set(_last_group "${_platform}.${_arch}")

        # 遍历 debug/release（或 editor）。
        foreach(_config_tag IN LISTS _config_tags)
            # key 里的 tag 叫 debug/release，文件名里的 target 叫
            # template_debug/template_release，这里做一次映射。
            if(_config_tag STREQUAL "debug")
                set(_target "template_debug")
            elseif(_config_tag STREQUAL "release")
                set(_target "template_release")
            else()
                set(_target "editor")
            endif()

            # 单精度和双精度都列出来：一个 .gdextension 可以同时声明两种精度的
            # 产物，Godot 会按当前运行的精度选择对应条目。
            foreach(_precision single double)
                # godotcpp_library_suffix() 读取的是这四个变量。
                # 这里临时改成“当前这一轮要枚举的组合”，让它算出正确后缀。
                # 函数作用域是独立的，这些赋值不会污染调用者。
                set(GODOTCPP_TARGET "${_target}")
                set(GODOTCPP_PRECISION "${_precision}")
                set(GODOTCPP_THREADS "${GodotCPP_THREADS}")
                set(GODOTCPP_DEV_BUILD "${GodotCPP_DEV_BUILD}")
                # 例：.windows.template_debug.double.x86_64
                godotcpp_library_suffix(_suffix "${_platform}" "${_arch}")

                # 拼一行声明，例如：
                # windows.x86_64.single.debug = "./windows/foo.windows.template_debug.x86_64.dll"
                #
                # 注意两边的写法不同：
                #   key   里的 single/double/debug/release 是 feature tag；
                #   路径里没有 single 段，double 则写成 .double，位置在 arch 之前。
                string(APPEND _libraries
                    "${_platform}.${_arch}.${_precision}.${_config_tag} = "
                    "\"./${_platform}/${NAME}${_suffix}.${_extension}\"\n")
            endforeach()
        endforeach()
    endforeach()

    # 函数里的变量默认只在函数内部可见；把结果写回调用者作用域。
    set(${OUTVAR} "${_libraries}" PARENT_SCOPE)
endfunction()


# --- godotcpp_extension ---
# 消费端入口。通常只需要传一个已经创建好的扩展 target：
#   godotcpp_extension(my_extension)
function(godotcpp_extension TARGET)
    # cmake_parse_arguments 把 TARGET 之后的参数分成三类：
    #   开关型：本函数没有
    #   单值型：NAME、OUTPUT_DIR、ENTRY_SYMBOL、RELOADABLE、
    #           COMPATIBILITY_MINIMUM、GODOT_PROJECT_DIR
    #   多值型：VARIANTS
    # PARSE_ARGV 1 表示从第 1 个参数开始解析，第 0 个是 TARGET。
    cmake_parse_arguments(PARSE_ARGV 1 _ext
        ""
        "NAME;OUTPUT_DIR;ENTRY_SYMBOL;RELOADABLE;COMPATIBILITY_MINIMUM;GODOT_PROJECT_DIR"
        "VARIANTS"
    )

    # 目标必须已经由消费端创建，本函数只负责改属性和生成文件。
    if(NOT TARGET "${TARGET}")
        message(FATAL_ERROR "godotcpp_extension: 目标 '${TARGET}' 不存在。")
    endif()
    # 把拼错的参数尽早暴露出来，而不是悄悄忽略。
    if(_ext_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR
            "godotcpp_extension: 无法识别的参数：${_ext_UNPARSED_ARGUMENTS}")
    endif()
    # RELOADABLE 是单值参数，必须跟 ON 或 OFF。
    if("RELOADABLE" IN_LIST _ext_KEYWORDS_MISSING_VALUES)
        message(FATAL_ERROR
            "godotcpp_extension: RELOADABLE 需要取值，例如 RELOADABLE ON。")
    endif()

    # 这些变量由 find_package(GodotCPP) 加载的变体文件提供。
    # ${${_fact}} 是双重展开：先得到变量名，再取该变量的值。
    foreach(_fact
            GodotCPP_API_VERSION
            GodotCPP_PLATFORM
            GodotCPP_SUFFIX
            GodotCPP_THREADS
            GodotCPP_DEV_BUILD)
        if(NOT DEFINED "${_fact}" OR "${${_fact}}" STREQUAL "")
            message(FATAL_ERROR
                "godotcpp_extension: 变量 ${_fact} 未设置，"
                "请先 find_package(GodotCPP CONFIG REQUIRED)。")
        endif()
    endforeach()
    # 后缀函数来自 GodotCPPPlatform.cmake，确认包配置确实已经加载。
    if(NOT COMMAND godotcpp_library_suffix)
        message(FATAL_ERROR
            "godotcpp_extension: 缺少 godotcpp_library_suffix()，"
            "GodotCPPPlatform.cmake 未加载。")
    endif()

    # 扩展名默认与 target 名一致，也可以通过 NAME 参数改成别的名字。
    set(_name "${_ext_NAME}")
    if(_name STREQUAL "")
        set(_name "${TARGET}")
    endif()

    # 输出根目录默认是 <工程源码>/bin/<扩展名>。
    # get_filename_component(... ABSOLUTE) 把相对路径按调用处的当前源码目录
    # 转成绝对路径，避免 configure_file 和 POST_BUILD 使用不同的相对基准。
    set(_out_dir "${_ext_OUTPUT_DIR}")
    if(_out_dir STREQUAL "")
        set(_out_dir "${PROJECT_SOURCE_DIR}/bin/${_name}")
    endif()
    get_filename_component(_out_dir "${_out_dir}" ABSOLUTE)

    # 输出目录属性支持生成器表达式。多配置生成器（VS、Xcode、Ninja Multi-Config）
    # 在目录值不含生成器表达式时会自动追加 /<CONFIG> 子目录，例如
    # windows/RelWithDebInfo/，导致 .gdextension 里的相对路径对不上。
    #
    # $<1:...> 是一个恒为真的生成器表达式，结果就是括号里的目录本身。
    # 它唯一的作用是让 CMake 认为“这里用了生成器表达式”，从而不再追加
    # 配置子目录。
    set(_platform_bin_dir "$<1:${_out_dir}/${GodotCPP_PLATFORM}>")

    # 三类产物目录分别对应：
    #   RUNTIME  Windows 的 .dll
    #   LIBRARY  Linux/macOS 的 .so/.dylib
    #   ARCHIVE  Windows 的导入库 .lib 和 .exp
    #
    # PREFIX "" 用来去掉 Unix 平台默认的 lib 前缀。
    # OUTPUT_NAME 拼接 GodotCPP_SUFFIX，得到带 feature tag 的文件名。
    set_target_properties(${TARGET} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${_platform_bin_dir}"
        LIBRARY_OUTPUT_DIRECTORY "${_platform_bin_dir}"
        ARCHIVE_OUTPUT_DIRECTORY "${_platform_bin_dir}"
        PREFIX ""
        OUTPUT_NAME "${_name}${GodotCPP_SUFFIX}"
    )

    # .gdextension 的 entry_symbol，默认是 Godot 约定的 library_init。
    set(_entry_symbol "${_ext_ENTRY_SYMBOL}")
    if(_entry_symbol STREQUAL "")
        set(_entry_symbol "library_init")
    endif()

    # compatibility_minimum 默认跟随预编译包的 API 版本。
    set(_compatibility_minimum "${_ext_COMPATIBILITY_MINIMUM}")
    if(_compatibility_minimum STREQUAL "")
        set(_compatibility_minimum "${GodotCPP_API_VERSION}")
    endif()

    # .gdextension 里需要的是 true/false 文本。
    # CMake 的 if() 已按标准布尔常量判断：ON/OFF、TRUE/FALSE、YES/NO、1/0。
    if(_ext_RELOADABLE)
        set(_reloadable "true")
    else()
        set(_reloadable "false")
    endif()

    # 生成 [libraries] 文本。这里不加引号展开 _ext_VARIANTS，
    # 让每个平台表项作为独立参数传给辅助函数。
    _godotcpp_extension_libraries(_libraries "${_name}" ${_ext_VARIANTS})

    # 下面这些变量供 configure_file 替换模板里的 @...@ 占位符。
    # 它们只存在于本次函数调用作用域，不会影响调用者的同名变量。
    set(GODOTCPP_EXTENSION_ENTRY_SYMBOL "${_entry_symbol}")
    set(GODOTCPP_EXTENSION_COMPATIBILITY_MINIMUM "${_compatibility_minimum}")
    set(GODOTCPP_EXTENSION_RELOADABLE "${_reloadable}")
    set(GODOTCPP_EXTENSION_LIBRARIES "${_libraries}")

    # .gdextension 在 CMake 配置阶段生成，不是构建阶段；输出目录必须先存在。
    # configure_file 的 @ONLY 表示只替换 @变量名@，不替换 ${变量名}。
    file(MAKE_DIRECTORY "${_out_dir}")
    configure_file(
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/GodotCPPExtension.gdextension.in"
        "${_out_dir}/${_name}.gdextension"
        @ONLY
    )

    # 可选步骤：把整个输出目录同步到 Godot 工程的 bin/<扩展名>/。
    # copy_directory 会复制 .gdextension 和所有平台子目录；重复执行是覆盖式复制。
    if(NOT "${_ext_GODOT_PROJECT_DIR}" STREQUAL "")
        get_filename_component(_project_dir "${_ext_GODOT_PROJECT_DIR}" ABSOLUTE)
        add_custom_command(TARGET ${TARGET} POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -E copy_directory
                "${_out_dir}" "${_project_dir}/bin/${_name}"
            COMMENT "复制 ${_name} 扩展产物到 ${_project_dir}/bin/${_name}"
            # VERBATIM 让 CMake 正确处理命令参数里的空格和特殊字符。
            VERBATIM
        )
    endif()

    # 先在当前作用域定义结果变量，便于下面的日志直接复用；再写入父作用域，
    # 供调用者读取。变量名带 target 前缀，多 target 工程不会互相覆盖。
    set(${TARGET}_GDEXTENSION_FILE "${_out_dir}/${_name}.gdextension")
    set(${TARGET}_GDEXTENSION_OUT_DIR "${_out_dir}")

    # 在配置输出中报告产物位置，便于确认路径与排查拷贝问题。
    message(STATUS "godotcpp_extension(${TARGET}):")
    message(STATUS "  GDExtension file: ${${TARGET}_GDEXTENSION_FILE}")
    message(STATUS "  Output directory: ${${TARGET}_GDEXTENSION_OUT_DIR}")
    message(STATUS "  Binary directory: ${${TARGET}_GDEXTENSION_OUT_DIR}/${GodotCPP_PLATFORM}")

    set(${TARGET}_GDEXTENSION_FILE "${${TARGET}_GDEXTENSION_FILE}" PARENT_SCOPE)
    set(${TARGET}_GDEXTENSION_OUT_DIR "${${TARGET}_GDEXTENSION_OUT_DIR}" PARENT_SCOPE)
endfunction()
