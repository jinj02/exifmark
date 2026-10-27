return {
    sectionsForTopOfDialog = function(f)
        return {
            {
                title = 'exify · 照片卡片',
                f:static_text {
                    title = '在导出窗口左下角选择“exify照片卡片”，双击添加到后期处理操作。',
                    width_in_chars = 52,
                    height_in_lines = 2,
                    wrap = true,
                },
                f:static_text {
                    title = '支持macOS13及以上、LrC13及以上的SDRJPEG导出。\n照片下方追加10%宽度的信息带，可选白底或黑底。',
                    width_in_chars = 52,
                    height_in_lines = 3,
                    wrap = true,
                },
            },
        }
    end,
}
