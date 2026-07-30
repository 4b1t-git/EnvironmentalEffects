local Config = require "EnvironmentalWeapons/EW_Config"
local Diagnostics = {}

function Diagnostics.log(message)
    if Config.DEBUG then print("[EnvironmentalWeapons] " .. tostring(message)) end
end

return Diagnostics

