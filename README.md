<div align="center">

# exifmark

**为 Lightroom Classic 导出的照片自动生成 EXIF 参数边框卡片**

[![Release](https://img.shields.io/badge/release-v0.1.0-blue.svg)](https://github.com/jinj02/exifmark/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/jinj02/exifmark/ci.yml?label=CI&logo=github)](https://github.com/jinj02/exifmark/actions)
[![Platform](https://img.shields.io/badge/macOS-13.0%2B-000000.svg?logo=apple&logoColor=white)](https://github.com/jinj02/exifmark)
[![Lightroom Classic](https://img.shields.io/badge/Lightroom%20Classic-14.3%2B-31A8FF.svg?logo=adobelightroomclassic&logoColor=white)](https://github.com/jinj02/exifmark)
[![License](https://img.shields.io/github/license/jinj02/exifmark)](https://github.com/jinj02/exifmark/blob/main/LICENSE)
[![Stars](https://img.shields.io/github/stars/jinj02/exifmark?style=social)](https://github.com/jinj02/exifmark/stargazers)

</div>

---

**exifmark** 是一款针对 macOS 平台的 Adobe Lightroom Classic (LrC) 导出增效工具。它直接嵌入 LrC 的导出流程中，无需借助 Photoshop 或第三方拼图软件，即可在导出 JPEG 照片时自动加上画框留白、相机与镜头型号、SONY 矢量字标、曝光参数（光圈 / 快门 / ISO）以及拍摄时间。

底层渲染采用 macOS 原生 Swift + CoreGraphics / CoreText / ImageIO 实现，零第三方运行时依赖，完整保留原图画质与色彩空间配置。

## ✨ 功能特性

- **原生集成 LrC 导出管线**：作为「后期处理动作」挂载，支持直接随 LrC 导出预设（Preset）保存和批量导出。
- **双色主题 & 两种边框布局**：
  - **配色**：支持纯白底（黑字）与纯黑底（白字），内置矢量 SONY 字标自动反色。
  - **三边留白 + 底部参数栏（默认）**：上、左、右各追加照片宽度 `2%` 的留白边框，底部追加 `8%` 的参数栏。
  - **仅底部参数栏**：照片上、左、右三边贴边，仅底部追加照片宽度 `8%` 的参数栏。
- **无损照片区域**：所有外框与参数栏均为**向外扩展画布**，绝不裁切或挤压 LrC 设定的原始导出像素尺寸。
- **智能排版与防溢出**：字号、Logo 与边距随照片宽度同比缩放；过长的相机或镜头名称会自动缩字（最低至 `75%`）并在超宽时优雅省略；缺失的 EXIF 字段自动留空。
- **色彩与隐私安全**：
  - LrC先输出8位无损TIFF，原生程序将照片、边框和参数栏合成为完整的无损TIFF，再临时导入当前目录，由LrC按导出窗口中的原有JPEG质量压缩整张成片，继承选定的RGB色彩空间。
  - 展示的拍摄参数直接读取自 LrC 目录——即使你在导出设置中选择「移除位置信息」或「仅版权信息」，画面上的参数依然正常渲染，同时严格遵守导出隐私设置不向文件写入多余 EXIF。
- **开箱即用**：内置 `arm64` + `x86_64` 通用二进制程序（Universal Binary），用户无需安装 Swift、Python 或 ImageMagick。

---


## 🚀 安装与使用

### 环境要求

- **操作系统**：macOS 13.0 (Ventura) 及以上（支持 Apple Silicon 与 Intel）
- **宿主软件**：Adobe Lightroom Classic14.3及以上

### 1. 安装插件

1. 解压发布包 `dist/exifmark-0.1.0-macos.zip`（或自行构建），将完整的 `exifmark.lrplugin` 文件夹移动到固定目录（如 `~/Documents/LightroomPlugins/`，请勿删改其中的 `bin` 目录）。
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
- **中间图自动清理**：导出结束后移除临时导入的TIFF照片记录，再清理中间文件，并恢复清理前的照片选择、来源和筛选条件。清理会短暂切换到临时图所在文件夹；若LrC无法确认记录已移除，会保留相应文件并报告错误。自动清理使用LrC14.3新增接口。
- **画布尺寸上限**：单张最终成片最大支持 2 亿像素（200 MP），且单边宽高不超过 `65,535 px`。
- **批量处理与取消**：LrC生成最终JPEG后，以原始字节复制到目标目录内的临时文件，再原子替换目标文件；单张失败按张报告，其他照片继续处理；取消会在当前照片处理完成后停止后续照片。

---

## 🛠️ 从源码构建

本项目无需任何第三方外部依赖，仅需安装 macOS **Xcode Command Line Tools**（支持 Swift 5.9+）。

```bash
# 1. 编译 arm64 + x86_64 通用二进制渲染器，并写入 exifmark.lrplugin/bin/
./scripts/build.sh

# 2. 打包生成可分发的 dist/exifmark-0.1.0-macos.zip
./scripts/package.sh
```

> [!NOTE]
> 构建脚本默认执行本地临时签名（Ad-hoc signing），尚未进行 Apple Developer ID 签名与公证（Notarization）。

### 目录结构

```text
exifmark/
├── exifmark.lrplugin/  # Lightroom Classic Lua 插件源码与二进制包目录
├── renderer/           # Swift 原生图像合成渲染器 (CoreGraphics / CoreText / ImageIO)
├── scripts/            # 构建、打包、自动化测试及矢量 Logo 转换脚本
├── tests/              # Lua 单元测试与基于 Pillow 的独立像素级解码验证
├── assets/             # 原始 SONY 矢量 SVG 字标与版权说明
├── examples/           # 本地渲染效果样例说明
└── docs/               # 完整验证报告与测试记录
```
---

## 📄 声明与致谢

- 内置 `SONY` 矢量字标源自 [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Sony_logo.svg)，相关商标与名称权利归 Sony Group Corporation 所有。详见 [资源说明 (assets/NOTICE.md)](assets/NOTICE.md)。
- 本项目为独立开发的开源工具，与 Sony 及 Adobe Inc. 无隶属、赞助或官方合作关系。
