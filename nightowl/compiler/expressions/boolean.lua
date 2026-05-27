local Ast = require("nightowl.ast")

local evals = {
    [Ast.GreaterThanExpression]          = function(a,b) return a>b end,
    [Ast.LessThanExpression]             = function(a,b) return a<b end,
    [Ast.GreaterThanOrEqualsExpression]  = function(a,b) return a>=b end,
    [Ast.LessThanOrEqualsExpression]     = function(a,b) return a<=b end,
    [Ast.NotEqualsExpression]            = function(a,b) return a~=b end,
}

local function randomCflow(result)
    local pool = {Ast.GreaterThanExpression, Ast.LessThanExpression, Ast.GreaterThanOrEqualsExpression, Ast.LessThanOrEqualsExpression, Ast.NotEqualsExpression}
    local exp, l, r, res
    repeat
        exp = pool[math.random(#pool)]
        l   = Ast.NumberExpression(math.random(1, 2^24))
        r   = Ast.NumberExpression(math.random(1, 2^24))
        res = evals[exp](l.value, r.value)
    until res == result
    return exp(l, r, false)
end

return function(self, expression, funcDepth, numReturns)
    local scope = self.activeBlock.scope
    local regs  = {}
    for i = 1, numReturns do
        regs[i] = self:allocRegister()
        self:addStatement(self:setRegister(scope, regs[i], i==1 and randomCflow(expression.value) or Ast.NilExpression()), {regs[i]}, {}, false)
    end
    return regs
end
