-- NightOwl - logger.lua

local Logger = {
    level = "info" -- "debug", "info", "warn", "error"
}

function Logger:debug(msg) if self.level=="debug" then print("[DEBUG] " .. msg) end end
function Logger:info(msg)  print("[INFO]  " .. msg) end
function Logger:warn(msg)  print("[WARN]  " .. msg) end
function Logger:error(msg) error("[ERROR] " .. msg, 2) end

return Logger
