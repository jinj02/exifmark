local Settings = {}

Settings.observedKeys = {
    'LR_format', 'LR_enableHDRDisplay', 'LR_jpeg_useLimitSize', 'exify_theme',
}

function Settings.error(properties, isMac, rendererExists)
    if not isMac then return 'exify首版支持macOS，请在Mac上导出。' end
    if not rendererExists then return 'exify渲染程序缺失，请安装完整的exify.lrplugin。' end
    if properties.LR_format ~= 'JPEG' then return 'exify支持JPEG，请将图像格式设为JPEG。' end
    if properties.LR_enableHDRDisplay then return 'exify支持SDR照片，请关闭“文件设置”中的HDR输出。' end
    if properties.LR_jpeg_useLimitSize then return 'exify需要追加信息带，请关闭JPEG的“限制文件大小”。' end
    if properties.exify_theme ~= 'white' and properties.exify_theme ~= 'black' then
        return '请选择白色或黑色背景。'
    end
end

-- POSIX shell quoting: metadata never appears in command arguments.
function Settings.quote(value)
    assert(type(value) == 'string' and not value:find('%z'), 'Invalid shell argument')
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

return Settings
