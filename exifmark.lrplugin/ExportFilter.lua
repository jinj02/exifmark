local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'
local LrUUID = import 'LrUUID'
local LrView = import 'LrView'

local Metadata = require 'Metadata'
local Json = require 'Json'
local Settings = require 'Settings'
local Filter = {}
local helper = LrPathUtils.child(_PLUGIN.path, 'bin/exifmark-render')
local dialogObservers = setmetatable({}, { __mode = 'k' })

local function compatibilityError(properties)
    return Settings.error(properties, MAC_ENV, LrFileUtils.exists(helper) == 'file')
end

local function updateStatus(properties)
    local reason = compatibilityError(properties)
    local borderName = ({ white = '白色边框', black = '黑色边框', blurred = '原图模糊边框' })[properties.exifmark_theme]
    local watermarkName = properties.exifmark_watermarkStyle == 'centered' and '简洁水印' or '详细水印'
    properties.exifmark_synopsis = (borderName or '') .. ' · ' .. watermarkName
    properties.exifmark_status = reason or (properties.exifmark_layout == 'bottomOnly'
        and '底部追加参数栏，并对齐JPEG块。保留照片压缩数据。'
        or '上、左、右各留白照片宽度的2%，底部追加参数栏，并对齐JPEG块。')
    if not reason and properties.exifmark_theme == 'blurred' then
        properties.exifmark_status = properties.exifmark_status .. '原图模糊背景，整条水印自动选择黑字或白字。'
    end
    -- Do not overwrite a validation error owned by another export provider.
    local previous = dialogObservers[properties]
    if reason and (properties.LR_cantExportBecause == nil or properties.LR_cantExportBecause == previous) then
        properties.LR_cantExportBecause = reason
    elseif not reason and previous and properties.LR_cantExportBecause == previous then
        properties.LR_cantExportBecause = nil
    end
    dialogObservers[properties] = reason or false
end

function Filter.startDialog(properties)
    if properties.exifmark_theme == nil then properties.exifmark_theme = 'white' end
    if properties.exifmark_layout == nil then properties.exifmark_layout = 'bordered' end
    if properties.exifmark_watermarkStyle == nil then properties.exifmark_watermarkStyle = 'detailed' end
    if properties.exifmark_cameraNameStyle == nil then properties.exifmark_cameraNameStyle = 'common' end
    for _, key in ipairs(Settings.observedKeys) do
        properties:addObserver(key, Filter, function() updateStatus(properties) end)
    end
    updateStatus(properties)
end

function Filter.endDialog(properties)
    for _, key in ipairs(Settings.observedKeys) do properties:removeObserver(key, Filter) end
    local previous = dialogObservers[properties]
    if previous and properties.LR_cantExportBecause == previous then properties.LR_cantExportBecause = nil end
    dialogObservers[properties] = nil
end

function Filter.sectionForFilterInDialog(f, properties)
    return {
        title = 'exifmark照片卡片',
        bind_to_object = properties,
        synopsis = LrView.bind { key = 'exifmark_synopsis', object = properties },
        f:row {
            f:static_text { title = '边框样式：' },
            f:popup_menu {
                value = LrView.bind 'exifmark_theme',
                items = {
                    { title = '白色', value = 'white' }, { title = '黑色', value = 'black' },
                    { title = '原图模糊', value = 'blurred' },
                },
                width_in_chars = 12,
            },
        },
        f:row {
            f:static_text { title = '水印样式：' },
            f:popup_menu {
                value = LrView.bind 'exifmark_watermarkStyle',
                items = {
                    { title = '详细（左右排版）', value = 'detailed' },
                    { title = '简洁（居中两行）', value = 'centered' },
                },
                width_in_chars = 20,
            },
        },
        f:row {
            f:static_text { title = '边框布局：' },
            f:popup_menu {
                value = LrView.bind 'exifmark_layout',
                items = {
                    { title = '三边2%留白＋底部参数栏', value = 'bordered' },
                    { title = '仅底部参数栏', value = 'bottomOnly' },
                },
                width_in_chars = 30,
            },
        },
        f:row {
            f:static_text { title = '相机名称：' },
            f:popup_menu {
                value = LrView.bind 'exifmark_cameraNameStyle',
                items = { { title = '常用名称', value = 'common' }, { title = 'EXIF原名', value = 'exif' } },
                width_in_chars = 12,
            },
        },
        f:static_text {
            title = LrView.bind 'exifmark_status',
            width_in_chars = 48, height_in_lines = 3, wrap = true,
        },
    }
end

local function writeRequest(path, request)
    local file, reason = io.open(path, 'wb')
    if not file then error('无法创建渲染请求：' .. tostring(reason)) end
    local success, writeError = file:write(Json.encode(request))
    local closed, closeError = file:close()
    if not success or not closed then error('无法写入渲染请求：' .. tostring(writeError or closeError)) end
end

local function errorMessage(path, exitCode)
    local file = io.open(path, 'rb')
    local message = file and file:read(4096) or ''
    if file then file:close() end
    message = message:gsub('%s+$', '')
    return message ~= '' and message or ('exifmark渲染失败，退出码：' .. tostring(exitCode))
end

function Filter.postProcessRenderedPhotos(functionContext, filterContext)
    local properties = filterContext.propertyTable
    local problem = compatibilityError(properties)
    local progress = LrProgressScope { title = 'exifmark · 生成照片卡片', functionContext = functionContext }
    local workDir = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'exifmark-' .. LrUUID.generateUUID())
    LrFileUtils.createAllDirectories(workDir)
    functionContext:addCleanupHandler(function()
        LrFileUtils.delete(workDir)
        progress:done()
    end)

    local total = #filterContext.renditionsToSatisfy
    local index = 0
    local renditionOptions = {
        filterSettings = function(rendition, upstream)
            -- Leave Lightroom's size, sharpening, privacy and ICC settings intact.
            upstream.LR_format = 'JPEG'
            upstream.LR_enableHDRDisplay = false
            upstream.LR_jpeg_useLimitSize = false
            return LrPathUtils.child(workDir, LrUUID.generateUUID() .. '.jpg')
        end,
    }

    local completed, exportError = LrTasks.pcall(function()
        for source, destination in filterContext:renditions(renditionOptions) do
            index = index + 1
            local sourcePath
            -- LrTasks.pcall supports the yields in waitForRender and execute.
            local ok, failure = LrTasks.pcall(function()
                if progress:isCanceled() then
                    source:skipRender()
                    error('导出已取消。')
                end
                if problem then source:skipRender(); error(problem) end
                local rendered, path = source:waitForRender()
                if not rendered then error(tostring(path)) end
                sourcePath = path
                if progress:isCanceled() then error('导出已取消。') end
                if destination.photo:getRawMetadata('isVideo') then error('exifmark支持静态照片。') end

                local fields = Metadata.read(destination.photo, LrTasks.pcall, function(timestamp)
                    return LrDate.timeToUserFormat(timestamp, '%Y.%m.%d %H:%M', true)
                end)
                local stem = LrPathUtils.child(workDir, LrUUID.generateUUID())
                local requestPath, errorPath = stem .. '.json', stem .. '.error'
                writeRequest(requestPath, {
                    version = 1,
                    input = sourcePath,
                    output = destination.destinationPath,
                    theme = properties.exifmark_theme,
                    layout = properties.exifmark_layout or 'bordered',
                    watermarkStyle = properties.exifmark_watermarkStyle or 'detailed',
                    cameraMake = fields.cameraMake, camera = fields.camera, lens = fields.lens,
                    cameraNameStyle = properties.exifmark_cameraNameStyle or 'common',
                    exposure = fields.exposure, capturedAt = fields.capturedAt,
                    focalLength = fields.focalLength,
                    quality = properties.LR_jpeg_quality or 0.9,
                })
                progress:setCaption(LrPathUtils.leafName(destination.destinationPath))
                local command = Settings.quote(helper) .. ' --request ' .. Settings.quote(requestPath)
                    .. ' > /dev/null 2> ' .. Settings.quote(errorPath)
                local exitCode = LrTasks.execute(command)
                if exitCode ~= 0 then error(errorMessage(errorPath, exitCode)) end
                if LrFileUtils.exists(destination.destinationPath) ~= 'file' then error('渲染程序未生成最终JPEG文件。') end
                LrFileUtils.delete(requestPath)
                LrFileUtils.delete(errorPath)
            end)
            -- Only dispose of images produced in this session's private scratch folder.
            if sourcePath and LrPathUtils.parent(sourcePath) == workDir then LrFileUtils.delete(sourcePath) end
            destination:renditionIsDone(ok, ok and nil or tostring(failure))
            progress:setPortionComplete(index, math.max(total, 1))
        end
    end)
    if not completed then error(exportError) end
end

Filter.exportPresetFields = {
    { key = 'exifmark_theme', default = 'white' },
    { key = 'exifmark_layout', default = 'bordered' },
    { key = 'exifmark_cameraNameStyle', default = 'common' },
    { key = 'exifmark_watermarkStyle', default = 'detailed' },
}
return Filter
