local Ast  = require("nightowl.ast")
local util = require("nightowl.util")

return function(self, statement, funcDepth)
    local scope      = self.activeBlock.scope
    local checkBlock = self:createBlock()
    local innerBlock = self:createBlock()
    local finalBlock = self:createBlock()

    statement.__start_block = checkBlock
    statement.__final_block = finalBlock

    local posState = self.registers[self.POS_REGISTER]
    self.registers[self.POS_REGISTER] = self.VAR_REGISTER

    local initReg  = self:compileExpression(statement.initialValue, funcDepth, 1)[1]
    local finalEReg= self:compileExpression(statement.finalValue,   funcDepth, 1)[1]
    local finalReg = self:allocRegister(false)
    self:addStatement(self:copyRegisters(scope, {finalReg}, {finalEReg}), {finalReg}, {finalEReg}, false)
    self:freeRegister(finalEReg)

    local incrEReg = self:compileExpression(statement.incrementBy, funcDepth, 1)[1]
    local incrReg  = self:allocRegister(false)
    self:addStatement(self:copyRegisters(scope, {incrReg}, {incrEReg}), {incrReg}, {incrEReg}, false)
    self:freeRegister(incrEReg)

    local tmpReg      = self:allocRegister(false)
    local negReg      = self:allocRegister(false)
    local shouldSwap3 = math.random(1,2) == 2
    local sr4         = shouldSwap3 and {incrReg, tmpReg} or {tmpReg, incrReg}
    self:addStatement(self:setRegister(scope, tmpReg, Ast.NumberExpression(0)), {tmpReg}, {}, false)
    self:addStatement(self:setRegister(scope, negReg, Ast[shouldSwap3 and "LessThanExpression" or "GreaterThanExpression"](self:register(scope, sr4[1]), self:register(scope, sr4[2]))), {negReg}, {sr4[1], sr4[2]}, false)
    self:freeRegister(tmpReg)

    local curReg = self:allocRegister(true)
    self:addStatement(self:setRegister(scope, curReg, Ast.SubExpression(self:register(scope, initReg), self:register(scope, incrReg))), {curReg}, {initReg, incrReg}, false)
    self:freeRegister(initReg)
    self:addStatement(self:jmp(scope, Ast.NumberExpression(checkBlock.id)), {self.POS_REGISTER}, {}, false)

    self:setActiveBlock(checkBlock)
    scope = checkBlock.scope

    local sr    = util.shuffle({curReg, incrReg})
    self:addStatement(self:setRegister(scope, curReg, Ast.AddExpression(self:register(scope, sr[1]), self:register(scope, sr[2]))), {curReg}, {sr[1], sr[2]}, false)

    local t1 = self:allocRegister(false)
    local t2 = self:allocRegister(false)
    self:addStatement(self:setRegister(scope, t2, Ast.NotExpression(self:register(scope, negReg))), {t2}, {negReg}, false)

    local ss = math.random(1,2)==2
    local sr2 = ss and {curReg, finalReg} or {finalReg, curReg}
    self:addStatement(self:setRegister(scope, t1, Ast[ss and "LessThanOrEqualsExpression" or "GreaterThanOrEqualsExpression"](self:register(scope, sr2[1]), self:register(scope, sr2[2]))), {t1}, {sr2[1], sr2[2]}, false)
    self:addStatement(self:setRegister(scope, t1, Ast.AndExpression(self:register(scope, t2), self:register(scope, t1))), {t1}, {t1, t2}, false)

    local ss2 = math.random(1,2)==2
    local sr3 = ss2 and {curReg, finalReg} or {finalReg, curReg}
    self:addStatement(self:setRegister(scope, t2, Ast[ss2 and "GreaterThanOrEqualsExpression" or "LessThanOrEqualsExpression"](self:register(scope, sr3[1]), self:register(scope, sr3[2]))), {t2}, {sr3[1], sr3[2]}, false)
    self:addStatement(self:setRegister(scope, t2, Ast.AndExpression(self:register(scope, negReg), self:register(scope, t2))), {t2}, {t2, negReg}, false)
    self:addStatement(self:setRegister(scope, t1, Ast.OrExpression(self:register(scope, t2), self:register(scope, t1))), {t1}, {t1, t2}, false)
    self:freeRegister(t2)

    local innerIdReg = self:compileExpression(Ast.NumberExpression(innerBlock.id), funcDepth, 1)[1]
    self:addStatement(self:setRegister(scope, self.POS_REGISTER, Ast.AndExpression(self:register(scope, t1), self:register(scope, innerIdReg))), {self.POS_REGISTER}, {t1, innerIdReg}, false)
    self:freeRegister(innerIdReg); self:freeRegister(t1)
    local finalIdReg = self:compileExpression(Ast.NumberExpression(finalBlock.id), funcDepth, 1)[1]
    self:addStatement(self:setRegister(scope, self.POS_REGISTER, Ast.OrExpression(self:register(scope, self.POS_REGISTER), self:register(scope, finalIdReg))), {self.POS_REGISTER}, {self.POS_REGISTER, finalIdReg}, false)
    self:freeRegister(finalIdReg)

    self:setActiveBlock(innerBlock)
    scope = innerBlock.scope
    self.registers[self.POS_REGISTER] = posState

    local varReg = self:getVarRegister(statement.scope, statement.id, funcDepth, nil)
    if self:isUpvalue(statement.scope, statement.id) then
        scope:addReferenceToHigherScope(self.scope, self.allocUpvalFunction)
        self:addStatement(self:setRegister(scope, varReg, Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.allocUpvalFunction), {})), {varReg}, {}, false)
        self:addStatement(self:setUpvalueMember(scope, self:register(scope, varReg), self:register(scope, curReg)), {}, {varReg, curReg}, true)
    else
        self:addStatement(self:setRegister(scope, varReg, self:register(scope, curReg)), {varReg}, {curReg}, false)
    end

    self:compileBlock(statement.body, funcDepth)
    self:addStatement(self:setRegister(self.activeBlock.scope, self.POS_REGISTER, Ast.NumberExpression(checkBlock.id)), {self.POS_REGISTER}, {}, false)

    self.registers[self.POS_REGISTER] = self.VAR_REGISTER
    self:freeRegister(finalReg); self:freeRegister(negReg); self:freeRegister(incrReg); self:freeRegister(curReg, true)
    self.registers[self.POS_REGISTER] = posState
    self:setActiveBlock(finalBlock)
end
