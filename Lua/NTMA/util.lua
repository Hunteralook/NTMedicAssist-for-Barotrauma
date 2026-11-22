local U = {}
NTMA.Util = U
local L = NTMA.L

function U.Id(item)
	if item == nil or item.Prefab == nil then return "" end
	return item.Prefab.Identifier.Value
end

function U.Str(s)
	if s == nil then return "" end
	local ok, v = pcall(function() return s.Value end)
	if ok and type(v) == "string" then return v end
	return tostring(s)
end

function U.SplitId(id)
	local base, variant = string.match(id, "^([^:]+):(.+)$")
	if base == nil then return id, nil end
	return base, variant
end

local prefabNames = {}
function U.ItemName(id)
	local name = prefabNames[id]
	if name ~= nil then return name end
	local base, variant = U.SplitId(id)
	local prefab = ItemPrefab.GetItemPrefab(base)
	name = prefab ~= nil and U.Str(prefab.Name) or base
	if name == "" then name = base end
	if variant ~= nil then name = name .. " (" .. L("variant_" .. variant) .. ")" end
	prefabNames[id] = name
	return name
end

function U.PatternName(pattern)
	if string.sub(pattern, -1) == "*" then pattern = string.sub(pattern, 1, -2) end
	return U.ItemName(pattern)
end

function U.ItemIcon(id)
	local prefab = ItemPrefab.GetItemPrefab((U.SplitId(id)))
	if prefab == nil then return nil end
	return prefab.InventoryIcon or prefab.Sprite
end

local limbNames = {
	[LimbType.Head] = "limb_head",
	[LimbType.Torso] = "limb_torso",
	[LimbType.LeftArm] = "limb_larm",
	[LimbType.RightArm] = "limb_rarm",
	[LimbType.LeftLeg] = "limb_lleg",
	[LimbType.RightLeg] = "limb_rleg",
}
function U.LimbName(limbtype)
	if limbtype == nil then return L("any_limb") end
	return L(limbNames[limbtype] or "any_limb")
end

function U.Matches(id, pattern)
	if string.sub(pattern, -1) == "*" then
		local prefix = string.sub(pattern, 1, -2)
		return string.sub(id, 1, #prefix) == prefix
	end
	return id == pattern
end

local function walk(out, inventory, depth)
	if inventory == nil or depth > 3 then return end
	for item in inventory.AllItems do
		table.insert(out, item)
		if item.OwnInventory ~= nil then walk(out, item.OwnInventory, depth + 1) end
	end
end

function U.CarriedItems(character)
	local out = {}
	if character ~= nil then walk(out, character.Inventory, 0) end
	return out
end

function U.OpenContainerItems(character)
	local out = {}
	if character == nil then return out end
	local seen = {}
	for _, field in ipairs({ "SelectedItem", "SelectedSecondaryItem" }) do
		local ok, item = pcall(function() return character[field] end)
		if ok and item ~= nil and not seen[item] then
			seen[item] = true
			walk(out, item.OwnInventory, 0)
		end
	end
	return out
end

local function contained(item)
	if item == nil or item.OwnInventory == nil then return nil end
	return item.OwnInventory.GetItemAt(0)
end
U.Contained = contained

local function hasCharge(item)
	local battery = contained(item)
	return battery ~= nil and battery.Condition > 0
end

local readiness = {
	aed = hasCharge,
	healthscanner = hasCharge,
	defibrillator = hasCharge,
	bvm = function(item) return contained(item) ~= nil end,
	antisepticspray = function(item)
		local c = contained(item)
		return c ~= nil and U.Id(c) == "antiseptic"
	end,
	gelipack = function(item) return item.Condition > 25 end,
	antibloodloss2 = function(item) return item.Condition > 0 end,
	emptybloodpack = function(item) return item.Condition > 0 end,
}

local function scalpelMode(mode)
	return function(item) return item.HasTag("multiscalpel_" .. mode) end
end
local VARIANTS = {
	multiscalpel = {
		incision = scalpelMode("incision"), liver = scalpelMode("liver"), kidneys = scalpelMode("kidneys"),
		lungs = scalpelMode("lungs"), heart = scalpelMode("heart"), brain = scalpelMode("brain"),
	},
	antisepticspray = {
		saline = function(item)
			local c = contained(item)
			return c ~= nil and U.Id(c) == "antibloodloss1"
		end,
	},
}

local variantNames = {}
for id, list in pairs(VARIANTS) do
	local names = {}
	for name in pairs(list) do table.insert(names, name) end
	table.sort(names)
	variantNames[id] = names
end
function U.VariantNames(id)
	return variantNames[id] or {}
end

function U.ItemReady(item, variant)
	local id = U.Id(item)
	if variant ~= nil then
		local check = VARIANTS[id] and VARIANTS[id][variant]
		if check == nil then return false end
		local ok, ready = pcall(check, item)
		return ok and ready == true
	end
	if string.sub(id, 1, 9) == "bloodpack" then return item.Condition > 0 end
	local check = readiness[id]
	if check == nil then return true end
	local ok, ready = pcall(check, item)
	return ok and ready == true
end

function U.NTConfig(key, default)
	local ok, value = pcall(function() return NTConfig.Get(key, default) end)
	if ok and value ~= nil then return value end
	return default
end

local LT = LimbType
U.FRACTURE = {
	[LT.RightArm] = "ra_fracture", [LT.LeftArm] = "la_fracture",
	[LT.RightLeg] = "rl_fracture", [LT.LeftLeg] = "ll_fracture",
}
U.DISLOCATION = {
	[LT.RightLeg] = "dislocation1", [LT.LeftLeg] = "dislocation2",
	[LT.RightArm] = "dislocation3", [LT.LeftArm] = "dislocation4",
}
U.ARTERIAL = {
	[LT.RightArm] = "ra_arterialcut", [LT.LeftArm] = "la_arterialcut",
	[LT.RightLeg] = "rl_arterialcut", [LT.LeftLeg] = "ll_arterialcut",
	[LT.Torso] = "t_arterialcut", [LT.Head] = "h_arterialcut",
}
U.T_AMPUTATION = {
	[LT.RightArm] = "tra_amputation", [LT.LeftArm] = "tla_amputation",
	[LT.RightLeg] = "trl_amputation", [LT.LeftLeg] = "tll_amputation",
}
U.S_AMPUTATION = {
	[LT.RightArm] = "sra_amputation", [LT.LeftArm] = "sla_amputation",
	[LT.RightLeg] = "srl_amputation", [LT.LeftLeg] = "sll_amputation",
}
U.LIMB_ITEM = {
	[LT.RightArm] = "rarm", [LT.LeftArm] = "larm", [LT.RightLeg] = "rleg", [LT.LeftLeg] = "lleg",
}
U.EXTREMITIES = { LT.LeftArm, LT.RightArm, LT.LeftLeg, LT.RightLeg }

function U.Context(patient, me)
	local health = patient.CharacterHealth
	local anim = patient.AnimController
	local cache = {}
	local c = { patient = patient, me = me }

	function c.a(id)
		local v = cache[id]
		if v == nil then
			local aff = health.GetAffliction(id)
			v = aff ~= nil and aff.Strength or 0
			cache[id] = v
		end
		return v
	end

	function c.la(limbtype, id)
		local limb = anim.GetLimb(limbtype)
		if limb == nil then return 0 end
		local aff = health.GetAffliction(id, limb)
		return aff ~= nil and aff.Strength or 0
	end

	local function level(id)
		if me == nil then return 0 end
		local ok, v = pcall(function() return me.GetSkillLevel(Identifier(id)) end)
		if ok and v ~= nil then return v end
		return 0
	end
	c.skill = level("medical")
	c.surgery = c.skill
	if NTSP ~= nil and U.NTConfig("NTSP_enableSurgerySkill", false) then
		c.surgery = math.max(5, level("surgery"), c.skill / 4)
	end
	c.bloodtype = U.KnownBloodType(patient)
	return c
end

function U.CanOperate(c)
	return c.a("analgesia") >= 1 or c.a("sym_unconsciousness") >= 0.1
end

function U.Amputated(c, lt)
	local t, s = U.T_AMPUTATION[lt], U.S_AMPUTATION[lt]
	return (t ~= nil and c.a(t) >= 0.1) or (s ~= nil and c.a(s) >= 0.1)
end

function U.Chance(c, required, surgery)
	local skill = surgery and c.surgery or c.skill
	local p
	if U.NTConfig("NT_vanillaSkillCheck", false) then
		p = (100 - (required - skill)) / 100
	else
		p = skill / required
	end
	p = math.max(0, math.min(1, p))
	return math.floor(p * 100 + 0.5)
end

function U.Risky(c, required, surgery)
	return U.Chance(c, required, surgery) < 100
end


U.BloodTypes = { "ominus", "oplus", "aminus", "aplus", "bminus", "bplus", "abminus", "abplus" }

local bloodLabels = {
	ominus = "O-", oplus = "O+", aminus = "A-", aplus = "A+",
	bminus = "B-", bplus = "B+", abminus = "AB-", abplus = "AB+",
}
function U.BloodLabel(bt) return bloodLabels[bt] or "?" end

function U.CardBloodType(item)
	if item == nil then return nil end
	local id = U.Id(item)
	if string.sub(id, -4) ~= "card" then return nil end
	local bt = string.sub(id, 1, -5)
	if bloodLabels[bt] ~= nil then return bt end
	return nil
end

function U.PackItemId(bt)
	if bt == "ominus" then return "antibloodloss2" end
	return "bloodpack" .. bt
end

function U.Compatible(pack, target)
	local function has(t, s) return string.find(t, s, 1, true) ~= nil end
	return (has(target, "plus") or not has(pack, "plus"))
		and (has(target, "a") or not has(pack, "a"))
		and (has(target, "b") or not has(pack, "b"))
end

function U.PacksFor(bt)
	if bt == nil then return { "antibloodloss2" } end
	local list = { U.PackItemId(bt) }
	for _, pack in ipairs(U.BloodTypes) do
		if pack ~= bt and pack ~= "ominus" and U.Compatible(pack, bt) then table.insert(list, U.PackItemId(pack)) end
	end
	if bt ~= "ominus" then table.insert(list, "antibloodloss2") end
	return list
end

function U.PatientIdCard(patient)
	if patient == nil or patient.Inventory == nil then return nil end
	local card = patient.Inventory.GetItemAt(0)
	if card == nil or card.OwnInventory == nil then return nil end
	return card
end

function U.ReadBloodType(patient)
	if patient == nil or patient.CharacterHealth == nil then return nil end
	for _, bt in ipairs(U.BloodTypes) do
		local ok, aff = pcall(function() return patient.CharacterHealth.GetAffliction(bt) end)
		if ok and aff ~= nil and aff.Strength > 0 then return bt end
	end
	return nil
end

U.ScannedBloodTypes = {}
U.ScannedByName = {}

local function patientName(patient)
	local ok, name = pcall(function() return U.Str(patient.Name) end)
	if ok and name ~= "" then return name end
	return nil
end

function U.RememberBloodType(patient, bt)
	if patient == nil or bt == nil then return end
	U.ScannedBloodTypes[patient.ID] = bt
	local name = patientName(patient)
	if name ~= nil then U.ScannedByName[name] = bt end
end

function U.KnownBloodType(patient)
	if patient == nil then return nil end
	local bt = U.CardBloodType(contained(U.PatientIdCard(patient)))
	if bt ~= nil then return bt end
	bt = U.ScannedBloodTypes[patient.ID]
	if bt == nil then
		local name = patientName(patient)
		bt = name ~= nil and U.ScannedByName[name] or nil
	end
	if bt == nil then return nil end
	local actual = U.ReadBloodType(patient)
	if actual ~= nil and actual ~= bt then return nil end
	return bt
end
