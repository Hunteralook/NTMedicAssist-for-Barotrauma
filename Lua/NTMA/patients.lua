
local P = {}
NTMA.Patients = P
local L = NTMA.L
local U = NTMA.Util
local R = NTMA.Rules

local MAX_PATIENTS = 12
local SAMPLE_INTERVAL = 1
local TREND_WINDOW = 10
local HISTORY = 30
local TREND_MIN = 1
local MAX_TRENDS = 4

P.List = {}

local function limbSum(id)
	return function(c)
		local sum = 0
		for _, lt in ipairs(R.Limbs) do sum = sum + c.la(lt, id) end
		return sum
	end
end
local function organs(c)
	local v = 0
	for _, id in ipairs({ "heartdamage", "lungdamage", "liverdamage", "kidneydamage", "organdamage" }) do
		v = math.max(v, c.a(id))
	end
	return v
end
P.Metrics = {
	{ key = "bloodloss", text = "bloodloss", show = 10 },
	{ key = "bleeding", text = "bleeding", show = 5, value = limbSum("bleeding") },
	{ key = "internalbleeding", text = "internal_bleeding", show = 5 },
	{ key = "sepsis", text = "sepsis", show = 5 },
	{ key = "cerebralhypoxia", text = "cerebral_hypoxia", show = 10 },
	{ key = "hypoxemia", text = "hypoxemia", show = 20 },
	{ key = "bloodpressure", text = "trend_bp", worse = "down", value = function(c) return c.a("bloodpressure") end,
		visible = function(v) return v > 0 and (v < 70 or v > 150) end },
	{ key = "traumaticshock", text = "traumatic_shock", show = 15 },
	{ key = "infectedcavity", text = "infected_cavity", show = 5 },
	{ key = "huskinfection", text = "husk", show = 5 },
	{ key = "pneumothorax", text = "pneumothorax", show = 5 },
	{ key = "tamponade", text = "tamponade", show = 5 },
	{ key = "organs", text = "organ_damage", show = 30, value = organs },
	{ key = "acidosis", text = "acidosis", show = 20 },
	{ key = "alkalosis", text = "alkalosis", show = 20 },
	{ key = "opiateoverdose", text = "overdose", show = 20 },
	{ key = "radiationsickness", text = "radiation", show = 20 },
}

local function metricValue(m, c)
	if m.value ~= nil then return m.value(c) end
	return c.a(m.key)
end

local function find(patient)
	for i, e in ipairs(P.List) do
		if e.character == patient then return e, i end
	end
end

local function removed(character)
	local ok, r = pcall(function() return character.Removed end)
	return ok and r == true
end

local function now()
	local ok, t = pcall(function() return Timer.GetTime() end)
	if ok and t ~= nil then return t end
	return Timer.Time
end

local function sample(e, t)
	local c = U.Context(e.character, Character.Controlled)
	local values = {}
	for _, m in ipairs(P.Metrics) do values[m.key] = metricValue(m, c) end
	table.insert(e.history, { t = t, values = values })
	while #e.history > 1 and e.history[1].t < t - HISTORY do table.remove(e.history, 1) end
end

function P.Note(patient)
	if patient == nil or removed(patient) then return end
	local t = now()
	local e = find(patient)
	if e == nil then
		e = { character = patient, history = {}, nextSample = t }
		table.insert(P.List, 1, e)
		if #P.List > MAX_PATIENTS then table.remove(P.List) end
	end
	e.name = U.Str(patient.Name)
	e.seen = t
end

function P.Clear()
	P.List = {}
end

local function trend(e, m)
	local last = e.history[#e.history]
	if last == nil then return nil end
	local cur = last.values[m.key]
	local past = e.history[1]
	for i = #e.history, 1, -1 do
		if e.history[i].t <= last.t - TREND_WINDOW then
			past = e.history[i]
			break
		end
	end
	local diff = cur - past.values[m.key]
	local arrow, worse = "→", false
	if diff >= TREND_MIN then
		arrow, worse = "↑", m.worse ~= "down"
	elseif diff <= -TREND_MIN then
		arrow, worse = "↓", m.worse == "down"
	end
	return { key = m.key, text = L(m.text), value = cur, arrow = arrow, worse = worse }
end

function P.Trends(e)
	local out = {}
	local last = e.history[#e.history]
	if last == nil then return out end
	for _, m in ipairs(P.Metrics) do
		local v = last.values[m.key]
		local visible
		if m.visible ~= nil then visible = m.visible(v) else visible = v >= m.show end
		if visible then
			local tr = trend(e, m)
			tr.weight = m.key == "bloodpressure" and math.abs(100 - v) or v
			table.insert(out, tr)
		end
	end
	table.sort(out, function(a, b)
		if a.worse ~= b.worse then return a.worse end
		return a.weight > b.weight
	end)
	while #out > MAX_TRENDS do table.remove(out) end
	return out
end

P.STATUS_ORDER = { critical = 1, surgery = 2, care = 3, stable = 4, dead = 5 }

function P.Status(e, me)
	local patient = e.character
	if patient.IsDead then return "dead", nil end
	local recs = R.Analyze(patient, me)
	local top = recs[1]
	if top == nil then return "stable", nil end
	if top.prio == 1 then return "critical", top.text end
	for _, rec in ipairs(recs) do
		if rec.op ~= nil and rec.prio <= 3 then return "surgery", rec.text end
	end
	if top.prio <= 3 then return "care", top.text end
	return "stable", nil
end

function P.Update()
	local t = now()
	for i = #P.List, 1, -1 do
		local e = P.List[i]
		if removed(e.character) then
			table.remove(P.List, i)
		elseif t >= e.nextSample then
			e.nextSample = t + SAMPLE_INTERVAL
			if not e.character.IsDead then sample(e, t) end
		end
	end
end

function P.Rows(me)
	local rows = {}
	for _, e in ipairs(P.List) do
		local status, reason = P.Status(e, me)
		table.insert(rows, { entry = e, status = status, reason = reason, trends = P.Trends(e) })
	end
	table.sort(rows, function(a, b)
		local oa, ob = P.STATUS_ORDER[a.status], P.STATUS_ORDER[b.status]
		if oa ~= ob then return oa < ob end
		return a.entry.seen > b.entry.seen
	end)
	return rows
end
