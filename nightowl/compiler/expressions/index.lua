local Ast = require("nightowl.ast")
return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope
    local regs  = {}
    for i = 1, numReturns do
        regs[i] = self:allocRegister()
        if i == 1 then
            local bReg = self:compileExpression(expression.base,  funcDepth, 1)[1]
            local iReg = self:compileExpression(expression.index, funcDepth, 1)[1]
            self:addStatement(self:setRegister(scope, regs[i], Ast.IndexExpression(self:register(scope, bReg), self:register(scope, iReg))), {regs[i]}, {bReg, iReg}, true)
            self:freeRegister(bReg, false); self:freeRegister(iReg, false)
        else
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false)
        end
    end
    return regs
end
