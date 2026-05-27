local Ast     = require("nightowl.ast")
local AstKind = Ast.AstKind

local ctors = {
    [AstKind.CompoundAddStatement]    = Ast.CompoundAddStatement,
    [AstKind.CompoundSubStatement]    = Ast.CompoundSubStatement,
    [AstKind.CompoundMulStatement]    = Ast.CompoundMulStatement,
    [AstKind.CompoundDivStatement]    = Ast.CompoundDivStatement,
    [AstKind.CompoundModStatement]    = Ast.CompoundModStatement,
    [AstKind.CompoundPowStatement]    = Ast.CompoundPowStatement,
    [AstKind.CompoundConcatStatement] = Ast.CompoundConcatStatement,
}

return function(self, statement, funcDepth)
    local scope = self.activeBlock.scope
    local ctor  = ctors[statement.kind]

    if statement.lhs.kind == AstKind.AssignmentIndexing then
        local baseReg  = self:compileExpression(statement.lhs.base,  funcDepth, 1)[1]
        local indexReg = self:compileExpression(statement.lhs.index, funcDepth, 1)[1]
        local valReg   = self:compileExpression(statement.rhs,       funcDepth, 1)[1]
        self:addStatement(ctor(Ast.AssignmentIndexing(self:register(scope, baseReg), self:register(scope, indexReg)), self:register(scope, valReg)), {}, {baseReg, indexReg, valReg}, true)
        self:freeRegister(baseReg, false); self:freeRegister(indexReg, false); self:freeRegister(valReg, false)
    else
        local valReg = self:compileExpression(statement.rhs, funcDepth, 1)[1]
        local pe     = statement.lhs
        if pe.scope.isGlobal then
            local tmp = self:allocRegister(false)
            self:addStatement(self:setRegister(scope, tmp, Ast.StringExpression(pe.scope:getVariableName(pe.id))), {tmp}, {}, false)
            self:addStatement(ctor(Ast.AssignmentIndexing(self:env(scope), self:register(scope, tmp)), self:register(scope, valReg)), {}, {tmp, valReg}, true)
            self:freeRegister(tmp, false); self:freeRegister(valReg, false)
        else
            if self.scopeFunctionDepths[pe.scope] == funcDepth then
                if self:isUpvalue(pe.scope, pe.id) then
                    local reg = self:getVarRegister(pe.scope, pe.id, funcDepth)
                    self:addStatement(self:setUpvalueMember(scope, self:register(scope, reg), self:register(scope, valReg), ctor), {}, {reg, valReg}, true)
                else
                    local reg = self:getVarRegister(pe.scope, pe.id, funcDepth, valReg)
                    if reg ~= valReg then
                        self:addStatement(self:setRegister(scope, reg, self:register(scope, valReg), ctor), {reg}, {valReg}, false)
                    end
                end
            else
                local uid = self:getUpvalueId(pe.scope, pe.id)
                scope:addReferenceToHigherScope(self.containerFuncScope, self.currentUpvaluesVar)
                self:addStatement(self:setUpvalueMember(scope, Ast.IndexExpression(Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar), Ast.NumberExpression(uid)), self:register(scope, valReg), ctor), {}, {valReg}, true)
            end
            self:freeRegister(valReg, false)
        end
    end
end	
