
local UI = {}
NTMA.UI = UI
local L = NTMA.L
local U = NTMA.Util
local R = NTMA.Rules
local S = NTMA.Surgery
local DC = NTMA.DonorCard

local PANEL_SIZE = Vector2(0.36, 0.42)
local TAB_WIDTH = 0.16
local TAB_HEIGHT = 0.14
local PANEL_OFFSET = Point(0, 60)
local MAX_ROWS = 20
local UPDATE_INTERVAL = 0.35

local PRIO_COLORS = {
	Color(235, 64, 52),
	Color(255, 150, 40),
	Color(235, 210, 70),
	Color(110, 170, 255),
}
local DIM = Color(150, 150, 150)
local STEP_PRIO = 2

local function now()
	local ok, t = pcall(function() return Timer.GetTime() end)
	if ok and t ~= nil then return t end
	return Timer.Time
end
local OK_GREEN = Color(120, 220, 120)

UI.Enabled = true
UI.Active = false
UI.Highlight = {}
UI.LastRecs = {}
UI.Mode = nil
UI.PickEntry = nil

pcall(function() LuaUserData.RegisterType("Barotrauma.VisualSlot") end)
pcall(function() LuaUserData.RegisterType("Barotrauma.CharacterHealth") end)

local HealthStatic = nil
pcall(function() HealthStatic = LuaUserData.CreateStatic("Barotrauma.CharacterHealth") end)
local GUIStatic = nil
pcall(function() GUIStatic = LuaUserData.CreateStatic("Barotrauma.GUI") end)
if GUIStatic == nil then GUIStatic = GUI end

local function style(name)
	local ok, value = pcall(function() return GUI.GUIStyle[name] end)
	if ok then return value end
	return nil
end

local function openHealthWindow()
	local ok, window = pcall(function() return (HealthStatic or CharacterHealth).OpenHealthWindow end)
	if ok then return window end
	return nil
end


local frame = GUI.Frame(GUI.RectTransform(Vector2(1, 1)), nil)
frame.CanBeFocused = false

local panel = GUI.Frame(GUI.RectTransform(PANEL_SIZE, frame.RectTransform, GUI.Anchor.TopCenter), nil)
panel.RectTransform.AbsoluteOffset = PANEL_OFFSET
panel.CanBeFocused = false
panel.Visible = false
UI.Panel = panel

local panelRow = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 1), panel.RectTransform), true)
panelRow.CanBeFocused = false
local tabColumn = GUI.LayoutGroup(GUI.RectTransform(Vector2(TAB_WIDTH, 1), panelRow.RectTransform), false)
tabColumn.RelativeSpacing = 0.01
tabColumn.CanBeFocused = false
local content = GUI.Frame(GUI.RectTransform(Vector2(1 - TAB_WIDTH, 1), panelRow.RectTransform), "GUIFrame")
UI.Content = content

local layout = GUI.LayoutGroup(GUI.RectTransform(Vector2(0.94, 0.92), content.RectTransform, GUI.Anchor.Center), false)
layout.RelativeSpacing = 0.015

local title = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.09), layout.RectTransform), L("title"), nil,
	style("SubHeadingFont"), GUI.Alignment.CenterLeft)
title.CanBeFocused = false

local bloodRow = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.1), layout.RectTransform), true)
bloodRow.RelativeSpacing = 0.02
local bloodText = GUI.TextBlock(GUI.RectTransform(Vector2(0.34, 1), bloodRow.RectTransform), "", nil, nil,
	GUI.Alignment.CenterLeft)
bloodText.CanBeFocused = false
local donorButton = GUI.Button(GUI.RectTransform(Vector2(0.38, 1), bloodRow.RectTransform), L("btn_donor"),
	GUI.Alignment.Center, "GUIButtonSmall")
local opsButton = GUI.Button(GUI.RectTransform(Vector2(0.24, 1), bloodRow.RectTransform), L("btn_ops"),
	GUI.Alignment.Center, "GUIButtonSmall")

local statusText = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.09), layout.RectTransform), "", Color(200, 200, 200),
	style("SmallFont"), GUI.Alignment.CenterLeft, true)
statusText.CanBeFocused = false

local list = GUI.ListBox(GUI.RectTransform(Vector2(1, 0.68), layout.RectTransform))


UI.Tabs = {}
UI.Tab = "hints"

function UI.CurrentTab()
	for _, tab in ipairs(UI.Tabs) do
		if tab.id == UI.Tab then return tab end
	end
	return UI.Tabs[1]
end

function UI.SelectTab(id)
	UI.Tab = id
	for _, tab in ipairs(UI.Tabs) do
		local open = tab.id == id
		tab.layout.Visible = open
		pcall(function() tab.button.Selected = open end)
	end
	local tab = UI.CurrentTab()
	if tab.onSelect ~= nil then tab.onSelect() end
end

function UI.AddTab(tab)
	local button = GUI.Button(GUI.RectTransform(Vector2(1, TAB_HEIGHT), tabColumn.RectTransform), L(tab.title),
		GUI.Alignment.Center, "GUIButtonSmallFreeScale")
	button.OnClicked = function()
		UI.SelectTab(tab.id)
		return true
	end
	tab.button = button
	table.insert(UI.Tabs, tab)
	tab.layout.Visible = tab.id == UI.Tab
	pcall(function() button.Selected = tab.id == UI.Tab end)
	return tab
end

UI.AddTab({ id = "hints", title = "tab_hints", layout = layout, list = list })


UI.Draggables = {}
local drag = nil

local function inside(rect, pos)
	return rect ~= nil and pos.X >= rect.X and pos.X < rect.X + rect.Width
		and pos.Y >= rect.Y and pos.Y < rect.Y + rect.Height
end
UI.Inside = inside

function UI.Draggable(opts)
	local d = opts
	local function default()
		if type(d.default) == "function" then return d.default() end
		return d.default
	end

	function d.setOffset(x, y)
		local ok, w, h = pcall(function() return GameMain.GraphicsWidth, GameMain.GraphicsHeight end)
		local rect = d.panel.Rect
		if ok and w ~= nil and rect ~= nil then
			local maxX = math.max(0, math.floor((w - rect.Width) / 2))
			x = math.max(-maxX, math.min(maxX, x))
			y = math.max(0, math.min(math.max(0, h - rect.Height), y))
		end
		d.panel.RectTransform.AbsoluteOffset = Point(x, y)
	end

	function d.save()
		local off = d.panel.RectTransform.AbsoluteOffset
		pcall(function() File.Write(d.file, off.X .. " " .. off.Y) end)
	end

	function d.reset()
		d.panel.RectTransform.AbsoluteOffset = default()
		d.save()
	end

	d.panel.RectTransform.AbsoluteOffset = default()
	local ok, text = pcall(function()
		if File.Exists(d.file) then return File.Read(d.file) end
	end)
	local x, y = nil, nil
	if ok and text ~= nil then x, y = string.match(text, "(-?%d+)%s+(-?%d+)") end
	if x ~= nil then d.panel.RectTransform.AbsoluteOffset = Point(tonumber(x), tonumber(y)) end

	table.insert(UI.Draggables, d)
	return d
end

function UI.UpdateDrag()
	local anyVisible = false
	for _, d in ipairs(UI.Draggables) do
		if d.panel.Visible then anyVisible = true end
	end
	if not anyVisible then
		drag = nil
		return
	end
	local mouse = PlayerInput.MousePosition
	if drag ~= nil then
		if not drag.d.panel.Visible then
			drag = nil
		elseif PlayerInput.PrimaryMouseButtonHeld() then
			drag.d.setOffset(drag.offX + math.floor(mouse.X - drag.mouseX), drag.offY + math.floor(mouse.Y - drag.mouseY))
		else
			drag.d.save()
			drag = nil
		end
		return
	end
	if not PlayerInput.PrimaryMouseButtonDown() then return end
	for _, d in ipairs(UI.Draggables) do
		if d.panel.Visible and d.header(mouse) then
			local off = d.panel.RectTransform.AbsoluteOffset
			drag = { d = d, mouseX = mouse.X, mouseY = mouse.Y, offX = off.X, offY = off.Y }
			return
		end
	end
end

UI.Draggable({
	panel = panel,
	file = (NTMA.Path or ".") .. "/panel_pos.txt",
	default = PANEL_OFFSET,
	header = function(mouse)
		local tab = UI.CurrentTab()
		if not inside(content.Rect, mouse) or mouse.Y >= tab.list.Rect.Y then return false end
		if tab.id ~= "hints" then return true end
		if donorButton.Visible and inside(donorButton.Rect, mouse) then return false end
		return not (opsButton.Visible and inside(opsButton.Rect, mouse))
	end,
})

function UI.ResetPosition()
	for _, d in ipairs(UI.Draggables) do d.reset() end
end

local currentPatient = nil
local lastSignature = ""
donorButton.OnClicked = function()
	DC.Run(currentPatient)
	return true
end


function UI.OpenPicker()
	UI.Mode, UI.PickEntry = "pick", nil
	lastSignature = ""
end

function UI.ClosePicker()
	UI.Mode, UI.PickEntry = nil, nil
	lastSignature = ""
end

function UI.StartOperation(patient, opId, lt)
	S.Start(patient, opId, lt)
	UI.ClosePicker()
end

function UI.CloseOperation()
	S.Stop()
	UI.ClosePicker()
end

opsButton.OnClicked = function()
	if UI.Mode ~= nil then UI.ClosePicker() else UI.OpenPicker() end
	return true
end


local function inventoryIndex(me)
	local byId = {}
	local function tally(key, ready, carried)
		local entry = byId[key]
		if entry == nil then
			entry = { ready = 0, total = 0, carried = 0 }
			byId[key] = entry
		end
		entry.total = entry.total + 1
		if ready then
			entry.ready = entry.ready + 1
			if carried then entry.carried = entry.carried + 1 end
		end
	end
	local function count(items, carried)
		for _, item in ipairs(items) do
			local id = U.Id(item)
			tally(id, U.ItemReady(item), carried)
			for _, variant in ipairs(U.VariantNames(id)) do
				tally(id .. ":" .. variant, U.ItemReady(item, variant), carried)
			end
		end
	end
	count(U.CarriedItems(me), true)
	count(U.OpenContainerItems(me), false)
	return byId
end

local function matchingIds(byId, pattern)
	local ids = {}
	for id, entry in pairs(byId) do
		if U.Matches(id, pattern) then table.insert(ids, { id = id, entry = entry }) end
	end
	return ids
end

local function annotate(rec, byId)
	rec.readyIds = {}
	rec.pick = nil
	rec.inCabinet = false
	if #rec.items == 0 then
		rec.state = "none"
		return
	end
	local notReady = nil
	for _, pattern in ipairs(rec.items) do
		for _, m in ipairs(matchingIds(byId, pattern)) do
			if m.entry.ready > 0 then
				table.insert(rec.readyIds, m.id)
			elseif notReady == nil then
				notReady = m.id
			end
		end
	end
	if #rec.readyIds > 0 then
		rec.state, rec.pick = "ready", rec.readyIds[1]
		rec.inCabinet = byId[rec.pick].carried == 0
	elseif notReady ~= nil then
		rec.state, rec.pick = "notready", notReady
	else
		local first = rec.items[1]
		rec.state = "missing"
		rec.pick = string.sub(first, -1) == "*" and string.sub(first, 1, -2) or first
	end
end

local function describeItems(rec)
	if #rec.items == 0 then return nil end
	if rec.chain then
		local names = {}
		for _, id in ipairs(rec.items) do table.insert(names, U.ItemName(id)) end
		return table.concat(names, " → ")
	end
	local text = U.ItemName(rec.pick)
	if rec.state == "missing" then
		if #rec.items > 1 then
			local others = {}
			for i = 2, math.min(#rec.items, 3) do
				local id = rec.items[i]
				if string.sub(id, -1) ~= "*" then table.insert(others, U.ItemName(id)) end
			end
			if #others > 0 then text = text .. " / " .. table.concat(others, " / ") end
		end
		text = text .. " (" .. L("missing") .. ")"
	elseif rec.state == "notready" then
		text = text .. " (" .. L("not_ready") .. ")"
	elseif rec.inCabinet then
		text = text .. " (" .. L("in_cabinet") .. ")"
	end
	return text
end

local function buildHighlight(recs)
	local map = {}
	local primaryDone = false
	for _, rec in ipairs(recs) do
		if rec.state == "ready" then
			local color = PRIO_COLORS[rec.prio] or DIM
			local ids = rec.chain and rec.readyIds or { rec.pick }
			for _, id in ipairs(ids) do
				local existing = map[id]
				if existing == nil or existing.prio > rec.prio then
					map[id] = { color = color, prio = rec.prio, primary = false }
				end
			end
			if not primaryDone then
				map[ids[1]].primary = true
				primaryDone = true
			end
		end
	end
	return map
end


local function iconImage(slot, icon)
	local ok, img = pcall(GUI.Image, slot, icon)
	if not ok or img == nil then return nil end
	img.CanBeFocused = false
	pcall(function()
		local src, r = icon.SourceRect, img.Rect
		img.Scale = math.min(r.Width / src.Width, r.Height / src.Height)
	end)
	return img
end

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

local function buttonRow(text, onClick, color)
	local button = GUI.Button(GUI.RectTransform(Vector2(1, 0.12), list.Content.RectTransform), text,
		GUI.Alignment.CenterLeft, "GUIButtonSmall")
	if color ~= nil then pcall(function() button.TextColor = color end) end
	button.OnClicked = function()
		onClick()
		return true
	end
	return button
end

local function headerRow(text, color, buttons)
	local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.12), list.Content.RectTransform), true)
	row.RelativeSpacing = 0.02
	row.CanBeFocused = false
	local width = 0.98 - 0.25 * #buttons
	local tb = GUI.TextBlock(GUI.RectTransform(Vector2(width, 1), row.RectTransform), text, color,
		style("SmallFont"), GUI.Alignment.CenterLeft, true)
	tb.CanBeFocused = false
	for _, b in ipairs(buttons) do
		local button = GUI.Button(GUI.RectTransform(Vector2(0.23, 1), row.RectTransform), b[1], GUI.Alignment.Center,
			"GUIButtonSmall")
		button.OnClicked = function()
			b[2]()
			return true
		end
	end
	pcall(fitRow, row, tb)
	return row
end

local function recRow(rec, opts)
	opts = opts or {}
	local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.17), list.Content.RectTransform), true)
	row.RelativeSpacing = 0.02
	row.CanBeFocused = false

	local slot = GUI.RectTransform(Vector2(0.12, 1), row.RectTransform)
	local icon = opts.items ~= false and rec.pick ~= nil and U.ItemIcon(rec.pick) or nil
	local img = icon ~= nil and iconImage(slot, icon) or nil
	if img ~= nil then
		if rec.state ~= "ready" or opts.dimIcon then img.Color = Color(255, 255, 255, 90) end
	else
		GUI.Frame(slot, nil).CanBeFocused = false
	end

	local line = (opts.prefix or "") .. rec.text
	if rec.limb ~= nil then line = line .. " · " .. U.LimbName(rec.limb) end
	if opts.suffix ~= nil then line = line .. opts.suffix end
	local items = opts.items ~= false and describeItems(rec) or nil
	if items ~= nil then line = line .. "\n→ " .. items end
	if rec.note ~= nil and opts.note ~= false then line = line .. "\n" .. rec.note end

	local color = opts.color or PRIO_COLORS[rec.prio] or DIM
	if opts.color == nil and (rec.state == "missing" or rec.state == "notready") then
		color = Color(color.R, color.G, color.B, 150)
	end
	local tb = GUI.TextBlock(GUI.RectTransform(Vector2(0.86, 1), row.RectTransform), line, color, style("SmallFont"),
		GUI.Alignment.CenterLeft, true)
	tb.CanBeFocused = false
	pcall(fitRow, row, tb)
end

local function finishList()
	pcall(function() list.RecalculateChildren() end)
	pcall(function() list.UpdateScrollBarSize() end)
end

local function hintRows(recs)
	if #recs == 0 then
		local tb = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.14), list.Content.RectTransform), L("no_hints"), OK_GREEN,
			nil, GUI.Alignment.CenterLeft, true)
		tb.CanBeFocused = false
		return
	end
	for i = 1, math.min(#recs, MAX_ROWS) do recRow(recs[i]) end
end

local function guideTitle(guide)
	if guide.op.anyLimb then return L("guide_title", L(guide.op.title)) end
	return L("guide_title", L(guide.op.title)) .. " · " .. U.LimbName(guide.limb)
end

local function guideRows(guide, stepRecs)
	headerRow(guideTitle(guide), OK_GREEN, {
		{ L("guide_change"), UI.OpenPicker },
		{ L("guide_close"), UI.CloseOperation },
	})
	if guide.note ~= nil then textRow(guide.note, DIM) end
	for i, rec in ipairs(stepRecs) do
		local row = guide.rows[i]
		if row.done then
			recRow(rec, { prefix = i .. ". ", suffix = " — " .. L("step_done"), color = OK_GREEN, items = false, note = false })
		elseif row.current then
			recRow(rec, { prefix = "→ " .. i .. ". " })
		else
			recRow(rec, { prefix = i .. ". ", color = DIM, note = false, dimIcon = true })
		end
	end
	if guide.finished then textRow(L("guide_done"), OK_GREEN) end
end

local function pickerRows(patient, me)
	if UI.Mode == "limb" and UI.PickEntry ~= nil then
		local entry = UI.PickEntry
		headerRow(L("ops_pick_limb", L(entry.op.title)), nil, { { L("ops_back"), UI.OpenPicker } })
		for _, lt in ipairs(entry.limbs) do
			local text = U.LimbName(lt)
			local color = nil
			if entry.needed[lt] then
				text = text .. " — " .. L("ops_recommended")
			elseif not entry.now[lt] then
				text = text .. " — " .. L("ops_not_needed")
				color = DIM
			end
			buttonRow(text, function() UI.StartOperation(patient, entry.op.id, lt) end, color)
		end
		return
	end
	headerRow(L("ops_title"), nil, { { L("ops_back"), UI.ClosePicker } })
	local all = S.All(patient, me)
	if #all == 0 then
		textRow(L("ops_none"), DIM)
		return
	end
	local section = nil
	for _, entry in ipairs(all) do
		local group = entry.state == "needed" and "needed" or "other"
		if group ~= section then
			section = group
			textRow(L(group == "needed" and "ops_needed_title" or "ops_other_title"), group == "needed" and OK_GREEN or DIM)
		end
		local text = L(entry.op.title)
		local color = nil
		local shown = {}
		for _, lt in ipairs(entry.limbs) do
			if (entry.state == "needed" and entry.needed[lt]) or (entry.state == "possible" and entry.now[lt]) then
				table.insert(shown, lt)
			end
		end
		if entry.state == "needed" then text = text .. " — " .. L("ops_recommended") end
		if #shown > 0 and #shown <= 2 and not entry.op.anyLimb then
			local names = {}
			for _, lt in ipairs(shown) do table.insert(names, U.LimbName(lt)) end
			text = text .. " · " .. table.concat(names, ", ")
		end
		if entry.state == "idle" then
			text = text .. " — " .. L(entry.op.ind or "ops_not_needed")
			color = DIM
		elseif entry.op.listInd and entry.op.ind ~= nil then
			text = text .. " — " .. L(entry.op.ind)
		end
		local direct = #entry.limbs == 1 and entry.limbs[1] or nil
		if direct == nil and #shown == 1 and entry.state ~= "idle" then direct = shown[1] end
		if direct ~= nil then
			buttonRow(text, function() UI.StartOperation(patient, entry.op.id, direct) end, color)
		else
			buttonRow(text, function()
				UI.Mode, UI.PickEntry = "limb", entry
				lastSignature = ""
			end, color)
		end
	end
end

local function recSignature(rec)
	return rec.key .. ":" .. rec.text .. ":" .. tostring(rec.state) .. ":" .. tostring(rec.pick) .. ":"
		.. tostring(rec.inCabinet) .. ":" .. tostring(rec.note)
end

local function signature(patient, recs, guide, stepRecs)
	local parts = { tostring(patient.ID), tostring(UI.Mode) }
	if UI.Mode ~= nil then
		local entry = UI.PickEntry
		table.insert(parts, entry ~= nil and entry.op.id or "")
		for _, e in ipairs(S.All(patient, Character.Controlled)) do
			local now, needed = {}, {}
			for _, lt in ipairs(e.limbs) do
				if e.now[lt] then table.insert(now, tostring(lt)) end
				if e.needed[lt] then table.insert(needed, tostring(lt)) end
			end
			table.insert(parts, e.op.id .. ":" .. e.state .. ":" .. table.concat(now, ",") .. ":" .. table.concat(needed, ","))
		end
		return table.concat(parts, "|")
	end
	if guide ~= nil then
		table.insert(parts, guide.op.id .. ":" .. tostring(guide.limb) .. ":" .. tostring(guide.finished))
		for i, rec in ipairs(stepRecs) do
			local row = guide.rows[i]
			table.insert(parts, tostring(row.done) .. tostring(row.current) .. recSignature(rec))
		end
	end
	for i = 1, math.min(#recs, MAX_ROWS) do table.insert(parts, recSignature(recs[i])) end
	return table.concat(parts, "|")
end

local function stepRecords(guide, byId)
	local out = {}
	for i, row in ipairs(guide.rows) do
		local rec = {
			prio = STEP_PRIO, key = "step" .. i, text = L(row.step.text), items = row.items or {},
			limb = row.limb, note = row.note,
		}
		annotate(rec, byId)
		out[i] = rec
	end
	return out
end

function UI.Update()
	local me = Character.Controlled
	local window = UI.Enabled and openHealthWindow() or nil
	local patient = window ~= nil and window.Character or nil
	UI.Patient = patient

	if me == nil or patient == nil then
		UI.Active = false
		UI.Highlight = {}
		UI.LastRecs = {}
		panel.Visible = false
		return
	end

	if currentPatient ~= patient then
		currentPatient = patient
		lastSignature = ""
		UI.Mode, UI.PickEntry = nil, nil
		if DC.PatientId ~= patient.ID and not DC.Busy then DC.Status = "" end
	end
	if patient ~= me and NTMA.Patients ~= nil then NTMA.Patients.Note(patient) end

	local byId = inventoryIndex(me)
	local guide = S.Guide(patient, me)
	local stepRecs = guide ~= nil and stepRecords(guide, byId) or {}

	local recs = {}
	for _, rec in ipairs(R.Analyze(patient, me)) do
		local covered = guide ~= nil and rec.opLimb == guide.limb and rec.op == guide.op.id
		if not covered then
			annotate(rec, byId)
			table.insert(recs, rec)
		end
	end

	local highlightRecs = {}
	if guide ~= nil and guide.current ~= nil then
		for i, row in ipairs(guide.rows) do
			if row.current then table.insert(highlightRecs, stepRecs[i]) end
		end
	end
	for _, rec in ipairs(recs) do table.insert(highlightRecs, rec) end
	UI.Highlight = buildHighlight(highlightRecs)
	UI.LastRecs = highlightRecs
	UI.Active = true
	panel.Visible = true

	local name = patient == me and L("patient_self") or U.Str(patient.Name)
	title.Text = L("title") .. ": " .. name

	local bt = U.KnownBloodType(patient)
	bloodText.Text = L("bt_label", bt ~= nil and U.BloodLabel(bt) or L("bt_unknown"))
	donorButton.Visible = bt == nil and not patient.IsDead
	donorButton.Enabled = not DC.Busy
	opsButton.Visible = not patient.IsDead
	statusText.Text = DC.Status or ""

	local sig = signature(patient, recs, guide, stepRecs)
	if sig ~= lastSignature then
		lastSignature = sig
		list.Content.ClearChildren()
		if UI.Mode ~= nil then
			pickerRows(patient, me)
		else
			if guide ~= nil then
				guideRows(guide, stepRecs)
				if #recs > 0 then textRow(L("rest_title"), DIM) end
				for i = 1, math.min(#recs, MAX_ROWS) do recRow(recs[i]) end
			else
				hintRows(recs)
			end
		end
		finishList()
	end
end


local nextUpdate = 0
local dragFailed = false

Hook.Add("think", "NTMA.think", function()
	if not dragFailed then
		local ok, err = pcall(UI.UpdateDrag)
		if not ok then
			dragFailed = true
			print("[NTMA] panel dragging disabled: " .. tostring(err))
		end
	end
	local t = now()
	if t < nextUpdate then return end
	nextUpdate = t + UPDATE_INTERVAL
	local ok, err = pcall(UI.Update)
	if not ok then
		UI.Active = false
		panel.Visible = false
		print("[NTMA] update failed: " .. tostring(err))
		pcall(function() list.Content.ClearChildren() end)
		lastSignature = ""
		nextUpdate = t + 5
	end
	for _, tab in ipairs(UI.Tabs) do
		if tab.update ~= nil and t >= (tab.retryAt or 0) then
			ok, err = pcall(tab.update)
			if not ok then
				print("[NTMA] " .. tab.id .. " tab update failed: " .. tostring(err))
				if tab.fail ~= nil then pcall(tab.fail) end
				tab.retryAt = t + 5
			end
		end
	end
end)

Hook.Patch("Barotrauma.GameScreen", "AddToGUIUpdateList", function()
	frame.AddToGUIUpdateList()
end, Hook.HookMethodType.After)

local drawFailed = false
local function drawHighlight(ptable)
	local item = ptable["item"]
	if item == nil then return end
	local id = U.Id(item)
	local hl = UI.Highlight[id]
	if hl ~= nil and not U.ItemReady(item) then hl = nil end
	for _, variant in ipairs(U.VariantNames(id)) do
		local vh = UI.Highlight[id .. ":" .. variant]
		if vh ~= nil and U.ItemReady(item, variant) and (hl == nil or vh.primary or vh.prio < hl.prio) then hl = vh end
	end
	if hl == nil then return end

	local slot = ptable["slot"]
	local rect = slot.Rect
	local offset = slot.DrawOffset
	local color = hl.color
	local pad, thickness = 1, 2
	if hl.primary then
		pad, thickness = 3, 4
		local pulse = 150 + math.floor(105 * math.abs(math.sin(now() * 4)))
		color = Color(color.R, color.G, color.B, pulse)
	end
	GUIStatic.DrawRectangle(ptable["spriteBatch"],
		Vector2(rect.X + offset.X - pad, rect.Y + offset.Y - pad),
		Vector2(rect.Width + pad * 2, rect.Height + pad * 2),
		color, false, 0, thickness)
end

Hook.Patch("Barotrauma.Inventory", "DrawSlot", function(instance, ptable)
	if not UI.Active or drawFailed then return end
	local ok, err = pcall(drawHighlight, ptable)
	if not ok then
		drawFailed = true
		print("[NTMA] slot highlight disabled: " .. tostring(err))
	end
end, Hook.HookMethodType.After)

pcall(function()
	Game.AddCommand("ntma", "ntma: toggle the NT Medic Assistant panel; ntma reset: move it back to the top", function(args)
		if args ~= nil and args[1] == "reset" then
			UI.ResetPosition()
			print("[NTMA] panel position reset")
			return
		end
		UI.Enabled = not UI.Enabled
		print("[NTMA] panel " .. (UI.Enabled and "on" or "off"))
	end)
end)
