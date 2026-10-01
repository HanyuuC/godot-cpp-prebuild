# godot-cpp-prebuild

把 [godot-cpp](https://github.com/godotengine/godot-cpp) 编译成一组预编译包，供多个 GDExtension 插件工程共用。

## 解决的问题

GDExtension 工程通常把 godot-cpp 作为子目录引入，于是每建一个新插件工程，就要把上千个绑定翻译单元重编一遍。本工程把 godot-cpp 独立编译、按变体安装，插件工程改为链接已编译好的静态库，godot-cpp 只在升级 API 版本或换变体时重编。

- godot-cpp 源码保持上游原样，不改动任何文件与脚本，升级时直接替换目录即可
- 每个变体落在独立目录里，多个配置可以在同一安装前缀下长期共存、互不覆盖

## 产物布局

安装前缀默认是 `<本工程>/install`。

```
install/
└── 4.7/                                          API 版本，GodotCPP_DIR 指向这一层
    ├── GodotCPPConfig.cmake                      find_package(GodotCPP) 的落点
    ├── GodotCPPConfigVersion.cmake
    ├── GodotCPPPlatform.cmake                    平台归一化，构建侧与消费侧共用
    ├── GodotCPPDoc.cmake                         提供 target_doc_sources()
    ├── doc_source_generator.py
    └── windows-x86_64/                           平台-架构
        ├── template_debug/                       target
        │   └── single-threads/                   精度-线程
        │       ├── GodotCPPVariant.cmake         本变体的坐标与工具链信息
        │       ├── GodotCPPTargets.cmake         导出的 GodotCPP::cpp 目标
        │       └── lib/  include/
        └── template_release/
            └── single-threads/
```

一个变体由四组配置确定：API 版本、平台与架构、target、精度与线程。任何一轴取新值就落在新目录，因此新增配置是纯加法，已有的变体不受影响。

## 快速开始

在 Windows x64 上构建并安装全部常用变体：

```bash
cmake --workflow --preset windows-x86_64-debug
cmake --workflow --preset windows-x86_64-release
```

每个 workflow preset 依次完成配置、构建、安装三步。查看可用的 preset：

```bash
cmake --list-presets=all
```

### 非默认变体

preset 只按平台和 target 铺开，精度与线程沿用默认值 `single` 和 `ON`。需要其它组合时改用三命令形式，configure 阶段追加 `-D`：

```bash
cmake --preset windows-x86_64-debug "-DGODOTCPP_PRECISION=double"
cmake --build --preset windows-x86_64-debug
cmake --build --preset windows-x86_64-debug-install
```

装出来的新变体落在 `install/4.7/windows-x86_64/template_debug/double-threads/`，与既有的 `single-threads` 并存。

## 构建侧配置项

- `GODOTCPP_VENDOR_DIR` — godot-cpp 源码目录，默认 `<本工程>/godot-cpp`
- `GODOTCPP_API_VERSION` — 目标 Godot API 版本，取值需对应 `godot-cpp/gdextension/extension_api-<版本>.json`；配置期会对照该目录反推可用版本，拼错立即报错
- `GODOTCPP_TARGET` — `template_debug`（编辑器加载）| `template_release`（导出包加载）| `editor`
- `GODOTCPP_PRECISION` — `single` | `double`，决定 `real_t` 的定义，与消费端 ABI 相关
- `GODOTCPP_THREADS` — 默认 `ON`；置 `OFF` 的产物文件名带 `.nothreads` 段
- `GODOTCPP_DEV_BUILD` — 配置期拒绝 `ON`。`.dev` 段没有体现在变体目录上，dev 与非 dev 产物会落进同一目录互相覆盖；要支持需先把 dev 加进变体坐标

平台与架构由工具链决定，不提供手工开关，避免选出与当前工具链 ABI 不匹配的变体。Visual Studio 生成器读 `CMAKE_VS_PLATFORM_NAME`，其余读 `CMAKE_SYSTEM_NAME` 与 `CMAKE_SYSTEM_PROCESSOR`。

## 消费端接入

在插件工程的 `CMakeLists.txt` 中：

```cmake
set(GODOTCPP_TARGET "template_debug" CACHE STRING "构建目标")
set(GODOTCPP_PRECISION "single" CACHE STRING "浮点精度")
set(GODOTCPP_THREADS ON CACHE BOOL "多线程支持")

set(GodotCPP_DIR "<godot-cpp-prebuild>/install/4.7" CACHE PATH "预编译包目录")
find_package(GodotCPP CONFIG REQUIRED)

target_link_libraries(my_extension PRIVATE GodotCPP::cpp)
```

平台与架构同样由工具链推导，交叉编译时通过 `CMAKE_TOOLCHAIN_FILE` 指定即可。

### 包提供的目标与变量

- `GodotCPP::cpp` — 静态库、头文件搜索路径，以及全部 ABI 相关编译宏与链接选项
- `GodotCPP_API_VERSION` — API 版本，可直接用作 `.gdextension` 的 `compatibility_minimum`
- `GodotCPP_PLATFORM` — 目标平台名，如 `windows`
- `GodotCPP_SUFFIX` — 库文件名后缀，如 `.windows.template_debug.x86_64`，用它拼装扩展库文件名即可与 `.gdextension` 里的路径声明一致
- `GodotCPP_ARCH` / `GodotCPP_TARGET` / `GodotCPP_PRECISION` / `GodotCPP_THREADS` — 实际命中的变体坐标
- `GodotCPP_VARIANT_DIR` — 实际命中的变体目录

同样的信息也回填在 `GodotCPP::cpp` 的目标属性上（`GODOTCPP_SUFFIX`、`GODOTCPP_PLATFORM` 等）。

命名约定：`GODOTCPP_*`（全大写）是使用者传入的选择，`GodotCPP_*` 是包回报的事实。

### 变体命中失败

`find_package` 会列出该安装前缀下实际可用的变体：

```
预编译包中没有 windows-x86_64/template_debug/double-threads 变体。
已安装的变体：
    windows-x86_64/template_debug/single-threads
补齐方式：在 godot-cpp-prebuild 中用对应的 CMakePreset 构建并安装。
```

### MSVC 运行库

godot-cpp 默认把 C/C++ 运行库静态链接，解析为 `/MT`，而 CMake 对未显式设置的工程给 `/MD`，两者混用会在链接期报 LNK2038。`GodotCPPConfig.cmake` 会把预编译包的取值写进消费端的 `CMAKE_MSVC_RUNTIME_LIBRARY` 缓存项；如果工程自行设置过且取值不同，配置期会给出告警。

### 内嵌文档

包已加载 `GodotCPPDoc.cmake`，无需再处理 `CMAKE_MODULE_PATH`：

```cmake
file(GLOB_RECURSE DOC_XML "${PROJECT_SOURCE_DIR}/doc_classes/*.xml")
if(DOC_XML)
    target_doc_sources(my_extension "${DOC_XML}")
endif()
```

Python 3.4+ 只在真正调用该函数时才查找，不用文档的工程不背这个依赖。

## 新增平台

以新增 Linux arm64 为例，已有的两个交叉平台是这么组织的：

1. 在 `cmake/toolchains/` 下写工具链文件，声明 `CMAKE_SYSTEM_NAME`、`CMAKE_SYSTEM_PROCESSOR` 与编译器
2. 在 `CMakePresets.json` 里加一对 configure preset 和对应的 build preset，再加一个 `targets: ["install"]` 的 build preset
3. 构建并安装，变体自动落到 `install/<API>/<platform>-<arch>/` 下

已备的两份模板：

- `cmake/toolchains/linux-arm64.cmake` — 前缀默认 `aarch64-linux-gnu`，可用 `-DGODOTCPP_CROSS_PREFIX=<前缀>` 覆盖。Windows 原生环境提供不了这套工具链，需在 WSL2、Docker 或 CI 中执行
- `cmake/toolchains/android-arm64.cmake` — 转交给 NDK 自带的 `android.toolchain.cmake`，NDK 位置读 `-DANDROID_NDK=<路径>` 或 `ANDROID_NDK` 环境变量

## 当前状态

已在 Windows x64 / VS 2022 上实机验证：

- `template_debug` 与 `template_release` 两个变体同时安装，互不覆盖
- 消费端在两种 target 下各自配置与构建通过，产物名与 `.gdextension` 声明一致，`compatibility_minimum` 为 `4.7`
- 变体未命中时给出可用变体列表
- `target_doc_sources` 完成从 XML 到内嵌 C++ 源的生成与编译

尚待验证：

- Linux arm64 与 Android arm64 的工具链与 preset 属于模板，暂未在编译环境执行过编译

