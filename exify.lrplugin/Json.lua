-- Only encoding is needed: renderer results use exit status and plain UTF-8 errors.
local Json = {}
local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

function Json.encode(value)
    local kind = type(value)
    if kind == 'string' then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
            return escapes[c] or string.format('\\u%04x', string.byte(c))
        end) .. '"'
    elseif kind == 'number' then
        assert(value == value and math.abs(value) < math.huge, 'JSON requires finite numbers')
        return (string.format('%.17g', value):gsub(',', '.'))
    elseif kind == 'boolean' then
        return tostring(value)
    elseif kind == 'nil' then
        return 'null'
    elseif kind == 'table' then
        local parts = {}
        for key, item in pairs(value) do
            assert(type(key) == 'string', 'JSON object keys must be strings')
            parts[#parts + 1] = Json.encode(key) .. ':' .. Json.encode(item)
        end
        table.sort(parts)
        return '{' .. table.concat(parts, ',') .. '}'
    end
    error('Unsupported JSON value: ' .. kind)
end

return Json
