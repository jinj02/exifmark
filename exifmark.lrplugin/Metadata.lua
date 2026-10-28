-- SDK-independent formatting. The caller supplies LrTasks.pcall because reads can yield.
local Metadata = {}

local function text(value)
    if type(value) ~= 'string' then return '' end
    return (value:gsub('[%z\1-\31\127]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$'))
end

local function positive(value)
    if type(value) == 'number' and value > 0 and value < math.huge then return value end
end

local function number(value, precision)
    return (string.format('%.' .. (precision or 2) .. 'f', value):gsub(',', '.'):gsub('0+$', ''):gsub('%.$', ''))
end

function Metadata.shutter(seconds)
    seconds = positive(seconds)
    if not seconds then return '' end
    if seconds < 0.5 then
        local inverse = 1 / seconds
        if inverse < 10 then
            return '1/' .. number(math.floor(inverse * 10 + 0.5) / 10) .. 's'
        end
        return string.format('1/%ds', math.floor(inverse + 0.5))
    end
    return number(seconds) .. 's'
end

function Metadata.captureTime(iso)
    if type(iso) ~= 'string' then return '' end
    -- ISO components describe the camera clock; deliberately retain them across time zones.
    local y, m, d, h, min = iso:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d)')
    if not y then return '' end
    return string.format('%s.%s.%s %s:%s', y, m, d, h, min)
end

function Metadata.read(photo, protectedCall, fallbackDate)
    protectedCall = protectedCall or pcall
    local function read(method, key)
        local ok, value = protectedCall(function() return photo[method](photo, key) end)
        if ok then return value end
    end
    local function raw(key) return read('getRawMetadata', key) end
    local function formatted(key) return text(read('getFormattedMetadata', key)) end

    local lens = formatted('lens')
    local focalLength = positive(raw('focalLength'))
    local focal = focalLength and (number(focalLength) .. 'mm') or ''
    if focalLength then
        lens = lens ~= '' and (lens .. ' · ' .. focal) or focal
    end

    local exposure = {}
    local aperture = positive(raw('aperture'))
    if aperture then exposure[#exposure + 1] = 'f/' .. number(aperture) end
    local shutter = Metadata.shutter(raw('shutterSpeed'))
    if shutter ~= '' then exposure[#exposure + 1] = shutter end
    local iso = positive(raw('isoSpeedRating'))
    if iso then exposure[#exposure + 1] = string.format('ISO %d', math.floor(iso + 0.5)) end

    local capturedAt = Metadata.captureTime(raw('dateTimeOriginalISO8601'))
    if capturedAt == '' then capturedAt = Metadata.captureTime(raw('dateTimeISO8601')) end
    if capturedAt == '' and fallbackDate then
        local timestamp = raw('dateTimeOriginal') or raw('dateTime')
        if type(timestamp) == 'number' then
            local ok, date = protectedCall(function() return fallbackDate(timestamp) end)
            if ok then capturedAt = text(date) end
        end
    end

    -- Keep camera identifiers exactly as supplied by the SDK. Display cleanup belongs to rendering.
    local make = raw('cameraMake')
    if type(make) ~= 'string' then make = read('getFormattedMetadata', 'cameraMake') end
    local model = raw('cameraModel')
    if type(model) ~= 'string' then model = read('getFormattedMetadata', 'cameraModel') end

    return {
        cameraMake = type(make) == 'string' and make or '',
        camera = type(model) == 'string' and model or '',
        lens = lens,
        focalLength = focal,
        exposure = table.concat(exposure, ' · '),
        capturedAt = capturedAt,
    }
end

return Metadata
