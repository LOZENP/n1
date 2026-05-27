local Ast     = require("nightowl.ast")
local AstKind = Ast.AstKind

return function(self, expression, funcDepth, numReturns)
    local scope     = self.activeBlock.scope
    local baseReg   = self:compileExpression(expression.base, funcDepth, 1)[1]
    local returnAll = numReturns == self.RETURN_ALL
    local retRegs   = {}
    if returnAll then
        retRegs[1] = self:allocRegister(false)
    else
        for i = 1, numReturns do retRegs[i] = self:allocRegister(false) end
    end

    local args = {self:register(scope, baseReg)}
    local regs = {baseReg}

    for i, expr in ipairs(expression.args) do
        if i == #expression.args and (expr.kind == AstKind.FunctionCallExpression or expr.kind == AstKind.PassSelfFunctionCallExpression or expr.kind == AstKind.VarargExpression) then
            local reg = self:compileExpression(expr, funcDepth, self.RETURN_ALL)[1]
            table.insert(args, Ast.FunctionCallExpression(self:unpack(scope), {self:register(scope, reg)}))
            table.insert(regs, reg)
        else
            local reg = self:compileExpression(expr, funcDepth, 1)[1]
            table.insert(args, self:register(scope, reg))
            table.insert(regs, reg)
        end
    end

    local tmp = self:allocRegister(false)
    self:addStatement(self:setRegister(scope, tmp, Ast.StringExpression(expression.passSelfFunctionName)), {tmp}, {}, false)
    self:addStatement(self:setRegister(scope, tmp, Ast.IndexExpression(self:register(scope, baseReg), self:register(scope, tmp))), {tmp}, {baseReg, tmp}, false)

    if returnAll then
        self:addStatement(self:setRegister(scope, retRegs[1], Ast.TableConstructorExpression{Ast.TableEntry(Ast.FunctionCallExpression(self:register(scope, tmp), args))}), {retRegs[1]}, {tmp, table.unpack(regs)}, true)
    elseif numReturns > 1 then
        self:addStatement(self:setRegister(scope, tmp, Ast.TableConstructorExpression{Ast.TableEntry(Ast.FunctionCallExpression(self:register(scope, tmp), args))}), {tmp}, {tmp, table.unpack(regs)}, true)
        for i, reg in ipairs(retRegs) do
            self:addStatement(self:setRegister(scope, reg, Ast.IndexExpression(self:register(scope, tmp), Ast.NumberExpression(i))), {reg}, {tmp}, false)
        end
    else
        self:addStatement(self:setRegister(scope, retRegs[1], Ast.FunctionCallExpression(self:register(scope, tmp), args)), {retRegs[1]}, {baseReg, table.unpack(regs)}, true)
    end

    self:freeRegister(tmp, false)
    for _, reg in ipairs(regs) do self:freeRegister(reg, false) end
    return retRegs
end
