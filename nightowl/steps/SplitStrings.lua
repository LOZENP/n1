local Step     = require("nightowl.step")
local Ast      = require("nightowl.ast")
local visitast = require("nightowl.visitast")
local util     = require("nightowl.util")
local AstKind  = Ast.AstKind

local SplitStrings = Step:extend()
SplitStrings.Name = "Split Strings"
SplitStrings.Description = "Splits string literals into concatenated chunks"
SplitStrings.SettingsDescriptor = {
    Threshold  = {type="number", default=1, min=0, max=1},
    MinLength  = {type="number", default=3, min=1},
    MaxLength  = {type="number", default=8, min=1},
}

function SplitStrings:init() end

function SplitStrings:apply(ast)
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression then
            if math.random() > self.Threshold then return end
            local str = node.value
            local chunks = {}
            local i = 1
            while i <= #str do
                local len = math.random(self.MinLength, self.MaxLength)
                table.insert(chunks, str:sub(i, i+len-1))
                i = i + len
            end
            if #chunks > 1 then
                local n = nil
                for _, chunk in ipairs(chunks) do
                    if n then n = Ast.StrCatExpression(n, Ast.StringExpression(chunk))
                    else n = Ast.StringExpression(chunk) end
                end
                return n
            end
        end
    end)
end

return SplitStrings
