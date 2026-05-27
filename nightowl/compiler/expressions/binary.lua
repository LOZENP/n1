local Ast = require("nightowl.ast")

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope
    local regs  = {}
    for i = 1, numReturns do
        regs[i] = self:allocRegister()
        if i == 1 then
            local lReg = self:compileExpression(expression.lhs, funcDepth, 1)[1]
            local rReg = self:compileExpression(expression.rhs, funcDepth, 1)[1]
            self:addStatement(self:setRegister(scope, regs[i], Ast[expression.kind](self:register(scope, lReg), self:register(scope, rReg))), {regs[i]}, {lReg, rReg}, true)
            self:freeRegister(rReg, false); self:freeRegister(lReg, false)
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false)
        end
    end
    return regs
end
