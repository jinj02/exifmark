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
local helper = LrPathUtils.child(_PLUGIN.path, 'bin/exify-render')
local dialogObservers = setmetatable({}, { __mode = 'k' })

local function compatibilityError(properties)
    return Settings.error(properties, MAC_ENV, LrFileUtils.exists(helper) == 'file')
end

local function updateStatus(properties)
    local reason = compatibilityError(properties)
    properties.exify_status = reason or '仅追加底部信息带；照片尺寸保持不变。'
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
    if properties.exify_theme == nil then properties.exify_theme = 'white' end
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
        title = 'exify照片卡片',
        bind_to_object = properties,
        synopsis = LrView.bind { key = 'exify_theme', object = properties,
            transform = function(value) return value == 'black' and '黑色信息带 · SONY' or '白色信息带 · SONY' end },
        f:row {
            f:static_text { title = '背景颜色：' },
            f:popup_menu {
                value = LrView.bind 'exify_theme',
                items = { { title = '白色', value = 'white' }, { title = '黑色', value = 'black' } },
                width_in_chars = 12,
            },
        },
        f:static_text {
            title = LrView.bind 'exify_status',
            width_in_chars = 48, height_in_lines = 2, wrap = true,
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
    return message ~= '' and message or ('exify渲染失败，退出码：' .. tostring(exitCode))
end

function Filter.postProcessRenderedPhotos(functionContext, filterContext)
    local properties = filterContext.propertyTable
    local problem = compatibilityError(properties)
    local progress = LrProgressScope { title = 'exify · 生成照片卡片', functionContext = functionContext }
    local workDir = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'exify-' .. LrUUID.generateUUID())
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
            upstream.LR_format = 'TIFF'
            upstream.LR_export_bitDepth = 8
            upstream.LR_tiff_compressionMethod = 'compressionMethod_ZIP'
            upstream.LR_tiff_preserveTransparency = false
            upstream.LR_enableHDRDisplay = false
            upstream.LR_jpeg_useLimitSize = false
            return LrPathUtils.child(workDir, LrUUID.generateUUID() .. '.tif')
        end,
    }

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
            if destination.photo:getRawMetadata('isVideo') then error('exify支持静态照片。') end

            local fields = Metadata.read(destination.photo, LrTasks.pcall, function(timestamp)
                return LrDate.timeToUserFormat(timestamp, '%Y.%m.%d %H:%M', true)
            end)
            local stem = LrPathUtils.child(workDir, LrUUID.generateUUID())
            local requestPath, errorPath = stem .. '.json', stem .. '.error'
            writeRequest(requestPath, {
                version = 1,
                input = sourcePath,
                output = destination.destinationPath,
                theme = properties.exify_theme,
                camera = fields.camera, lens = fields.lens,
                exposure = fields.exposure, capturedAt = fields.capturedAt,
                quality = properties.LR_jpeg_quality or 0.9,
            })
            progress:setCaption(LrPathUtils.leafName(destination.destinationPath))
            local command = Settings.quote(helper) .. ' --request ' .. Settings.quote(requestPath)
                .. ' > /dev/null 2> ' .. Settings.quote(errorPath)
            local exitCode = LrTasks.execute(command)
            if exitCode ~= 0 then error(errorMessage(errorPath, exitCode)) end
            if LrFileUtils.exists(destination.destinationPath) ~= 'file' then error('渲染程序未生成JPEG文件。') end
            LrFileUtils.delete(requestPath)
            LrFileUtils.delete(errorPath)
        end)
        -- Only dispose of images produced in this session's private scratch folder.
        if sourcePath and LrPathUtils.parent(sourcePath) == workDir then LrFileUtils.delete(sourcePath) end
        destination:renditionIsDone(ok, ok and nil or tostring(failure))
        progress:setPortionComplete(index, math.max(total, 1))
    end
end

Filter.exportPresetFields = { { key = 'exify_theme', default = 'white' } }
return Filter
