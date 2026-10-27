local root = assert(arg[1], 'Pass the project root')
assert(_VERSION == 'Lua 5.1', 'The Lightroom SDK uses Lua5.1; select it with EXIFMARK_LUA')
package.path = root .. '/exifmark.lrplugin/?.lua;' .. package.path
local Metadata, Json, Settings = require 'Metadata', require 'Json', require 'Settings'
local count = 0
local function equal(actual, expected)
    count = count + 1
    assert(actual == expected, string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
end
for _, case in ipairs({{1/250,'1/250s'}, {1/8000,'1/8000s'}, {1/2.5,'1/2.5s'}, {0.8,'0.8s'}, {30,'30s'}, {-1,''}}) do
    equal(Metadata.shutter(case[1]), case[2])
end
equal(Metadata.shutter(nil), '')
equal(Metadata.captureTime('2026-10-27T09:41:35+09:00'), '2026.10.27 09:41')
equal(Metadata.captureTime('2026-10-27T09:41:35-07:00'), '2026.10.27 09:41')
equal(Metadata.captureTime(nil), '')
local raw = { aperture = 2.8, shutterSpeed = 1/250, isoSpeedRating = 100,
    focalLength = 35, dateTimeOriginalISO8601 = '2026-10-27T09:41:35+09:00' }
local formatted = { cameraModel = 'ILCE-7M4', lens = 'FE 24-70mm F2.8 GM II' }
local photo = {getRawMetadata = function(_, key) return raw[key] end,
    getFormattedMetadata = function(_, key) return formatted[key] end}
local fields = Metadata.read(photo)
equal(fields.camera, 'ILCE-7M4')
equal(fields.lens, 'FE 24-70mm F2.8 GM II · 35mm')
equal(fields.exposure, 'f/2.8 · 1/250s · ISO 100')
equal(fields.capturedAt, '2026.10.27 09:41')
local missing = Metadata.read({getRawMetadata = function() error('missing') end, getFormattedMetadata = function() end})
for _, key in ipairs({'camera','lens','exposure','capturedAt'}) do equal(missing[key], '') end
raw.aperture, raw.shutterSpeed = nil, nil
equal(Metadata.read(photo).exposure, 'ISO 100')
raw.aperture, raw.shutterSpeed = 2.8, 1/250
equal(Json.encode('"\n\0\\'), '"\\"\\n\\u0000\\\\"')
equal(pcall(Json.encode, math.huge), false)
equal(pcall(Json.encode, 0/0), false)
local valid = { LR_format = 'JPEG', exifmark_theme = 'white', LR_jpeg_quality = 0.9 }
equal(Settings.error(valid, true, true), nil)
equal(Settings.error(valid, false, true) ~= nil, true)
equal(Settings.error(valid, true, false) ~= nil, true)
for key, value in pairs({LR_format='TIFF', LR_enableHDRDisplay=true, LR_jpeg_useLimitSize=true,
    exifmark_theme='invalid', exifmark_layout='invalid'}) do
    local p = {}; for k,v in pairs(valid) do p[k] = v end; p[key] = value
    equal(Settings.error(p, true, true) ~= nil, true)
end
local scratch = '/tmp/exifmark-lua-tests-' .. os.time() .. '-' .. math.random(100000,999999)
assert(os.execute('mkdir -p ' .. Settings.quote(scratch)) == 0)
local special = "中文 ' \" $(touch /tmp/exifmark-injection-marker) `echo bad` & ; \\"
local quotedFile = scratch .. '/shell.txt'
assert(os.execute('printf %s ' .. Settings.quote(special) .. ' > ' .. Settings.quote(quotedFile)) == 0)
local f = assert(io.open(quotedFile, 'rb')); equal(f:read('*a'), special); f:close()
local uuid, cancellation, executeFailure, renderedCount = 0, false, false, 0
local createdWorkDir, requestPayload, executionCount, installCount, lrcExportCount
local exportOptions = {}
local catalog, entries = {}, {}
local original = {getRawMetadata = function() return '/photos/original.arw' end}
local active, selected, activeSources, viewFilter
local removalCalls, sleepCalls
function catalog:findPhotoByPath(path) return entries[path] end
function catalog:withWriteAccessDo(_, callback, options)
    equal(options.timeout,30)
    return callback()
end
function catalog:addPhoto(path)
    equal(path:sub(-4),'.tif')
    entries[path]={getRawMetadata=function(_,key) if key=='path' then return path end end}
end
function catalog:getTargetPhoto() return active end
function catalog:getTargetPhotos()
    if exportOptions.selectionFailure then return {original} end
    return selected
end
function catalog:getActiveSources() return activeSources end
function catalog:getCurrentViewFilter() return viewFilter end
function catalog:getFolderByPath(path) return {path=path} end
function catalog:setActiveSources(value) activeSources=value; return true end
function catalog:setViewFilter(value) viewFilter=value; return true end
function catalog:setSelectedPhotos(value, others) active=value; selected=others end
local function read(path)
    local file = io.open(path,'rb'); if not file then return end
    local value = file:read('*a'); file:close(); return value
end
local sdk = {
    LrDate = {timeToUserFormat = function() return '2026.10.27 09:41' end},
    LrFileUtils = {
        exists = function(path)
            if path == root .. '/exifmark.lrplugin/bin/exifmark-render' then return 'file' end
            local file = io.open(path,'rb'); if file then file:close(); return 'file' end
        end,
        createAllDirectories = function(path) createdWorkDir=path; assert(os.execute('mkdir -p ' .. Settings.quote(path)) == 0) end,
        delete = function(path)
            assert(path:sub(1,#scratch+1) == scratch .. '/', 'Cleanup must stay in the test folder')
            return os.execute('rm -rf ' .. Settings.quote(path)) == 0
        end,
    },
    LrPathUtils = {
        child = function(parent,name) return parent .. '/' .. name end,
        parent = function(path) return path:match('^(.*)/[^/]+$') end,
        leafName = function(path) return path:match('[^/]+$') end,
        getStandardFilePath = function() return scratch end,
    },
    LrUUID = {generateUUID = function() uuid=uuid+1; return tostring(uuid) end},
    LrView = {bind = function(value) return value end},
    LrTasks = {
        pcall = pcall,
        sleep = function() sleepCalls=sleepCalls+1 end,
        execute = function(command)
            local install=command:find('--install-jpeg',1,true)
            local path=command:match("%-%-request '([^']+)'") or command:match("%-%-install%-jpeg '([^']+)'")
            local payload=assert(read(path))
            local output=payload:match('"output":"(.-)"')
            local contents
            if install then
                installCount=installCount+1
                if exportOptions.installFailure then return 1 end
                contents=assert(read(payload:match('"input":"(.-)"')))
                equal(contents:sub(1,8),'LrC JPEG')
            else
                executionCount=executionCount+1
                requestPayload=payload
                equal(output:sub(-4),'.tif')
                if executeFailure then return 1 end
                contents='mock lossless TIFF'
            end
            local file=assert(io.open(output,'wb')); file:write(contents); file:close(); return 0
        end,
    },
    LrSelection = {
        selectNone = function() active=nil; selected={} end,
        removeFromCatalog = function()
            removalCalls=removalCalls+1
            equal(#selected,1)
            local path=selected[1]:getRawMetadata('path')
            equal(path:sub(1,#createdWorkDir+1),createdWorkDir .. '/')
            equal(selected[1]~=original,true)
            if not exportOptions.cleanupFailure then entries[path]=nil end
        end,
    },
    LrExportSession = function(params)
        lrcExportCount=lrcExportCount+1
        local n=lrcExportCount
        local settings=params.exportSettings
        equal(#params.photosToExport,1)
        equal(settings.LR_format,'JPEG')
        equal(settings.LR_jpeg_quality,exportOptions.quality or 0.9)
        equal(settings.LR_export_colorSpace,'AdobeRGB')
        equal(settings.LR_removeLocationMetadata,true)
        equal(settings.LR_size_doConstrain,false)
        equal(settings.LR_outputSharpeningOn,false)
        equal(settings.LR_useWatermark,false)
        equal(settings.LR_reimportExportedPhoto,false)
        equal(next(settings.LR_exportFiltersFromThisPlugin),nil)
        equal(settings.exifmark_layout,nil)
        local input=params.photosToExport[1]:getRawMetadata('path')
        equal(read(input),'mock lossless TIFF')
        local output=input:gsub('%.tif$','.jpg')
        return {renditions=function()
            local visited=false
            return function()
                if visited then return end; visited=true
                return 1,{waitForRender=function()
                    if exportOptions.lrcFailure and n==2 then return false,'mock LrC failure' end
                    local file=assert(io.open(output,'wb'))
                    file:write('LrC JPEG quality=' .. tostring(settings.LR_jpeg_quality)); file:close()
                    return true,output
                end}
            end
        end}
    end,
    LrProgressScope = function()
        return {isCanceled=function() return cancellation end, done=function() end,
            setCaption=function() end, setPortionComplete=function() end}
    end,
}
_G.import = function(name) return assert(sdk[name], 'Unsupported SDK import: ' .. name) end
_G._PLUGIN, _G.MAC_ENV = {path=root .. '/exifmark.lrplugin'}, true
local Filter = require 'ExportFilter'
equal(Filter.exportPresetFields[1].key, 'exifmark_theme')
equal(Filter.exportPresetFields[1].default, 'white')
equal(Filter.exportPresetFields[2].key, 'exifmark_layout')
equal(Filter.exportPresetFields[2].default, 'bordered')
local props = {LR_format='JPEG', LR_jpeg_quality=0.9, callbacks={}}
function props:addObserver(key,owner,callback) self.callbacks[key]=callback end
function props:removeObserver(key) self.callbacks[key]=nil end
Filter.startDialog(props)
equal(props.exifmark_theme,'white'); equal(props.LR_cantExportBecause,nil)
equal(props.exifmark_layout,'bordered')
equal(props.exifmark_status:find('各留白2%',1,true) ~= nil,true)
props.exifmark_layout='bottomOnly'; props.callbacks.exifmark_layout()
equal(props.LR_cantExportBecause,nil)
equal(props.exifmark_status:find('底部追加8%',1,true) ~= nil,true)
equal(props.exifmark_status:find('各留白2%',1,true),nil)
props.exifmark_layout='invalid'; props.callbacks.exifmark_layout()
equal(props.LR_cantExportBecause ~= nil,true)
props.exifmark_layout='bordered'; props.callbacks.exifmark_layout()
equal(props.LR_cantExportBecause,nil)
props.LR_enableHDRDisplay=true; props.callbacks.LR_enableHDRDisplay()
equal(props.LR_cantExportBecause ~= nil,true)
props.LR_enableHDRDisplay=false; props.callbacks.LR_enableHDRDisplay()
equal(props.LR_cantExportBecause,nil)
props.LR_cantExportBecause='another plugin error'
props.LR_format='PNG'; props.callbacks.LR_format()
equal(props.LR_cantExportBecause,'another plugin error')
Filter.endDialog(props)
equal(next(props.callbacks),nil); equal(props.LR_cantExportBecause,'another plugin error')
local function runExport(options)
    options=options or {}
    cancellation,executeFailure = options.cancel or false,options.fail or false
    exportOptions=options
    entries={}
    active,selected,activeSources,viewFilter=original,{original},{'original folder'},{filtersActive=true}
    removalCalls,sleepCalls=0,0
    executionCount,renderedCount,installCount,lrcExportCount=0,0,0,0
    local destinations,sources,cleanup={},{},{}
    for i=1,3 do
        destinations[i] = {photo=photo, destinationPath=scratch .. '/out-' .. i .. '.jpg',
            renditionIsDone=function(self,ok,message) self.ok=ok; self.message=message; self.calls=(self.calls or 0)+1 end}
    end
    local exportProperties = {}; for key,value in pairs(valid) do exportProperties[key]=value end
    exportProperties.exifmark_layout = options.layout
    exportProperties.LR_jpeg_quality=options.quality or 0.9
    exportProperties.LR_export_colorSpace='AdobeRGB'
    exportProperties.LR_removeLocationMetadata=true
    exportProperties.LR_size_doConstrain=true
    exportProperties.LR_outputSharpeningOn=true
    exportProperties.LR_useWatermark=true
    exportProperties.LR_exportFiltersFromThisPlugin={exifmarkCard=1}
    local context = {propertyTable=exportProperties, renditionsToSatisfy=destinations,
        sourceExportSession={catalog=catalog}}
    function context:renditions(renditionOptions)
        local i=0
        return function()
            i=i+1; if i>#destinations then return end
            local upstream={LR_format='JPEG', LR_export_colorSpace='AdobeRGB', LR_removeLocationMetadata=true}
            local path=renditionOptions.filterSettings(destinations[i],upstream)
            equal(upstream.LR_format,'TIFF'); equal(upstream.LR_export_colorSpace,'AdobeRGB')
            equal(upstream.LRtiff_compressionMethod,'compressionMethod_ZIP')
            equal(upstream.LR_removeLocationMetadata,true); equal(upstream.LR_enableHDRDisplay,false)
            local source={skipRender=function(self) self.skipped=true end, waitForRender=function()
                renderedCount=renderedCount+1
                if options.upstreamFailure and i==2 then return false,'upstream render failed' end
                local file=assert(io.open(path,'wb')); file:write('mock tiff'); file:close(); return true,path
            end}
            sources[i]=source; return source,destinations[i]
        end
    end
    local ok,message=pcall(Filter.postProcessRenderedPhotos,
        {addCleanupHandler=function(_,cb) cleanup[#cleanup+1]=cb end},context)
    for _,callback in ipairs(cleanup) do callback() end
    if not options.expectError then equal(ok,true) end
    for _,destination in ipairs(destinations) do equal(destination.calls,1) end
    if options.cleanupFailure or options.selectionFailure then
        equal(os.execute('test -d ' .. Settings.quote(createdWorkDir)),0)
        equal(next(entries)~=nil,true)
    else
        equal(os.execute('test ! -e ' .. Settings.quote(createdWorkDir)),0)
        equal(next(entries),nil)
    end
    equal(active,original); equal(#selected,1); equal(selected[1],original)
    equal(activeSources[1],'original folder'); equal(viewFilter.filtersActive,true)
    equal(exportProperties.LR_jpeg_quality,options.quality or 0.9)
    equal(exportProperties.LR_size_doConstrain,true)
    equal(exportProperties.LR_outputSharpeningOn,true)
    equal(exportProperties.LR_useWatermark,true)
    equal(exportProperties.LR_exportFiltersFromThisPlugin.exifmarkCard,1)
    return destinations,sources,ok,message
end
local destinations=runExport()
for _,d in ipairs(destinations) do equal(d.ok,true) end
equal(executionCount,3); equal(installCount,3); equal(lrcExportCount,3); equal(removalCalls,3)
equal(read(scratch .. '/out-1.jpg'),'LrC JPEG quality=0.9')
equal(requestPayload:find('f/2.8 · 1/250s · ISO 100',1,true) ~= nil,true)
equal(requestPayload:find('"layout":"bordered"',1,true) ~= nil,true)
destinations=runExport({layout='bottomOnly'})
for _,d in ipairs(destinations) do equal(d.ok,true) end
equal(requestPayload:find('"layout":"bottomOnly"',1,true) ~= nil,true)
destinations=runExport({upstreamFailure=true})
equal(destinations[1].ok,true); equal(destinations[2].ok,false); equal(destinations[3].ok,true); equal(executionCount,2)
destinations=runExport({fail=true})
for _,d in ipairs(destinations) do equal(d.ok,false) end
local sources
destinations,sources=runExport({cancel=true})
for i,d in ipairs(destinations) do equal(d.ok,false); equal(sources[i].skipped,true) end
equal(executionCount,0); equal(renderedCount,0)
-- The requested quality reaches Lightroom unchanged, including both endpoints.
for _,quality in ipairs({0,1}) do
    destinations=runExport({quality=quality})
    for _,d in ipairs(destinations) do equal(d.ok,true) end
    equal(read(scratch .. '/out-1.jpg'),'LrC JPEG quality=' .. tostring(quality))
end
destinations=runExport({lrcFailure=true})
equal(destinations[1].ok,true); equal(destinations[2].ok,false); equal(destinations[3].ok,true)
equal(installCount,2); equal(removalCalls,3)
destinations=runExport({installFailure=true})
for _,d in ipairs(destinations) do equal(d.ok,false) end
equal(removalCalls,3)
local ok,message
destinations,_,ok,message=runExport({cleanupFailure=true,expectError=true})
equal(ok,false); equal(message:find('清理失败',1,true)~=nil,true)
equal(removalCalls,1)
destinations,_,ok,message=runExport({selectionFailure=true,expectError=true})
equal(ok,false); equal(removalCalls,0)
assert(os.execute('rm -rf ' .. Settings.quote(scratch)) == 0)
print('Plugin validation: ' .. count .. ' assertions passed')
