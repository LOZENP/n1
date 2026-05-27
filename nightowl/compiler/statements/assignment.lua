local Ast     = require("nightowl.ast")
local AstKind = Ast.AstKind

return function(self, statement, funcDepth)
    local scope    = self.activeBlock.scope
    local exprregs = {}
    local indexRegs = {}

    for i, pe in ipairs(statement.lhs) do
        if pe.kind == AstKind.AssignmentIndexing then
            indexRegs[i] = {
                base  = self:compileExpression(pe.base,  funcDepth, 1)[1],
                index = self:compileExpression(pe.index, funcDepth, 1)[1],
            }
        end
    end

    for i, expr in ipairs(statement.rhs) do
        if i == #statement.rhs and #statement.lhs > #statement.rhs then
            local regs = self:compileExpression(expr, funcDepth, #statement.lhs - #statement.rhs + 1)
            for _, reg in ipairs(regs) do
                if self:isVarRegister(reg) then
                    local ro = reg; reg = self:allocRegister(false)
                    self:addStatement(self:copyRegisters(scope, {reg}, {ro}), {reg}, {ro}, false)
                end
                table.insert(exprregs, reg)
            end
        else
            if statement.lhs[i] or expr.kind == AstKind.FunctionCallExpression or expr.kind == AstKind.PassSelfFunctionCallExpression then
                local reg = self:compileExpression(expr, funcDepth, 1)[1]
                if self:isVarRegister(reg) then
                    local ro = reg; reg = self:allocRegister(false)
                    self:addStatement(self:copyRegisters(scope, {reg}, {ro}), {reg}, {ro}, false)
                end
                table.insert(exprregs, reg)
            end
        end
    end

    for i, pe in ipairs(statement.lhs) do
        if pe.kind == AstKind.AssignmentVariable then
            if pe.scope.isGlobal then
                local tmp = self:allocRegister(false)
                self:addStatement(self:setRegister(scope, tmp, Ast.StringExpression(pe.scope:getVariableName(pe.id))), {tmp}, {}, false)
                self:addStatement(Ast.AssignmentStatement({Ast.AssignmentIndexing(self:env(scope), self:register(scope, tmp))}, {self:register(scope, exprregs[i])}), {}, {tmp, exprregs[i]}, true)
                self:freeRegister(tmp, false)
            else
                if self.scopeFunctionDepths[pe.scope] == funcDepth then
                    if self:isUpvalue(pe.scope, pe.id) then
                        local reg = self:getVarRegister(pe.scope, pe.id, funcDepth)
                        self:addStatement(self:setUpvalueMember(scope, self:register(scope, reg), self:register(scope, exprregs[i])), {}, {reg, exprregs[i]}, true)
                    else
                        local reg = self:getVarRegister(pe.scope, pe.id, funcDepth, exprregs[i])
                        if reg ~= exprregs[i] then
                            self:addStatement(self:setRegister(scope, reg, self:register(scope, exprregs[i])), {reg}, {exprregs[i]}, false)
                        end
                    end
                else
                    local uid = self:getUpvalueId(pe.scope, pe.id)
                    scope:addReferenceToHigherScope(self.containerFuncScope, self.currentUpvaluesVar)
                    self:addStatement(self:setUpvalueMember(scope, Ast.IndexExpression(Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar), Ast.NumberExpression(uid)), self:register(scope, exprregs[i])), {}, {exprregs[i]}, true)
                end
            end
        elseif pe.kind == AstKind.AssignmentIndexing then
            local br = indexRegs[i].base
            local ir = indexRegs[i].index
            self:addStatement(Ast.AssignmentStatement({Ast.AssignmentIndexing(self:register(scope, br), self:register(scope, ir))}, {self:register(scope, exprregs[i])}), {}, {exprregs[i], br, ir}, true)
            self:freeRegister(exprregs[i], false)
            self:freeRegister(br, false)
            self:freeRegister(ir, false)
        end
    end
end
