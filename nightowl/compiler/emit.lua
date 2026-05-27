local Ast       = require("nightowl.ast")
local Scope     = require("nightowl.scope")
local util      = require("nightowl.util")
local constants = require("nightowl.compiler.constants")
local AstKind   = Ast.AstKind

local MAX_REGS = constants.MAX_REGS

return function(Compiler)
    local function hasAnyEntries(tbl)
        return type(tbl) == "table" and next(tbl) ~= nil
    end

    local function unionLookup(a, b)
        local out = {}
        for k in pairs(a or {}) do out[k] = true end
        for k in pairs(b or {}) do out[k] = true end
        return out
    end

    local function canMerge(sA, sB)
        if type(sA) ~= "table" or type(sB) ~= "table" then return false end
        if sA.usesUpvals or sB.usesUpvals then return false end
        local a, b = sA.statement, sB.statement
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        if a.kind ~= AstKind.AssignmentStatement or b.kind ~= AstKind.AssignmentStatement then return false end
        if #a.lhs ~= #a.rhs or #b.lhs ~= #b.rhs then return false end
        local function unsafeRhs(rhs)
            for _, e in ipairs(rhs) do
                if type(e) ~= "table" then return true end
                local k = e.kind
                if k == AstKind.FunctionCallExpression or k == AstKind.PassSelfFunctionCallExpression or k == AstKind.VarargExpression then return true end
            end
        end
        if unsafeRhs(a.rhs) or unsafeRhs(b.rhs) then return false end
        if not hasAnyEntries(sA.writes) and not hasAnyEntries(sB.writes) then return false end
        for r in pairs(sA.reads)  do if sB.writes[r] then return false end end
        for r in pairs(sA.writes) do if sB.writes[r] or sB.reads[r] then return false end end
        return true
    end

    local function doMerge(sA, sB)
        local lhs, rhs = {}, {}
        for _, v in ipairs(sA.statement.lhs) do table.insert(lhs, v) end
        for _, v in ipairs(sB.statement.lhs) do table.insert(lhs, v) end
        for _, v in ipairs(sA.statement.rhs) do table.insert(rhs, v) end
        for _, v in ipairs(sB.statement.rhs) do table.insert(rhs, v) end
        return {
            statement  = Ast.AssignmentStatement(lhs, rhs),
            writes     = unionLookup(sA.writes, sB.writes),
            reads      = unionLookup(sA.reads,  sB.reads),
            usesUpvals = sA.usesUpvals or sB.usesUpvals,
        }
    end

    local function mergePass(stats)
        local out = {}
        local i = 1
        while i <= #stats do
            local s = stats[i]; i = i + 1
            while i <= #stats and canMerge(s, stats[i]) do
                s = doMerge(s, stats[i]); i = i + 1
            end
            table.insert(out, s)
        end
        return out
    end

    function Compiler:emitContainerFuncBody()
        local blocks = {}

        util.shuffle(self.blocks)

        for i, block in ipairs(self.blocks) do
            local bstats = block.statements

            -- instruction scheduling: shuffle independent statements
            for i2 = 2, #bstats do
                local stat   = bstats[i2]
                local reads  = stat.reads
                local writes = stat.writes
                local maxShift = 0
                for shift = 1, i2 - 1 do
                    local s2 = bstats[i2 - shift]
                    if stat.usesUpvals and s2.usesUpvals then break end
                    local ok = true
                    for r in pairs(s2.reads)  do if writes[r] then ok = false; break end end
                    if ok then
                        for r in pairs(s2.writes) do
                            if writes[r] or reads[r] then ok = false; break end
                        end
                    end
                    if not ok then break end
                    maxShift = shift
                end
                local shift = math.random(0, maxShift)
                for j = 1, shift do
                    bstats[i2-j], bstats[i2-j+1] = bstats[i2-j+1], bstats[i2-j]
                end
            end

            -- merge adjacent parallel assignments
            local merged = bstats
            for _ = 1, 8 do merged = mergePass(merged) end

            local finalStats = {}
            for _, s in ipairs(merged) do table.insert(finalStats, s.statement) end

            local b = {id = block.id, index = i, block = Ast.Block(finalStats, block.scope)}
            table.insert(blocks, b)
            blocks[block.id] = b
        end

        table.sort(blocks, function(a, b) return a.id < b.id end)

        local function buildChain(tb, l, r, pScope)
            if r < l then
                return Ast.Block({}, Scope:new(pScope))
            end
            if r == l then
                tb[l].block.scope:setParent(pScope)
                return tb[l].block
            end

            local len = r - l + 1

            if len <= 4 then
                local ifScope = Scope:new(pScope)
                local elseifs = {}
                tb[l].block.scope:setParent(ifScope)
                local bound1 = math.floor((tb[l].id + tb[l+1].id) / 2)
                local firstCond = Ast.LessThanExpression(self:pos(ifScope), Ast.NumberExpression(bound1))

                for ii = l+1, r-1 do
                    tb[ii].block.scope:setParent(ifScope)
                    local bound = math.floor((tb[ii].id + tb[ii+1].id) / 2)
                    table.insert(elseifs, {
                        condition = Ast.LessThanExpression(self:pos(ifScope), Ast.NumberExpression(bound)),
                        body      = tb[ii].block,
                    })
                end
                tb[r].block.scope:setParent(ifScope)
                return Ast.Block({
                    Ast.IfStatement(firstCond, tb[l].block, elseifs, tb[r].block)
                }, ifScope)
            end

            local mid     = l + math.ceil(len / 2)
            local bound   = math.floor((tb[mid-1].id + tb[mid].id) / 2)
            local ifScope = Scope:new(pScope)
            local lBlock  = buildChain(tb, l,   mid-1, ifScope)
            local rBlock  = buildChain(tb, mid,  r,     ifScope)

            local style = math.random(1, 3)
            local cond, tB, fB
            if style == 1 then
                cond = Ast.LessThanExpression(self:pos(ifScope), Ast.NumberExpression(bound))
                tB, fB = lBlock, rBlock
            elseif style == 2 then
                cond = Ast.GreaterThanExpression(Ast.NumberExpression(bound), self:pos(ifScope))
                tB, fB = lBlock, rBlock
            else
                cond = Ast.GreaterThanExpression(self:pos(ifScope), Ast.NumberExpression(bound))
                tB, fB = rBlock, lBlock
            end

            return Ast.Block({Ast.IfStatement(cond, tB, {}, fB)}, ifScope)
        end

        local whileBody = buildChain(blocks, 1, #blocks, self.containerFuncScope)

        self.whileScope:setParent(self.containerFuncScope)
        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.returnVar, 1)
        self.whileScope:addReferenceToHigherScope(self.containerFuncScope, self.posVar)
        self.containerFuncScope:addReferenceToHigherScope(self.scope, self.unpackVar)

        local declarations = {self.returnVar}
        for i, var in pairs(self.registerVars) do
            if i ~= MAX_REGS then table.insert(declarations, var) end
        end

        local stats = {}
        if self.maxUsedRegister >= MAX_REGS then
            table.insert(stats, Ast.LocalVariableDeclaration(
                self.containerFuncScope,
                {self.registerVars[MAX_REGS]},
                {Ast.TableConstructorExpression({})}
            ))
        end
        table.insert(stats, Ast.LocalVariableDeclaration(
            self.containerFuncScope,
            util.shuffle(declarations),
            {}
        ))
        table.insert(stats, Ast.WhileStatement(
            whileBody,
            Ast.VariableExpression(self.containerFuncScope, self.posVar),
            self.containerFuncScope
        ))
        table.insert(stats, Ast.AssignmentStatement(
            {Ast.AssignmentVariable(self.containerFuncScope, self.posVar)},
            {Ast.LenExpression(Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar))}
        ))
        table.insert(stats, Ast.ReturnStatement{
            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.unpackVar), {
                Ast.VariableExpression(self.containerFuncScope, self.returnVar)
            })
        })

        return Ast.Block(stats, self.containerFuncScope)
    end
end
