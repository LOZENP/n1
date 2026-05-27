local Ast   = require("nightowl.ast")
local Scope = require("nightowl.scope")
local util  = require("nightowl.util")

local unpack = unpack or table.unpack

return function(Compiler)
    function Compiler:createUpvaluesGcFunc()
        local scope      = Scope:new(self.scope)
        local selfVar    = scope:addVariable()
        local iterVar    = scope:addVariable()
        local valueVar   = scope:addVariable()
        local whileScope = Scope:new(scope)
        whileScope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 3)
        whileScope:addReferenceToHigherScope(scope, valueVar, 3)
        whileScope:addReferenceToHigherScope(scope, iterVar, 3)
        local ifScope = Scope:new(whileScope)
        ifScope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 1)
        ifScope:addReferenceToHigherScope(self.scope, self.upvaluesTable, 1)

        return Ast.FunctionLiteralExpression(
            {Ast.VariableExpression(scope, selfVar)},
            Ast.Block({
                Ast.LocalVariableDeclaration(scope, {iterVar, valueVar}, {
                    Ast.NumberExpression(1),
                    Ast.IndexExpression(Ast.VariableExpression(scope, selfVar), Ast.NumberExpression(1))
                }),
                Ast.WhileStatement(
                    Ast.Block({
                        Ast.AssignmentStatement({
                            Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)),
                            Ast.AssignmentVariable(scope, iterVar),
                        }, {
                            Ast.SubExpression(
                                Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)),
                                Ast.NumberExpression(1)
                            ),
                            Ast.AddExpression(unpack(util.shuffle{Ast.VariableExpression(scope, iterVar), Ast.NumberExpression(1)})),
                        }),
                        Ast.IfStatement(
                            Ast.EqualsExpression(unpack(util.shuffle{
                                Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)),
                                Ast.NumberExpression(0)
                            })),
                            Ast.Block({
                                Ast.AssignmentStatement({
                                    Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, valueVar)),
                                    Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesTable), Ast.VariableExpression(scope, valueVar)),
                                }, {Ast.NilExpression(), Ast.NilExpression()})
                            }, ifScope),
                            {}, nil
                        ),
                        Ast.AssignmentStatement({
                            Ast.AssignmentVariable(scope, valueVar),
                        }, {
                            Ast.IndexExpression(Ast.VariableExpression(scope, selfVar), Ast.VariableExpression(scope, iterVar)),
                        }),
                    }, whileScope),
                    Ast.VariableExpression(scope, valueVar),
                    scope
                ),
            }, scope)
        )
    end

    function Compiler:createFreeUpvalueFunc()
        local scope   = Scope:new(self.scope)
        local argVar  = scope:addVariable()
        local ifScope = Scope:new(scope)
        ifScope:addReferenceToHigherScope(scope, argVar, 3)
        scope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 2)

        return Ast.FunctionLiteralExpression(
            {Ast.VariableExpression(scope, argVar)},
            Ast.Block({
                Ast.AssignmentStatement({
                    Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar))
                }, {
                    Ast.SubExpression(
                        Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar)),
                        Ast.NumberExpression(1)
                    )
                }),
                Ast.IfStatement(
                    Ast.EqualsExpression(unpack(util.shuffle{
                        Ast.IndexExpression(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar)),
                        Ast.NumberExpression(0)
                    })),
                    Ast.Block({
                        Ast.AssignmentStatement({
                            Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable), Ast.VariableExpression(scope, argVar)),
                            Ast.AssignmentIndexing(Ast.VariableExpression(self.scope, self.upvaluesTable), Ast.VariableExpression(scope, argVar)),
                        }, {Ast.NilExpression(), Ast.NilExpression()})
                    }, ifScope),
                    {}, nil
                )
            }, scope)
        )
    end

    function Compiler:createUpvaluesProxyFunc()
        local scope      = Scope:new(self.scope)
        local entriesVar = scope:addVariable()
        local ifScope    = Scope:new(scope)
        local proxyVar   = ifScope:addVariable()
        local metaVar    = ifScope:addVariable()
        local elseScope  = Scope:new(scope)
        local forScope   = Scope:new(scope)
        local forArg     = forScope:addVariable()

        scope:addReferenceToHigherScope(self.scope, self.newproxyVar)
        ifScope:addReferenceToHigherScope(self.scope, self.newproxyVar)
        ifScope:addReferenceToHigherScope(self.scope, self.getmetatableVar)
        ifScope:addReferenceToHigherScope(self.scope, self.upvaluesGcFunctionVar)
        ifScope:addReferenceToHigherScope(scope, entriesVar)
        elseScope:addReferenceToHigherScope(self.scope, self.setmetatableVar)
        elseScope:addReferenceToHigherScope(scope, entriesVar)
        elseScope:addReferenceToHigherScope(self.scope, self.upvaluesGcFunctionVar)
        forScope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 2)
        forScope:addReferenceToHigherScope(scope, entriesVar, 2)

        return Ast.FunctionLiteralExpression(
            {Ast.VariableExpression(scope, entriesVar)},
            Ast.Block({
                Ast.ForStatement(
                    forScope, forArg,
                    Ast.NumberExpression(1),
                    Ast.LenExpression(Ast.VariableExpression(scope, entriesVar)),
                    Ast.NumberExpression(1),
                    Ast.Block({
                        Ast.AssignmentStatement({
                            Ast.AssignmentIndexing(
                                Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable),
                                Ast.IndexExpression(Ast.VariableExpression(scope, entriesVar), Ast.VariableExpression(forScope, forArg))
                            )
                        }, {
                            Ast.AddExpression(unpack(util.shuffle{
                                Ast.IndexExpression(
                                    Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable),
                                    Ast.IndexExpression(Ast.VariableExpression(scope, entriesVar), Ast.VariableExpression(forScope, forArg))
                                ),
                                Ast.NumberExpression(1),
                            }))
                        })
                    }, forScope),
                    scope
                ),
                Ast.IfStatement(
                    Ast.VariableExpression(self.scope, self.newproxyVar),
                    Ast.Block({
                        Ast.LocalVariableDeclaration(ifScope, {proxyVar}, {
                            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.newproxyVar), {Ast.BooleanExpression(true)})
                        }),
                        Ast.LocalVariableDeclaration(ifScope, {metaVar}, {
                            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.getmetatableVar), {Ast.VariableExpression(ifScope, proxyVar)})
                        }),
                        Ast.AssignmentStatement({
                            Ast.AssignmentIndexing(Ast.VariableExpression(ifScope, metaVar), Ast.StringExpression("__index")),
                            Ast.AssignmentIndexing(Ast.VariableExpression(ifScope, metaVar), Ast.StringExpression("__gc")),
                            Ast.AssignmentIndexing(Ast.VariableExpression(ifScope, metaVar), Ast.StringExpression("__len")),
                        }, {
                            Ast.VariableExpression(scope, entriesVar),
                            Ast.VariableExpression(self.scope, self.upvaluesGcFunctionVar),
                            Ast.FunctionLiteralExpression({}, Ast.Block({
                                Ast.ReturnStatement({Ast.NumberExpression(self.upvalsProxyLenReturn)})
                            }, Scope:new(ifScope))),
                        }),
                        Ast.ReturnStatement({Ast.VariableExpression(ifScope, proxyVar)})
                    }, ifScope),
                    {},
                    Ast.Block({
                        Ast.ReturnStatement({
                            Ast.FunctionCallExpression(Ast.VariableExpression(self.scope, self.setmetatableVar), {
                                Ast.TableConstructorExpression({}),
                                Ast.TableConstructorExpression({
                                    Ast.KeyedTableEntry(Ast.StringExpression("__gc"),    Ast.VariableExpression(self.scope, self.upvaluesGcFunctionVar)),
                                    Ast.KeyedTableEntry(Ast.StringExpression("__index"), Ast.VariableExpression(scope, entriesVar)),
                                    Ast.KeyedTableEntry(Ast.StringExpression("__len"),   Ast.FunctionLiteralExpression({}, Ast.Block({
                                        Ast.ReturnStatement({Ast.NumberExpression(self.upvalsProxyLenReturn)})
                                    }, Scope:new(ifScope)))),
                                })
                            })
                        })
                    }, elseScope)
                ),
            }, scope)
        )
    end

    function Compiler:createAllocUpvalFunction()
        local scope = Scope:new(self.scope)
        scope:addReferenceToHigherScope(self.scope, self.currentUpvalId, 4)
        scope:addReferenceToHigherScope(self.scope, self.upvaluesReferenceCountsTable, 1)

        return Ast.FunctionLiteralExpression({}, Ast.Block({
            Ast.AssignmentStatement({
                Ast.AssignmentVariable(self.scope, self.currentUpvalId),
            }, {
                Ast.AddExpression(unpack(util.shuffle{
                    Ast.VariableExpression(self.scope, self.currentUpvalId),
                    Ast.NumberExpression(1),
                }))
            }),
            Ast.AssignmentStatement({
                Ast.AssignmentIndexing(
                    Ast.VariableExpression(self.scope, self.upvaluesReferenceCountsTable),
                    Ast.VariableExpression(self.scope, self.currentUpvalId)
                ),
            }, {Ast.NumberExpression(1)}),
            Ast.ReturnStatement({Ast.VariableExpression(self.scope, self.currentUpvalId)})
        }, scope))
    end
end
