-- NightOwl Obfuscator - Main Entry

local function script_path()
    local str = debug.getinfo(2,"S").source:sub(2)
    return str:match("(.*[/\\])") or "./"
end

local oldPkg = package.path
package.path = script_path() .. "?.lua;" .. package.path

-- Lua 5.1 math.random large range fix
if not pcall(function() return math.random(1,2^40) end) then
    local old = math.random
    math.random = function(a,b)
        if not a and not b then return old() end
        if not b then return math.random(1,a) end
        if a>b then a,b=b,a end
        local d=b-a
        if d>2^31-1 then return math.floor(old()*d+a) end
        return old(a,b)
    end
end

_G.newproxy = _G.newproxy or function(arg)
    if arg then return setmetatable({},{}) end
    return {}
end

local Pipeline = require("nightowl.pipeline")
local Presets  = require("presets")
local Config   = require("config")
local util     = require("nightowl.util")

package.path = oldPkg

return {
    Pipeline = Pipeline,
    Presets  = Presets,
    Config   = util.readonly(Config),
}
