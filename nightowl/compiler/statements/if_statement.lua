local Ast = require("nightowl.ast")

return function(self, statement, funcDepth)
    local scope        = self.activeBlock.scope
    local condReg      = self:compileExpression(statement.condition, funcDepth, 1)[1]
    local finalBlock   = self:createBlock()
    local nextBlock    = (#statement.elseifs > 0 or statement.elsebody) and self:createBlock() or finalBlock
    local innerBlock   = self:createBlock()

    self:addStatement(self:setRegister(scope, self.POS_REGISTER,
        Ast.OrExpression(Ast.AndExpression(self:register(scope, condReg), Ast.NumberExpression(innerBlock.id)), Ast.NumberExpression(nextBlock.id))
    ), {self.POS_REGISTER}, {condReg}, false)
    self:freeRegister(condReg, false)

    self:setActiveBlock(innerBlock)
    self:compileBlock(statement.body, funcDepth)
    self:addStatement(self:setRegister(self.activeBlock.scope, self.POS_REGISTER, Ast.NumberExpression(finalBlock.id)), {self.POS_REGISTER}, {}, false)

    for i, eif in ipairs(statement.elseifs) do
        self:setActiveBlock(nextBlock)
        local ecReg     = self:compileExpression(eif.condition, funcDepth, 1)[1]
        local eifInner  = self:createBlock()
        nextBlock = (statement.elsebody or i < #statement.elseifs) and self:createBlock() or finalBlock
        local sc2 = self.activeBlock.scope
        self:addStatement(self:setRegister(sc2, self.POS_REGISTER,
            Ast.OrExpression(Ast.AndExpression(self:register(sc2, ecReg), Ast.NumberExpression(eifInner.id)), Ast.NumberExpression(nextBlock.id))
        ), {self.POS_REGISTER}, {ecReg}, false)
        self:freeRegister(ecReg, false)
        self:setActiveBlock(eifInner)
        self:compileBlock(eif.body, funcDepth)
        self:addStatement(self:setRegister(self.activeBlock.scope, self.POS_REGISTER, Ast.NumberExpression(finalBlock.id)), {self.POS_REGISTER}, {}, false)
    end

    if statement.elsebody then
        self:setActiveBlock(nextBlock)
        self:compileBlock(statement.elsebody, funcDepth)
        self:addStatement(self:setRegister(self.activeBlock.scope, self.POS_REGISTER, Ast.NumberExpression(finalBlock.id)), {self.POS_REGISTER}, {}, false)
    end

    self:setActiveBlock(finalBlock)
end
