local Ast = require("nightowl.ast")
return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope
    local regs  = {}
    for i = 1, numReturns do
        regs[i] = self:allocRegister()
        self:addStatement(self:setRegister(scope, regs[i], i==1 and Ast.StringExpression(expression.value) or Ast.NilExpression()), {regs[i]}, {}, false)
    end
    return regs
end
