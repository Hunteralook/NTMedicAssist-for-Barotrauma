
local T = {}
NTMA.GeneLab = T
local L = NTMA.L
local U = NTMA.Util
local G = NTMA.Genes
local St = NTMA.Stock
local UI = NTMA.UI

local SCAN_INTERVAL = 3
local MAX_PLAN = 6

local TERMINAL = "op_researchterminal"
local UNIDENTIFIED = "geneticmaterial_unresearched"
local STABILOZINE = "stabilozine"
local SUPPLIES = { "genesplicer", "advancedgenesplicer", UNIDENTIFIED, STABILOZINE }

local OK_GREEN = Color(120, 220, 120)
local DIM = Color(150, 150, 150)
local TEXT = Color(210, 210, 210)
local LOW = Color(235, 210, 70)
local BAD = Color(255, 150, 40)


local function betterFirst(a, b)
	if a.quality ~= b.quality then return a.quality > b.quality end
	if a.def.order ~= b.def.order then return a.def.order < b.def.order end
	return a.item.ID < b.item.ID
end

function T.Scan(me)
	local sub = St.Scope(me)
	local mySplicer = G.Splicer(me)
	local scan = { materials = {}, supplies = {}, terminal = nil }
	for _, id in ipairs(SUPPLIES) do scan.supplies[id] = St.NewEntry(id, "genes") end
	local terminalHere = false
	for item in Item.ItemList do
		local id = U.Id(item)
		if id == TERMINAL then
			local here = sub ~= nil and item.Submarine == sub
			if scan.terminal == nil or (here and not terminalHere) then
				scan.terminal = St.HullName(item)
				terminalHere = here
			end
		elseif G.Materials[id] ~= nil then
			local parent = item.Container
			if parent == nil or (G.Materials[U.Id(parent)] == nil and parent ~= mySplicer) then
				local room, container = St.Locate(item, me, sub)
				if room ~= nil then
					local m = G.ReadMaterial(item)
					m.room, m.container = room, container
					table.insert(scan.materials, m)
				end
			end
		elseif scan.supplies[id] ~= nil then
			local room, container = St.Locate(item, me, sub)
			if room ~= nil then St.Tally(scan.supplies[id], item, room, container) end
		end
	end
	for _, e in pairs(scan.supplies) do St.FinishEntry(e) end
	table.sort(scan.materials, betterFirst)
	return scan
end


local function patientRows(add, patient, me, c)
	local name = patient == me and L("patient_self") or U.Str(patient.Name)
	add(L("gene_patient", name), OK_GREEN)

	local splicer = G.Splicer(patient)
	local spliced = G.SplicedMaterials(splicer)
	if splicer ~= nil then
		if #spliced == 0 then
			add(L("gene_splicer_empty", U.ItemName(U.Id(splicer))), DIM)
		else
			for _, m in ipairs(spliced) do
				local line = L("gene_splicer", U.ItemName(U.Id(splicer)), G.MaterialText(m))
				if m.tainted then line = line .. " · " .. L("gene_tainted") end
				add(line, m.tainted and LOW or TEXT)
			end
		end
	end

	local buffs, debuffs = G.ActiveBuffs(c), G.ActiveDebuffs(c)
	for _, gene in ipairs(buffs) do
		add(gene.name .. " " .. math.floor(gene.strength) .. " — " .. gene.text, TEXT)
	end
	for _, gene in ipairs(debuffs) do
		add(L("gene_debuff", gene.name, math.floor(gene.strength)) .. " — " .. gene.text, BAD)
	end
	if splicer == nil and #buffs == 0 and #debuffs == 0 then
		add(L("gene_none"), DIM)
		add(L("gene_howto"), DIM)
	end
	if #debuffs > 0 then add(L("gene_debuff_note"), DIM) end
	if #spliced > 0 then add(L("gene_remove_note"), DIM) end
	for _, m in ipairs(spliced) do
		if not m.tainted and not patient.IsDead then
			add(L("gene_death_note"), DIM)
			break
		end
	end
end

local function materialRows(add, scan)
	add(L("gene_materials"), OK_GREEN)
	if #scan.materials == 0 then add(L("gene_no_materials"), DIM) end
	for _, m in ipairs(scan.materials) do
		local line = G.MaterialText(m)
		if m.tainted then line = line .. " · " .. L("gene_tainted") end
		line = line .. " — " .. G.MaterialEffect(m) .. "\n"
		if m.container == nil then
			line = line .. L("gene_on_you")
		else
			line = line .. m.room .. ": " .. m.container
		end
		add(line, m.tainted and LOW or TEXT)
	end
	local unidentified = scan.supplies[UNIDENTIFIED]
	for _, id in ipairs(SUPPLIES) do
		local e = scan.supplies[id]
		local shown = e.total > 0 or e.mine > 0
		if id == "genesplicer" then shown = true end
		if id == STABILOZINE then shown = unidentified.total + unidentified.mine > 0 end
		if shown then add(St.EntryLine(e), DIM) end
	end
end

local function riskColor(risk)
	if risk <= 0 then return OK_GREEN end
	if risk < 0.3 then return TEXT end
	if risk < 0.6 then return LOW end
	return BAD
end

local function planLine(step)
	local line = L(step.kind == "refine" and "gene_refine" or "gene_combine", G.MaterialText(step.a), G.MaterialText(step.b),
		math.floor(step.quality))
	if step.clears then
		line = line .. "; " .. L("gene_no_risk")
		if step.tainted then line = line .. ", " .. L("gene_clears") end
		return line
	end
	if step.risk >= 1 then return line .. "; " .. L("gene_will_taint") end
	line = line .. "; " .. L("gene_risk", math.floor(step.risk * 100 + 0.5))
	if step.tainted then line = line .. ", " .. L("gene_may_stay") end
	return line
end

local function planRows(add, scan, c)
	local unidentified = scan.supplies[UNIDENTIFIED]
	local toResearch = unidentified.total + unidentified.mine > 0
	local plan = G.Plan(scan.materials, G.MedicStats(c))
	if #plan == 0 and not toResearch then return end

	add(L("gene_terminal_title"), OK_GREEN)
	if scan.terminal ~= nil then
		add(L("gene_terminal", scan.terminal), DIM)
	else
		add(L("gene_no_terminal"), DIM)
	end
	if toResearch then add(L("gene_research"), TEXT) end

	local shown, hidden = { refine = 0, combine = 0 }, 0
	for _, step in ipairs(plan) do
		if shown[step.kind] < MAX_PLAN then
			shown[step.kind] = shown[step.kind] + 1
			add(planLine(step), riskColor(step.risk))
		else
			hidden = hidden + 1
		end
	end
	if hidden > 0 then add(L("gene_more", hidden), DIM) end
	if shown.refine > 0 then add(L("gene_refine_note"), DIM) end
end


local function style(name)
	local ok, value = pcall(function() return GUI.GUIStyle[name] end)
	if ok then return value end
	return nil
end

local layout = GUI.LayoutGroup(GUI.RectTransform(Vector2(0.94, 0.92), UI.Content.RectTransform, GUI.Anchor.Center), false)
layout.RelativeSpacing = 0.015
T.Layout = layout

local title = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.09), layout.RectTransform), L("tab_genes"), nil,
	style("SubHeadingFont"), GUI.Alignment.CenterLeft)
title.CanBeFocused = false

local list = GUI.ListBox(GUI.RectTransform(Vector2(1, 0.88), layout.RectTransform))
T.List = list

local function fitRow(row, tb)
	local pad = tb.Padding
	local height = math.ceil(tb.TextSize.Y + pad.Y + pad.W)
	if height > row.Rect.Height then row.RectTransform.MinSize = Point(0, height) end
end

local function textRow(text, color)
	local tb = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.12), list.Content.RectTransform), text, color,
		style("SmallFont"), GUI.Alignment.CenterLeft, true)
	tb.CanBeFocused = false
	pcall(fitRow, tb, tb)
	return tb
end


local scan = nil
local nextScan = 0
local lastSignature = nil

local function now()
	local ok, t = pcall(function() return Timer.GetTime() end)
	if ok and t ~= nil then return t end
	return Timer.Time
end

function T.Refresh()
	lastSignature = nil
	nextScan = 0
end

function T.Fail()
	pcall(function() list.Content.ClearChildren() end)
	T.Refresh()
end

function T.Update()
	if not UI.Active or UI.Tab ~= "genes" or UI.Patient == nil then return end
	local t = now()
	local me = Character.Controlled
	if scan == nil or t >= nextScan then
		nextScan = t + SCAN_INTERVAL
		scan = T.Scan(me)
	end
	local out = {}
	local function add(text, color) table.insert(out, { text = text, color = color }) end
	local c = U.Context(UI.Patient, me)
	patientRows(add, UI.Patient, me, c)
	materialRows(add, scan)
	planRows(add, scan, c)

	local parts = {}
	for _, r in ipairs(out) do table.insert(parts, r.text) end
	local sig = table.concat(parts, "|")
	if sig == lastSignature then return end
	lastSignature = sig
	list.Content.ClearChildren()
	for _, r in ipairs(out) do textRow(r.text, r.color) end
	pcall(function() list.RecalculateChildren() end)
	pcall(function() list.UpdateScrollBarSize() end)
end

UI.AddTab({ id = "genes", title = "tab_genes", layout = layout, list = list, onSelect = T.Refresh,
	update = T.Update, fail = T.Fail })
