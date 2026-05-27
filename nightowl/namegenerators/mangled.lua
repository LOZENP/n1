local util = require("nightowl.util")
local VarDigits      = util.chararray("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
local VarStartDigits = util.chararray("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

return function(id, _)
    local name = ""
    local d = id % #VarStartDigits
    id = (id - d) / #VarStartDigits
    name = name .. VarStartDigits[d+1]
    while id > 0 do
        local e = id % #VarDigits
        id = (id - e) / #VarDigits
        name = name .. VarDigits[e+1]
    end
    return name
end
