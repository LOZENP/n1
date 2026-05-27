local Ast = require("nightowl.ast")

return function(self, statement, funcDepth)
    local scope  = self.activeBlock.scope
    local retReg = self:compileFunction(statement, funcDepth)

    if #statement.indices > 0 then
        local tblReg
        if statement.scope.isGlobal then
            tblReg = self:allocRegister(false)
            self:addStatement(self:setRegister(scope, tblReg, Ast.StringExpression(statement.scope:getVariableName(statement.id))), {tblReg}, {}, false)
            self:addStatement(self:setRegister(scope, tblReg, Ast.IndexExpression(self:env(scope), self:register(scope, tblReg))), {tblReg}, {tblReg}, true)
        else
            if self.scopeFunctionDepths[statement.scope] == funcDepth then
                if self:isUpvalue(statement.scope, statement.id) then
                    tblReg = self:allocRegister(false)
                    local reg = self:getVarRegister(statement.scope, statement.id, funcDepth)
                    self:addStatement(self:setRegister(scope, tblReg, self:getUpvalueMember(scope, self:register(scope, reg))), {tblReg}, {reg}, true)
                else
                    tblReg = self:getVarRegister(statement.scope, statement.id, funcDepth, retReg)
                end
            else
                tblReg = self:allocRegister(false)
                local uid = self:getUpvalueId(statement.scope, statement.id)
                scope:addReferenceToHigherScope(self.containerFuncScope, self.currentUpvaluesVar)
                self:addStatement(self:setRegister(scope, tblReg, self:getUpvalueMember(scope, Ast.IndexExpression(Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar), Ast.NumberExpression(uid)))), {tblReg}, {}, true)
            end
        end

        for i = 1, #statement.indices - 1 do
            local idxReg    = self:compileExpression(Ast.StringExpression(statement.indices[i]), funcDepth, 1)[1]
            local oldTblReg = tblReg
            tblReg = self:allocRegister(false)
            self:addStatement(self:setRegister(scope, tblReg, Ast.IndexExpression(self:register(scope, oldTblReg), self:register(scope, idxReg))), {tblReg}, {tblReg, idxReg}, false)
            self:freeRegister(oldTblReg, false); self:freeRegister(idxReg, false)
        end

        local idxReg = self:compileExpression(Ast.StringExpression(statement.indices[#statement.indices]), funcDepth, 1)[1]
        self:addStatement(Ast.AssignmentStatement({Ast.AssignmentIndexing(self:register(scope, tblReg), self:register(scope, idxReg))}, {self:register(scope, retReg)}), {}, {tblReg, idxReg, retReg}, true)
        self:freeRegister(idxReg, false); self:freeRegister(tblReg, false); self:freeRegister(retReg, false)
        return
    end

    if statement.scope.isGlobal then
        local tmp = self:allocRegister(false)
        self:addStatement(self:setRegister(scope, tmp, Ast.StringExpression(statement.scope:getVariableName(statement.id))), {tmp}, {}, false)
        self:addStatement(Ast.AssignmentStatement({Ast.AssignmentIndexing(self:env(scope), self:register(scope, tmp))}, {self:register(scope, retReg)}), {}, {tmp, retReg}, true)
        self:freeRegister(tmp, false)
    else
        if self.scopeFunctionDepths[statement.scope] == funcDepth then
            if self:isUpvalue(statement.scope, statement.id) then
                local reg = self:getVarRegister(statement.scope, statement.id, funcDepth)
                self:addStatement(self:setUpvalueMember(scope, self:register(scope, reg), self:register(scope, retReg)), {}, {reg, retReg}, true)
            else
                local reg = self:getVarRegister(statement.scope, statement.id, funcDepth, retReg)
                if reg ~= retReg then
                    self:addStatement(self:setRegister(scope, reg, self:register(scope, retReg)), {reg}, {retReg}, false)
                end
            end
        else
            local uid = self:getUpvalueId(statement.scope, statement.id)
            scope:addReferenceToHigherScope(self.containerFuncScope, self.currentUpvaluesVar)
            self:addStatement(self:setUpvalueMember(scope, Ast.IndexExpression(Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar), Ast.NumberExpression(uid)), self:register(scope, retReg)), {}, {retReg}, true)
        end
    end
    self:freeRegister(retReg, false)
end
