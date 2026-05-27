local Step     = require("nightowl.step")
local Ast      = require("nightowl.ast")
local Scope    = require("nightowl.scope")
local visitast = require("nightowl.visitast")
local RL       = require("nightowl.randomLiterals")
local AstKind  = Ast.AstKind

local ProxifyLocals = Step:extend()
ProxifyLocals.Name = "Proxify Locals"
ProxifyLocals.Description = "Wraps local variables in proxy metatables"
ProxifyLocals.SettingsDescriptor = {
    LiteralType = {type="enum", default="string", values={"dictionary","number","string","any"}},
}

function ProxifyLocals:init() end

local MetaExprs = {
    {ctor=Ast.AddExpression,    key="__add"},
    {ctor=Ast.SubExpression,    key="__sub"},
    {ctor=Ast.IndexExpression,  key="__index"},
    {ctor=Ast.MulExpression,    key="__mul"},
    {ctor=Ast.DivExpression,    key="__div"},
    {ctor=Ast.PowExpression,    key="__pow"},
    {ctor=Ast.StrCatExpression, key="__concat"},
}

local function genInfo(pipeline)
    local used, info = {}, {}
    local function callNG(gf,...)
        if type(gf)=="table" then gf=gf.generateName end
        return gf(...)
    end
    for _, slot in ipairs({"setValue","getValue","index"}) do
        local r
        repeat r=MetaExprs[math.random(#MetaExprs)] until not used[r]
        used[r]=true; info[slot]=r
    end
    info.valueName = callNG(pipeline.namegenerator, math.random(1,4096))
    return info
end

function ProxifyLocals:CreateAssignment(info, expr, parentScope)
    local mvals = {}

    -- __set
    local setScope = Scope:new(parentScope)
    local setSelf  = setScope:addVariable()
    local setArg   = setScope:addVariable()
    table.insert(mvals, Ast.KeyedTableEntry(Ast.StringExpression(info.setValue.key),
        Ast.FunctionLiteralExpression(
            {Ast.VariableExpression(setScope,setSelf), Ast.VariableExpression(setScope,setArg)},
            Ast.Block({Ast.AssignmentStatement(
                {Ast.AssignmentIndexing(Ast.VariableExpression(setScope,setSelf), Ast.StringExpression(info.valueName))},
                {Ast.VariableExpression(setScope,setArg)}
            )}, setScope)
        )
    ))

    -- __get
    local getScope = Scope:new(parentScope)
    local getSelf  = getScope:addVariable()
    local getArg   = getScope:addVariable()
    local getExpr
    if info.getValue.key=="__index" or info.setValue.key=="__index" then
        getExpr = Ast.FunctionCallExpression(
            Ast.VariableExpression(getScope:resolveGlobal("rawget")),
            {Ast.VariableExpression(getScope,getSelf), Ast.StringExpression(info.valueName)}
        )
    else
        getExpr = Ast.IndexExpression(Ast.VariableExpression(getScope,getSelf), Ast.StringExpression(info.valueName))
    end
    table.insert(mvals, Ast.KeyedTableEntry(Ast.StringExpression(info.getValue.key),
        Ast.FunctionLiteralExpression(
            {Ast.VariableExpression(getScope,getSelf), Ast.VariableExpression(getScope,getArg)},
            Ast.Block({Ast.ReturnStatement({getExpr})}, getScope)
        )
    ))

    parentScope:addReferenceToHigherScope(self.smScope, self.smId)
    return Ast.FunctionCallExpression(
        Ast.VariableExpression(self.smScope, self.smId),
        {
            Ast.TableConstructorExpression({Ast.KeyedTableEntry(Ast.StringExpression(info.valueName), expr)}),
            Ast.TableConstructorExpression(mvals)
        }
    )
end

function ProxifyLocals:apply(ast, pipeline)
    local infos = {}
    local function getInfo(scope, id)
        if scope.isGlobal then return nil end
        infos[scope] = infos[scope] or {}
        if infos[scope][id] then
            if infos[scope][id].locked then return nil end
            return infos[scope][id]
        end
        local i = genInfo(pipeline)
        infos[scope][id] = i
        return i
    end
    local function disable(scope, id)
        if scope.isGlobal then return end
        infos[scope] = infos[scope] or {}
        infos[scope][id] = {locked=true}
    end

    self.smScope = ast.body.scope
    self.smId    = ast.body.scope:addVariable()

    visitast(ast,
        function(node, data)
            local k = node.kind
            if k==AstKind.ForStatement then disable(node.scope, node.id) end
            if k==AstKind.ForInStatement then
                for _,id in ipairs(node.ids) do disable(node.scope,id) end
            end
            if k==AstKind.FunctionDeclaration or k==AstKind.LocalFunctionDeclaration or k==AstKind.FunctionLiteralExpression then
                for _,arg in ipairs(node.args) do
                    if arg.kind==AstKind.VariableExpression then disable(arg.scope,arg.id) end
                end
            end
        end,
        function(node, data)
            if node.kind == AstKind.LocalVariableDeclaration then
                for i, id in ipairs(node.ids) do
                    local info = getInfo(node.scope, id)
                    if info then
                        node.expressions[i] = self:CreateAssignment(info, node.expressions[i] or Ast.NilExpression(), node.scope)
                    end
                end
            end
            if node.kind == AstKind.VariableExpression and not node.__noProxy then
                local info = getInfo(node.scope, node.id)
                if info then
                    local lit
                    if self.LiteralType=="dictionary" then lit=RL.Dictionary()
                    elseif self.LiteralType=="number"  then lit=RL.Number()
                    elseif self.LiteralType=="string"  then lit=RL.String(pipeline)
                    else lit=RL.Any(pipeline) end
                    return info.getValue.ctor(node, lit)
                end
            end
            if node.kind == AstKind.AssignmentVariable then
                local info = getInfo(node.scope, node.id)
                if info then return Ast.AssignmentIndexing(node, Ast.StringExpression(info.valueName)) end
            end
            if node.kind == AstKind.LocalFunctionDeclaration then
                local info = getInfo(node.scope, node.id)
                if info then
                    local lit = Ast.FunctionLiteralExpression(node.args, node.body)
                    return Ast.LocalVariableDeclaration(node.scope, {node.id}, {self:CreateAssignment(info,lit,node.scope)})
                end
            end
        end
    )

    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(self.smScope, {self.smId}, {
            Ast.VariableExpression(self.smScope:resolveGlobal("setmetatable"))
        })
    )
end

return ProxifyLocals
