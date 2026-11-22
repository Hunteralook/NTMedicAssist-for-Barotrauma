
if not CLIENT or (NTMA ~= nil and NTMA.Loaded) then return end

local path = "LocalMods/NTMedicAssistant"
if not File.Exists(path .. "/Lua/Autorun/init.lua") then return end

NTMA_PATH = path
dofile(path .. "/Lua/Autorun/init.lua")
