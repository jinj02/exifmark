return {
    sectionsForTopOfDialog = function(f)
        return {
            {
                title = 'exifmark · 照片卡片',
                f:static_text {
                    title = '在导出窗口左下角选择“exifmark照片卡片”，双击添加到后期处理操作。',
                    width_in_chars = 52,
                    height_in_lines = 2,
                    wrap = true,
                },
                f:static_text {
                    title = '支持macOS13及以上、LrC14.3及以上的SDRJPEG导出。\n保留照片压缩数据，边框和参数栏沿用原JPEG压缩参数。',
                    width_in_chars = 52,
                    height_in_lines = 3,
                    wrap = true,
                },
            },
        }
    end,
}
