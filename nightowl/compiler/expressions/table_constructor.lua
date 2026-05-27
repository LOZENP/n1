local Ast     = require("nightowl.ast")
local AstKind = Ast.AstKind

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope
    local regs  = {}
    for i = 1, numReturns do
        regs[i] = self:allocRegister()
        if i == 1 then
            local entries    = {}
            local entryRegs  = {}
            for j, entry in ipairs(expression.entries) do
                if entry.kind == AstKind.TableEntry then
                    local val = entry.value
                    if j == #expression.entries and (val.kind == AstKind.FunctionCallExpression or val.kind == AstKind.PassSelfFunctionCallExpression or val.kind == AstKind.VarargExpression) then
                        local reg = self:compileExpression(val, funcDepth, self.RETURN_ALL)[1]
                        table.insert(entries,   Ast.TableEntry(Ast.FunctionCallExpression(self:unpack(scope), {self:register(scope, reg)})))
                        table.insert(entryRegs, reg)
                    else
                        local reg = self:compileExpression(val, funcDepth, 1)[1]
                        table.insert(entries,   Ast.TableEntry(self:register(scope, reg)))
                        table.insert(entryRegs, reg)
                    end
                else
                    local kReg = self:compileExpression(entry.key,   funcDepth, 1)[1]
                    local vReg = self:compileExpression(entry.value, funcDepth, 1)[1]
                    table.insert(entries,   Ast.KeyedTableEntry(self:register(scope, kReg), self:register(scope, vReg)))
                    table.insert(entryRegs, vReg); table.insert(entryRegs, kReg)
                end
            end
            self:addStatement(self:setRegister(scope, regs[i], Ast.TableConstructorExpression(entries)), {regs[i]}, entryRegs, false)
            for _, reg in ipairs(entryRegs) do self:freeRegister(reg, false) end
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false)
        end
    end
    return regs
end
