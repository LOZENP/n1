local Ast = require("nightowl.ast")

return function(self, expression, funcDepth, numReturns)
    local scope    = self.activeBlock.scope
    local posState = self.registers[self.POS_REGISTER]
    self.registers[self.POS_REGISTER] = self.VAR_REGISTER

    local regs = {}
    for i = 1, numReturns do
        regs[i] = self:allocRegister()
        if i ~= 1 then self:addStatement(self:setRegister(scope, regs[i], Ast.NilExpression()), {regs[i]}, {}, false) end
    end

    local resReg = regs[1]
    local tmpReg
    if posState then
        tmpReg = self:allocRegister(false)
        self:addStatement(self:copyRegisters(scope, {tmpReg}, {self.POS_REGISTER}), {tmpReg}, {self.POS_REGISTER}, false)
    end

    local lReg = self:compileExpression(expression.lhs, funcDepth, 1)[1]
    if expression.rhs.isConstant then
        local rReg = self:compileExpression(expression.rhs, funcDepth, 1)[1]
        self:addStatement(self:setRegister(scope, resReg, Ast.AndExpression(self:register(scope, lReg), self:register(scope, rReg))), {resReg}, {lReg, rReg}, false)
        if tmpReg then self:freeRegister(tmpReg, false) end
        self:freeRegister(lReg, false); self:freeRegister(rReg, false)
        return regs
    end

    local b1, b2 = self:createBlock(), self:createBlock()
    self:addStatement(self:copyRegisters(scope, {resReg}, {lReg}), {resReg}, {lReg}, false)
    self:addStatement(self:setRegister(scope, self.POS_REGISTER,
        Ast.OrExpression(Ast.AndExpression(self:register(scope, lReg), Ast.NumberExpression(b1.id)), Ast.NumberExpression(b2.id))
    ), {self.POS_REGISTER}, {lReg}, false)
    self:freeRegister(lReg, false)

    self:setActiveBlock(b1)
    local rReg = self:compileExpression(expression.rhs, funcDepth, 1)[1]
    self:addStatement(self:copyRegisters(b1.scope, {resReg}, {rReg}), {resReg}, {rReg}, false)
    self:freeRegister(rReg, false)
    self:addStatement(self:setRegister(b1.scope, self.POS_REGISTER, Ast.NumberExpression(b2.id)), {self.POS_REGISTER}, {}, false)

    self.registers[self.POS_REGISTER] = posState
    self:setActiveBlock(b2)
    if tmpReg then
        self:addStatement(self:copyRegisters(b2.scope, {self.POS_REGISTER}, {tmpReg}), {self.POS_REGISTER}, {tmpReg}, false)
        self:freeRegister(tmpReg, false)
    end
    return regs
end
