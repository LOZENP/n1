local Step         = require("nightowl.step")
local RandomStrings= require("nightowl.randomStrings")
local Parser       = require("nightowl.parser")
local Enums        = require("nightowl.enums")
local logger       = require("logger")

local AntiTamper = Step:extend()
AntiTamper.Name = "Anti Tamper"
AntiTamper.Description = "Breaks script if tampered with"
AntiTamper.SettingsDescriptor = {
    UseDebug = {type="boolean", default=true},
}

function AntiTamper:init() end

local function genSanity()
    local answers = {}
    local passes  = math.random(1,10)
    for i=1,passes do answers[i] = (math.random(1,2^24)%2==1) end
    local primary = RandomStrings.randomString()
    local parts   = {}
    local function add(fmt,...) table.insert(parts, string.format(fmt,...)) end

    add("do local valid='%s';", primary)
    add("for i=0,%d do\n", passes)
    for i=0,passes do
        if i==0 then
            add("if i==0 then\n")
            add("  if valid~='%s' then while true do end end\n", primary)
            add("  valid=%s;\n", tostring(answers[1]))
        elseif i==1 then
            add("elseif i==1 then\n")
            add("  if valid==%s then end\n", tostring(answers[1]))
        else
            add("elseif i==%d then\n", i)
            if i%2==0 then
                add("  valid=%s;\n", tostring(answers[math.min(i,passes)]))
            else
                add("  if valid==%s then else while true do end end\n", tostring(answers[math.min(i-1,passes)]))
            end
        end
    end
    add("end\nend\n")
    add("do valid=true end\n")
    return table.concat(parts)
end

function AntiTamper:apply(ast, pipeline)
    if pipeline.PrettyPrint then
        logger:warn("AntiTamper cannot be used with PrettyPrint, skipping")
        return ast
    end
    local code = genSanity()
    code = code .. [[
local gmatch=string.gmatch
local err=function() error("Tamper detected!") end
local pcallIntact2=false
local pcallIntact=pcall(function() pcallIntact2=true end) and pcallIntact2
local random=math.random
local n=random(3,65); local acc1=0; local acc2=0
local pcallRet={pcall(function() local a=]] .. tostring(math.random(1,2^24)) .. [[-"]] .. RandomStrings.randomString() .. [[" return "]] .. RandomStrings.randomString() .. [["/a end)}
local origMsg=pcallRet[2]
local line=tonumber(gmatch(tostring(origMsg),':(%d*):')())
for i=1,n do
    local len=random(1,100); local n2=random(0,255)
    local pos=random(1,len); local shouldErr=random(1,2)==1
    local arr={pcall(function()
        if shouldErr then error("x",0) end
        local a={}; for j=1,len do a[j]=random(0,255) end; a[pos]=n2
        return (table.unpack or unpack)(a)
    end)}
    if shouldErr then
        valid=valid and arr[1]==false
    else
        valid=valid and arr[1]
        acc1=(acc1+arr[pos+1])%256; acc2=(acc2+n2)%256
    end
end
valid=valid and acc1==acc2
if valid then else
    while true do err() end
end
end
]]
    local parsed = Parser:new({LuaVersion=Enums.LuaVersion.Lua51}):parse(code)
    local doStat = parsed.body.statements[1]
    doStat.body.scope:setParent(ast.body.scope)
    table.insert(ast.body.statements, 1, doStat)
    return ast
end

return AntiTamper
