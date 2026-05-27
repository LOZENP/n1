local Ast = require("nightowl.ast")

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope
    local regs  = {}
    for i = 1, numReturns do
        if i == 1 then
            if expression.scope.isGlobal then
                regs[i] = self:allocRegister(false)
                local tmp = self:allocRegister(false)
                self:addStatement(self:setRegister(scope, tmp, Ast.StringExpression(expression.scope:getVariableName(expression.id))), {tmp}, {}, false)
                self:addStatement(self:setRegister(scope, regs[i], Ast.IndexExpression(self:env(scope), self:register(scope, tmp))), {regs[i]}, {tmp}, true)
                self:freeRegister(tmp, false)
            else
                if self.scopeFunctionDepths[expression.scope] == funcDepth then
                    if self:isUpvalue(expression.scope, expression.id) then
                        local reg    = self:allocRegister(false)
                        local varReg = self:getVarRegister(expression.scope, expression.id, funcDepth, nil)
                        self:addStatement(self:setRegister(scope, reg, self:getUpvalueMember(scope, self:register(scope, varReg))), {reg}, {varReg}, true)
                        regs[i] = reg
                    else
                        regs[i] = self:getVarRegister(expression.scope, expression.id, funcDepth, nil)
                    end
                else
                    local reg = self:allocRegister(false)
                    local uid = self:getUpvalueId(expression.scope, expression.id)
                    scope:addReferenceToHigherScope(self.containerFuncScope, self.currentUpvaluesVar)
                    self:addStatement(self:setRegister(scope, reg, self:getUpvalueMember(scope, Ast.IndexExpression(Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar), Ast.NumberExpression(uid)))), {reg}, {}, true)
                    regs[i] = reg
                end
            end
        else
            regs[i] = self:allocRegister()
            self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false)
        end
    end
    return regs
end
