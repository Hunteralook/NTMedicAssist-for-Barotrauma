
local St = {}
NTMA.Stock = St
local L = NTMA.L
local U = NTMA.Util
local UI = NTMA.UI

local SCAN_INTERVAL = 3
local MAX_PLACES = 3
local MAX_NEEDS = 8

local OK_GREEN = Color(120, 220, 120)
local DIM = Color(150, 150, 150)
local TEXT = Color(210, 210, 210)
local LOW = Color(235, 210, 70)
local NONE = Color(235, 64, 52)
local PRIO_COLORS = { Color(235, 64, 52), Color(255, 150, 40), Color(235, 210, 70), Color(110, 170, 255) }

St.Categories = {
	{ id = "blood", title = "stock_blood", items = { "antibloodloss2", "bloodpack*", "antibloodloss1", "ringerssolution",
		"emptybloodpack", "bloodcollector" } },
	{ id = "dressing", title = "stock_dressing", items = { "antibleeding1", "antibleeding2", "antibleeding3", "suture",
		"tourniquet", "gypsum", "gelipack", "ointment", "skinaid", "antiseptic" } },
	{ id = "drugs", title = "stock_drugs", items = { "antidama1", "antidama2", "opium", "adrenaline", "antibiotics",
		"propofol", "streptokinase", "mannitol", "thiamine", "antinarc", "antipsychosis", "antiparalysis", "pressuremeds",
		"nitroglycerin", "liquidoxygenite", "calyxanide", "stabilozine", "immunosuppressant", "deusizine" } },
	{ id = "surgery", title = "stock_surgery", items = { "advscalpel", "advhemostat", "advretractors", "surgicaldrill",
		"surgerysaw", "tweezers", "traumashears", "multiscalpel", "organscalpel_*", "needle", "drainage",
		"osteosynthesisimplants", "spinalimplant", "endovascballoon", "medstent" } },
	{ id = "devices", title = "stock_devices", items = { "healthscanner", "bloodanalyzer", "aed", "defibrillator", "bvm",
		"autocpr", "stasisbag", "antisepticspray", "analgesictank", "toxfilter", "dialyzer" } },
	{ id = "organs", title = "stock_organs", items = { "livertransplant*", "kidneytransplant*", "lungtransplant*",
		"hearttransplant*", "braintransplant", "rarm", "larm", "rleg", "lleg", "rarmp", "larmp", "rlegp", "llegp" } },
	{ id = "other", title = "stock_other", items = {} },
}

St.Important = {
	antibleeding1 = 5, suture = 5, tourniquet = 2, antibloodloss2 = 3, antibloodloss1 = 3, antidama1 = 3,
	adrenaline = 2, antibiotics = 2, propofol = 2, gypsum = 2, needle = 2,
}

local CONTAINER_TAGS = { "crate", "container", "mobilecontainer", "toolbox" }

local kindCache = {}
local function kindOf(item, id)
	local kind = kindCache[id]
	if kind ~= nil then return kind end
	kind = false
	if U.CardBloodType(item) == nil then
		for _, cat in ipairs(St.Categories) do
			for _, pattern in ipairs(cat.items) do
				if U.Matches(id, pattern) then
					kind = cat.id
					break
				end
			end
			if kind then break end
		end
		if not kind then
			local ok, category = pcall(function() return tostring(item.Prefab.Category) end)
			if ok and category ~= nil and category:find("Medical", 1, true) ~= nil then
				kind = "other"
				for _, tag in ipairs(CONTAINER_TAGS) do
					if item.HasTag(tag) then kind = false end
				end
			end
		end
	end
	kindCache[id] = kind
	return kind
end
St.KindOf = kindOf

local function isCharacter(entity)
	local ok, result = pcall(function() return LuaUserData.IsTargetType(entity, "Barotrauma.Character") end)
	return ok and result == true
end

local function rootOwner(item)
	local ok, owner = pcall(function() return item.GetRootInventoryOwner() end)
	if ok then return owner end
	return nil
end

local function hullName(entity)
	local ok, hull = pcall(function() return entity.CurrentHull end)
	if not ok or hull == nil then return L("stock_no_room") end
	local okName, name = pcall(function() return U.Str(hull.DisplayName) end)
	if okName and name ~= nil and name ~= "" then return name end
	local okRoom, room = pcall(function() return tostring(hull.RoomName) end)
	if okRoom and room ~= nil and room ~= "" then return (room:gsub("^[Rr]oom[Nn]ame%.", "")) end
	return L("stock_no_room")
end

St.HullName = hullName

local function scope(me)
	local ok, sub = pcall(function() return me.Submarine end)
	if ok and sub ~= nil then return sub end
	ok, sub = pcall(function() return Submarine.MainSub end)
	if ok then return sub end
	return nil
end
St.Scope = scope

function St.Locate(item, me, sub)
	local owner = rootOwner(item)
	if owner == nil then return nil end
	if owner == me then return "mine", nil end
	if owner ~= item and not isCharacter(owner) and (sub == nil or owner.Submarine == sub) then
		return hullName(owner), U.ItemName(U.Id(owner))
	end
	return nil
end

function St.NewEntry(id, kind)
	return { id = id, kind = kind, name = U.ItemName(id), total = 0, ready = 0, mine = 0, placeIndex = {}, places = {} }
end

function St.Tally(e, item, room, container)
	if container == nil then
		e.mine = e.mine + 1
		return
	end
	e.total = e.total + 1
	if U.ItemReady(item) then e.ready = e.ready + 1 end
	local key = room .. "\0" .. container
	local place = e.placeIndex[key]
	if place == nil then
		place = { room = room, container = container, count = 0 }
		e.placeIndex[key] = place
		table.insert(e.places, place)
	end
	place.count = place.count + 1
end

function St.FinishEntry(e)
	table.sort(e.places, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.room .. a.container < b.room .. b.container
	end)
	e.placeIndex = nil
end

function St.Scan(me)
	local sub = scope(me)
	local byId = {}
	local function entry(id, kind)
		local e = byId[id]
		if e == nil then
			e = St.NewEntry(id, kind)
			byId[id] = e
		end
		return e
	end
	for item in Item.ItemList do
		local id = U.Id(item)
		local kind = id ~= "" and kindOf(item, id) or false
		if kind then
			local room, container = St.Locate(item, me, sub)
			if room ~= nil then St.Tally(entry(id, kind), item, room, container) end
		end
	end
	for id, low in pairs(St.Important) do
		if byId[id] == nil then
			entry(id, kindOf({ Prefab = nil, HasTag = function() return false end }, id) or "other")
		end
		byId[id].low = low
	end
	for _, e in pairs(byId) do St.FinishEntry(e) end
	local subName = nil
	pcall(function() subName = U.Str(sub.Info.DisplayName) end)
	if subName == nil or subName == "" then pcall(function() subName = tostring(sub.Info.Name) end) end
	return { byId = byId, sub = subName }
end

function St.Grouped(scan)
	local out = {}
	for _, cat in ipairs(St.Categories) do
		local entries = {}
		for _, e in pairs(scan.byId) do
			if e.kind == cat.id and (e.total > 0 or e.mine > 0 or e.low ~= nil) then table.insert(entries, e) end
		end
		table.sort(entries, function(a, b) return a.name < b.name end)
		if #entries > 0 then table.insert(out, { cat = cat, entries = entries }) end
	end
	return out
end

function St.Needs(scan, recs)
	local out = {}
	local seen = {}
	for _, rec in ipairs(recs or {}) do
		if rec.state == "missing" and #rec.items > 0 and not seen[rec.key] then
			seen[rec.key] = true
			local found = nil
			for _, pattern in ipairs(rec.items) do
				local base = U.SplitId(pattern)
				local best = nil
				for id, e in pairs(scan.byId) do
					if e.ready > 0 and U.Matches(id, base) and (best == nil or e.ready > best.ready) then best = e end
				end
				if best ~= nil then
					found = best
					break
				end
			end
			table.insert(out, { rec = rec, entry = found, name = U.PatternName(U.SplitId(rec.items[1])) })
			if #out >= MAX_NEEDS then break end
		end
	end
	return out
end

local function placesText(e)
	local parts = {}
	for i = 1, math.min(#e.places, MAX_PLACES) do
		local p = e.places[i]
		table.insert(parts, p.room .. ": " .. p.container .. " ×" .. p.count)
	end
	if #e.places > MAX_PLACES then table.insert(parts, L("stock_more_places", #e.places - MAX_PLACES)) end
	return table.concat(parts, " · ")
end
St.PlacesText = placesText

function St.EntryLine(e)
	local line = e.name .. " ×" .. e.total
	if e.mine > 0 then line = line .. " · " .. L("stock_mine", e.mine) end
	if e.total > e.ready then line = line .. " · " .. L("stock_unready", e.total - e.ready) end
	if e.total == 0 then
		line = e.name .. " — " .. L("stock_none")
		if e.mine > 0 then line = line .. " · " .. L("stock_mine", e.mine) end
	elseif #e.places > 0 then
		line = line .. "\n" .. placesText(e)
	end
	return line
end

local function entryColor(e)
	if e.low ~= nil and e.ready + e.mine == 0 then return NONE end
	if e.low ~= nil and e.ready + e.mine < e.low then return LOW end
	return TEXT
end


local function style(name)
	local ok, value = pcall(function() return GUI.GUIStyle[name] end)
	if ok then return value end
	return nil
end

local layout = GUI.LayoutGroup(GUI.RectTransform(Vector2(0.94, 0.92), UI.Content.RectTransform, GUI.Anchor.Center), false)
layout.RelativeSpacing = 0.015
St.Layout = layout

local title = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.09), layout.RectTransform), L("tab_stock"), nil,
	style("SubHeadingFont"), GUI.Alignment.CenterLeft)
title.CanBeFocused = false

local list = GUI.ListBox(GUI.RectTransform(Vector2(1, 0.88), layout.RectTransform))
St.List = list

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

local function rows()
	local out = {}
	local function add(text, color) table.insert(out, { text = text, color = color }) end
	add(scan.sub ~= nil and L("stock_sub", scan.sub) or L("stock_sub_unknown"), DIM)

	local needs = St.Needs(scan, UI.LastRecs)
	if #needs > 0 then
		add(L("stock_needs_title"), OK_GREEN)
		for _, n in ipairs(needs) do
			local color = PRIO_COLORS[n.rec.prio] or TEXT
			if n.entry ~= nil then
				add(n.rec.text .. " → " .. n.entry.name .. " ×" .. n.entry.ready .. "\n" .. placesText(n.entry), color)
			else
				add(n.rec.text .. " → " .. n.name .. " — " .. L("stock_none"), color)
			end
		end
	end

	local groups = St.Grouped(scan)
	local any = false
	for _, g in ipairs(groups) do
		for _, e in ipairs(g.entries) do
			if e.total > 0 then any = true end
		end
	end
	if not any then add(L("stock_empty"), DIM) end
	for _, g in ipairs(groups) do
		add(L(g.cat.title), OK_GREEN)
		for _, e in ipairs(g.entries) do add(St.EntryLine(e), entryColor(e)) end
	end
	return out
end

function St.Refresh()
	lastSignature = nil
	nextScan = 0
end

function St.Fail()
	pcall(function() list.Content.ClearChildren() end)
	St.Refresh()
end

function St.Update()
	if not UI.Active or UI.Tab ~= "stock" then return end
	local t = now()
	if scan == nil or t >= nextScan then
		nextScan = t + SCAN_INTERVAL
		scan = St.Scan(Character.Controlled)
	end
	local out = rows()
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

UI.AddTab({ id = "stock", title = "tab_stock", layout = layout, list = list, onSelect = St.Refresh,
	update = St.Update, fail = St.Fail })
