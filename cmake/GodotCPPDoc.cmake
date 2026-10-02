#[=======================================================================[.rst:

GodotCPPDoc.cmake
-----------------

把扩展的 XML 文档编译成可内嵌进扩展库的 C++ 源文件，供 Godot 编辑器帮助面板显示。

GodotCPPConfig.cmake 会自动加载本文件，消费端无需处理 CMAKE_MODULE_PATH，直接::

    file(GLOB_RECURSE DOC_XML "${PROJECT_SOURCE_DIR}/doc_classes/*.xml")
    if(DOC_XML)
        target_doc_sources(my_extension "${DOC_XML}")
    endif()

与上游 GodotCPPModule.cmake 的差别：脚本随包安装，用
``CMAKE_CURRENT_FUNCTION_LIST_DIR`` 定位；Python 只在真正调用本函数时才查找，
因此没有文档目录的工程不需要安装 Python。

]=======================================================================]

function(target_doc_sources TARGET SOURCES)
    find_package(Python3 3.4 REQUIRED COMPONENTS Interpreter)

    set(_script_dir "${CMAKE_CURRENT_FUNCTION_LIST_DIR}")
    set(_script "${_script_dir}/doc_source_generator.py")
    set(_output "${CMAKE_CURRENT_BINARY_DIR}/gen/doc_source.cpp")
    get_filename_component(_output_dir "${_output}" DIRECTORY)
    file(MAKE_DIRECTORY "${_output_dir}")

    # 把 XML 路径列表转成 Python 列表字面量：每个元素加单引号，再用逗号连接。
    set(_py_sources "${SOURCES}")
    list(TRANSFORM _py_sources REPLACE "(.*\.xml)" "'\\1'")
    list(JOIN _py_sources "," _py_sources)

    # 一条 python -c 完成导入与调用，分号即为 Python 的语句分隔符。
    # -B 抑制字节码写入：工作目录是安装目录，不加会在里面留下 __pycache__。
    set(_py_script
        "from doc_source_generator import generate_doc_source;generate_doc_source('${_output}', [${_py_sources}])")

    add_custom_command(
        OUTPUT "${_output}"
        COMMAND "${Python3_EXECUTABLE}" "-B" "-c" "${_py_script}"
        VERBATIM
        WORKING_DIRECTORY "${_script_dir}"
        DEPENDS "${_script}" ${SOURCES}
        COMMENT "Generating doc source: ${_output}"
    )

    target_sources(${TARGET} PRIVATE "${_output}")
endfunction()