local Ast = require("nightowl.ast")

local CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"

local function randomString(len)
    len = len or math.random(4, 12)
    local t = {}
    for i=1,len do
        local idx = math.random(1, #CHARS)
        t[i] = CHARS:sub(idx,idx)
    end
    return table.concat(t)
end

local function randomStringNode(dict)
    if dict then
        local entries = {}
        for i=1,math.random(1,4) do
            entries[i] = Ast.KeyedTableEntry(
                Ast.StringExpression(randomString()),
                Ast.StringExpression(randomString())
            )
        end
        return Ast.TableConstructorExpression(entries)
    end
    return Ast.StringExpression(randomString())
end

return { randomString=randomString, randomStringNode=randomStringNode }
