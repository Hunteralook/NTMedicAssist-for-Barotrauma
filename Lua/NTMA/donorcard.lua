
local DC = {}
NTMA.DonorCard = DC
local L = NTMA.L
local U = NTMA.Util

DC.Status = ""
DC.Busy = false
DC.PatientId = nil

local function setStatus(text)
	DC.Status = text
end

local function finish(text)
	if text ~= nil then setStatus(text) end
	DC.Busy = false
end

local function isCartridge(item)
	if item == nil then return false end
	return U.Id(item) == "bloodcollector" or item.HasTag("donorCard")
end

local function ready(analyzer)
	return analyzer.Condition >= 50
end

local function pickAnalyzer(me)
	local best, bestScore = nil, -1
	for _, item in ipairs(U.CarriedItems(me)) do
		if U.Id(item) == "bloodanalyzer" then
			local score = 0
			if isCartridge(U.Contained(item)) then score = score + 2 end
			if ready(item) then score = score + 1 end
			if score > bestScore then best, bestScore = item, score end
		end
	end
	return best
end

local function findBlank(me, analyzer)
	local loose = nil
	for _, item in ipairs(U.CarriedItems(me)) do
		local parent = item.Container
		local parentId = parent ~= nil and U.Id(parent) or ""
		if parent ~= analyzer and parentId ~= "idcard" and parentId ~= "bloodanalyzer" then
			if U.Id(item) == "bloodcollector" then return item end
			if loose == nil and item.HasTag("donorCard") then loose = item end
		end
	end
	return loose
end

local function verify(patient, analyzer, cartridgeId)
	local bt = U.CardBloodType(U.Contained(U.PatientIdCard(patient)))
	if bt ~= nil then
		finish(L("dc_done_id", U.BloodLabel(bt)))
		return
	end
	local inside = U.Contained(analyzer)
	bt = U.CardBloodType(inside)
	if bt ~= nil and inside.ID ~= cartridgeId then
		U.RememberBloodType(patient, bt)
		finish(L("dc_done_analyzer", U.BloodLabel(bt)))
		return
	end
	finish(L("dc_failed"))
end

local function apply(patient, analyzer, me)
	local limb = patient.AnimController.GetLimb(LimbType.Torso) or patient.AnimController.MainLimb
	local text = L("dc_scanning")
	local idcard = U.PatientIdCard(patient)
	if idcard == nil then
		text = text .. " " .. L("dc_no_idcard")
	elseif U.Contained(idcard) ~= nil then
		text = text .. " " .. L("dc_idcard_full")
	end
	setStatus(text)
	local cartridge = U.Contained(analyzer)
	local cartridgeId = cartridge ~= nil and cartridge.ID or -1
	analyzer.ApplyTreatment(me, patient, limb)
	Timer.Wait(function()
		local ok, err = pcall(verify, patient, analyzer, cartridgeId)
		if not ok then finish(L("dc_failed")); print("[NTMA] " .. tostring(err)) end
	end, 2500)
end

local function waitUntilReady(patient, analyzer, me, attempt)
	if ready(analyzer) then
		Timer.Wait(function()
			local ok, err = pcall(apply, patient, analyzer, me)
			if not ok then finish(L("dc_failed")); print("[NTMA] " .. tostring(err)) end
		end, 600)
		return
	end
	if attempt >= 10 then
		finish(L("dc_cooldown"))
		return
	end
	setStatus(L("dc_cooldown"))
	Timer.Wait(function() waitUntilReady(patient, analyzer, me, attempt + 1) end, 1000)
end

local function loadCartridge(analyzer, me, onReady)
	local inside = U.Contained(analyzer)
	if isCartridge(inside) then
		onReady()
		return
	end

	if inside ~= nil then
		local name = U.ItemName(U.Id(inside))
		if not me.Inventory.TryPutItem(inside, me, { InvSlotType.Any }) then
			finish(L("dc_cant_clear", name))
			return
		end
		setStatus(L("dc_cleared", name))
	end

	local blank = findBlank(me, analyzer)
	if blank == nil then
		finish(L("dc_no_blank"))
		return
	end
	if not analyzer.OwnInventory.TryPutItem(blank, me) then
		finish(L("dc_no_blank"))
		return
	end
	setStatus(L("dc_inserted"))
	Timer.Wait(onReady, 500)
end

function DC.Run(patient)
	if DC.Busy then
		setStatus(L("dc_busy"))
		return
	end
	local me = Character.Controlled
	if me == nil or patient == nil then
		setStatus(L("dc_no_patient"))
		return
	end
	DC.PatientId = patient.ID

	local known = U.KnownBloodType(patient)
	if known ~= nil then
		setStatus(L("dc_known", U.BloodLabel(known)))
		return
	end

	local analyzer = pickAnalyzer(me)
	if analyzer == nil then
		setStatus(L("dc_no_analyzer"))
		return
	end

	DC.Busy = true
	local runId = {}
	DC.RunId = runId
	Timer.Wait(function()
		if DC.Busy and DC.RunId == runId then finish(L("dc_failed")) end
	end, 20000)

	local ok, err = pcall(loadCartridge, analyzer, me, function()
		waitUntilReady(patient, analyzer, me, 0)
	end)
	if not ok then
		finish(L("dc_failed"))
		print("[NTMA] " .. tostring(err))
	end
end

local SCANNERS = {
	healthscanner = function(item) return U.ItemReady(item) end,
	bloodanalyzer = function(item) return item.Condition >= 50 end,
}

function DC.OnTreatment(item, user, target)
	local me = Character.Controlled
	if me == nil or user ~= me or target == nil then return end
	local works = SCANNERS[U.Id(item)]
	if works == nil or not works(item) then return end
	local bt = U.ReadBloodType(target)
	if bt == nil or U.KnownBloodType(target) == bt then return end
	U.RememberBloodType(target, bt)
	if not DC.Busy then
		DC.PatientId = target.ID
		setStatus(L("dc_scanned", U.BloodLabel(bt)))
	end
end

pcall(function()
	Hook.Patch("Barotrauma.Item", "ApplyTreatment", function(instance, ptable)
		local ok, err = pcall(DC.OnTreatment, instance, ptable["user"], ptable["character"])
		if not ok then print("[NTMA] scan: " .. tostring(err)) end
	end, Hook.HookMethodType.Before)
end)
