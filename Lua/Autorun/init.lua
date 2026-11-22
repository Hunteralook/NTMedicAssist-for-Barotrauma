
if NTMA ~= nil and NTMA.Loaded then return end

NTMA = NTMA or {}
NTMA.Name = "NT Medic Assistant"
NTMA.Version = "1.6.0"
NTMA.Path = table.pack(...)[1] or NTMA_PATH

if not CLIENT then return end
if Game.IsSubEditor then return end
if NTMA.Path == nil then
	print("[NTMA] mod path unknown, not loading")
	return
end
NTMA.Loaded = true

dofile(NTMA.Path .. "/Lua/NTMA/lang.lua")
dofile(NTMA.Path .. "/Lua/NTMA/util.lua")
dofile(NTMA.Path .. "/Lua/NTMA/genes.lua")
dofile(NTMA.Path .. "/Lua/NTMA/surgery.lua")
dofile(NTMA.Path .. "/Lua/NTMA/rules.lua")
dofile(NTMA.Path .. "/Lua/NTMA/donorcard.lua")
dofile(NTMA.Path .. "/Lua/NTMA/patients.lua")
dofile(NTMA.Path .. "/Lua/NTMA/ui.lua")
dofile(NTMA.Path .. "/Lua/NTMA/journal.lua")
dofile(NTMA.Path .. "/Lua/NTMA/stock.lua")
dofile(NTMA.Path .. "/Lua/NTMA/genelab.lua")

print("[NTMA] " .. NTMA.Name .. " " .. NTMA.Version .. " loaded from " .. NTMA.Path)
