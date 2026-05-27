local Scope = require("nightowl.scope")
local util  = require("nightowl.util")

return function(Compiler)
    function Compiler:createBlock()
        local id
        repeat
            id = math.random(0, 2^24)
        until not self.usedBlockIds[id]
        self.usedBlockIds[id] = true

        local scope = Scope:new(self.containerFuncScope)
        local block = {
            id                = id,
            statements        = {},
            scope             = scope,
            advanceToNextBlock= true,
        }
        table.insert(self.blocks, block)
        return block
    end

    function Compiler:setActiveBlock(block)
        self.activeBlock = block
    end

    function Compiler:addStatement(statement, writes, reads, usesUpvals)
        if self.activeBlock.advanceToNextBlock then
            table.insert(self.activeBlock.statements, {
                statement  = statement,
                writes     = util.lookupify(writes),
                reads      = util.lookupify(reads),
                usesUpvals = usesUpvals or false,
            })
        end
    end
end
