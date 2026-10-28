local Settings = {}

Settings.observedKeys = {
    'LR_format', 'LR_enableHDRDisplay', 'LR_jpeg_useLimitSize', 'exifmark_theme', 'exifmark_layout',
    'exifmark_cameraNameStyle', 'exifmark_watermarkStyle',
}

function Settings.error(properties, isMac, rendererExists)
    if not isMac then return 'exifmark首版支持macOS，请在Mac上导出。' end
    if not rendererExists then return 'exifmark渲染程序缺失，请安装完整的exifmark.lrplugin。' end
    if properties.LR_format ~= 'JPEG' then return 'exifmark支持JPEG，请将图像格式设为JPEG。' end
    if properties.LR_enableHDRDisplay then return 'exifmark支持SDR照片，请关闭“文件设置”中的HDR输出。' end
    if properties.LR_jpeg_useLimitSize then return 'exifmark需要追加信息带，请关闭JPEG的“限制文件大小”。' end
    if properties.exifmark_theme ~= 'white' and properties.exifmark_theme ~= 'black'
        and properties.exifmark_theme ~= 'blurred' then
        return '请选择白色、黑色或原图模糊边框。'
    end
    if properties.exifmark_watermarkStyle ~= nil and properties.exifmark_watermarkStyle ~= 'detailed'
        and properties.exifmark_watermarkStyle ~= 'centered' then
        return '请选择详细或简洁水印。'
    end
    if properties.exifmark_cameraNameStyle ~= nil and properties.exifmark_cameraNameStyle ~= 'common'
        and properties.exifmark_cameraNameStyle ~= 'exif' then
        return '请选择常用名称或EXIF原名。'
    end
    if properties.exifmark_layout ~= nil and properties.exifmark_layout ~= 'bordered'
        and properties.exifmark_layout ~= 'bottomOnly' then
        return '请选择三边2%留白或仅底部8%的布局。'
    end
end

-- POSIX shell quoting: metadata never appears in command arguments.
function Settings.quote(value)
    assert(type(value) == 'string' and not value:find('%z'), 'Invalid shell argument')
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

return Settings
