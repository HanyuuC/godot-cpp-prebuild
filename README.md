# godot-cpp-prebuild

把 [godot-cpp](https://github.com/godotengine/godot-cpp) 编译为预编译包，支持一次编译，多个 GDExtension 插件工程复用。

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
    ├── GodotCPPExtension.cmake                   提供 godotcpp_extension()
    ├── GodotCPPExtension.gdextension.in          .gdextension 生成模板
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

一个变体指这四组配置的一次具体取值：API 版本、平台与架构、godot_target、精度与线程。其中任何一项取新值就会多安装出一个新目录，已有的变体不受影响。

## 快速开始

godot-cpp 作为 git submodule 放在 `godot-cpp/`，执行 `git submodule update --init` 进行 submodule 初始化

需要构建本机平台与架构的产物时，使用 `native-debug` / `native-release`。native 与交叉编译相对，指目标平台与架构由本机环境决定；两个预设都不声明生成器、架构与工具链，配置时由 CMake 取本机默认生成器，平台与架构再从生成器提供的系统名与处理器名归一化得出。

Windows x64 上的产物落在 `install/4.7/windows-x86_64/`，Linux arm64 上的产物落在 `install/4.7/linux-arm64/`。

```bash
cmake --workflow --preset native-debug
cmake --workflow --preset native-release
```

指定平台与架构时用对应平台的 preset，例如在 Windows x64 上构建并安装全部常用变体，每个 workflow preset 内部依次完成配置、构建、安装三步：

```bash
cmake --workflow --preset windows-x86_64-debug
cmake --workflow --preset windows-x86_64-release
```

查看可用的 preset：

```bash
cmake --list-presets=all
```

### 构建配置的两种表达

构建配置同时写在两个位置，取值按 target 固定：`template_debug` 用 `RelWithDebInfo`，`template_release` 用 `Release`。

- configure preset 的 `CMAKE_BUILD_TYPE` — 单配置生成器（Make、Ninja）在配置期读取该值
- build preset 的 `configuration` — 多配置生成器（Visual Studio）在构建期读取该值，单配置生成器下对应的 `--config` 被忽略

单配置生成器读取 `CMAKE_BUILD_TYPE`，多配置生成器读取 `configuration`，另一项对两者都不产生影响，同一个预设因此可以同时覆盖两类生成器；不限定生成器的 `native-*` 预设只需一套取值，无需按生成器分别编写规则。

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
- `GODOTCPP_API_VERSION` — 目标 Godot API 版本，无默认值，必须显式指定；取值需对应 `godot-cpp/gdextension/extension_api-<版本>.json`；CMake 配置时会检查这个版本在 godot-cpp 里是否存在，拼错会直接报错并列出可用版本
- `GODOTCPP_TARGET` — 决定编译库面向的运行程序类型，默认 `template_debug`，取值：`template_debug`（debug导出包加载）| `template_release`（release导出包加载）| `editor`（编辑器加载，可采用`template_debug`）。其中`template_debug` 采用 `RelWithDebInfo` 构建配置，`template_release` 采用 `Release` 构建配置
- `GODOTCPP_PRECISION` — 决定 `real_t` 的定义为单精度/双精度浮点数，与消费端 ABI 相关，默认 `single`，取值 `single` | `double`
- `GODOTCPP_THREADS` — godot-cpp 的 `threads` 特性开关，默认 `ON`；置 `OFF` 的产物文件名带 `.nothreads` 段
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
- `GODOTCPP_TARGET` — 决定编译库面向的运行程序类型，取值 `template_debug`（debug导出包加载）| `template_release`（release导出包加载）| `editor`（编辑器加载，可采用`template_debug`）。未设置时默认为 `template_debug`；该变量不跟随 `CMAKE_BUILD_TYPE`，用 Release 配置构建时同样需要显式指定 `template_release`
- `GODOTCPP_PRECISION` — 决定 `real_t` 的定义为单精度/双精度浮点数，取值 `single` | `double`。未设置时默认为 `single`
- `GODOTCPP_THREADS` — 决定 godot-cpp 线程特性是否启用，取值 `ON` | `OFF`。未设置时默认为 `ON`

平台与架构没有配置项，由工具链决定。交叉编译时用 `CMAKE_TOOLCHAIN_FILE` 指定工具链文件即可。

配置项可以在 `CMakeLists.txt` 中设置，也可以在配置时用 `-D` 覆盖；`set(... CACHE ...)` 不会覆盖已存在的缓存条目，命令行传入的值优先：

```bash
cmake -B build "-DGODOTCPP_TARGET=template_release"
```

### 包提供的目标与变量

- `GodotCPP::cpp` — 预编译库的导入目标，包含静态库、头文件搜索路径，以及全部 ABI 相关编译宏与链接选项
- `GodotCPP_API_VERSION` — 包对应的 Godot API 版本，如 `4.7`，可直接用作 `.gdextension` 的 `compatibility_minimum`
- `GodotCPP_PLATFORM` — 目标平台名，如 `windows`
- `GodotCPP_ARCH` / `GodotCPP_TARGET` / `GodotCPP_PRECISION` / `GodotCPP_THREADS` — 本次选用变体在这四项上的取值，依次为目标架构、target、浮点精度、threads 开关
- `GodotCPP_SUFFIX` — 库文件名后缀，如 `.windows.template_debug.x86_64`，用它拼接扩展库文件名即可与 `.gdextension` 中的路径声明一致
- `GodotCPP_VARIANT_DIR` — 本次选用变体所在目录

包还提供消费端函数 `godotcpp_extension(...)`，用于统一设置产物命名并生成 `.gdextension`，参数见下一节。

上述取值同时记录在 `GodotCPP::cpp` 的目标属性上，属性名为 `GODOTCPP_PLATFORM`、`GODOTCPP_TARGET`、`GODOTCPP_ARCH`、`GODOTCPP_PRECISION`、`GODOTCPP_SUFFIX`。

命名约定：`GODOTCPP_*`（全大写）由使用者在 CMakeLists.txt 中设置，用来指定使用哪一份预编译库；`GodotCPP_*` 在 `find_package` 完成后由包设置，供使用者读取。

### CMakeLists.txt 示例

```cmake
cmake_minimum_required(VERSION 3.25)
project(my_extension LANGUAGES CXX)

# godot-cpp 头文件要求 C++17，消费端需以 C++17 或更高标准编译
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON) # 编译动态库，开启位置无关代码

# 选择变体：三项对应预编译包中的变体目录，未设置时取默认值 template_debug、single、ON
set(GODOTCPP_TARGET "template_debug" CACHE STRING "构建目标")
set(GODOTCPP_PRECISION "single" CACHE STRING "浮点精度")
set(GODOTCPP_THREADS ON CACHE BOOL "多线程支持")

# 设置预编译包目录为 <godot-cpp-prebuild> 工程目录下的 4.7 版本，需替换为实际路径
set(GodotCPP_DIR "<godot-cpp-prebuild>/install/4.7" CACHE PATH "预编译包目录")
find_package(GodotCPP CONFIG REQUIRED)

set(GDEXTENSION_NAME "${PROJECT_NAME}") # 消费端扩展库名

add_library(${GDEXTENSION_NAME} SHARED)
target_sources(${GDEXTENSION_NAME} PRIVATE <my_source_code.cpp>)# <my_source_code.cpp>需替换为实际源文件路径

target_link_libraries(${GDEXTENSION_NAME} PRIVATE GodotCPP::cpp)

# 预编译库提供godotcpp_extension()函数
# 该函数按当前变体自动设置产物输出目录与文件名，并生成 .gdextension
godotcpp_extension(${GDEXTENSION_NAME})
```

`godotcpp_extension()` 函数参数说明：

```cmake
godotcpp_extension(<target>
    [NAME <扩展名>]
    [OUTPUT_DIR <目录>]
    [ENTRY_SYMBOL <库初始化入口函数名>]
    [RELOADABLE <布尔值>]
    [COMPATIBILITY_MINIMUM <版本>]
    [GODOT_PROJECT_DIR <目录>]
    [VARIANTS <platform|arch|extension>...]
)
```

- `NAME`：扩展名，默认取 target 名；决定生成的库文件名与 `.gdextension` 文件名
- `OUTPUT_DIR`：输出根目录，默认 `${PROJECT_SOURCE_DIR}/bin/<扩展名>`；决定产物与 `.gdextension` 的生成位置，二进制放入 `<OUTPUT_DIR>/<GodotCPP_PLATFORM>` 目录，相对路径相对于 `CMAKE_CURRENT_SOURCE_DIR` 解析
- `ENTRY_SYMBOL`：`.gdextension` 的 `entry_symbol`，决定扩展初始化入口函数符号名，默认 `library_init`
- `RELOADABLE`：控制 `.gdextension` 的 `reloadable`，按 CMake 布尔语义解析（`ON`/`OFF`、`TRUE`/`FALSE`、`YES`/`NO`、`1`/`0`），默认 `OFF`
- `COMPATIBILITY_MINIMUM`：`.gdextension` 的 `compatibility_minimum`，决定可加载该扩展的最低 Godot 版本，默认 `GodotCPP_API_VERSION`
- `GODOT_PROJECT_DIR`：给出时，构建后将产物复制到 `<目录>/bin/<扩展名>`，未给出时不复制；用于把编译产物直接复制到加载该扩展的 Godot 工程，省去手动拷贝，相对路径相对于 `CMAKE_CURRENT_SOURCE_DIR` 解析
- `VARIANTS`：覆盖默认库路径表，元素形如 `platform|arch|extension`；决定 `.gdextension` 中 `[libraries]` 配置表中声明的平台、架构与扩展名组合，默认覆盖 windows、linux、android

函数还会在父作用域设置两个结果变量，供后续构建步骤读取：

- `<target>_GDEXTENSION_FILE`：生成的 `.gdextension` 路径
- `<target>_GDEXTENSION_OUT_DIR`：输出根目录

这两个变量带 target 前缀，多 target 工程不会互相覆盖。配置阶段会用 `STATUS` 消息打印 `.gdextension` 路径、输出根目录与二进制目录，便于确认生成位置。

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

## 如何新增平台

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
- `godotcpp_extension` 替换 hello 工程原有的手写输出配置，生成的 `.gdextension` 与二进制产物路径一致；自定义 `NAME` / `ENTRY_SYMBOL` / `RELOADABLE ON` / `VARIANTS` 的参数组合在临时消费工程中配置与构建通过
- 双精度路径按 godot-cpp 的 `.double` 段顺序生成（如 `.windows.template_debug.double.x86_64`），不再使用容易与实际产物失配的 `.x86_64.double` 写法
- `native-debug` 与 `windows-x86_64-debug` 判定出同一个平台与架构，变体路径同为 `4.7/windows-x86_64/template_debug/single-withthreads`
- 单配置生成器下 `--config` 被忽略已在 Linux 的 Make 生成器上确认

尚待验证：

- Linux arm64 与 Android arm64 的工具链与 preset 属于模板，暂未在编译环境执行过编译
- `native-*` 只在本机 Windows x64 上配置过，Linux 与 macOS 上尚未执行过编译；

