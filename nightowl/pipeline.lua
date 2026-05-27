-- NightOwl - pipeline.lua

local Enums      = require("nightowl.enums")
local util       = require("nightowl.util")
local Parser     = require("nightowl.parser")
local Unparser   = require("nightowl.unparser")
local logger     = require("logger")
local NameGens   = require("nightowl.namegenerators")
local Steps      = require("nightowl.steps")
local LuaVersion = Enums.LuaVersion

local isWindows = package and package.config and type(package.config)=="string" and package.config:sub(1,1)=="\\"
local function gettime() return isWindows and os.clock() or os.time() end

local Pipeline = {
    NameGenerators = NameGens,
    Steps = Steps,
    DefaultSettings = {
        LuaVersion   = LuaVersion.LuaU,
        PrettyPrint  = false,
        Seed         = 0,
        VarNamePrefix= "",
    }
}

function Pipeline:new(settings)
    local ver  = settings.luaVersion or settings.LuaVersion or Pipeline.DefaultSettings.LuaVersion
    local conv = Enums.Conventions[ver]
    if not conv then
        logger:error("Unknown Lua version: " .. ver)
    end
    local p = {
        LuaVersion    = ver,
        PrettyPrint   = settings.PrettyPrint or false,
        VarNamePrefix = settings.VarNamePrefix or "",
        Seed          = settings.Seed or 0,
        parser        = Parser:new({LuaVersion=ver}),
        unparser      = Unparser:new({LuaVersion=ver, PrettyPrint=settings.PrettyPrint, Highlight=settings.Highlight}),
        namegenerator = Pipeline.NameGenerators.MangledShuffled,
        conventions   = conv,
        steps         = {},
    }
    setmetatable(p, self); self.__index = self
    return p
end

function Pipeline:fromConfig(config)
    config = config or {}
    local p = Pipeline:new({
        LuaVersion    = config.LuaVersion or LuaVersion.Lua51,
        PrettyPrint   = config.PrettyPrint or false,
        VarNamePrefix = config.VarNamePrefix or "",
        Seed          = config.Seed or 0,
    })
    p:setNameGenerator(config.NameGenerator or "MangledShuffled")
    for _, step in ipairs(config.Steps or {}) do
        if type(step.Name) ~= "string" then logger:error("Step.Name must be a string") end
        local ctor = p.Steps[step.Name]
        if not ctor then logger:error(string.format("Step \"%s\" not found", step.Name)) end
        p:addStep(ctor:new(step.Settings or {}))
    end
    return p
end

function Pipeline:addStep(step)   table.insert(self.steps, step) end
function Pipeline:resetSteps()    self.steps = {} end
function Pipeline:getSteps()      return self.steps end

function Pipeline:setNameGenerator(ng)
    if type(ng) == "string" then ng = Pipeline.NameGenerators[ng] end
    if type(ng) == "function" or type(ng) == "table" then
        self.namegenerator = ng
    else
        logger:error("Invalid name generator")
    end
end

function Pipeline:apply(code, filename)
    local t0 = gettime()
    filename = filename or "Anonymous"
    logger:info(string.format("Applying pipeline to %s ...", filename))

    if self.Seed > 0 then
        math.randomseed(self.Seed)
    else
        local ok, seed = pcall(function()
            local s = io.popen("openssl rand -hex 12"):read("*a"):gsub("\n","")
            local n = 0
            for i=1,#s do
                local c = s:sub(i,i):lower()
                local d = c:match("%d") and (c:byte()-48) or (c:byte()-87)
                n = n*16+d
            end
            if _VERSION=="Lua 5.1" and not jit then n = n % 9.007199254741e+15 end
            return n
        end)
        if ok then math.randomseed(seed)
        else logger:warn("OpenSSL unavailable, using os.time"); math.randomseed(os.time()) end
    end

    logger:info("Parsing...")
    local srcLen = #code
    local ast = self.parser:parse(code)
    logger:info("Parsing done")

    for _, step in ipairs(self.steps) do
        logger:info(string.format("Applying step \"%s\" ...", step.Name or "Unnamed"))
        local t1 = gettime()
        local newAst = step:apply(ast, self)
        if type(newAst) == "table" then ast = newAst end
        logger:info(string.format("Step \"%s\" done in %.2f s", step.Name or "Unnamed", gettime()-t1))
    end

    self:renameVariables(ast)
    code = self:unparse(ast)
    logger:info(string.format("Done in %.2f s | Output is %.2f%% of source", gettime()-t0, (#code/srcLen)*100))
    return code
end

function Pipeline:unparse(ast)
    logger:info("Generating code...")
    local t0 = gettime()
    local out = self.unparser:unparse(ast)
    logger:info(string.format("Code gen done in %.2f s", gettime()-t0))
    return out
end

function Pipeline:renameVariables(ast)
    logger:info("Renaming variables...")
    local t0 = gettime()
    local gf = self.namegenerator
    if type(gf) == "table" then
        if type(gf.prepare) == "function" then gf.prepare(ast) end
        gf = gf.generateName
    end
    if not self.unparser:isValidIdentifier(self.VarNamePrefix) and #self.VarNamePrefix ~= 0 then
        logger:error(string.format("Prefix \"%s\" is not a valid identifier", self.VarNamePrefix))
    end
    ast.globalScope:renameVariables({
        Keywords     = self.conventions.Keywords,
        generateName = gf,
        prefix       = self.VarNamePrefix,
    })
    logger:info(string.format("Rename done in %.2f s", gettime()-t0))
end

return Pipeline
