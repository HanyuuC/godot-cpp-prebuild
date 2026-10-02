# godot-cpp-prebuild

把 [godot-cpp](https://github.com/godotengine/godot-cpp) 编译成一组预编译包，供多个 GDExtension 插件工程共用。

## 解决的问题

GDExtension 工程通常把 godot-cpp 作为子目录引入，每新建一个插件工程都需要重新编译上千个绑定翻译单元。本工程将 godot-cpp 独立编译并按变体安装，插件工程改为链接编译好的静态库，godot-cpp 仅在升级 API 版本或更换变体时重编。

- godot-cpp 源码采用 submodule 纳入本项目，保持上游原样，不改动任何文件与脚本，升级时在 submodule 内切换 commit 即可
- 每个变体安装在独立目录里，多个配置可以在同一安装前缀下长期共存、互不覆盖

## 产物布局

安装前缀默认是 `<本工程>/install`。

```
install/
└── 4.7/                                          API 版本，GodotCPP_DIR 指向该目录
    ├── GodotCPPConfig.cmake                      find_package(GodotCPP) 读取该文件
    ├── GodotCPPConfigVersion.cmake
    ├── GodotCPPPlatform.cmake                    平台归一化，构建侧与消费侧共用
    ├── GodotCPPDoc.cmake                         提供 target_doc_sources()
    ├── doc_source_generator.py
    └── windows-x86_64/                           平台-架构
        ├── template_debug/                       target
        │   └── single-withthreads/               精度-线程
        │       ├── GodotCPPVariant.cmake         记录本变体的配置项与工具链信息
        │       ├── GodotCPPTargets.cmake         导出的 GodotCPP::cpp 目标
        │       └── lib/  include/
        └── template_release/
            └── single-withthreads/
```

一个变体指这四组配置的一次具体取值：API 版本、平台与架构、target、精度与线程。其中任何一项取新值就会多安装出一个新目录，已有的变体不受影响。

## 快速开始

godot-cpp 作为 git submodule 放在 `godot-cpp/`，执行 `git submodule update --init` 进行 submodule 初始化

在 Windows x64 上使用 workflow preset 构建并安装全部常用变体，每个 workflow preset 内部依次完成配置、构建、安装三步：

```bash
cmake --workflow --preset windows-x86_64-debug
cmake --workflow --preset windows-x86_64-release
```

查看可用的 preset：

```bash
cmake --list-presets=all
```

### 非默认变体

preset 只区分平台和 target，精度与线程特性沿用默认值 `single` 和 `ON`。需要其它组合时改用 configure、build、install 三阶段命令形式，在configure 阶段追加 `-D` 设置值，例如 double 浮点精度变体：

```bash
cmake --preset windows-x86_64-debug "-DGODOTCPP_PRECISION=double"
cmake --build --preset windows-x86_64-debug
cmake --build --preset windows-x86_64-debug-install
```

新变体安装到 `install/4.7/windows-x86_64/template_debug/double-withthreads/`，与既有的 `single-withthreads` 并存。

## 预编译配置项

- `GODOTCPP_VENDOR_DIR` — godot-cpp 源码目录，默认 `<本工程>/godot-cpp`
- `GODOTCPP_API_VERSION` — 目标 Godot API 版本，取值需对应 `godot-cpp/gdextension/extension_api-<版本>.json`；CMake 配置时会检查这个版本在 godot-cpp 里是否存在，拼错会直接报错并列出可用版本
- `GODOTCPP_TARGET` — `template_debug`（编辑器加载）| `template_release`（导出包加载）| `editor`；其中`template_debug` 采用 `RelWithDebInfo` 构建配置，`template_release` 采用 `Release` 构建配置
- `GODOTCPP_PRECISION` — `single` | `double`，决定 `real_t` 的定义，与消费端 ABI 相关
- `GODOTCPP_THREADS` — Godot 的 `threads` 特性开关，默认 `ON`；置 `OFF` 的产物文件名带 `.nothreads` 段
- `GODOTCPP_DEV_BUILD` — godot-cpp 自带的开发构建开关，该选项面向 godot-cpp 开发者，默认 `OFF`。设为 `ON` 时会定义 `DEV_ENABLED`、关掉内联与优化（`-O0 -fno-omit-frame-pointer`）、把调试信息提到 `-g3`，并启用只在开发期生效的内部检查。本工程暂不支持设为 `ON`：它会让库文件名多出 `.dev` 段，而目录名中不包含 `.dev`，dev 与非 dev 的产物就会安装进同一个目录互相覆盖；如需支持，需要先将 dev 纳入目录命名。这些编译选项在 godot-cpp 中声明为 PUBLIC，会传递给链接它的工程，因此开启该选项后消费端的优化等级也会随之降低

平台与架构由工具链决定，没有单独的开关可以手工指定，避免选到与当前工具链 ABI 不兼容的预编译库。Visual Studio 生成器读 `CMAKE_VS_PLATFORM_NAME`，其余读 `CMAKE_SYSTEM_NAME` 与 `CMAKE_SYSTEM_PROCESSOR`。

> [!NOTE] 消费端的构建配置
>
> 消费端选用的构建配置可以与本项目预编译库采用不同构建配置，例如：`template_release` 预编译变体以 Release 构建，消费端以 Debug 或 RelWithDebInfo 配置构建时可以链接。
>
> MSVC 上 Debug 与 Release 默认使用不同的 CRT（`/MDd` 与 `/MD`，或 `/MTd` 与 `/MT`），STL 调试级别也随之不同，混用会在链接期报错 LNK2038。本项目把预编译库与消费端的 C 运行库统一为 `/MT`，CRT 与 STL 调试级别因此一致，因此支持使用者以与预编译库不同的构建配置链接。
>
> Linux 与 Android 上，Debug 与 Release 的差别在优化等级、调试信息与 `NDEBUG`，三者都不进入 ABI 与符号签名，默认不影响不同构建配置链接。

## 消费端接入

### 消费端配置项

- `GodotCPP_DIR` — 预编译包目录，指向 `install/<API 版本>/` 中 `GodotCPPConfig.cmake`文件所在目录。必须设置
- `GODOTCPP_TARGET` — `template_debug`（编辑器加载）| `template_release`（导出包加载）| `editor`。未设置时默认为 `template_debug`；该变量不跟随 `CMAKE_BUILD_TYPE`，用 Release 配置构建时同样需要显式指定 `template_release`
- `GODOTCPP_PRECISION` — `single` | `double`。未设置时默认为 `single`
- `GODOTCPP_THREADS` — `ON` | `OFF`。未设置时默认为 `ON`

平台与架构没有配置项，由工具链决定。交叉编译时用 `CMAKE_TOOLCHAIN_FILE` 指定工具链文件即可。

配置项可以在 `CMakeLists.txt` 中设置，也可以在配置时用 `-D` 覆盖；`set(... CACHE ...)` 不会覆盖已存在的缓存条目，命令行传入的值优先：

```bash
cmake -B build "-DGODOTCPP_TARGET=template_release"
```

### CMakeLists.txt 示例

```cmake
set(GODOTCPP_TARGET "template_debug" CACHE STRING "构建目标")
set(GODOTCPP_PRECISION "single" CACHE STRING "浮点精度")
set(GODOTCPP_THREADS ON CACHE BOOL "多线程支持")

set(GodotCPP_DIR "<godot-cpp-prebuild>/install/4.7" CACHE PATH "预编译包目录")
find_package(GodotCPP CONFIG REQUIRED)

target_link_libraries(my_extension PRIVATE GodotCPP::cpp)
```

### 包提供的目标与变量

- `GodotCPP::cpp` — 预编译库的导入目标，包含静态库、头文件搜索路径，以及全部 ABI 相关编译宏与链接选项
- `GodotCPP_API_VERSION` — 包对应的 Godot API 版本，如 `4.7`，可直接用作 `.gdextension` 的 `compatibility_minimum`
- `GodotCPP_PLATFORM` — 目标平台名，如 `windows`
- `GodotCPP_ARCH` / `GodotCPP_TARGET` / `GodotCPP_PRECISION` / `GodotCPP_THREADS` — 本次选用变体在这四项上的取值，依次为目标架构、target、浮点精度、threads 开关
- `GodotCPP_SUFFIX` — 库文件名后缀，如 `.windows.template_debug.x86_64`，用它拼接扩展库文件名即可与 `.gdextension` 中的路径声明一致
- `GodotCPP_VARIANT_DIR` — 本次选用变体所在目录

上述取值同时记录在 `GodotCPP::cpp` 的目标属性上，属性名为 `GODOTCPP_PLATFORM`、`GODOTCPP_TARGET`、`GODOTCPP_ARCH`、`GODOTCPP_PRECISION`、`GODOTCPP_SUFFIX`。

命名约定：`GODOTCPP_*`（全大写）由使用者在 CMakeLists.txt 中设置，用来指定使用哪一份预编译库；`GodotCPP_*` 在 `find_package` 完成后由包设置，供使用者读取。

### 找不到匹配的变体

选择的三项配置在当前预编译包里没有对应目录时，`find_package` 会列出这个安装前缀下已有的变体：

```
预编译包中没有 windows-x86_64/template_debug/double-withthreads 变体。
已安装的变体：
    windows-x86_64/template_debug/single-withthreads
补齐方式：在 godot-cpp-prebuild 中用对应的 CMakePreset 构建并安装。
```

### MSVC 运行库

godot-cpp 默认把 C/C++ 运行库静态链接（`/MT`），而 CMake 对未显式设置的工程用 `/MD`，两者混用会在链接期报 LNK2038。`GodotCPPConfig.cmake` 会把预编译包的取值写进消费端的 `CMAKE_MSVC_RUNTIME_LIBRARY` 缓存项；如果工程自行设置过且取值不同，CMake 配置阶段会给出告警。

### 内嵌文档

包已加载 `GodotCPPDoc.cmake`，无需再处理 `CMAKE_MODULE_PATH`：

```cmake
file(GLOB_RECURSE DOC_XML "${PROJECT_SOURCE_DIR}/doc_classes/*.xml")
if(DOC_XML)
    target_doc_sources(my_extension "${DOC_XML}")
endif()
```

Python 3.4+ 只在真正调用该函数时才查找，所以没有文档目录的工程不需要安装 Python。

## 新增平台

以新增 Linux arm64 为例，已有的两个交叉平台按以下方式组织：

1. 在 `cmake/toolchains/` 下写工具链文件，声明 `CMAKE_SYSTEM_NAME`、`CMAKE_SYSTEM_PROCESSOR` 与编译器
2. 在 `CMakePresets.json` 里加一对 configure preset 和对应的 build preset，再加一个 `targets: ["install"]` 的 build preset
3. 构建并安装，产物自动安装到 `install/<API>/<platform>-<arch>/` 下

已提供的两份工具链文件模板：

- `cmake/toolchains/linux-arm64.cmake` — 前缀默认 `aarch64-linux-gnu`，可用 `-DGODOTCPP_CROSS_PREFIX=<前缀>` 覆盖。Windows 原生环境不提供这套工具链，需在 WSL2、Docker 或 CI 中执行
- `cmake/toolchains/android-arm64.cmake` — 转交给 NDK 自带的 `android.toolchain.cmake`，NDK 位置读 `-DANDROID_NDK=<路径>` 或 `ANDROID_NDK` 环境变量

## 当前状态

已在 Windows x64 / VS 2022 上实机验证：

- `template_debug` 与 `template_release` 两个变体同时安装，互不覆盖
- 消费端在两种 target 下各自配置与构建通过，产物名与 `.gdextension` 声明一致，`compatibility_minimum` 为 `4.7`
- 找不到匹配的变体时会列出已有的变体
- `target_doc_sources` 完成从 XML 到内嵌 C++ 源的生成与编译

尚待验证：

- Linux arm64 与 Android arm64 的工具链与 preset 属于模板，暂未在编译环境执行过编译