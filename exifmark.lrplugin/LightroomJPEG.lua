local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrSelection = import 'LrSelection'
local LrTasks = import 'LrTasks'

local LightroomJPEG = {}
LightroomJPEG.__index = LightroomJPEG
local cleaning = false

function LightroomJPEG.new(catalog, workDir)
    assert(catalog, '无法获取当前导出使用的LrC目录。')
    assert(type(LrSelection.removeFromCatalog) == 'function', '自动清理中间图需要LrC14.3及以上。')
    return setmetatable({catalog = catalog, workDir = workDir, pending = {}}, LightroomJPEG)
end

function LightroomJPEG:isClean()
    return next(self.pending) == nil
end

function LightroomJPEG:encode(input, properties)
    assert(LrPathUtils.parent(input) == self.workDir, '中间图必须位于本次导出的临时目录。')
    local catalog = self.catalog
    assert(not catalog:findPhotoByPath(input), '中间图已存在于LrC目录。')
    -- Track the path before acquiring the write gate so a partial failure can be cleaned up.
    self.pending[input] = true
    catalog:withWriteAccessDo('exifmark · 临时载入带框图', function()
        catalog:addPhoto(input)
    end, {timeout = 30})
    local photo = assert(catalog:findPhotoByPath(input), 'LrC未能载入带框TIFF。')

    -- Build a fresh export session. No export filters or publishing actions are inherited.
    local settings = {
        LR_format = 'JPEG',
        LR_jpeg_quality = properties.LR_jpeg_quality or 0.9,
        LR_jpeg_useLimitSize = properties.LR_jpeg_useLimitSize or false,
        LR_export_colorSpace = properties.LR_export_colorSpace or 'sRGB',
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = self.workDir,
        LR_export_useSubfolder = false,
        LR_renamingTokensOn = false,
        LR_extensionCase = 'lowercase',
        LR_collisionHandling = 'overwrite',
        LR_reimportExportedPhoto = false,
        LR_exportFiltersFromThisPlugin = {},
        -- The first render already applies sizing, sharpening and watermarking.
        LR_size_doConstrain = false,
        LR_outputSharpeningOn = false,
        LR_useWatermark = false,
        LR_enableHDRDisplay = false,
    }
    for _, key in ipairs({
        'LR_jpeg_limitSize', 'LR_size_resolution', 'LR_size_resolutionUnits',
        'LR_embeddedMetadataOption', 'LR_minimizeEmbeddedMetadata', 'LR_metadata_keywordOptions',
        'LR_removeLocationMetadata', 'LR_removeFaceMetadata', 'LR_removePersonMetadata',
    }) do
        settings[key] = properties[key]
    end
    local session = LrExportSession {photosToExport = {photo}, exportSettings = settings}
    local result
    for _, rendition in session:renditions() do
        assert(not result, 'LrC返回了多张中间成片。')
        local ok, path = rendition:waitForRender()
        if not ok then error('LrC最终JPEG导出失败：' .. tostring(path)) end
        assert(LrPathUtils.parent(path) == self.workDir, 'LrC成片超出本次导出的临时目录。')
        result = path
    end
    return assert(result, 'LrC未生成最终JPEG。')
end

local function waitUntil(predicate)
    for _ = 1, 100 do
        if predicate() then return true end
        LrTasks.sleep(0.05)
    end
    return false
end

function LightroomJPEG:cleanup()
    if self:isClean() then return end
    -- Selection commands are shared by all export tasks in this plug-in.
    while cleaning do LrTasks.sleep(0.05) end
    cleaning = true
    local catalog = self.catalog
    local active, selected, sources, viewFilter
    local ok, reason = LrTasks.pcall(function()
        for path in pairs(self.pending) do
            if not catalog:findPhotoByPath(path) then self.pending[path] = nil end
        end
        if self:isClean() then return end
        active = catalog:getTargetPhoto()
        selected = active and catalog:getTargetPhotos() or {}
        sources = catalog:getActiveSources()
        viewFilter = catalog:getCurrentViewFilter()
        local folder = assert(catalog:getFolderByPath(self.workDir), '找不到临时图所在的LrC文件夹。')
        assert(catalog:setActiveSources({folder}), '无法切换到临时图文件夹。')
        catalog:setViewFilter({filtersActive = false})
        for path in pairs(self.pending) do
            assert(LrPathUtils.parent(path) == self.workDir, '拒绝清理临时目录之外的图像。')
            local photo = catalog:findPhotoByPath(path)
            if photo then
                catalog:setSelectedPhotos(photo, {photo})
                -- Never issue a selection command while any other photo is selected.
                assert(waitUntil(function()
                    local targets = catalog:getTargetPhotos()
                    return #targets == 1 and targets[1]:getRawMetadata('path') == path
                end), '无法独立选中临时图，已停止清理。')
                LrSelection.removeFromCatalog()
                assert(waitUntil(function() return not catalog:findPhotoByPath(path) end),
                    'LrC尚未移除临时图记录，已保留中间文件：' .. path)
            end
            self.pending[path] = nil
        end
    end)
    local restored, restoreError = LrTasks.pcall(function()
        if sources then catalog:setActiveSources(sources) end
        if viewFilter then catalog:setViewFilter(viewFilter) end
        if selected then
            if active then catalog:setSelectedPhotos(active, selected)
            else LrSelection.selectNone() end
        end
    end)
    cleaning = false
    if not ok then error(reason) end
    if not restored then error('无法恢复照片选择：' .. tostring(restoreError)) end
end

return LightroomJPEG
