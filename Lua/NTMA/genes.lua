
local G = {}
NTMA.Genes = G
local L = NTMA.L
local U = NTMA.Util

pcall(function() LuaUserData.RegisterType("Barotrauma.Items.Components.GeneticMaterial") end)

G.List = {
	{ id = "geneticmaterialcrawler", type = "crawler", effect = "increasedswimmingspeed", min = 10, max = 50 },
	{ id = "geneticmaterialmudraptor", type = "mudraptor", effect = "naturalmeleeweapon", min = 20, max = 60 },
	{ id = "geneticmaterialmoloch", type = "moloch", effect = "damageresistance", min = 10, max = 25 },
	{ id = "geneticmaterialthresher", type = "thresher", effect = "decreasedoxygenconsumption", min = 20, max = 100 },
	{ id = "geneticmaterialmantis", type = "mantis", effect = "increasedwalkingspeed", min = 10, max = 25 },
	{ id = "geneticmaterialhammerhead", type = "hammerhead", effect = "increasedmeleedamage", min = 20, max = 100 },
	{ id = "geneticmaterialhammerheadmatriarch", type = "matriarch", effect = "healdamage", min = 6, max = 45 },
	{ id = "geneticmaterialspineling", type = "spineling", effect = "naturalrangedweapon", min = 0, max = 100 },
	{ id = "geneticmaterialhusk", type = "husk", effect = "husktransformimmunity", min = 60, max = 100 },
	{ id = "geneticmaterialmollusc", type = "mollusc", effect = "vigorondamage", min = 10, max = 60 },
	{ id = "geneticmaterialskitter", type = "skitter", effect = "hyperactivityondamage", min = 10, max = 60 },
	{ id = "geneticmaterialhunter", type = "hunter", effect = "increasedmeleedamageondamage", min = 75, max = 150 },
}
G.Materials = {}
for i, def in ipairs(G.List) do
	def.order = i
	G.Materials[def.id] = def
end

G.Debuffs = {
	{ id = "tunnelvision" },
	{ id = "rigidjoints", min = 10, max = 20 },
	{ id = "hypersensitivity", min = 10, max = 15 },
	{ id = "xenobiology", min = 20, max = 25 },
	{ id = "outsideinfluence", tiers = { 5, 6, 7, 8 } },
	{ id = "glassjaw", min = 25, max = 30 },
	{ id = "decrepify", min = 10, max = 15 },
	{ id = "musculardystrophy", min = 30, max = 40 },
	{ id = "inflamedlung", min = 0, max = 20 },
}
for i, def in ipairs(G.Debuffs) do def.order = i end

G.Splicers = { genesplicer = true, advancedgenesplicer = true }

G.HUSK_BLOCK = 80

local REQUIRED_SKILL = 30
local REFINE_LOW, REFINE_HIGH, REFINE_FULL_AT = 3, 25, 80
local FULL_QUALITY = 99.99

local function clamp01(x)
	return math.max(0, math.min(1, x))
end

function G.Value(def, strength)
	return math.floor(def.min + (def.max - def.min) * clamp01(strength / 100))
end

function G.EffectText(def, strength)
	local text = L("gene_fx_" .. def.type, G.Value(def, strength))
	if def.type == "husk" and strength >= G.HUSK_BLOCK then text = text .. "; " .. L("gene_husk_block") end
	return text
end

local function debuffText(def, strength)
	local key = "gene_badfx_" .. def.id
	if def.tiers ~= nil then return L(key, def.tiers[math.min(#def.tiers, math.floor(strength / 25) + 1)]) end
	if def.min ~= nil then return L(key, G.Value(def, strength)) end
	return L(key)
end

local function strongestFirst(a, b)
	if a.strength ~= b.strength then return a.strength > b.strength end
	return a.def.order < b.def.order
end

function G.ActiveBuffs(c)
	local out = {}
	for _, def in ipairs(G.List) do
		local strength = c.a(def.effect)
		if strength > 0 then
			table.insert(out, { def = def, strength = strength, name = L("gene_type_" .. def.type),
				text = G.EffectText(def, strength) })
		end
	end
	table.sort(out, strongestFirst)
	return out
end

function G.ActiveDebuffs(c)
	local out = {}
	for _, def in ipairs(G.Debuffs) do
		local strength = c.a(def.id)
		if strength > 0 then
			table.insert(out, { def = def, id = def.id, strength = strength, name = L("gene_bad_" .. def.id),
				text = debuffText(def, strength) })
		end
	end
	table.sort(out, strongestFirst)
	return out
end

function G.Splicer(character)
	if character == nil then return nil end
	local ok, item = pcall(function() return character.Inventory.GetItemInLimbSlot(InvSlotType.HealthInterface) end)
	if ok and item ~= nil and G.Splicers[U.Id(item)] then return item end
	return nil
end

local function isTainted(item)
	local ok, value = pcall(function() return item.GetComponentString("GeneticMaterial").Tainted end)
	return ok and value == true
end

function G.ReadMaterial(item)
	local id = U.Id(item)
	local def = G.Materials[id]
	if def == nil then return nil end
	local m = { item = item, id = id, def = def, quality = item.Condition, tainted = isTainted(item), types = { def.type } }
	local inner = U.Contained(item)
	if inner ~= nil and G.Materials[U.Id(inner)] ~= nil then
		m.nested = G.ReadMaterial(inner)
		table.insert(m.types, m.nested.def.type)
		m.tainted = m.tainted or m.nested.tainted
	end
	return m
end

function G.SplicedMaterials(splicer)
	local out = {}
	if splicer == nil or splicer.OwnInventory == nil then return out end
	for item in splicer.OwnInventory.AllItems do
		local m = G.ReadMaterial(item)
		if m ~= nil then table.insert(out, m) end
	end
	return out
end

function G.MaterialText(m)
	local name = L("gene_type_" .. m.def.type)
	if m.nested ~= nil then name = name .. " + " .. L("gene_type_" .. m.nested.def.type) end
	return name .. " " .. math.floor(m.quality) .. "%"
end

function G.MaterialEffect(m)
	local text = G.EffectText(m.def, m.quality)
	if m.nested ~= nil then text = text .. "; " .. G.EffectText(m.nested.def, m.quality) end
	return text
end

function G.MedicStats(c)
	local function stat(name)
		local ok, value = pcall(function() return c.me.GetStatValue(StatTypes[name]) end)
		if ok and type(value) == "number" then return value end
		return 0
	end
	return {
		skill = c.skill,
		refineBonus = stat("GeneticMaterialRefineBonus"),
		combineReduction = stat("GeneticMaterialTaintedProbabilityReductionOnCombine"),
	}
end

local function sharesType(a, b)
	for _, ta in ipairs(a.types) do
		for _, tb in ipairs(b.types) do
			if ta == tb then return true end
		end
	end
	return false
end

function G.Result(a, b)
	if a.nested ~= nil and b.nested ~= nil then return nil end
	if sharesType(a, b) then return "refine" end
	if a.nested == nil and b.nested == nil then return "combine" end
	return nil
end

local function degreeOfSuccess(skill)
	return (skill - REQUIRED_SKILL + 100) / 2 / 100
end

function G.Refine(a, b, stats)
	local high, low = math.max(a.quality, b.quality), math.min(a.quality, b.quality)
	local gain = REFINE_LOW + (REFINE_HIGH - REFINE_LOW) * clamp01(low / REFINE_FULL_AT) + stats.refineBonus
	if a.nested ~= nil or b.nested ~= nil then gain = gain / 2 end
	local quality = math.min(100, high + gain)
	if high >= FULL_QUALITY then return quality, 0, true end
	return quality, clamp01(0.99 * quality / 100 * (1 - 0.75 * degreeOfSuccess(stats.skill))), false
end

function G.Combine(a, b, stats)
	local quality = math.min(100, (a.quality + b.quality) / 2 + stats.refineBonus)
	if math.max(a.quality, b.quality) >= FULL_QUALITY then return quality, 0, true end
	return quality, clamp01(1 - stats.combineReduction), false
end

local function pairKey(kind, a, b)
	local function side(m) return G.MaterialText(m) .. (m.tainted and "!" or "") end
	local x, y = side(a), side(b)
	if y < x then x, y = y, x end
	return kind .. ":" .. x .. ":" .. y
end

function G.Plan(materials, stats)
	local out = {}
	local seen = {}
	for i = 1, #materials do
		for j = i + 1, #materials do
			local a, b = materials[i], materials[j]
			local kind = G.Result(a, b)
			local key = kind ~= nil and pairKey(kind, a, b) or nil
			if key ~= nil and not seen[key] then
				seen[key] = true
				local quality, risk, clears
				if kind == "refine" then
					quality, risk, clears = G.Refine(a, b, stats)
				else
					quality, risk, clears = G.Combine(a, b, stats)
				end
				table.insert(out, { kind = kind, a = a, b = b, quality = quality, risk = risk, clears = clears,
					tainted = a.tainted or b.tainted, key = key })
			end
		end
	end
	table.sort(out, function(x, y)
		if x.kind ~= y.kind then return x.kind == "refine" end
		if x.quality ~= y.quality then return x.quality > y.quality end
		if x.risk ~= y.risk then return x.risk < y.risk end
		return x.key < y.key
	end)
	return out
end
