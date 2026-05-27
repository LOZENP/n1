local Ast = require("nightowl.ast")

return function(self, statement, funcDepth)
    local scope      = self.activeBlock.scope
    local innerBlock = self:createBlock()
    local finalBlock = self:createBlock()
    local checkBlock = self:createBlock()

    statement.__start_block = checkBlock
    statement.__final_block = finalBlock

    self:addStatement(self:setPos(scope, checkBlock.id), {self.POS_REGISTER}, {}, false)
    self:setActiveBlock(checkBlock)
    local condReg = self:compileExpression(statement.condition, funcDepth, 1)[1]
    local sc = self.activeBlock.scope
    self:addStatement(self:setRegister(sc, self.POS_REGISTER,
        Ast.OrExpression(Ast.AndExpression(self:register(sc, condReg), Ast.NumberExpression(innerBlock.id)), Ast.NumberExpression(finalBlock.id))
    ), {self.POS_REGISTER}, {condReg}, false)
    self:freeRegister(condReg, false)

    self:setActiveBlock(innerBlock)
    self:compileBlock(statement.body, funcDepth)
    self:addStatement(self:setPos(self.activeBlock.scope, checkBlock.id), {self.POS_REGISTER}, {}, false)
    self:setActiveBlock(finalBlock)
end
