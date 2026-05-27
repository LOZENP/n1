-- NightOwl CLI

local function script_path()
    local str = debug.getinfo(2,"S").source:sub(2)
    return str:match("(.*[/\\])") or "./"
end
package.path = script_path() .. "?.lua;" .. package.path

local NightOwl = require("nightowl")
local Pipeline = NightOwl.Pipeline
local Presets  = NightOwl.Presets

local args = arg or {}
local inputFile, outputFile, preset = nil, nil, "Minify"

local i = 1
while i <= #args do
    if args[i] == "--in"     then inputFile  = args[i+1]; i=i+2
    elseif args[i] == "--out" then outputFile = args[i+1]; i=i+2
    elseif args[i] == "--preset" then preset  = args[i+1]; i=i+2
    else i=i+1 end
end

if not inputFile then
    print("Usage: lua cli.lua --in <input.lua> --out <output.lua> [--preset Weak|Medium|Strong|Minify]")
    os.exit(1)
end

local f = io.open(inputFile, "r")
if not f then print("Cannot open: " .. inputFile); os.exit(1) end
local code = f:read("*a"); f:close()

local cfg = Presets[preset]
if not cfg then print("Unknown preset: " .. preset); os.exit(1) end

local pipeline = Pipeline:fromConfig(cfg)
local result   = pipeline:apply(code, inputFile)

local out = outputFile and io.open(outputFile,"w") or io.stdout
out:write(result)
if outputFile then out:close() end
print("Done! -> " .. (outputFile or "stdout"))
