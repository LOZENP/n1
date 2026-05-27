local Ast = require("nightowl.ast")

return function(self, statement, funcDepth)
    local scope    = self.activeBlock.scope
    local expLen   = #statement.expressions
    local exprregs = {}

    for i, expr in ipairs(statement.expressions) do
        if i == expLen and expLen < 3 then
            local regs = self:compileExpression(expr, funcDepth, 4 - expLen)
            for j = 1, 4 - expLen do table.insert(exprregs, regs[j]) end
        else
            if i <= 3 then
                table.insert(exprregs, self:compileExpression(expr, funcDepth, 1)[1])
            else
                self:freeRegister(self:compileExpression(expr, funcDepth, 1)[1], false)
            end
        end
    end

    for i, reg in ipairs(exprregs) do
        if reg and self.registers[reg] ~= self.VAR_REGISTER and reg ~= self.POS_REGISTER and reg ~= self.RETURN_REGISTER then
            self.registers[reg] = self.VAR_REGISTER
        else
            exprregs[i] = self:allocRegister(true)
            self:addStatement(self:copyRegisters(scope, {exprregs[i]}, {reg}), {exprregs[i]}, {reg}, false)
        end
    end

    local checkBlock = self:createBlock()
    local bodyBlock  = self:createBlock()
    local finalBlock = self:createBlock()

    statement.__start_block = checkBlock
    statement.__final_block = finalBlock

    self:addStatement(self:setPos(scope, checkBlock.id), {self.POS_REGISTER}, {}, false)
    self:setActiveBlock(checkBlock)
    local sc = self.activeBlock.scope

    local varRegs = {}
    for i, id in ipairs(statement.ids) do
        varRegs[i] = self:getVarRegister(statement.scope, id, funcDepth)
    end

    self:addStatement(Ast.AssignmentStatement({
        self:registerAssignment(sc, exprregs[3]),
        varRegs[2] and self:registerAssignment(sc, varRegs[2]),
    }, {
        Ast.FunctionCallExpression(self:register(sc, exprregs[1]), {self:register(sc, exprregs[2]), self:register(sc, exprregs[3])})
    }), {exprregs[3], varRegs[2]}, {exprregs[1], exprregs[2], exprregs[3]}, true)

    self:addStatement(Ast.AssignmentStatement({self:posAssignment(sc)}, {
        Ast.OrExpression(Ast.AndExpression(self:register(sc, exprregs[3]), Ast.NumberExpression(bodyBlock.id)), Ast.NumberExpression(finalBlock.id))
    }), {self.POS_REGISTER}, {exprregs[3]}, false)

    self:setActiveBlock(bodyBlock)
    sc = self.activeBlock.scope
    self:addStatement(self:copyRegisters(sc, {varRegs[1]}, {exprregs[3]}), {varRegs[1]}, {exprregs[3]}, false)

    for i = 3, #varRegs do
        self:addStatement(self:setRegister(sc, varRegs[i], Ast.NilExpression()), {varRegs[i]}, {}, false)
    end

    for i, id in ipairs(statement.ids) do
        if self:isUpvalue(statement.scope, id) then
            local varreg = varRegs[i]
            local tmp    = self:allocRegister(false)
            sc:addReferenceToHigherScope(self.scope, self.allocUpvalFunction)
            self:addStatement(self:setRegister(sc, tmp, Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.allocUpvalFunction), {})), {tmp}, {}, false)
            self:addStatement(self:setUpvalueMember(sc, self:register(sc, tmp), self:register(sc, varreg)), {}, {tmp, varreg}, true)
            self:addStatement(self:copyRegisters(sc, {varreg}, {tmp}), {varreg}, {tmp}, false)
            self:freeRegister(tmp, false)
        end
    end

    self:compileBlock(statement.body, funcDepth)
    self:addStatement(self:setPos(self.activeBlock.scope, checkBlock.id), {self.POS_REGISTER}, {}, false)
    self:setActiveBlock(finalBlock)

    for _, reg in ipairs(exprregs) do self:freeRegister(reg, true) end
end
