<div align="center">

# exifmark

**为 Lightroom Classic 导出的照片自动生成 EXIF 参数边框卡片**

[![Release](https://img.shields.io/github/v/release/jinj02/exifmark)](https://github.com/jinj02/exifmark/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/jinj02/exifmark/ci.yml?label=CI&logo=github)](https://github.com/jinj02/exifmark/actions)
[![Platform](https://img.shields.io/badge/macOS-13.0%2B-000000.svg?logo=apple&logoColor=white)](https://github.com/jinj02/exifmark)
[![Lightroom Classic](https://img.shields.io/badge/Lightroom%20Classic-14.3%2B-31A8FF.svg?logo=adobelightroomclassic&logoColor=white)](https://github.com/jinj02/exifmark)
[![License](https://img.shields.io/github/license/jinj02/exifmark)](https://github.com/jinj02/exifmark/blob/main/LICENSE)
[![Stars](https://img.shields.io/github/stars/jinj02/exifmark?style=social)](https://github.com/jinj02/exifmark/stargazers)

</div>

---

**exifmark** 是一款针对 macOS 平台的 Adobe Lightroom Classic (LrC) 导出增效工具。它直接嵌入 LrC 的导出流程中，无需借助 Photoshop 或第三方拼图软件，即可在导出 JPEG 照片时自动加上画框留白、相机与镜头型号、SONY 矢量字标、曝光参数（光圈 / 快门 / ISO）以及拍摄时间。

底层渲染采用macOS原生Swift、CoreGraphics、CoreText与ImageIO，静态链接libjpeg-turbo处理JPEG压缩系数，保留照片区域的原始量化系数与色彩空间配置。

## ✨ 功能特性

- **原生集成 LrC 导出管线**：作为「后期处理动作」挂载，支持直接随 LrC 导出预设（Preset）保存和批量导出。
- **双色主题 & 两种边框布局**：
  - **配色**：支持纯白底（黑字）与纯黑底（白字），内置矢量 SONY 字标自动反色。
  - **三边留白 + 底部参数栏（默认）**：上、左、右各追加照片宽度 `2%` 的留白边框，底部追加 `8%` 的参数栏。
  - **仅底部参数栏**：照片上、左、右三边贴边，仅底部追加照片宽度 `8%` 的参数栏。
- **保留照片压缩数据**：所有外框与参数栏均向外扩展画布，直接复制LrC导出JPEG的量化DCT系数，照片区域免于二次有损编码。边框位置和照片占位向上对齐JPEG的MCU块，末端不足整块的部分保留原有块并向外补齐。
- **智能排版与防溢出**：字号、Logo 与边距随照片宽度同比缩放；过长的相机或镜头名称会自动缩字（最低至 `75%`）并在超宽时优雅省略；缺失的 EXIF 字段自动留空。
- **色彩与隐私安全**：
  - LrC按导出窗口中的质量输出JPEG。新增边框和参数栏使用这张JPEG的实际量化表、色度采样与分量配置进行压缩，再拼接原照片的量化系数并优化熵编码。整个流程无需TIFF中转或临时入库，继承原JPEG的ICC配置。
  - 展示的拍摄参数直接读取自 LrC 目录——即使你在导出设置中选择「移除位置信息」或「仅版权信息」，画面上的参数依然正常渲染，同时严格遵守导出隐私设置不向文件写入多余 EXIF。
- **开箱即用**：内置 `arm64` + `x86_64` 通用二进制程序（Universal Binary），用户无需安装 Swift、Python 或 ImageMagick。

---


## 🚀 安装与使用

### 环境要求

- **操作系统**：macOS 13.0 (Ventura) 及以上（支持 Apple Silicon 与 Intel）
- **宿主软件**：Adobe Lightroom Classic14.3及以上

### 1. 安装插件

1. 从[Releases](https://github.com/jinj02/exifmark/releases)下载`exifmark-<版本>-macos.zip`，解压后将完整的`exifmark.lrplugin`文件夹移动到固定目录（如`~/Documents/LightroomPlugins/`，请保留完整的`bin`目录）。开发包在[Actions](https://github.com/jinj02/exifmark/actions/workflows/ci.yml)的成功运行页面下载；首次正式版为`0.1.0`。
2. 打开 Lightroom Classic，在顶部菜单栏选择 **文件 → 增效工具管理器...**（快捷键 `⌘` + `⌥` + `⇧` + `,`）。
3. 点击左下角的 **添加**，选中刚才放置的 `exifmark.lrplugin` 文件夹并确认。

### 2. 导出照片

1. 在 LrC 中选中要导出的照片，打开 **文件 → 导出...**。
2. 在导出窗口左下角的 **后期处理动作 (Post-Processing)** 列表中找到 **exifmark**，双击 **「exifmark照片卡片」** 将其加入右侧导出处理链。
3. 在弹出的 **exifmark 面板** 中选择：
   - **背景颜色**：白色 / 黑色
   - **边框布局**：三边 2% 留白 + 底部 8% 参数栏 / 仅底部 8% 参数栏
4. 在 LrC 的 **文件设置 (File Settings)** 中确认：
   - 图像格式选择 **JPEG**
   - **取消勾选**「HDR 输出」
   - **取消勾选**「限制文件大小」
5. 点击 **导出** 即可。

> [!TIP]
> - **保存为导出预设**：你可以点击导出窗口左下角的「添加」将当前配置存为 LrC 导出预设，背景色与边框布局会一并保存，下次一键导出。
> - **与其他插件联用**：如果同时挂载了其他后期处理动作，建议将 **exifmark** 放在处理链的最后一个。

---

## ⚠️ 已知限制与兼容性

- **仅支持 SDR JPEG 导出**：若在导出设置中选择了 TIFF / PNG / DNG 等其他格式、开启了「HDR 输出」或开启了「限制文件大小」，插件会在面板中给出提示并禁用导出按钮。
- **JPEG块对齐**：2%边框和8%参数栏按JPEG块向上取整，常见块尺寸为8×8或16×16像素。照片占位同步补齐到整块，尺寸可能增加少量像素；EXIF方向标记保留，照片无需旋转重编码。
- **画布尺寸上限**：单张最终成片最大支持 2 亿像素（200 MP），且单边宽高不超过 `65,535 px`。
- **批量处理与取消**：成片先写入目标目录内的临时文件，再原子替换目标文件；导出结束后清理临时JPEG和请求文件。单张失败按张报告，其他照片继续处理；取消会在当前照片处理完成后停止后续照片。

---

## 🛠️ 从源码构建

从源码构建需要macOS的Xcode命令行工具（Swift5.9+）和CMake。构建脚本首次运行会从上游下载固定版本的libjpeg-turbo3.1.4.1，校验SHA-256后静态编译两个架构。可用`EXIFMARK_CMAKE=/path/to/cmake`指定CMake；插件用户无需安装该依赖。

```bash
# 1. 编译 arm64 + x86_64 通用二进制渲染器，并写入 exifmark.lrplugin/bin/
./scripts/build.sh

# 2. 构建并打包，输出实际ZIP路径，同时生成.zip.sha256校验文件
./scripts/package.sh

# 3. 验证本次开发安装包；可将实际ZIP路径作为第一个参数传入
./scripts/test.sh
```

开发包名称包含版本、Git提交数生成的build号和短commit SHA，例如`exifmark-<版本>-build<编号>-<SHA>-macos.zip`。ZIP内顶层仅有`exifmark.lrplugin`，包含完整运行依赖。打包时在暂存目录生成实际插件版本及`build-info.json`，已跟踪源码保持干净。

测试依赖Python3.10+与`tests/requirements.txt`中的Pillow。测试脚本会下载固定版本的Lua5.1.5，校验SHA-256后在`.build/`内编译；也可通过`EXIFMARK_LUA=/path/to/lua5.1`指定已有解释器。

> [!NOTE]
> 构建脚本默认执行本地临时签名（Ad-hoc signing），尚未进行 Apple Developer ID 签名与公证（Notarization）。

### 版本管理与发布

主分支统一为`main`。`exifmark.lrplugin/Info.lua`中的`major.minor.revision`是唯一版本来源；源码build字段为占位值0，实际build采用完整Git历史的提交数，同一提交重复构建时保持一致。CLI的`--version`输出版本、build和commit；渲染请求中的`version = 1`独立表示协议版本。

升版前先同步主分支与tag，并提交功能变更，然后运行：

```bash
# 首次正式升版：0.0.0 → 0.1.0
python3 scripts/release.py bump minor

# 后续修复、功能和主版本升级分别使用patch、minor、major
python3 scripts/release.py bump patch
```

命令修改插件版本并更新`CHANGELOG.md`，生成的变更可先审阅、补充说明，再以`chore(release): <版本>`提交。首次更新文档涵盖全部提交，后续涵盖上次正式tag以来的提交；兼容`[feat]`、`[fix]`和`feat:`、`fix:`等格式，按英文标题分类，保留提交原文及链接，并忽略merge和升版提交。

PR、推送`main`和手动触发都会运行CI。CI在Apple Silicon构建双架构插件并运行完整自动测试，再将同一份ZIP交给Intel运行器验证。ZIP和SHA-256校验文件在Actions保存14天。`0.0.0`、PR和手动运行提供开发包；`main`上的正式版本升级push通过全部检查后，自动创建`v<版本>`tag和GitHub Release，发布说明来自对应的CHANGELOG章节。

发布先创建草稿、上传插件ZIP和校验文件，最后公开。上传失败后可重跑原工作流补齐；已完成的相同版本、相同提交会跳过，已绑定其他提交的tag会报错。Release使用工作流自带的`GITHUB_TOKEN`，发布任务具有`contents: write`权限。GitHub自动附带的源码存档保留，安装时请选择插件ZIP附件。

版本与发布测试可单独运行`python3 tests/release-tests.py`。正式安装包可用`./scripts/package.sh --release`在本地生成，再将输出路径传给测试脚本。

### 目录结构

```text
exifmark/
├── exifmark.lrplugin/  # Lightroom Classic Lua 插件源码与二进制包目录
├── renderer/           # Swift图像合成与C接口JPEG系数拼接
├── scripts/            # 构建、打包、自动化测试及矢量 Logo 转换脚本
├── tests/              # Lua 单元测试与基于 Pillow 的独立像素级解码验证
├── assets/             # 原始 SONY 矢量 SVG 字标与版权说明
├── examples/           # 本地渲染效果样例说明
└── docs/               # 完整验证报告与测试记录
```
---

## 📄 声明与致谢

- JPEG处理静态链接[libjpeg-turbo](https://github.com/libjpeg-turbo/libjpeg-turbo)，许可证随插件放在`licenses/`。This software is based in part on the work of the Independent JPEG Group.
- 内置 `SONY` 矢量字标源自 [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Sony_logo.svg)，相关商标与名称权利归 Sony Group Corporation 所有。详见 [资源说明 (assets/NOTICE.md)](assets/NOTICE.md)。
- 本项目为独立开发的开源工具，与 Sony 及 Adobe Inc. 无隶属、赞助或官方合作关系。
