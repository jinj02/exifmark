# 相机型号命名

## 读取与输出路径

`Metadata.read`通过受保护的Lightroom SDK调用读取品牌和型号，优先读取`getRawMetadata`，不支持时读取`getFormattedMetadata`。原始字符串完整保存在已有的`cameraMake`、`camera`字段，包含大小写、空格和控制字符。其他拍摄参数沿用现有格式化路径。

`ExportFilter`将原始字段和命名方式写入JSON请求；`RenderRequest`解码后，由`CameraNames`解析显示名，再经`CardRenderer.drawFooter`绘制。JPEG压缩系数路径和普通图像路径、两种布局、黑白主题共用此逻辑。文件元数据仍由现有保留与隐私逻辑处理，显示名不会写回EXIF。当前项目没有单独的元数据详情界面。

## 显示规则与兼容

1. 渲染器接口保留非空自定义名称优先的兼容行为；只对显示副本替换控制字符、去除首尾空白。LrC插件不传递自定义名称。
2. 选择EXIF原名时直接使用原始型号，不额外添加厂商前缀；请求中保存的原始字段保持完整。
3. 选择常用名称时，先按规范化后的品牌和完整型号查表；索尼型号交由独立正则解析器处理。匹配只统一大小写及空白，保留连字符、代际、数字、字母和后缀。
4. 未匹配、映射资源缺失或解析失败时回退原始型号；缺少型号时沿用原有留空行为。

型号映射仍存储独立型号文字，`CameraNames.watermarkName`在常用名称模式输出时组合“厂商＋型号”，例如SONY α7R IVA、Canon EOS R5、Nikon Z 8。品牌名称沿用品牌识别结果，未识别厂商使用原始厂商字符串的显示副本；厂商与型号间以空格分隔。型号已经以该厂商名称开头时按大小写不敏感的完整名称边界检查去重，避免SONY SONY和Canon Canon。原型号缺失时保持留空。自定义名称作为完整标签优先，不自动添加厂商。品牌字标继续单独绘制，识别始终使用原始品牌、型号。

旧版请求缺少`cameraNameStyle`时默认为`common`，缺少`cameraCustomName`时默认为空字符串。旧请求仍使用既有`cameraMake`和`camera`结构；品牌缺失时可沿用输入图像的TIFF Make进行匹配与字标识别，完全缺少品牌时保留型号原文，并允许现有品牌识别器根据型号识别可用的厂商前缀。显示型号为空时不会从图像重新填充。

导出面板提供“相机名称”，沿用`exportPresetFields`保存与恢复，默认使用常用名称。LrC插件已移除自定义名称输入、预设字段和导出传参，旧预设中的自定义文字会被忽略。

## 数据结构与扩充

集中维护文件：`renderer/Sources/ExifmarkCore/Resources/CameraNames.json`。SwiftPM将其随既有资源包安装，运行时从可执行文件旁读取。

- `version`：映射结构版本。
- `brands`：内部品牌标识对应明确允许的EXIF品牌字符串。使用完整字符串匹配，避免将未知厂商认作已知厂商。RICOH制造的PENTAX与RICOH产品通过完整型号区分。
- `entries[].models`：同一产品的明确型号标识列表。商品名中的品牌前缀与不含前缀的产品标识须逐项列出；此列表也容纳经过验证的地区EXIF别名。索尼通用系列由`SonyCameraNames.swift`中的正则规则处理，无需逐机型加入条目。
- `entries[].names`：`default`为保留官方大小写与符号的通用名称，可按语言／地区键扩充显示名。首版沿用项目现有中文界面，依次选择`zh-CN`、`default`，没有新建语言设置。
- `sources`、`verifiedOn`：核实用的厂商资料链接及日期。加入地区别名或新后缀前，应补充能证明该标识与产品对应关系的资料。

新增条目需核对品牌、完整型号、商品名、代际和后缀，并补充验证用例。解析器拒绝空名称、无来源条目及规范化后重复的品牌型号组合，防止后加入的数据覆盖已有条目。

## 索尼正则规则

`SonyCameraNames.swift`集中处理索尼微单编码，已移除JSON中的逐机型索尼映射。规则仅在品牌匹配`brands.sony`且选择常用名称时运行；自定义名称、EXIF原名及明确的地区映射仍优先。

|系列|匹配结构|显示示例|
|---|---|---|
|ILCE全画幅与APS-C|数字系列＋可选R／S／C／CR＋可选M代际＋单字母后缀|ILCE-7RM5→α7R V；ILCE-7CM2→α7C II；ILCE-6700→α6700|
|ZV-E|数字系列＋可选M代际＋单字母后缀|ZV-E10M2→ZV-E10 II|
|NEX|可选前缀字母＋数字＋可选后缀字母|nex-5n→NEX-5N；NEX-C3保持NEX-C3|
|ILCE-QX|QX＋数字|ILCE-QX1保持ILCE-QX1|

M代际统一转换为罗马数字；按项目显示约定，后缀直接紧接代际，例如ILCE-7RM4A→α7R IVA、ILCE-7RM3A→α7R IIIA。带后缀的编码与基础机型保持不同显示结果。型号包含一次`SONY `品牌前缀时，解析显示副本会去除该前缀。

规则使用完整字符串匹配，同一编码语法可覆盖后续机型，无需维护型号白名单。自动化中的ILCE-7RM99A、ILCE-9M99、ILCE-1M99、ILCE-42RM14A等用于检查规则扩展能力，不构成产品存在性核实。M0、M1、前导零、多字母修订后缀及混入其他文字的编码会回退原文。A卡口ILCA／DSLR、DSC固定镜头、ZV固定镜头、NEX-VG摄像机及ILME电影机沿用原文。

规则核对资料：[α7 V](https://www.sony.jp/ichigan/products/ILCE-7M5/)、[α7R VI](https://www.sony.jp/ichigan/products/ILCE-7RM6/)、[α1 II](https://www.sony.jp/ichigan/products/ILCE-1M2/)、[α7C II说明书](https://helpguide.sony.net/ilc/2360/v1/ja/print.pdf)、[α9 III](https://www.sony.com/electronics/support/e-mount-body-ilce-7-series/ilce-9m3)、[α6700说明书](https://helpguide.sony.net/ilc/2320/v1/en/contents/221h_specifications_ilc2320.html)、[ZV-E10 II](https://electronics.sony.com/imaging/interchangeable-lens-cameras/aps-c/p/zve10m2b)、[ILCE-7RM4A](https://www.sony.jp/ichigan/products/ILCE-7RM4A/)、[NEX系列](https://www.sony.co.kr/electronics/support/articles/S500076165)、[ILCE-QX1](https://www.sony.jp/ichigan/products/ILCE-QX1/)。核对日期：2026-10-28。

## 其他品牌映射覆盖

核实日期：2026-10-28。JSON保留其他6个品牌、10款产品；来源为厂商产品页、规格书、说明书和公告。产品标识逐项列出，未验证的EXIF拼写、地区别名和后缀继续回退原文。

|品牌|匹配型号|水印常用名|核实来源|
|---|---|---|---|
|canon|Canon EOS R5、EOS R5|EOS R5|[厂商资料](https://downloads.canon.com/nw/camera/products/eos/product-1/pdfs/EOSR5_specifications_FINAL_JULY14.pdf)|
|canon|Canon EOS R5 Mark II、EOS R5 Mark II|EOS R5 Mark II|[厂商资料](https://www.usa.canon.com/shop/p/eos-r5-mark-ii)|
|nikon|NIKON Z 8、Z 8|Z 8|[厂商资料](https://www.nikonusa.com/p/z-8/1695/overview)|
|fujifilm|X-T5、FUJIFILM X-T5|X-T5|[厂商资料](https://fujifilm-dsc.com/en/manual/x-t5/technical_notes/spec/)|
|pentax|PENTAX K-1|K-1|[厂商资料](https://news.ricoh-imaging.co.jp/rim_info2/2016/20160218_019317.html)|
|pentax|PENTAX K-1 Mark II|K-1 Mark II|[厂商资料](https://news.ricoh-imaging.co.jp/rim_info2/2018/20180222_019721.html)|
|ricoh|RICOH GR III、GR III|GR III|[厂商资料](https://www.ricoh-imaging.co.jp/japan/products/gr-3/index.html)|
|ricoh|RICOH GR IIIx、GR IIIx|GR IIIx|[厂商资料](https://www.ricoh-imaging.co.jp/japan/products/gr-3/index.html)|
|panasonic|DC-S5M2|LUMIX S5II|[厂商资料](https://help.na.panasonic.com/wp-content/uploads/2023/02/DCS5M2_DVQX2329ZA_ENG.pdf)|
|panasonic|DC-S5M2X|LUMIX S5IIX|[厂商资料](https://eww.pavc.panasonic.co.jp/dscoi/DC-S5M2X/pdf/DC-S5M2X_DVQP2992_full_eng.pdf)|

覆盖已有测试样例ILCE-7M4、Z 8、PENTAX K-1。README视觉素材中的型号文字仅为设计样例，不作为产品核实证据；符合索尼语法的编码按规则解析。EOS R5 C和GR IIIx HDF等未收录的其他品牌标识保持原文。

## 验证范围

- Lua验证：SDK原始字符串保留、读取失败回退、默认设置、设置校验、预设保存恢复模拟、导出请求传参。
- Swift验证：其他品牌10款产品、索尼系列正则与罗马数字和后缀、品牌大小写和空白、完整品牌限制、未知型号、空型号、代际与后缀、自定义优先级、地区显示名、重复数据拒绝、请求往返与旧版兼容。
- CLI验证：JPEG与TIFF输入、两种布局和黑白主题，将实际渲染像素与明确指定的预期文字渲染结果比较，并检查显示名未回写EXIF。
- 安装包验证：资源包含与迁移后的映射生效、双架构、签名及既有渲染检查。

真实Lightroom导出预设的磁盘写入由宿主处理，自动化使用SDK模拟核对插件声明及恢复行为；发布前可按`docs/VALIDATION.md`在Lightroom中实测保存与重启恢复。
