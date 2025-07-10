local helpers = {}

function helpers.formatGold(value)
    value = tonumber(value) or 0
    local gold = math.floor(value / 10000)
    local silver = math.floor((value % 10000) / 100)
    local copper = value % 100
    local result = ""
    if gold > 0 then result = result .. gold .. "g " end
    if silver > 0 or gold > 0 then result = result .. silver .. "s " end
    result = result .. copper .. "c"
    return result
end

return helpers 
