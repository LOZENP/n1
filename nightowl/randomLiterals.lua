local Ast           = require("nightowl.ast")
local RandomStrings = require("nightowl.randomStrings")

local function callNameGen(gf, ...)
    if type(gf)=="table" then gf=gf.generateName end
    return gf(...)
end

local RL = {}

function RL.String(pipeline)
    return Ast.StringExpression(callNameGen(pipeline.namegenerator, math.random(1,4096)))
end
function RL.Dictionary()  return RandomStrings.randomStringNode(true) end
function RL.Number()      return Ast.NumberExpression(math.random(-8388608,8388607)) end
function RL.Any(pipeline)
    local t = math.random(1,3)
    if t==1 then return RL.String(pipeline) end
    if t==2 then return RL.Number() end
    return RL.Dictionary()
end

return RL
