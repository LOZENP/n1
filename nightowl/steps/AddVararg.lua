local Step     = require("nightowl.step")
local Ast      = require("nightowl.ast")
local visitast = require("nightowl.visitast")
local AstKind  = Ast.AstKind

local AddVararg = Step:extend()
AddVararg.Name = "Add Vararg"
AddVararg.Description = "Adds ... to all functions"
AddVararg.SettingsDescriptor = {}

function AddVararg:init() end

function AddVararg:apply(ast)
    visitast(ast, nil, function(node)
        local k = node.kind
        if k==AstKind.FunctionDeclaration or k==AstKind.LocalFunctionDeclaration or k==AstKind.FunctionLiteralExpression then
            if #node.args < 1 or node.args[#node.args].kind ~= AstKind.VarargExpression then
                node.args[#node.args+1] = Ast.VarargExpression()
            end
        end
    end)
end

return AddVararg	
