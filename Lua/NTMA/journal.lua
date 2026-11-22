
local J = {}
NTMA.Journal = J
local L = NTMA.L
local UI = NTMA.UI
local P = NTMA.Patients

local ROWS_INTERVAL = 1

local STATUS_COLORS = {
	critical = Color(235, 64, 52),
	surgery = Color(255, 150, 40),
	care = Color(235, 210, 70),
	stable = Color(120, 220, 120),
	dead = Color(150, 150, 150),
}
local DIM = Color(150, 150, 150)

local function style(name)
	local ok, value = pcall(function() return GUI.GUIStyle[name] end)
	if ok then return value end
	return nil
end


local layout = GUI.LayoutGroup(GUI.RectTransform(Vector2(0.94, 0.92), UI.Content.RectTransform, GUI.Anchor.Center), false)
layout.RelativeSpacing = 0.015
J.Layout = layout

local title = GUI.TextBlock(GUI.RectTransform(Vector2(1, 0.09), layout.RectTransform), L("tab_journal"), nil,
	style("SubHeadingFont"), GUI.Alignment.CenterLeft)
title.CanBeFocused = false

local list = GUI.ListBox(GUI.RectTransform(Vector2(1, 0.88), layout.RectTransform))
J.List = list


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

local function headerRow(text, buttons)
	local row = GUI.LayoutGroup(GUI.RectTransform(Vector2(1, 0.12), list.Content.RectTransform), true)
	row.RelativeSpacing = 0.02
	row.CanBeFocused = false
	local tb = GUI.TextBlock(GUI.RectTransform(Vector2(0.98 - 0.4 * #buttons, 1), row.RectTransform), text, DIM,
		style("SmallFont"), GUI.Alignment.CenterLeft, true)
	tb.CanBeFocused = false
	for _, b in ipairs(buttons) do
		local button = GUI.Button(GUI.RectTransform(Vector2(0.38, 1), row.RectTransform), b[1], GUI.Alignment.Center,
			"GUIButtonSmall")
		button.OnClicked = function()
			b[2]()
			return true
		end
	end
end

local function finishList()
	pcall(function() list.RecalculateChildren() end)
	pcall(function() list.UpdateScrollBarSize() end)
end


local function trendText(trends)
	local parts = {}
	for _, tr in ipairs(trends) do
		table.insert(parts, tr.text .. " " .. math.floor(tr.value + 0.5) .. " " .. tr.arrow)
	end
	return table.concat(parts, " · ")
end

local function patientLine(row)
	local line = row.entry.name .. " — " .. L("status_" .. row.status)
	if row.reason ~= nil then line = line .. ": " .. row.reason end
	if row.entry.character == UI.Patient then line = "» " .. line end
	local trends = trendText(row.trends)
	if trends ~= "" then line = line .. "\n" .. trends end
	return line
end

local queueRows = {}
local function queueSignature()
	local parts = {}
	for _, row in ipairs(queueRows) do table.insert(parts, row.status .. patientLine(row)) end
	return table.concat(parts, "|")
end

local function buildQueue()
	if #queueRows == 0 then
		textRow(L("queue_empty"), DIM)
		return
	end
	headerRow(L("queue_count", #queueRows), { { L("queue_clear"), function()
		P.Clear()
		queueRows = {}
		J.Refresh()
	end } })
	for _, row in ipairs(queueRows) do
		textRow(patientLine(row), STATUS_COLORS[row.status] or DIM)
	end
end

local function refreshQueue()
	queueRows = P.Rows(Character.Controlled)
end


local lastSignature = nil
local nextRows = 0

local function now()
	local ok, t = pcall(function() return Timer.GetTime() end)
	if ok and t ~= nil then return t end
	return Timer.Time
end

function J.Refresh()
	lastSignature = nil
	nextRows = 0
end

function J.Fail()
	pcall(function() list.Content.ClearChildren() end)
	J.Refresh()
end


function J.Update()
	P.Update()
	if not UI.Active or UI.Tab ~= "journal" then return end
	local t = now()
	if t >= nextRows then
		nextRows = t + ROWS_INTERVAL
		refreshQueue()
	end
	local sig = queueSignature()
	if sig == lastSignature then return end
	lastSignature = sig
	list.Content.ClearChildren()
	buildQueue()
	finishList()
end

UI.AddTab({ id = "journal", title = "tab_journal", layout = layout, list = list, onSelect = J.Refresh,
	update = J.Update, fail = J.Fail })
