
local S = {}
NTMA.Surgery = S
local L = NTMA.L
local U = NTMA.Util
local LT = LimbType

local ALL = { LT.Head, LT.Torso, LT.LeftArm, LT.RightArm, LT.LeftLeg, LT.RightLeg }

local function la(c, lt, id) return c.la(lt, id) end


local ANESTH = {
	key = "anesth", text = "st_anesth", items = { "propofol", "antidama1", "antidama2" }, anyLimb = true,
	done = function(c) return U.CanOperate(c) end,
}

local function close(c)
	local note = nil
	if U.Risky(c, 30) then note = L("note_suture_chance", U.Chance(c, 30)) end
	return { key = "close", text = "st_close", items = { "suture" }, noteText = note }
end

local function incision(threshold)
	return {
		key = "incision", text = "st_incision", items = { "advscalpel", "multiscalpel:incision" }, anesth = true, skill = 30,
		done = function(c, lt) return la(c, lt, "surgeryincision") >= (threshold or 99) end,
		wait = function(c, lt) return la(c, lt, "surgeryincision") >= 1 end,
	}
end
local CLAMP = {
	key = "clamp", text = "st_clamp", items = { "advhemostat" }, anesth = true,
	done = function(c, lt) return la(c, lt, "clampedbleeders") >= 99 end,
	wait = function(c, lt) return la(c, lt, "clampedbleeders") >= 1 end,
}
local RETRACT = {
	key = "retract", text = "st_retract", items = { "advretractors" }, anesth = true, skill = 30,
	done = function(c, lt) return la(c, lt, "retractedskin") >= 99 end,
	wait = function(c, lt) return la(c, lt, "retractedskin") >= 1 end,
}
local function opened(...)
	local list = { incision(), CLAMP, RETRACT }
	for _, s in ipairs({ ... }) do table.insert(list, s) end
	return list
end

local DRILL = {
	key = "drill", text = "st_drill", items = { "surgicaldrill" }, anesth = true, skill = 45,
	done = function(c, lt) return la(c, lt, "drilledbones") >= 99 end,
	wait = function(c, lt) return la(c, lt, "drilledbones") >= 1 end,
}
local SAW = {
	key = "saw", text = "st_saw", items = { "surgerysaw" }, anesth = true, skill = 50,
	done = function(c, lt) return la(c, lt, "bonecut") >= 99 end,
	wait = function(c, lt) return la(c, lt, "bonecut") >= 1 end,
}


local function fractureOn(c, lt)
	if lt == LT.Head then return math.max(c.a("h_fracture"), c.a("n_fracture")) end
	if lt == LT.Torso then return c.a("t_fracture") end
	local id = U.FRACTURE[lt]
	return id ~= nil and c.a(id) or 0
end
S.FractureOn = fractureOn

local function only(lt) return function() return { lt } end end

local function filter(list, pred)
	return function(c)
		local out = {}
		for _, lt in ipairs(list) do
			if pred(c, lt) then table.insert(out, lt) end
		end
		return out
	end
end

local ORGANS = {
	{ id = "liver", damage = "liverdamage", removed = "liverremoved", swap = "liverswap", scalpel = "organscalpel_liver",
		mode = "liver", transplant = "livertransplant*" },
	{ id = "kidneys", damage = "kidneydamage", removed = "kidneyremoved", swap = "kidneyswap",
		scalpel = "organscalpel_kidneys", mode = "kidneys", transplant = "kidneytransplant*" },
	{ id = "lungs", damage = "lungdamage", removed = "lungremoved", swap = "lungswap", scalpel = "organscalpel_lungs",
		mode = "lungs", transplant = "lungtransplant*", after = "note_after_lungs" },
	{ id = "heart", damage = "heartdamage", removed = "heartremoved", swap = "heartswap", scalpel = "organscalpel_heart",
		mode = "heart", transplant = "hearttransplant*", after = "note_after_heart" },
}
S.Organs = ORGANS


S.Ops = {}
local byId = {}
local function op(def)
	table.insert(S.Ops, def)
	byId[def.id] = def
end

op({
	id = "osteo", title = "op_osteo", where = ALL, ind = "ind_osteo",
	limbs = filter(ALL, function(c, lt) return fractureOn(c, lt) >= 1 or c.a("bonedamage") >= 1 end),
	recommended = function(c, lt) return fractureOn(c, lt) >= 1 and not U.Amputated(c, lt) end,
	steps = function(c, lt)
		return opened(DRILL, {
			key = "implants", text = "st_implants", items = { "osteosynthesisimplants" }, anesth = true, skill = 45,
			done = function() return false end,
		})
	end,
	goal = function(c, lt)
		return fractureOn(c, lt) < 1 and (c.a("bonedamage") < 1 or la(c, lt, "bonegrowth") > 0)
	end,
	progress = function(c, lt) return la(c, lt, "drilledbones") >= 1 end,
	note = function(c, lt)
		if U.FRACTURE[lt] ~= nil then return L("note_osteo_cast") end
		if lt == LT.Torso then return L("note_osteo_ribs") end
	end,
})

op({
	id = "stroke", title = "op_stroke", limbs = only(LT.Head), where = { LT.Head },
	available = function(c) return c.a("stroke") > 0 end,
	recommended = function() return true end,
	steps = function() return opened() end,
	goal = function(c) return c.a("stroke") <= 0 end,
	closeTreats = true,
	note = function() return L("note_op_stroke") end,
})

op({
	id = "artery", title = "op_artery", ind = "ind_artery",
	where = { LT.Head, LT.LeftArm, LT.RightArm, LT.LeftLeg, LT.RightLeg },
	limbs = filter({ LT.Head, LT.LeftArm, LT.RightArm, LT.LeftLeg, LT.RightLeg }, function(c, lt) return c.a(U.ARTERIAL[lt]) >= 0.5 end),
	recommended = function() return true end,
	steps = function() return opened() end,
	goal = function(c, lt) return c.a(U.ARTERIAL[lt]) < 0.5 end,
	closeTreats = true,
	note = function(c, lt)
		if lt == LT.Head then return L("note_no_tourniquet_head") end
		if c.la(lt, "arteriesclamp") < 1 then return L("note_tourniquet_first") end
	end,
})

op({
	id = "aorta", title = "op_aorta", limbs = only(LT.Torso), where = { LT.Torso },
	available = function(c) return c.a("t_arterialcut") >= 0.5 end,
	recommended = function() return true end,
	steps = function()
		return {
			incision(1),
			{ key = "balloon", text = "st_balloon", items = { "endovascballoon" },
				done = function(c) return c.a("balloonedaorta") >= 1 or c.a("t_arterialcut") < 0.5 end },
			{ key = "stent", text = "st_stent", items = { "medstent" },
				done = function(c) return c.a("t_arterialcut") < 0.5 end },
		}
	end,
	goal = function(c) return c.a("t_arterialcut") < 0.5 end,
	note = function()
		if not U.NTConfig("NT_HardmodeAorticRupture", false) then return L("note_aorta_suture") end
	end,
})

op({
	id = "internal", title = "op_internal", limbs = only(LT.Torso), where = { LT.Torso },
	available = function(c) return c.a("internalbleeding") > 0 end,
	recommended = function() return true end,
	steps = function() return opened() end,
	goal = function(c) return c.a("internalbleeding") <= 0 end,
	closeTreats = true,
})

op({
	id = "drain", title = "op_drain", limbs = only(LT.Torso), where = { LT.Torso },
	available = function(c) return c.a("pneumothorax") > 0 or c.a("tamponade") > 0 end,
	recommended = function() return true end,
	steps = function()
		return opened({
			key = "drainage", text = "st_drainage", items = { "drainage" },
			done = function(c)
				return c.a("pneumothorax") <= 0
					and (c.a("tamponade") <= 0 or U.NTConfig("NT_OpenCloseTamponade", false))
			end,
		})
	end,
	goal = function(c) return c.a("pneumothorax") <= 0 and c.a("tamponade") <= 0 end,
	closeTreats = true,
	note = function(c)
		if c.a("tamponade") > 0 and U.NTConfig("NT_OpenCloseTamponade", false) then return L("note_tamponade_suture") end
	end,
})

op({
	id = "cavity", title = "op_cavity", limbs = only(LT.Torso), where = { LT.Torso },
	available = function(c) return c.a("infectedcavity") > 0 end,
	recommended = function() return true end,
	steps = function()
		return opened({
			key = "spray", text = "st_spray", items = { "antisepticspray:saline" }, note = "note_spray_saline",
			done = function(c, lt) return la(c, lt, "caviclean") >= 100 end,
			wait = function(c, lt) return la(c, lt, "caviclean") >= 1 end,
		})
	end,
	goal = function(c) return c.a("infectedcavity") <= 0 end,
	progress = function(c, lt) return la(c, lt, "caviclean") > 0 end,
})

local function tweezersGoal(c, lt)
	return la(c, lt, "foreignbody") <= 0 and la(c, lt, "blunttrauma") < 100 and la(c, lt, "internaldamage") < 50
end
op({
	id = "tweezers", title = "op_tweezers", where = ALL, ind = "ind_tweezers",
	limbs = filter(ALL, function(c, lt) return not tweezersGoal(c, lt) end),
	recommended = function() return true end,
	steps = function()
		return opened({
			key = "tweezers", text = "st_tweezers", items = { "tweezers" }, anesth = true, skill = 30, note = "note_tweezers_repeat",
			repeated = true,
			done = tweezersGoal,
		})
	end,
	goal = tweezersGoal,
})

op({
	id = "burn", title = "op_burn", where = ALL, ind = "ind_burn",
	limbs = filter(ALL, function(c, lt) return la(c, lt, "burn") > 50 end),
	recommended = function() return true end,
	steps = function()
		return opened({
			key = "plastiseal", text = "st_plastiseal", items = { "antibleeding2" },
			done = function(c, lt) return la(c, lt, "burn") < 1 end,
		})
	end,
	goal = function(c, lt) return la(c, lt, "burn") < 1 end,
})

op({
	id = "amputate", title = "op_amputate", where = U.EXTREMITIES, ind = "ind_amputate",
	limbs = filter(U.EXTREMITIES, function(c, lt) return c.a(U.S_AMPUTATION[lt]) < 0.1 end),
	recommended = function(c, lt) return la(c, lt, "gangrene") >= 15 or c.a(U.T_AMPUTATION[lt]) >= 0.1 end,
	steps = function() return opened(SAW) end,
	goal = function(c, lt) return c.a(U.S_AMPUTATION[lt]) >= 0.1 end,
	progress = function(c, lt) return la(c, lt, "bonecut") >= 1 end,
	note = function(c, lt)
		if c.a(U.T_AMPUTATION[lt]) >= 0.1 then return L("note_amputate_stump") end
		if la(c, lt, "gangrene") >= 15 then return L("note_amputate_gangrene") end
		return L("note_amputate_item")
	end,
	closeNote = function(c, lt)
		if U.Amputated(c, lt) then return "note_close_stump" end
		return "note_close_amputates"
	end,
})

op({
	id = "reattach", title = "op_reattach", where = U.EXTREMITIES, ind = "ind_reattach",
	limbs = filter(U.EXTREMITIES, function(c, lt) return U.Amputated(c, lt) end),
	recommended = function() return true end,
	steps = function(c, lt)
		local limbItem = U.LIMB_ITEM[lt]
		return opened(SAW, {
			key = "limb", text = "st_limb", items = { limbItem, limbItem .. "p" },
			done = function(c2, lt2) return not U.Amputated(c2, lt2) end,
		})
	end,
	goal = function(c, lt) return not U.Amputated(c, lt) end,
})

local function organState(c, o) return c.a(o.swap) >= 0.1 or c.a(o.removed) >= 0.1 end
local function organWorks(c, o) return c.a(o.damage) < 99 and not organState(c, o) end
S.OrganWorks = organWorks
for _, o in ipairs(ORGANS) do
	op({
		id = "organ_" .. o.id, title = "op_organ_" .. o.id, limbs = only(LT.Torso), where = { LT.Torso }, ind = "ind_organ",
		available = function(c) return not organWorks(c, o) end,
		recommended = function(c) return not organWorks(c, o) end,
		steps = function()
			return opened({
				key = "organcut", text = "st_organcut", items = { o.scalpel, "multiscalpel:" .. o.mode }, skill = 40,
				note = "note_organ_once",
				done = function(c) return organState(c, o) or organWorks(c, o) end,
			}, {
				key = "transplant", text = "st_transplant", items = { o.transplant }, note = o.after,
				done = function(c) return organWorks(c, o) end,
				skillNote = "note_transplant_skill", skill = 40,
			})
		end,
		goal = function(c) return organWorks(c, o) end,
		progress = function(c) return c.a(o.swap) >= 0.1 end,
		note = function(c, lt, session)
			if session ~= nil and session.seen.organcut and not organWorks(c, o) and not organState(c, o) then
				return L("note_transplant_interrupted")
			end
		end,
	})
end

op({
	id = "brain", title = "op_brain", limbs = only(LT.Head), where = { LT.Head }, ind = "ind_brain",
	available = function(c) return c.a("brainremoved") > 0 end,
	recommended = function(c) return c.a("brainremoved") > 0 end,
	steps = function()
		return opened({
			key = "transplant", text = "st_transplant", items = { "braintransplant" }, note = "note_brain_owner",
			done = function(c) return c.a("brainremoved") < 1 end,
			skillNote = "note_transplant_skill", skill = 100,
		})
	end,
	goal = function(c) return c.a("brainremoved") < 1 end,
})

op({
	id = "spinal", title = "op_spinal", limbs = only(LT.Head), where = { LT.Head },
	available = function(c) return c.a("t_paralysis") >= 0.1 end,
	recommended = function() return true end,
	steps = function()
		return opened({
			key = "spinal", text = "st_spinal", items = { "spinalimplant" }, anesth = true, skill = 45,
			done = function(c) return c.a("t_paralysis") < 0.1 end,
		})
	end,
	goal = function(c) return c.a("t_paralysis") < 0.1 end,
	note = function(c)
		if c.a("n_fracture") >= 1 then return L("note_spinal_neck") end
	end,
})

local function extractOp(def)
	op({
		id = "extract_" .. def.id, title = "op_extract_" .. def.id, limbs = only(def.limb), where = { def.limb },
		ind = "ind_extract", listInd = true,
		available = function(c) return c.a(def.removed) < 0.1 end,
		recommended = function() return false end,
		steps = function()
			local items = { def.scalpel, "multiscalpel:" .. def.mode }
			return opened({
				key = "organmark", text = "st_organmark", items = items, skill = 40,
				done = function(c) return c.a(def.swap) >= 0.1 or c.a(def.removed) >= 0.1 end,
			}, {
				key = "organextract", text = "st_organextract", items = items, skill = def.extractSkill,
				done = function(c) return c.a(def.removed) >= 0.1 end,
			})
		end,
		goal = function(c) return c.a(def.removed) >= 0.1 end,
		progress = function(c) return c.a(def.swap) >= 0.1 end,
		note = function(c)
			local parts = { L(def.warning) }
			if c.a(def.damage) >= 90 then table.insert(parts, L("note_extract_damaged")) end
			return table.concat(parts, "; ")
		end,
	})
end
for _, o in ipairs(ORGANS) do
	extractOp({ id = o.id, limb = LT.Torso, damage = o.damage, removed = o.removed, swap = o.swap,
		scalpel = o.scalpel, mode = o.mode, extractSkill = 50,
		warning = (o.id == "heart" or o.id == "lungs") and "note_extract_vital" or "note_extract_organ" })
end
extractOp({ id = "brain", limb = LT.Head, damage = "cerebralhypoxia", removed = "brainremoved", swap = "brainswap",
	scalpel = "organscalpel_brain", mode = "brain", warning = "note_extract_brain" })

local function drawn(c, lt, session)
	return session ~= nil and session.bloodloss ~= nil and c.a("bloodloss") >= session.bloodloss + 20
end
op({
	id = "blood_draw", title = "op_blood_draw", limbs = only(LT.Torso), where = { LT.Torso }, ind = "ind_blood_draw",
	plain = true, anyLimb = true, listInd = true,
	available = function(c) return c.a("bloodloss") <= 31 end,
	recommended = function() return false end,
	start = function(c, lt, session) session.bloodloss = c.a("bloodloss") end,
	steps = function()
		return {
			{ key = "draw", text = "st_draw", items = { "emptybloodpack" }, anyLimb = true, skill = 30, medical = true,
				done = drawn },
		}
	end,
	goal = drawn,
	note = function(c)
		local parts = { L("note_blood_draw") }
		if c.a("bloodloss") > 31 then table.insert(parts, 1, L("note_blood_draw_blocked")) end
		if c.bloodtype ~= nil then table.insert(parts, L("note_blood_draw_type", U.BloodLabel(c.bloodtype))) end
		return table.concat(parts, "; ")
	end,
})

function S.Get(id) return byId[id] end


local function stepNote(c, st)
	local parts = {}
	if st.note ~= nil then table.insert(parts, L(st.note)) end
	if st.noteText ~= nil then table.insert(parts, st.noteText) end
	local surgical = not st.medical
	if st.skill ~= nil and U.Risky(c, st.skill, surgical) then
		table.insert(parts, L(st.skillNote or "note_surgery_chance", U.Chance(c, st.skill, surgical)))
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "; ")
end

local function evaluate(c, opDef, lt, session)
	local plain = opDef.plain == true
	local steps = plain and {} or { ANESTH }
	for _, st in ipairs(opDef.steps(c, lt)) do table.insert(steps, st) end
	local closeStep = nil
	if not plain then
		closeStep = close(c)
		if opDef.closeNote ~= nil then
			closeStep.note = opDef.closeNote(c, lt)
		end
		table.insert(steps, closeStep)
	end
	local first, last = plain and 1 or 2, plain and #steps or #steps - 1

	local rows = {}
	for i, st in ipairs(steps) do
		local done = false
		if st ~= closeStep then
			done = st.done(c, lt, session) == true
			if done and session ~= nil and st.key ~= "anesth" then session.seen[st.key] = true end
		end
		rows[i] = { step = st, done = done }
	end

	local open = c.la(lt, "surgeryincision") >= 1
	local goal
	if session ~= nil and session.reference then
		goal = session.seen.incision == true and not open
	else
		goal = opDef.goal(c, lt, session) == true
	end
	local target, finished = nil, false
	if goal then
		for i = first, last do rows[i].done = true end
		if open and not plain then
			target = #rows
		else
			finished = true
			for _, row in ipairs(rows) do row.done = true end
		end
	else
		for i = first, last do
			if not rows[i].done then
				target = i
				break
			end
		end
		target = target or #rows
	end
	if target ~= nil and not plain and steps[target].anesth and not rows[1].done then target = 1 end

	local guide = { op = opDef, limb = lt, rows = rows, finished = finished }
	for i, row in ipairs(rows) do
		row.items = row.step.items
		row.note = stepNote(c, row.step)
		if not row.step.anyLimb then row.limb = lt end
		if i == target then
			row.current = true
			if row.step.wait ~= nil and row.step.wait(c, lt) then
				row.waiting = true
				row.items = {}
				row.note = L("step_wait")
			end
			guide.current = row
		end
	end
	local notes = {}
	if session ~= nil and session.reference then
		table.insert(notes, opDef.ind ~= nil and L("note_reference_ind", L(opDef.ind)) or L("note_reference"))
	end
	if opDef.note ~= nil then
		local note = opDef.note(c, lt, session)
		if note ~= nil then table.insert(notes, note) end
	end
	if #notes > 0 then guide.note = table.concat(notes, "; ") end
	return guide
end

local function contains(list, value)
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

local ALTERNATIVE = { amputate = "reattach", reattach = "amputate" }

function S.Pending(c, lt, exceptId)
	local out = {}
	local session = S.Session
	if session ~= nil and (c.patient == nil or c.patient.ID ~= session.patientId) then session = nil end
	for _, opDef in ipairs(S.Ops) do
		if opDef.id ~= exceptId and ALTERNATIVE[exceptId] ~= opDef.id then
			local mine = session ~= nil and session.opId == opDef.id and session.limb == lt
			local needed = mine
			if not needed and (opDef.available == nil or opDef.available(c)) and contains(opDef.limbs(c), lt) then
				needed = opDef.recommended(c, lt) == true
			end
			if needed and opDef.progress ~= nil and opDef.progress(c, lt) then
				local guide = evaluate(c, opDef, lt, mine and session or nil)
				if not guide.finished and guide.current ~= nil and guide.current.step.key ~= "close" then
					table.insert(out, opDef)
				end
			end
		end
	end
	return out
end

function S.SutureRisk(c, lt, opId)
	if opId == "amputate" then return nil end
	if c.la(lt, "bonecut") >= 1 and not U.Amputated(c, lt) then
		if lt == LT.Head then return L("note_suture_head"), {} end
		if lt == LT.Torso then return nil end
		return L("note_suture_amputates"), {}
	end
	if c.la(lt, "surgeryincision") < 1 then return nil end
	local pending = S.Pending(c, lt, opId)
	if #pending == 0 then return nil end
	local names = {}
	for _, opDef in ipairs(pending) do table.insert(names, L(opDef.title)) end
	return L("note_suture_resets", table.concat(names, ", ")), pending
end

function S.Evaluate(c, opDef, lt, session)
	local guide = evaluate(c, opDef, lt, session)
	local cur = guide.current
	if cur ~= nil and cur.step.key == "close" then
		local warning, pending = S.SutureRisk(c, lt, opDef.id)
		if warning ~= nil then
			cur.warning, cur.warnOps = warning, pending
			cur.note = cur.note ~= nil and (cur.note .. "; " .. warning) or warning
		end
	end
	return guide
end

function S.Current(c, opId, lt)
	local opDef = byId[opId]
	if opDef == nil then return nil end
	local guide = S.Evaluate(c, opDef, lt, nil)
	if guide.current == nil then return nil end
	local cur = guide.current
	local note = cur.note
	if cur.step.key == "anesth" then note = L("step_anesth") end
	return {
		items = cur.items, note = note, key = cur.step.key, warnOps = cur.warnOps,
		single = not cur.waiting and #cur.items > 0 and not cur.step.repeated,
	}
end

function S.Available(patient, me)
	local out = {}
	if patient == nil or patient.CharacterHealth == nil or patient.IsDead then return out end
	local c = U.Context(patient, me)
	for index, opDef in ipairs(S.Ops) do
		if opDef.available == nil or opDef.available(c) then
			local limbs = opDef.limbs(c)
			if #limbs > 0 then
				local rec = false
				for _, lt in ipairs(limbs) do
					if opDef.recommended(c, lt) then rec = true end
				end
				table.insert(out, { op = opDef, limbs = limbs, recommended = rec, index = index })
			end
		end
	end
	table.sort(out, function(a, b)
		if a.recommended ~= b.recommended then return a.recommended end
		return a.index < b.index
	end)
	return out
end

local function limbSet(list)
	local set = {}
	for _, lt in ipairs(list) do set[lt] = true end
	return set
end

local function status(c, opDef)
	local now = {}
	if opDef.available == nil or opDef.available(c) then now = opDef.limbs(c) end
	local needed = {}
	for _, lt in ipairs(now) do
		if opDef.recommended(c, lt) then table.insert(needed, lt) end
	end
	local state = #needed > 0 and "needed" or (#now > 0 and "possible" or "idle")
	return state, limbSet(now), limbSet(needed)
end

function S.All(patient, me)
	local out = {}
	if patient == nil or patient.CharacterHealth == nil or patient.IsDead then return out end
	local c = U.Context(patient, me)
	local order = { needed = 1, possible = 2, idle = 3 }
	for index, opDef in ipairs(S.Ops) do
		local state, now, needed = status(c, opDef)
		table.insert(out, {
			op = opDef, state = state, limbs = opDef.where or ALL, now = now, needed = needed,
			recommended = state == "needed", index = index,
		})
	end
	table.sort(out, function(a, b)
		if a.state ~= b.state then return order[a.state] < order[b.state] end
		return a.index < b.index
	end)
	return out
end

S.Session = nil

function S.Start(patient, opId, lt)
	local session = { patientId = patient.ID, opId = opId, limb = lt, seen = {} }
	local opDef = byId[opId]
	if opDef ~= nil and patient.CharacterHealth ~= nil then
		local c = U.Context(patient, Character.Controlled)
		local state, now = status(c, opDef)
		local can = (state ~= "idle" and now[lt]) or opDef.plain
		session.reference = not can and opDef.goal(c, lt, session) == true
		if opDef.start ~= nil then opDef.start(c, lt, session) end
	end
	S.Session = session
	return session
end

function S.Stop()
	S.Session = nil
end

function S.Guide(patient, me)
	local session = S.Session
	if session == nil or patient == nil or patient.ID ~= session.patientId then return nil end
	local opDef = byId[session.opId]
	if opDef == nil or patient.CharacterHealth == nil then return nil end
	return S.Evaluate(U.Context(patient, me), opDef, session.limb, session)
end
