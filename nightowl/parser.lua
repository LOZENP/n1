-- NightOwl - parser.lua

local Tokenizer = require("nightowl.tokenizer")
local Enums     = require("nightowl.enums")
local util      = require("nightowl.util")
local Ast       = require("nightowl.ast")
local Scope     = require("nightowl.scope")
local logger    = require("logger")

local AstKind    = Ast.AstKind
local LuaVersion = Enums.LuaVersion
local lookupify  = util.lookupify
local TokenKind  = Tokenizer.TokenKind

local Parser = {}

local NO_WARN_LOOKUP = lookupify{
    AstKind.NilExpression, AstKind.FunctionCallExpression,
    AstKind.PassSelfFunctionCallExpression, AstKind.VarargExpression
}
local CALLABLE_LOOKUP = lookupify{
    AstKind.VariableExpression, AstKind.IndexExpression,
    AstKind.FunctionCallExpression, AstKind.PassSelfFunctionCallExpression
}

local function genErr(self, msg)
    local tk
    if self.index > self.length then tk = self.tokens[self.length]
    elseif self.index < 1 then return "Parse Error at 0:0, " .. msg
    else tk = self.tokens[self.index] end
    return "Parse Error at " .. tk.line .. ":" .. tk.linePos .. ", " .. msg
end

function Parser:new(settings)
    local ver = (settings and (settings.luaVersion or settings.LuaVersion)) or LuaVersion.LuaU
    local p = {
        luaVersion = ver,
        tokenizer  = Tokenizer:new({luaVersion=ver}),
        tokens = {}, length = 0, index = 0,
    }
    setmetatable(p, self); self.__index = self
    return p
end

local function peek(self, n)
    n = n or 0
    local i = self.index + n + 1
    if i > self.length then return Tokenizer.EOF_TOKEN end
    return self.tokens[i]
end

local function get(self)
    local i = self.index + 1
    if i > self.length then error(genErr(self, "Unexpected end of input")) end
    self.index = i
    return self.tokens[i]
end

local function is(self, kind, srcOrN, n)
    local src
    if type(srcOrN) == "string" then src = srcOrN else n = srcOrN end
    n = n or 0
    local tk = peek(self, n)
    if tk.kind == kind then
        if src == nil or tk.source == src then return true end
    end
    return false
end

local function consume(self, kind, src)
    if is(self, kind, src) then self.index = self.index+1; return true end
    return false
end

local function expect(self, kind, src)
    if is(self, kind, src, 0) then return get(self) end
    local tk = peek(self)
    if self.disableLog then error() end
    if src then
        logger:error(genErr(self, string.format("unexpected <%s> \"%s\", expected <%s> \"%s\"", tk.kind, tk.source, kind, src)))
    else
        logger:error(genErr(self, string.format("unexpected <%s> \"%s\", expected <%s>", tk.kind, tk.source, kind)))
    end
end

function Parser:parse(code)
    self.tokenizer:append(code)
    self.tokens = self.tokenizer:scanAll()
    self.length = #self.tokens
    local gs = Scope:newGlobal()
    local ast = Ast.TopNode(self:block(gs, false), gs)
    expect(self, TokenKind.Eof)
    self.tokenizer:reset(); self.tokens = {}; self.index = 0; self.length = 0
    return ast
end

function Parser:block(parentScope, currentLoop, scope)
    scope = scope or Scope:new(parentScope)
    local stmts = {}
    repeat
        local stmt, isTerminating = self:statement(scope, currentLoop)
        table.insert(stmts, stmt)
    until isTerminating or not stmt
    consume(self, TokenKind.Symbol, ";")
    return Ast.Block(stmts, scope)
end

function Parser:statement(scope, currentLoop)
    while consume(self, TokenKind.Symbol, ";") do end

    if consume(self, TokenKind.Keyword, "break") then
        if not currentLoop then
            if self.disableLog then error() end
            logger:error(genErr(self, "break only valid inside loops"))
        end
        return Ast.BreakStatement(currentLoop, scope), true
    end

    if self.luaVersion == LuaVersion.LuaU and consume(self, TokenKind.Keyword, "continue") then
        if not currentLoop then
            if self.disableLog then error() end
            logger:error(genErr(self, "continue only valid inside loops"))
        end
        return Ast.ContinueStatement(currentLoop, scope), true
    end

    if consume(self, TokenKind.Keyword, "do") then
        local body = self:block(scope, currentLoop)
        expect(self, TokenKind.Keyword, "end")
        return Ast.DoStatement(body)
    end

    if consume(self, TokenKind.Keyword, "while") then
        local cond = self:expression(scope)
        expect(self, TokenKind.Keyword, "do")
        local stat = Ast.WhileStatement(nil, cond, scope)
        stat.body = self:block(scope, stat)
        expect(self, TokenKind.Keyword, "end")
        return stat
    end

    if consume(self, TokenKind.Keyword, "repeat") then
        local rs = Scope:new(scope)
        local stat = Ast.RepeatStatement(nil, nil, scope)
        stat.body = self:block(nil, stat, rs)
        expect(self, TokenKind.Keyword, "until")
        stat.condition = self:expression(rs)
        return stat
    end

    if consume(self, TokenKind.Keyword, "return") then
        local args = {}
        if not is(self,TokenKind.Keyword,"end") and not is(self,TokenKind.Keyword,"elseif")
            and not is(self,TokenKind.Keyword,"else") and not is(self,TokenKind.Symbol,";")
            and not is(self,TokenKind.Eof) then
            args = self:exprList(scope)
        end
        return Ast.ReturnStatement(args), true
    end

    if consume(self, TokenKind.Keyword, "if") then
        local cond = self:expression(scope)
        expect(self, TokenKind.Keyword, "then")
        local body = self:block(scope, currentLoop)
        local elseifs = {}
        while consume(self, TokenKind.Keyword, "elseif") do
            local ec = self:expression(scope)
            expect(self, TokenKind.Keyword, "then")
            local eb = self:block(scope, currentLoop)
            table.insert(elseifs, {condition=ec, body=eb})
        end
        local elsebody
        if consume(self, TokenKind.Keyword, "else") then
            elsebody = self:block(scope, currentLoop)
        end
        expect(self, TokenKind.Keyword, "end")
        return Ast.IfStatement(cond, body, elseifs, elsebody)
    end

    if consume(self, TokenKind.Keyword, "function") then
        local obj = self:funcName(scope)
        local funcScope = Scope:new(scope)
        expect(self, TokenKind.Symbol, "(")
        local args = self:functionArgList(funcScope)
        expect(self, TokenKind.Symbol, ")")
        if obj.passSelf then
            local id = funcScope:addVariable("self", obj.token)
            table.insert(args, 1, Ast.VariableExpression(funcScope, id))
        end
        local body = self:block(nil, false, funcScope)
        expect(self, TokenKind.Keyword, "end")
        return Ast.FunctionDeclaration(obj.scope, obj.id, obj.indices, args, body)
    end

    if consume(self, TokenKind.Keyword, "local") then
        if consume(self, TokenKind.Keyword, "function") then
            local ident = expect(self, TokenKind.Ident)
            local id = scope:addVariable(ident.value, ident)
            local funcScope = Scope:new(scope)
            expect(self, TokenKind.Symbol, "(")
            local args = self:functionArgList(funcScope)
            expect(self, TokenKind.Symbol, ")")
            local body = self:block(nil, false, funcScope)
            expect(self, TokenKind.Keyword, "end")
            return Ast.LocalFunctionDeclaration(scope, id, args, body)
        end
        local ids = self:nameList(scope)
        local exprs = {}
        if consume(self, TokenKind.Symbol, "=") then exprs = self:exprList(scope) end
        self:enableNameList(scope, ids)
        return Ast.LocalVariableDeclaration(scope, ids, exprs)
    end

    if consume(self, TokenKind.Keyword, "for") then
        if is(self, TokenKind.Symbol, "=", 1) then
            local fs = Scope:new(scope)
            local ident = expect(self, TokenKind.Ident)
            local varId = fs:addDisabledVariable(ident.value, ident)
            expect(self, TokenKind.Symbol, "=")
            local init = self:expression(scope)
            expect(self, TokenKind.Symbol, ",")
            local final = self:expression(scope)
            local inc = Ast.NumberExpression(1)
            if consume(self, TokenKind.Symbol, ",") then inc = self:expression(scope) end
            local stat = Ast.ForStatement(fs, varId, init, final, inc, nil, scope)
            fs:enableVariable(varId)
            expect(self, TokenKind.Keyword, "do")
            stat.body = self:block(nil, stat, fs)
            expect(self, TokenKind.Keyword, "end")
            return stat
        end
        local fs = Scope:new(scope)
        local ids = self:nameList(fs)
        expect(self, TokenKind.Keyword, "in")
        local exprs = self:exprList(scope)
        self:enableNameList(fs, ids)
        expect(self, TokenKind.Keyword, "do")
        local stat = Ast.ForInStatement(fs, ids, exprs, nil, scope)
        stat.body = self:block(nil, stat, fs)
        expect(self, TokenKind.Keyword, "end")
        return stat
    end

    local expr = self:primaryExpression(scope)
    if expr then
        if expr.kind == AstKind.FunctionCallExpression then
            return Ast.FunctionCallStatement(expr.base, expr.args)
        end
        if expr.kind == AstKind.PassSelfFunctionCallExpression then
            return Ast.PassSelfFunctionCallStatement(expr.base, expr.passSelfFunctionName, expr.args)
        end
        if expr.kind == AstKind.IndexExpression or expr.kind == AstKind.VariableExpression then
            if expr.kind == AstKind.IndexExpression then expr.kind = AstKind.AssignmentIndexing end
            if expr.kind == AstKind.VariableExpression then expr.kind = AstKind.AssignmentVariable end

            -- LuaU compound assignments
            if self.luaVersion == LuaVersion.LuaU then
                local compoundMap = {
                    ["+="] = Ast.CompoundAddStatement,
                    ["-="] = Ast.CompoundSubStatement,
                    ["*="] = Ast.CompoundMulStatement,
                    ["/="] = Ast.CompoundDivStatement,
                    ["%="] = Ast.CompoundModStatement,
                    ["^="] = Ast.CompoundPowStatement,
                    ["..="] = Ast.CompoundConcatStatement,
                }
                for sym, ctor in pairs(compoundMap) do
                    if consume(self, TokenKind.Symbol, sym) then
                        return ctor(expr, self:expression(scope))
                    end
                end
            end

            local lhs = {expr}
            while consume(self, TokenKind.Symbol, ",") do
                local e = self:primaryExpression(scope)
                if not e then
                    if self.disableLog then error() end
                    logger:error(genErr(self, "expected valid lhs"))
                end
                if e.kind == AstKind.IndexExpression then e.kind = AstKind.AssignmentIndexing end
                if e.kind == AstKind.VariableExpression then e.kind = AstKind.AssignmentVariable end
                table.insert(lhs, e)
            end
            expect(self, TokenKind.Symbol, "=")
            return Ast.AssignmentStatement(lhs, self:exprList(scope))
        end
        if self.disableLog then error() end
        logger:error(genErr(self, "expressions are not valid statements"))
    end
    return nil
end

function Parser:primaryExpression(scope)
    local i = self.index
    self.disableLog = true
    local ok, val = pcall(self.expressionFunctionCall, self, scope)
    self.disableLog = false
    if ok then return val end
    self.index = i
    return nil
end

function Parser:exprList(scope)
    local exprs = {self:expression(scope)}
    while consume(self, TokenKind.Symbol, ",") do
        table.insert(exprs, self:expression(scope))
    end
    return exprs
end

function Parser:nameList(scope)
    local ids = {}
    local ident = expect(self, TokenKind.Ident)
    table.insert(ids, scope:addDisabledVariable(ident.value, ident))
    while consume(self, TokenKind.Symbol, ",") do
        ident = expect(self, TokenKind.Ident)
        table.insert(ids, scope:addDisabledVariable(ident.value, ident))
    end
    return ids
end

function Parser:enableNameList(scope, list)
    for _, id in ipairs(list) do scope:enableVariable(id) end
end

function Parser:funcName(scope)
    local ident = expect(self, TokenKind.Ident)
    local baseName = ident.value
    local bscope, bid = scope:resolve(baseName)
    local indices, passSelf = {}, false
    while consume(self, TokenKind.Symbol, ".") do
        table.insert(indices, expect(self, TokenKind.Ident).value)
    end
    if consume(self, TokenKind.Symbol, ":") then
        table.insert(indices, expect(self, TokenKind.Ident).value)
        passSelf = true
    end
    return {scope=bscope, id=bid, indices=indices, passSelf=passSelf, token=ident}
end

function Parser:expression(scope)  return self:expressionOr(scope) end

function Parser:expressionOr(scope)
    local lhs = self:expressionAnd(scope)
    if consume(self, TokenKind.Keyword, "or") then
        return Ast.OrExpression(lhs, self:expressionOr(scope), true)
    end
    return lhs
end

function Parser:expressionAnd(scope)
    local lhs = self:expressionComparision(scope)
    if consume(self, TokenKind.Keyword, "and") then
        return Ast.AndExpression(lhs, self:expressionAnd(scope), true)
    end
    return lhs
end

function Parser:expressionComparision(scope)
    local curr = self:expressionStrCat(scope)
    local cmpMap = {
        ["<"]  = Ast.LessThanExpression,
        [">"]  = Ast.GreaterThanExpression,
        ["<="] = Ast.LessThanOrEqualsExpression,
        [">="] = Ast.GreaterThanOrEqualsExpression,
        ["~="] = Ast.NotEqualsExpression,
        ["=="] = Ast.EqualsExpression,
    }
    repeat
        local found = false
        for sym, ctor in pairs(cmpMap) do
            if consume(self, TokenKind.Symbol, sym) then
                curr = ctor(curr, self:expressionStrCat(scope), true)
                found = true; break
            end
        end
    until not found
    return curr
end

function Parser:expressionStrCat(scope)
    local lhs = self:expressionAddSub(scope)
    if consume(self, TokenKind.Symbol, "..") then
        return Ast.StrCatExpression(lhs, self:expressionStrCat(scope), true)
    end
    return lhs
end

function Parser:expressionAddSub(scope)
    local curr = self:expressionMulDivMod(scope)
    repeat
        local found = false
        if consume(self, TokenKind.Symbol, "+") then
            curr = Ast.AddExpression(curr, self:expressionMulDivMod(scope), true); found=true
        end
        if consume(self, TokenKind.Symbol, "-") then
            curr = Ast.SubExpression(curr, self:expressionMulDivMod(scope), true); found=true
        end
    until not found
    return curr
end

function Parser:expressionMulDivMod(scope)
    local curr = self:expressionUnary(scope)
    repeat
        local found = false
        if consume(self, TokenKind.Symbol, "*") then
            curr = Ast.MulExpression(curr, self:expressionUnary(scope), true); found=true
        end
        if consume(self, TokenKind.Symbol, "/") then
            curr = Ast.DivExpression(curr, self:expressionUnary(scope), true); found=true
        end
        if consume(self, TokenKind.Symbol, "%") then
            curr = Ast.ModExpression(curr, self:expressionUnary(scope), true); found=true
        end
    until not found
    return curr
end

function Parser:expressionUnary(scope)
    if consume(self, TokenKind.Keyword, "not") then return Ast.NotExpression(self:expressionUnary(scope), true) end
    if consume(self, TokenKind.Symbol, "#")   then return Ast.LenExpression(self:expressionUnary(scope), true) end
    if consume(self, TokenKind.Symbol, "-")   then return Ast.NegateExpression(self:expressionUnary(scope), true) end
    return self:expressionPow(scope)
end

function Parser:expressionPow(scope)
    local lhs = self:tableOrFunctionLiteral(scope)
    if consume(self, TokenKind.Symbol, "^") then
        return Ast.PowExpression(lhs, self:expressionUnary(scope), true)
    end
    return lhs
end

function Parser:tableOrFunctionLiteral(scope)
    if is(self, TokenKind.Symbol, "{")         then return self:tableConstructor(scope) end
    if is(self, TokenKind.Keyword, "function") then return self:expressionFunctionLiteral(scope) end
    return self:expressionFunctionCall(scope)
end

function Parser:expressionFunctionLiteral(parentScope)
    local scope = Scope:new(parentScope)
    expect(self, TokenKind.Keyword, "function")
    expect(self, TokenKind.Symbol, "(")
    local args = self:functionArgList(scope)
    expect(self, TokenKind.Symbol, ")")
    local body = self:block(nil, false, scope)
    expect(self, TokenKind.Keyword, "end")
    return Ast.FunctionLiteralExpression(args, body)
end

function Parser:functionArgList(scope)
    local args = {}
    if consume(self, TokenKind.Symbol, "...") then
        table.insert(args, Ast.VarargExpression()); return args
    end
    if is(self, TokenKind.Ident) then
        local ident = get(self)
        local id = scope:addVariable(ident.value, ident)
        table.insert(args, Ast.VariableExpression(scope, id))
        while consume(self, TokenKind.Symbol, ",") do
            if consume(self, TokenKind.Symbol, "...") then
                table.insert(args, Ast.VarargExpression()); return args
            end
            ident = get(self)
            id = scope:addVariable(ident.value, ident)
            table.insert(args, Ast.VariableExpression(scope, id))
        end
    end
    return args
end

function Parser:expressionFunctionCall(scope, base)
    base = base or self:expressionIndex(scope)
    if not (base and (CALLABLE_LOOKUP[base.kind] or base.isParenthesizedExpression)) then
        return base
    end
    local args = {}
    if is(self, TokenKind.String) then
        args = {Ast.StringExpression(get(self).value)}
    elseif is(self, TokenKind.Symbol, "{") then
        args = {self:tableConstructor(scope)}
    elseif consume(self, TokenKind.Symbol, "(") then
        if not is(self, TokenKind.Symbol, ")") then args = self:exprList(scope) end
        expect(self, TokenKind.Symbol, ")")
    else
        return base
    end
    local node = Ast.FunctionCallExpression(base, args)
    if is(self,TokenKind.Symbol,".") or is(self,TokenKind.Symbol,"[") or is(self,TokenKind.Symbol,":") then
        return self:expressionIndex(scope, node)
    end
    if is(self,TokenKind.Symbol,"(") or is(self,TokenKind.Symbol,"{") or is(self,TokenKind.String) then
        return self:expressionFunctionCall(scope, node)
    end
    return node
end

function Parser:expressionIndex(scope, base)
    base = base or self:expressionLiteral(scope)
    while consume(self, TokenKind.Symbol, "[") do
        local expr = self:expression(scope)
        expect(self, TokenKind.Symbol, "]")
        base = Ast.IndexExpression(base, expr)
    end
    while consume(self, TokenKind.Symbol, ".") do
        local ident = expect(self, TokenKind.Ident)
        base = Ast.IndexExpression(base, Ast.StringExpression(ident.value))
        while consume(self, TokenKind.Symbol, "[") do
            local expr = self:expression(scope)
            expect(self, TokenKind.Symbol, "]")
            base = Ast.IndexExpression(base, expr)
        end
    end
    if consume(self, TokenKind.Symbol, ":") then
        local name = expect(self, TokenKind.Ident).value
        local args = {}
        if is(self, TokenKind.String) then
            args = {Ast.StringExpression(get(self).value)}
        elseif is(self, TokenKind.Symbol, "{") then
            args = {self:tableConstructor(scope)}
        else
            expect(self, TokenKind.Symbol, "(")
            if not is(self, TokenKind.Symbol, ")") then args = self:exprList(scope) end
            expect(self, TokenKind.Symbol, ")")
        end
        local node = Ast.PassSelfFunctionCallExpression(base, name, args)
        if is(self,TokenKind.Symbol,".") or is(self,TokenKind.Symbol,"[") or is(self,TokenKind.Symbol,":") then
            return self:expressionIndex(scope, node)
        end
        if is(self,TokenKind.Symbol,"(") or is(self,TokenKind.Symbol,"{") or is(self,TokenKind.String) then
            return self:expressionFunctionCall(scope, node)
        end
        return node
    end
    if is(self,TokenKind.Symbol,"(") or is(self,TokenKind.Symbol,"{") or is(self,TokenKind.String) then
        return self:expressionFunctionCall(scope, base)
    end
    return base
end

function Parser:expressionLiteral(scope)
    if consume(self, TokenKind.Symbol, "(") then
        local expr = self:expression(scope)
        expect(self, TokenKind.Symbol, ")")
        if expr then expr.isParenthesizedExpression = true end
        return expr
    end
    if is(self, TokenKind.String)          then return Ast.StringExpression(get(self).value) end
    if is(self, TokenKind.Number)          then return Ast.NumberExpression(get(self).value) end
    if consume(self, TokenKind.Keyword, "true")  then return Ast.BooleanExpression(true) end
    if consume(self, TokenKind.Keyword, "false") then return Ast.BooleanExpression(false) end
    if consume(self, TokenKind.Keyword, "nil")   then return Ast.NilExpression() end
    if consume(self, TokenKind.Symbol, "...")    then return Ast.VarargExpression() end
    if is(self, TokenKind.Ident) then
        local ident = get(self)
        local sc, id = scope:resolve(ident.value)
        return Ast.VariableExpression(sc, id)
    end
    if LuaVersion.LuaU then
        if consume(self, TokenKind.Keyword, "if") then
            local cond = self:expression(scope)
            expect(self, TokenKind.Keyword, "then")
            local tv = self:expression(scope)
            expect(self, TokenKind.Keyword, "else")
            local fv = self:expression(scope)
            return Ast.IfElseExpression(cond, tv, fv)
        end
    end
    if self.disableLog then error() end
    logger:error(genErr(self, "Unexpected token \"" .. peek(self).source .. "\", expected expression"))
end

function Parser:tableConstructor(scope)
    local entries = {}
    expect(self, TokenKind.Symbol, "{")
    while not consume(self, TokenKind.Symbol, "}") do
        if consume(self, TokenKind.Symbol, "[") then
            local key = self:expression(scope)
            expect(self, TokenKind.Symbol, "]")
            expect(self, TokenKind.Symbol, "=")
            local val = self:expression(scope)
            table.insert(entries, Ast.KeyedTableEntry(key, val))
        elseif is(self, TokenKind.Ident, 0) and is(self, TokenKind.Symbol, "=", 1) then
            local key = Ast.StringExpression(get(self).value)
            expect(self, TokenKind.Symbol, "=")
            local val = self:expression(scope)
            table.insert(entries, Ast.KeyedTableEntry(key, val))
        else
            table.insert(entries, Ast.TableEntry(self:expression(scope)))
        end
        if not consume(self, TokenKind.Symbol, ";") and not consume(self, TokenKind.Symbol, ",") and not is(self, TokenKind.Symbol, "}") then
            if self.disableLog then error() end
            logger:error(genErr(self, "expected \";\" or \",\""))
        end
    end
    return Ast.TableConstructorExpression(entries)
end

return Parser
