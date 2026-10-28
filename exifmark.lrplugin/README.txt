exifmark

安装：LrC菜单“文件→增效工具管理器→添加”，选择整个exifmark.lrplugin文件夹。
使用：在导出窗口左下“后期处理动作”中展开exifmark，双击“exifmark照片卡片”。
选择JPEG、关闭HDR输出和文件体积限制，再选择背景颜色、边框布局和相机命名方式。

支持macOS13及以上、Lightroom Classic14.3及以上。
bin内包含Apple Silicon/Intel通用程序和矢量字标资源，请保留完整目录。
横图和竖图默认上、左、右各留白2%，底部追加8%参数栏；可选仅底部8%参数栏。
所有比例按显示方向的照片宽度计算，再向上对齐JPEG块。照片占位同步补齐到整块，尺寸可能增加少量像素。
相机名称默认使用常用名称，可切换EXIF原名。
背景颜色、边框布局、相机命名方式均可随LrC导出预设保存。

LrC先按原有质量导出JPEG，照片区域的量化DCT系数直接保留。
新增边框和参数栏使用原JPEG的实际量化表和色度采样进行压缩，拼接后优化熵编码。
无需TIFF中转或临时入库，导出结束后自动清理临时JPEG。
原JPEG的ICC和EXIF方向标记保留。

This software is based in part on the work of the Independent JPEG Group.
libjpeg-turbo许可证见licenses目录。
