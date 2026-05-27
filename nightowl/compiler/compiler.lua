local Ast   = require("nightowl.ast")
local Scope = require("nightowl.scope")
local util  = require("nightowl.util")

local AstKind   = Ast.AstKind
local lookupify = util.lookupify
local unpack    = unpack or table.unpack

local blockModule       = require("nightowl.compiler.block")
local registerModule    = require("nightowl.compiler.register")
local upvalueModule     = require("nightowl.compiler.upvalue")
local emitModule        = require("nightowl.compiler.emit")
local compileCoreModule = require("nightowl.compiler.compile_core")

local Compiler = {}

function Compiler:new()
    local c = {
        blocks            = {},
        registers         = {},
        activeBlock       = nil,
        registersForVar   = {},
        usedRegisters     = 0,
        maxUsedRegister   = 0,
        registerVars      = {},

        VAR_REGISTER    = newproxy(false),
        RETURN_ALL      = newproxy(false),
        POS_REGISTER    = newproxy(false),
        RETURN_REGISTER = newproxy(false),
        UPVALUE         = newproxy(false),

        BIN_OPS = lookupify{
            AstKind.LessThanExpression, AstKind.GreaterThanExpression,
            AstKind.LessThanOrEqualsExpression, AstKind.GreaterThanOrEqualsExpression,
            AstKind.NotEqualsExpression, AstKind.EqualsExpression,
            AstKind.StrCatExpression, AstKind.AddExpression, AstKind.SubExpression,
            AstKind.MulExpression, AstKind.DivExpression, AstKind.ModExpression,
            AstKind.PowExpression,
        },
    }
    setmetatable(c, self); self.__index = self
    return c
end

blockModule(Compiler)
registerModule(Compiler)
upvalueModule(Compiler)
emitModule(Compiler)
compileCoreModule(Compiler)

function Compiler:pushRegisterUsageInfo()
    if not self.registerUsageStack then self.registerUsageStack = {} end
    table.insert(self.registerUsageStack, {
        usedRegisters = self.usedRegisters,
        registers     = self.registers,
    })
    self.usedRegisters = 0
    self.registers     = {}
end

function Compiler:popRegisterUsageInfo()
    local info = table.remove(self.registerUsageStack)
    self.usedRegisters = info.usedRegisters
    self.registers     = info.registers
end

function Compiler:compile(ast)
    self.blocks              = {}
    self.registers           = {}
    self.activeBlock         = nil
    self.registersForVar     = {}
    self.scopeFunctionDepths = {}
    self.maxUsedRegister     = 0
    self.usedRegisters       = 0
    self.registerVars        = {}
    self.usedBlockIds        = {}
    self.upvalVars           = {}
    self.registerUsageStack  = {}

    self.upvalsProxyLenReturn = math.random(-2^22, 2^22)

    local newGlobalScope = Scope:newGlobal()
    local psc            = Scope:new(newGlobalScope, nil)

    local _, getfenvVar      = newGlobalScope:resolve("getfenv")
    local _, tableVar        = newGlobalScope:resolve("table")
    local _, unpackVar       = newGlobalScope:resolve("unpack")
    local _, envVar          = newGlobalScope:resolve("_ENV")
    local _, newproxyVar     = newGlobalScope:resolve("newproxy")
    local _, setmetatableVar = newGlobalScope:resolve("setmetatable")
    local _, getmetatableVar = newGlobalScope:resolve("getmetatable")
    local _, selectVar       = newGlobalScope:resolve("select")

    psc:addReferenceToHigherScope(newGlobalScope, getfenvVar, 2)
    psc:addReferenceToHigherScope(newGlobalScope, tableVar)
    psc:addReferenceToHigherScope(newGlobalScope, unpackVar)
    psc:addReferenceToHigherScope(newGlobalScope, envVar)
    psc:addReferenceToHigherScope(newGlobalScope, newproxyVar)
    psc:addReferenceToHigherScope(newGlobalScope, setmetatableVar)
    psc:addReferenceToHigherScope(newGlobalScope, getmetatableVar)

    self.scope              = Scope:new(psc)
    self.envVar             = self.scope:addVariable()
    self.containerFuncVar   = self.scope:addVariable()
    self.unpackVar          = self.scope:addVariable()
    self.newproxyVar        = self.scope:addVariable()
    self.setmetatableVar    = self.scope:addVariable()
    self.getmetatableVar    = self.scope:addVariable()
    self.selectVar          = self.scope:addVariable()

    local argVar = self.scope:addVariable()

    self.containerFuncScope = Scope:new(self.scope)
    self.whileScope         = Scope:new(self.containerFuncScope)

    self.posVar             = self.containerFuncScope:addVariable()
    self.argsVar            = self.containerFuncScope:addVariable()
    self.currentUpvaluesVar = self.containerFuncScope:addVariable()
    self.detectGcCollectVar = self.containerFuncScope:addVariable()
    self.returnVar          = self.containerFuncScope:addVariable()

    self.upvaluesTable                = self.scope:addVariable()
    self.upvaluesReferenceCountsTable = self.scope:addVariable()
    self.allocUpvalFunction           = self.scope:addVariable()
    self.currentUpvalId               = self.scope:addVariable()
    self.upvaluesProxyFunctionVar     = self.scope:addVariable()
    self.upvaluesGcFunctionVar        = self.scope:addVariable()
    self.freeUpvalueFunc              = self.scope:addVariable()

    self.createClosureVars      = {}
    self.createVarargClosureVar = self.scope:addVariable()

    local createClosureScope       = Scope:new(self.scope)
    local createClosurePosArg      = createClosureScope:addVariable()
    local createClosureUpvalsArg   = createClosureScope:addVariable()
    local createClosureProxyObject = createClosureScope:addVariable()
    local createClosureFuncVar     = createClosureScope:addVariable()
    local createClosureSubScope    = Scope:new(createClosureScope)

    local upvalEntries = {}
    local upvalueIds   = {}

    self.getUpvalueId = function(self2, scope, id)
        local expr
        local sfd = self2.scopeFunctionDepths[scope]
        if sfd == 0 then
            if upvalueIds[id] then return upvalueIds[id] end
            expr = Ast.FunctionCallExpression(
                Ast.VariableExpression(self2.scope, self2.allocUpvalFunction), {}
            )
        else
            require("logger"):error("Unresolved Upvalue!")
        end
        table.insert(upvalEntries, Ast.TableEntry(expr))
        local uid = #upvalEntries
        upvalueIds[id] = uid
        return uid
    end

    createClosureSubScope:addReferenceToHigherScope(self.scope, self.containerFuncVar)
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosurePosArg)
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureUpvalsArg, 1)
    createClosureScope:addReferenceToHigherScope(self.scope, self.upvaluesProxyFunctionVar)
    createClosureSubScope:addReferenceToHigherScope(createClosureScope, createClosureProxyObject)

    self:compileTopNode(ast)

    local fnAssignments = {
        {
            var = Ast.AssignmentVariable(self.scope, self.containerFuncVar),
            val = Ast.FunctionLiteralExpression({
                Ast.VariableExpression(self.containerFuncScope, self.posVar),
                Ast.VariableExpression(self.containerFuncScope, self.argsVar),
                Ast.VariableExpression(self.containerFuncScope, self.currentUpvaluesVar),
                Ast.VariableExpression(self.containerFuncScope, self.detectGcCollectVar),
            }, self:emitContainerFuncBody()),
        },
        {
            var = Ast.AssignmentVariable(self.scope, self.createVarargClosureVar),
            val = Ast.FunctionLiteralExpression({
                Ast.VariableExpression(createClosureScope, createClosurePosArg),
                Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
            }, Ast.Block({
                Ast.LocalVariableDeclaration(createClosureScope, {createClosureProxyObject}, {
                    Ast.FunctionCallExpression(
                        Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar),
                        {Ast.VariableExpression(createClosureScope, createClosureUpvalsArg)}
                    )
                }),
                Ast.LocalVariableDeclaration(createClosureScope, {createClosureFuncVar}, {
                    Ast.FunctionLiteralExpression({Ast.VarargExpression()},
                        Ast.Block({
                            Ast.ReturnStatement{
                                Ast.FunctionCallExpression(
                                    Ast.VariableExpression(self.scope, self.containerFuncVar),
                                    {
                                        Ast.VariableExpression(createClosureScope, createClosurePosArg),
                                        Ast.TableConstructorExpression({Ast.TableEntry(Ast.VarargExpression())}),
                                        Ast.VariableExpression(createClosureScope, createClosureUpvalsArg),
                                        Ast.VariableExpression(createClosureScope, createClosureProxyObject),
                                    }
                                )
                            }
                        }, createClosureSubScope)
                    )
                }),
                Ast.ReturnStatement{Ast.VariableExpression(createClosureScope, createClosureFuncVar)},
            }, createClosureScope)),
        },
        {var=Ast.AssignmentVariable(self.scope, self.upvaluesTable),                val=Ast.TableConstructorExpression({})},
        {var=Ast.AssignmentVariable(self.scope, self.upvaluesReferenceCountsTable), val=Ast.TableConstructorExpression({})},
        {var=Ast.AssignmentVariable(self.scope, self.allocUpvalFunction),           val=self:createAllocUpvalFunction()},
        {var=Ast.AssignmentVariable(self.scope, self.currentUpvalId),               val=Ast.NumberExpression(0)},
        {var=Ast.AssignmentVariable(self.scope, self.upvaluesProxyFunctionVar),     val=self:createUpvaluesProxyFunc()},
        {var=Ast.AssignmentVariable(self.scope, self.upvaluesGcFunctionVar),        val=self:createUpvaluesGcFunc()},
        {var=Ast.AssignmentVariable(self.scope, self.freeUpvalueFunc),              val=self:createFreeUpvalueFunc()},
    }

    local tbl = {
        Ast.VariableExpression(self.scope, self.containerFuncVar),
        Ast.VariableExpression(self.scope, self.createVarargClosureVar),
        Ast.VariableExpression(self.scope, self.upvaluesTable),
        Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable),
        Ast.VariableExpression(self.scope, self.allocUpvalFunction),
        Ast.VariableExpression(self.scope, self.currentUpvalId),
        Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar),
        Ast.VariableExpression(self.scope, self.upvaluesGcFunctionVar),
        Ast.VariableExpression(self.scope, self.freeUpvalueFunc),
    }

    for _, entry in pairs(self.createClosureVars) do
        table.insert(fnAssignments, entry)
        table.insert(tbl, Ast.VariableExpression(entry.var.scope, entry.var.id))
    end

    util.shuffle(fnAssignments)
    local lhs, rhs = {}, {}
    for i, v in ipairs(fnAssignments) do lhs[i] = v.var; rhs[i] = v.val end

    -- shuffle the 7 special params
    local ids = util.shuffle({1, 2, 3, 4, 5, 6, 7})

    -- param variables
    local items = {
        Ast.VariableExpression(self.scope, self.envVar),
        Ast.VariableExpression(self.scope, self.unpackVar),
        Ast.VariableExpression(self.scope, self.newproxyVar),
        Ast.VariableExpression(self.scope, self.setmetatableVar),
        Ast.VariableExpression(self.scope, self.getmetatableVar),
        Ast.VariableExpression(self.scope, self.selectVar),
        Ast.VariableExpression(self.scope, argVar),
    }

    -- call site argument expressions
    local astItems = {
        Ast.OrExpression(
            Ast.AndExpression(
                Ast.VariableExpression(newGlobalScope, getfenvVar),
                Ast.FunctionCallExpression(Ast.VariableExpression(newGlobalScope, getfenvVar), {})
            ),
            Ast.VariableExpression(newGlobalScope, envVar)
        ),
        Ast.OrExpression(
            Ast.VariableExpression(newGlobalScope, unpackVar),
            Ast.IndexExpression(
                Ast.VariableExpression(newGlobalScope, tableVar),
                Ast.StringExpression("unpack")
            )
        ),
        Ast.VariableExpression(newGlobalScope, newproxyVar),
        Ast.VariableExpression(newGlobalScope, setmetatableVar),
        Ast.VariableExpression(newGlobalScope, getmetatableVar),
        Ast.VariableExpression(newGlobalScope, selectVar),
        Ast.TableConstructorExpression({Ast.TableEntry(Ast.VarargExpression())}),
    }

    -- build special param pairs (param + matching arg)
    local specialPairs = {}
    for i = 1, 7 do
        table.insert(specialPairs, {
            param = items[ids[i]],
            arg   = astItems[ids[i]],
        })
    end

    -- shuffle tbl (internal vars, no call-site args)
    local shuffledTbl = util.shuffle(tbl)

    -- interleave: randomly insert each special pair into tbl positions
    -- result: finalParams has everything, finalArgs has only the 7 special args
    -- in the correct matching order
    local finalParams = {}
    local finalArgs   = {}

    -- start with tbl params
    for _, v in ipairs(shuffledTbl) do
        table.insert(finalParams, v)
    end

    -- randomly insert each special param at a random position
    for _, pair in ipairs(specialPairs) do
        local pos = math.random(1, #finalParams + 1)
        table.insert(finalParams, pos, pair.param)
        table.insert(finalArgs, pair.arg)
    end

    local funcNode = Ast.FunctionLiteralExpression(
        finalParams,
        Ast.Block({
            Ast.AssignmentStatement(lhs, rhs),
            Ast.ReturnStatement{
                Ast.FunctionCallExpression(
                    Ast.FunctionCallExpression(
                        Ast.VariableExpression(self.scope, self.createVarargClosureVar),
                        {
                            Ast.NumberExpression(self.startBlockId),
                            Ast.TableConstructorExpression(upvalEntries),
                        }
                    ),
                    {
                        Ast.FunctionCallExpression(
                            Ast.VariableExpression(self.scope, self.unpackVar),
                            {Ast.VariableExpression(self.scope, argVar)}
                        )
                    }
                )
            }
        }, self.scope)
    )

    return Ast.TopNode(Ast.Block({
        Ast.ReturnStatement{
            Ast.FunctionCallExpression(funcNode, finalArgs)
        }
    }, psc), newGlobalScope)
end

function Compiler:getCreateClosureVar(argCount)
    if not self.createClosureVars[argCount] then
        local var  = Ast.AssignmentVariable(self.scope, self.scope:addVariable())
        local ccs  = Scope:new(self.scope)
        local ccss = Scope:new(ccs)

        local posArg    = ccs:addVariable()
        local upvalsArg = ccs:addVariable()
        local proxyObj  = ccs:addVariable()
        local funcVar   = ccs:addVariable()

        ccss:addReferenceToHigherScope(self.scope, self.containerFuncVar)
        ccss:addReferenceToHigherScope(ccs, posArg)
        ccss:addReferenceToHigherScope(ccs, upvalsArg, 1)
        ccs:addReferenceToHigherScope(self.scope, self.upvaluesProxyFunctionVar)
        ccss:addReferenceToHigherScope(ccs, proxyObj)

        local argsTb, argsTb2 = {}, {}
        for i = 1, argCount do
            local a = ccss:addVariable()
            argsTb[i]  = Ast.VariableExpression(ccss, a)
            argsTb2[i] = Ast.TableEntry(Ast.VariableExpression(ccss, a))
        end

        local val = Ast.FunctionLiteralExpression({
            Ast.VariableExpression(ccs, posArg),
            Ast.VariableExpression(ccs, upvalsArg),
        }, Ast.Block({
            Ast.LocalVariableDeclaration(ccs, {proxyObj}, {
                Ast.FunctionCallExpression(
                    Ast.VariableExpression(self.scope, self.upvaluesProxyFunctionVar),
                    {Ast.VariableExpression(ccs, upvalsArg)}
                )
            }),
            Ast.LocalVariableDeclaration(ccs, {funcVar}, {
                Ast.FunctionLiteralExpression(argsTb,
                    Ast.Block({
                        Ast.ReturnStatement{
                            Ast.FunctionCallExpression(
                                Ast.VariableExpression(self.scope, self.containerFuncVar),
                                {
                                    Ast.VariableExpression(ccs, posArg),
                                    Ast.TableConstructorExpression(argsTb2),
                                    Ast.VariableExpression(ccs, upvalsArg),
                                    Ast.VariableExpression(ccs, proxyObj),
                                }
                            )
                        }
                    }, ccss)
                )
            }),
            Ast.ReturnStatement{Ast.VariableExpression(ccs, funcVar)},
        }, ccs))

        self.createClosureVars[argCount] = {var=var, val=val}
    end

    local var = self.createClosureVars[argCount].var
    return var.scope, var.id
end

return Compiler
