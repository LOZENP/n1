-- NightOwl - Vmify.lua
-- Uses the proper AST-to-AST Prometheus-style compiler

local Step     = require("nightowl.step")
local Compiler = require("nightowl.compiler.compiler")

local Vmify = Step:extend()
Vmify.Name = "Vmify"
Vmify.Description = "Compiles script into a fully custom block-dispatch VM"
Vmify.SettingsDescriptor = {}

function Vmify:init() end

function Vmify:apply(ast)
    local compiler = Compiler:new()
    return compiler:compile(ast)
end

return Vmify
