-- NightOwl - ConstantArray.lua

local Step     = require("nightowl.step")
local Ast      = require("nightowl.ast")
local Scope    = require("nightowl.scope")
local visitast = require("nightowl.visitast")
local util     = require("nightowl.util")
local Parser   = require("nightowl.parser")
local Enums    = require("nightowl.enums")
local AstKind  = Ast.AstKind

local ConstantArray = Step:extend()
ConstantArray.Name = "Constant Array"
ConstantArray.Description = "Extracts constants into a rotating, shuffled array"
ConstantArray.SettingsDescriptor = {
    Treshold             = {type="number",  default=1,     min=0, max=1},
    StringsOnly          = {type="boolean", default=false},
    Shuffle              = {type="boolean", default=true},
    Rotate               = {type="boolean", default=true},
    LocalWrapperCount    = {type="number",  default=0,     min=0, max=512},
    LocalWrapperArgCount = {type="number",  default=10,    min=1, max=200},
    MaxWrapperOffset     = {type="number",  default=65535, min=0},
    Encoding             = {type="enum",    default="mixed", values={"none","base64","base85","mixed"}},
    LocalWrapperTreshold = {type="number",  default=1,     min=0, max=1},
}

local function rev(t, i, j)
    while i < j do t[i], t[j] = t[j], t[i]; i, j = i+1, j-1 end
end

local function rotate(t, d, n)
    n = n or #t; d = d % n
    rev(t, 1, n); rev(t, 1, d); rev(t, d+1, n)
end

local rotateCode = [=[
for i,v in ipairs({{1,LEN},{1,SHIFT},{SHIFT+1,LEN}}) do
    while v[1]<v[2] do
        ARR[v[1]],ARR[v[2]],v[1],v[2]=ARR[v[2]],ARR[v[1]],v[1]+1,v[2]-1
    end
end
]=]

function ConstantArray:init() end

function ConstantArray:createArray()
    local entries = {}
    for i, v in ipairs(self.constants) do
        if type(v) == "string" then v = self:encode(v) end
        entries[i] = Ast.TableEntry(Ast.ConstantNode(v))
    end
    return Ast.TableConstructorExpression(entries)
end

function ConstantArray:indexing(idx, data)
    data.scope:addReferenceToHigherScope(self.rootScope, self.wrapperId)
    return Ast.FunctionCallExpression(
        Ast.VariableExpression(self.rootScope, self.wrapperId),
        {Ast.NumberExpression(idx - self.wrapperOffset)}
    )
end

function ConstantArray:getConstant(value, data)
    if self.lookup[value] then return self:indexing(self.lookup[value], data) end
    local idx = #self.constants + 1
    self.constants[idx] = value
    self.lookup[value]  = idx
    return self:indexing(idx, data)
end

function ConstantArray:addConstant(value)
    if self.lookup[value] then return end
    local idx = #self.constants + 1
    self.constants[idx] = value
    self.lookup[value]  = idx
end

function ConstantArray:encode(str)
    if self.Encoding == "none" then return str end
    local b64 = self.base64chars
    local result = ((str:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i,i) == '1' and 2^(6-i) or 0) end
        return b64:sub(c+1, c+1)
    end) .. ({'', '==', '='})[#str % 3 + 1])
    return result
end

function ConstantArray:addDecodeCode(ast)
    if self.Encoding == "none" then return end
    local decodeCode = [[
do
local sub=string.sub local floor=math.floor local strchar=string.char
local insert=table.insert local concat=table.concat local arr=ARR
local lookup=LOOKUP_TABLE
for i=1,#arr do
    local data=arr[i]
    if type(data)=="string" then
        local length=#data local parts={}
        local index=1 local value=0 local count=0
        while index<=length do
            local char=sub(data,index,index)
            local code=lookup[char]
            if code then
                value=value+code*(64^(3-count)) count=count+1
                if count==4 then
                    count=0
                    local c1=floor(value/65536)
                    local c2=floor(value%65536/256)
                    local c3=value%256
                    insert(parts,strchar(c1,c2,c3)) value=0
                end
            elseif char=="=" then
                insert(parts,strchar(floor(value/65536)))
                if index>=length or sub(data,index+1,index+1)~="=" then
                    insert(parts,strchar(floor(value%65536/256)))
                end
                break
            end
            index=index+1
        end
        arr[i]=concat(parts)
    end
end
end]]
    local parser = Parser:new({LuaVersion=Enums.LuaVersion.Lua51})
    local newAst = parser:parse(decodeCode)
    local doStat = newAst.body.statements[1]
    doStat.body.scope:setParent(ast.body.scope)

    visitast(newAst, nil, function(node, data)
        if node.kind == AstKind.VariableExpression then
            if node.scope:getVariableName(node.id) == "ARR" then
                data.scope:removeReferenceToHigherScope(node.scope, node.id)
                data.scope:addReferenceToHigherScope(self.rootScope, self.arrId)
                node.scope = self.rootScope
                node.id    = self.arrId
            end
            if node.scope:getVariableName(node.id) == "LOOKUP_TABLE" then
                data.scope:removeReferenceToHigherScope(node.scope, node.id)
                return self:createBase64Lookup()
            end
        end
    end)

    -- insert at position 1 (top)
    table.insert(ast.body.statements, 1, doStat)
end

function ConstantArray:createBase64Lookup()
    local entries = {}
    local i = 0
    for char in self.base64chars:gmatch(".") do
        table.insert(entries, Ast.KeyedTableEntry(
            Ast.StringExpression(char),
            Ast.NumberExpression(i)
        ))
        i = i + 1
    end
    util.shuffle(entries)
    return Ast.TableConstructorExpression(entries)
end

function ConstantArray:addRotateCode(ast, shift)
    local code    = rotateCode:gsub("SHIFT", tostring(shift)):gsub("LEN", tostring(#self.constants))
    local parser  = Parser:new({LuaVersion=Enums.LuaVersion.Lua51})
    local newAst  = parser:parse(code)
    local forStat = newAst.body.statements[1]
    forStat.body.scope:setParent(ast.body.scope)

    visitast(newAst, nil, function(node, data)
        if node.kind == AstKind.VariableExpression then
            if node.scope:getVariableName(node.id) == "ARR" then
                data.scope:removeReferenceToHigherScope(node.scope, node.id)
                data.scope:addReferenceToHigherScope(self.rootScope, self.arrId)
                node.scope = self.rootScope
                node.id    = self.arrId
            end
        end
    end)

    -- insert at position 1 (top)
    table.insert(ast.body.statements, 1, forStat)
end

function ConstantArray:apply(ast, pipeline)
    self.rootScope = ast.body.scope
    self.arrId     = self.rootScope:addVariable()

    self.base64chars = table.concat(util.shuffle{
        "A","B","C","D","E","F","G","H","I","J","K","L","M",
        "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
        "a","b","c","d","e","f","g","h","i","j","k","l","m",
        "n","o","p","q","r","s","t","u","v","w","x","y","z",
        "0","1","2","3","4","5","6","7","8","9","+","/",
    })

    self.constants = {}
    self.lookup    = {}

    -- first pass: collect constants
    visitast(ast, nil, function(node)
        if math.random() <= self.Treshold then
            node.__apply_ca = true
            if node.kind == AstKind.StringExpression then
                self:addConstant(node.value)
            elseif not self.StringsOnly and node.isConstant and node.value ~= nil then
                self:addConstant(node.value)
            end
        end
    end)

    if self.Shuffle then
        self.constants = util.shuffle(self.constants)
        self.lookup    = {}
        for i, v in ipairs(self.constants) do self.lookup[v] = i end
    end

    self.wrapperOffset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset)
    self.wrapperId     = self.rootScope:addVariable()

    -- second pass: replace constants with wrapper calls
    visitast(ast, nil, function(node, data)
        if node.__apply_ca then
            node.__apply_ca = nil
            if node.kind == AstKind.StringExpression then
                return self:getConstant(node.value, data)
            elseif not self.StringsOnly and node.isConstant and node.value ~= nil then
                return self:getConstant(node.value, data)
            end
        end
    end)

    -- Insert everything at top in REVERSE order
    -- so final order is: array → decode → rotate → wrapper → script

    -- step 4: insert wrapper at top (pos 1) last = ends up at pos 1 after all inserts
    local funcScope = Scope:new(self.rootScope)
    funcScope:addReferenceToHigherScope(self.rootScope, self.arrId)
    local argId = funcScope:addVariable()
    local addSubArg
    if self.wrapperOffset < 0 then
        addSubArg = Ast.SubExpression(
            Ast.VariableExpression(funcScope, argId),
            Ast.NumberExpression(-self.wrapperOffset)
        )
    else
        addSubArg = Ast.AddExpression(
            Ast.VariableExpression(funcScope, argId),
            Ast.NumberExpression(self.wrapperOffset)
        )
    end
    table.insert(ast.body.statements, 1, Ast.LocalFunctionDeclaration(
        self.rootScope,
        self.wrapperId,
        {Ast.VariableExpression(funcScope, argId)},
        Ast.Block({
            Ast.ReturnStatement({
                Ast.IndexExpression(
                    Ast.VariableExpression(self.rootScope, self.arrId),
                    addSubArg
                )
            })
        }, funcScope)
    ))

    -- step 3: insert rotate at pos 1 (pushes wrapper down)
    if self.Rotate and #self.constants > 1 then
        local shift = math.random(1, #self.constants - 1)
        rotate(self.constants, -shift)
        self:addRotateCode(ast, shift)
    end

    -- step 2: insert decode at pos 1 (pushes rotate down)
    self:addDecodeCode(ast)

    -- step 1: insert array at pos 1 (pushes decode down) — ends up first
    table.insert(ast.body.statements, 1,
        Ast.LocalVariableDeclaration(
            self.rootScope,
            {self.arrId},
            {self:createArray()}
        )
    )

    -- final order in output:
    -- local arr = {...}        <- array
    -- do ... decode ... end    <- decode
    -- for ... rotate ... end   <- rotate
    -- local function wrap(...) <- wrapper
    -- ... rest of script ...

    self.rootScope = nil
    self.arrId     = nil
    self.constants = nil
    self.lookup    = nil
end

return ConstantArray
