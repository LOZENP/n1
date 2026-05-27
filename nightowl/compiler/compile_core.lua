local compileTop    = require("nightowl.compiler.compile_top")
local stmtHandlers  = require("nightowl.compiler.statements")
local exprHandlers  = require("nightowl.compiler.expressions")
local logger        = require("logger")

return function(Compiler)
    compileTop(Compiler)

    function Compiler:compileStatement(statement, funcDepth)
        local handler = stmtHandlers[statement.kind]
        if handler then handler(self, statement, funcDepth); return end
        logger:error(string.format("%s is not a compileable statement!", statement.kind))
    end

    function Compiler:compileExpression(expression, funcDepth, numReturns)
        local handler = exprHandlers[expression.kind]
        if handler then return handler(self, expression, funcDepth, numReturns) end
        logger:error(string.format("%s is not a compileable expression!", expression.kind))
    end
end
