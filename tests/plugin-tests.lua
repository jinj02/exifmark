local root = assert(arg[1], 'Pass the project root')
assert(_VERSION == 'Lua 5.1', 'The Lightroom SDK uses Lua5.1; select it with EXIFY_LUA')
package.path = root .. '/exify.lrplugin/?.lua;' .. package.path
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
local valid = { LR_format = 'JPEG', exify_theme = 'white', LR_jpeg_quality = 0.9 }
equal(Settings.error(valid, true, true), nil)
equal(Settings.error(valid, false, true) ~= nil, true)
equal(Settings.error(valid, true, false) ~= nil, true)
for key, value in pairs({LR_format='TIFF', LR_enableHDRDisplay=true, LR_jpeg_useLimitSize=true, exify_theme='invalid'}) do
    local p = {}; for k,v in pairs(valid) do p[k] = v end; p[key] = value
    equal(Settings.error(p, true, true) ~= nil, true)
end
local scratch = '/tmp/exify-lua-tests-' .. os.time() .. '-' .. math.random(100000,999999)
assert(os.execute('mkdir -p ' .. Settings.quote(scratch)) == 0)
local special = "中文 ' \" $(touch /tmp/exify-injection-marker) `echo bad` & ; \\"
local quotedFile = scratch .. '/shell.txt'
assert(os.execute('printf %s ' .. Settings.quote(special) .. ' > ' .. Settings.quote(quotedFile)) == 0)
local f = assert(io.open(quotedFile, 'rb')); equal(f:read('*a'), special); f:close()
local uuid, cancellation, executeFailure, renderedCount = 0, false, false, 0
local createdWorkDir, requestPayload, executionCount
local function read(path)
    local file = io.open(path,'rb'); if not file then return end
    local value = file:read('*a'); file:close(); return value
end
local sdk = {
    LrDate = {timeToUserFormat = function() return '2026.10.27 09:41' end},
    LrFileUtils = {
        exists = function(path)
            if path == root .. '/exify.lrplugin/bin/exify-render' then return 'file' end
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
        execute = function(command)
            executionCount = executionCount+1
            requestPayload = assert(read(command:match("%-%-request '([^']+)'")))
            local output = requestPayload:match('"output":"(.-)"')
            if executeFailure then return 1 end
            local file = assert(io.open(output,'wb')); file:write('mock jpeg'); file:close(); return 0
        end,
    },
    LrProgressScope = function()
        return {isCanceled=function() return cancellation end, done=function() end,
            setCaption=function() end, setPortionComplete=function() end}
    end,
}
_G.import = function(name) return assert(sdk[name], 'Unsupported SDK import: ' .. name) end
_G._PLUGIN, _G.MAC_ENV = {path=root .. '/exify.lrplugin'}, true
local Filter = require 'ExportFilter'
equal(Filter.exportPresetFields[1].key, 'exify_theme')
equal(Filter.exportPresetFields[1].default, 'white')
local props = {LR_format='JPEG', LR_jpeg_quality=0.9, callbacks={}}
function props:addObserver(key,owner,callback) self.callbacks[key]=callback end
function props:removeObserver(key) self.callbacks[key]=nil end
Filter.startDialog(props)
equal(props.exify_theme,'white'); equal(props.LR_cantExportBecause,nil)
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
    executionCount,renderedCount=0,0
    local destinations,sources,cleanup={},{},{}
    for i=1,3 do
        destinations[i] = {photo=photo, destinationPath=scratch .. '/out-' .. i .. '.jpg',
            renditionIsDone=function(self,ok,message) self.ok=ok; self.message=message; self.calls=(self.calls or 0)+1 end}
    end
    local context = {propertyTable=valid, renditionsToSatisfy=destinations}
    function context:renditions(renditionOptions)
        local i=0
        return function()
            i=i+1; if i>#destinations then return end
            local upstream={LR_format='JPEG', LR_export_colorSpace='AdobeRGB', LR_removeLocationMetadata=true}
            local path=renditionOptions.filterSettings(destinations[i],upstream)
            equal(upstream.LR_format,'TIFF'); equal(upstream.LR_export_colorSpace,'AdobeRGB')
            equal(upstream.LR_removeLocationMetadata,true); equal(upstream.LR_enableHDRDisplay,false)
            local source={skipRender=function(self) self.skipped=true end, waitForRender=function()
                renderedCount=renderedCount+1
                if options.upstreamFailure and i==2 then return false,'upstream render failed' end
                local file=assert(io.open(path,'wb')); file:write('mock tiff'); file:close(); return true,path
            end}
            sources[i]=source; return source,destinations[i]
        end
    end
    Filter.postProcessRenderedPhotos({addCleanupHandler=function(_,cb) cleanup[#cleanup+1]=cb end},context)
    for _,callback in ipairs(cleanup) do callback() end
    for _,destination in ipairs(destinations) do equal(destination.calls,1) end
    equal(os.execute('test ! -e ' .. Settings.quote(createdWorkDir)),0)
    return destinations,sources
end
local destinations=runExport()
for _,d in ipairs(destinations) do equal(d.ok,true) end
equal(executionCount,3)
equal(requestPayload:find('f/2.8 · 1/250s · ISO 100',1,true) ~= nil,true)
destinations=runExport({upstreamFailure=true})
equal(destinations[1].ok,true); equal(destinations[2].ok,false); equal(destinations[3].ok,true); equal(executionCount,2)
destinations=runExport({fail=true})
for _,d in ipairs(destinations) do equal(d.ok,false) end
local sources
destinations,sources=runExport({cancel=true})
for i,d in ipairs(destinations) do equal(d.ok,false); equal(sources[i].skipped,true) end
equal(executionCount,0); equal(renderedCount,0)
assert(os.execute('rm -rf ' .. Settings.quote(scratch)) == 0)
print('Plugin validation: ' .. count .. ' assertions passed')
