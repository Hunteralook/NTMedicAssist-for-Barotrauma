
local R = {}
NTMA.Rules = R
local L = NTMA.L
local U = NTMA.Util
local S = NTMA.Surgery
local G = NTMA.Genes
local LT = LimbType

R.Limbs = { LT.Head, LT.Torso, LT.LeftArm, LT.RightArm, LT.LeftLeg, LT.RightLeg }

local FRACTURE = U.FRACTURE
local DISLOCATION = U.DISLOCATION
local ARTERIAL = U.ARTERIAL
local AMPUTATION = U.T_AMPUTATION
local WOUNDS = { "lacerations", "gunshotwound", "bitewounds", "explosiondamage" }
local ORGANS = { "heartdamage", "lungdamage", "liverdamage", "kidneydamage", "organdamage" }
local ORGAN_TEXT = { liver = "organ_liver", kidneys = "organ_kidneys", lungs = "organ_lungs", heart = "organ_heart" }
local POISONS = {
	morbusinepoisoning = "poisoning", cyanidepoisoning = "poisoning", sufforinpoisoning = "poisoning",
	deliriuminepoisoning = "poisoning", radiationsickness = "radiation",
}

local chance = U.Chance
local function itemChance(c, required)
	return math.floor(math.min(1, c.skill / required) * 100 + 0.5)
end

function R.Analyze(patient, me)
	local out = {}
	local seen = {}
	local order = 0

	local function add(prio, key, text, items, limb, opts)
		if seen[key] then return end
		seen[key] = true
		order = order + 1
		local rec = { prio = prio, key = key, text = text, items = items or {}, limb = limb, order = order, rank = 5, sev = 0 }
		if opts ~= nil then
			rec.note = opts.note
			rec.chain = opts.chain
			rec.rank = opts.rank or 5
			rec.sev = opts.sev or 0
		end
		table.insert(out, rec)
	end

	if patient == nil or patient.CharacterHealth == nil then return out end
	if patient.IsDead then
		add(1, "dead", L("dead"), {})
		return out
	end

	local c = U.Context(patient, me)

	local surgeryLimbs, surgeryOps = {}, {}
	local function surgery(prio, key, text, lt, opId, opts)
		opts = opts or {}
		surgeryLimbs[lt] = true
		surgeryOps[tostring(lt) .. ":" .. opId] = true
		local cur = S.Current(c, opId, lt)
		if cur == nil then return end
		local stepText = text
		if #cur.items == 1 then stepText = text .. " — " .. L("step_next", U.PatternName(cur.items[1])) end
		local limb = lt
		if cur.key == "anesth" then limb = nil end
		add(prio, key, stepText, cur.items, limb, { note = cur.note or opts.note, rank = opts.rank, sev = opts.sev })
		local rec = out[#out]
		if rec ~= nil and rec.key == key then
			rec.op, rec.opLimb, rec.warnOps, rec.single = opId, lt, cur.warnOps, cur.single
		end
	end

	local foreignBot = false
	pcall(function()
		foreignBot = patient.IsBot and me ~= nil and patient.TeamID ~= me.TeamID and not patient.IsEscorted
	end)
	if foreignBot then add(1, "consent", L("consent"), {}, nil, { rank = 0 }) end

	if c.a("stasis") > 0 then
		add(1, "stasis", L("stasis"), {})
		return out
	end

	local incisionOpen = false
	for _, lt in ipairs(R.Limbs) do
		if c.la(lt, "surgeryincision") >= 1 then incisionOpen = true end
	end

	local arrest = c.a("cardiacarrest")
	if arrest > 0 then
		add(1, "arrest_adr", L("cardiac_arrest"), { "adrenaline" }, nil, { note = L("note_adrenaline_arrest"), rank = 2 })
		add(1, "arrest_defib", L("cardiac_arrest"), { "aed", "defibrillator" }, LT.Torso, { note = L("note_defib"), rank = 2 })
		add(1, "arrest_cpr", L("cardiac_arrest"), { "autocpr" }, LT.Torso, { note = L("note_cpr"), rank = 2 })
	end

	local fib, tachy = c.a("fibrillation"), c.a("tachycardia")
	if arrest <= 0 and (fib >= 1 or tachy >= 5) then
		local prio = fib > 20 and 1 or (fib >= 1 and 2 or 3)
		add(prio, "fib", fib >= 1 and L("fibrillation") or L("tachycardia"), { "aed", "defibrillator" }, LT.Torso,
			{ note = L("note_defib"), rank = 4, sev = math.max(fib, tachy) })
	end

	local stroke = c.a("stroke")
	local heartattack = c.a("heartattack")
	if heartattack > 0 then
		if stroke > 0 then
			add(2, "heartattack", L("heartattack"), {}, nil, { note = L("note_strepto_stroke"), sev = heartattack })
		else
			add(1, "heartattack", L("heartattack"), { "streptokinase" }, nil, { sev = heartattack })
		end
	end
	if stroke > 0 then surgery(2, "stroke", L("stroke"), LT.Head, "stroke", { sev = stroke }) end

	local pneumo, tamponade = c.a("pneumothorax"), c.a("tamponade")
	if pneumo > 0 or tamponade > 0 then
		local text = tamponade > pneumo and L("tamponade") or L("pneumothorax")
		if c.a("needlec") < 1 and c.la(LT.Torso, "retractedskin") < 0.5 then
			local note = L("note_needle")
			if U.Risky(c, 20) then note = note .. "; " .. L("note_surgery_chance", chance(c, 20)) end
			add(math.max(pneumo, tamponade) > 15 and 1 or 2, "needle", text, { "needle" }, LT.Torso,
				{ note = note, rank = 3, sev = math.max(pneumo, tamponade) })
		else
			local prio = c.a("needlec") >= 1 and 4 or 2
			surgery(prio, "pneumo_surgery", c.a("needlec") >= 1 and L("needle_active") or text, LT.Torso, "drain",
				{ sev = math.max(pneumo, tamponade) })
		end
	end

	if c.a("respiratoryarrest") > 0 then
		add(1, "resp_bvm", L("resp_arrest"), { "bvm" }, LT.Head, { note = L("note_bvm"), rank = 2 })
		add(1, "resp_cpr", L("resp_arrest"), { "autocpr" }, LT.Torso, { note = L("note_cpr"), rank = 2 })
	end
	local hypox = c.a("hypoxemia")
	if hypox > 40 then add(hypox > 70 and 1 or 2, "hypoxemia", L("hypoxemia"), { "liquidoxygenite" }, nil, { rank = 3, sev = hypox }) end
	local brain = c.a("cerebralhypoxia")
	if brain > 30 and c.a("afmannitol") < 1 then
		local note = L("note_cause")
		if c.a("bloodpressure") < 70 or hypox > 30 then note = L("note_mannitol_blocked") end
		add(3, "brain", L("cerebral_hypoxia"), { "mannitol" }, nil, { note = note, sev = brain })
	end

	local bloodloss = c.a("bloodloss")
	if bloodloss > 15 then
		local note = c.bloodtype ~= nil and L("note_bt_known", U.BloodLabel(c.bloodtype)) or L("note_bt_unknown")
		add(bloodloss > 60 and 1 or (bloodloss > 30 and 2 or 3), "bloodloss", L("bloodloss"), U.PacksFor(c.bloodtype), nil,
			{ note = note, rank = 4, sev = bloodloss })
	end

	local acid, alkal = c.a("acidosis"), c.a("alkalosis")
	local bp = c.a("bloodpressure")
	if bp > 0 and bp < 70 and arrest <= 0 then
		local fluids = acid > alkal and { "ringerssolution", "antibloodloss1" } or { "antibloodloss1", "ringerssolution" }
		add(bp < 50 and 1 or 2, "hypotension", L("hypotension"), fluids, nil, { rank = 4, sev = 100 - bp })
	elseif bp > 150 then
		add(3, "hypertension", L("hypertension"), { "pressuremeds", "nitroglycerin" }, nil, { sev = bp - 100 })
	end
	if acid > 20 then add(acid > 50 and 2 or 3, "acidosis", L("acidosis"), { "ringerssolution" }, nil, { sev = acid }) end
	if alkal > 20 then add(alkal > 50 and 2 or 3, "alkalosis", L("alkalosis"), { "antibloodloss1" }, nil, { sev = alkal }) end

	local internal = c.a("internalbleeding")
	if internal > 5 then
		local note = c.la(LT.Torso, "infectedwound") > 0 and L("note_ice_infection") or nil
		add(2, "internalbleeding", L("internal_bleeding"), { "gelipack" }, LT.Torso, { sev = internal, note = note })
		surgery(3, "internalbleeding_surgery", L("internal_bleeding"), LT.Torso, "internal", { sev = internal })
	end
	local hemoshock = c.a("hemotransfusionshock")
	if hemoshock > 5 and stroke <= 0 then
		add(2, "hemoshock", L("hemotransfusion"), { "streptokinase" }, nil, { sev = hemoshock })
	end

	local sepsis = c.a("sepsis")
	if sepsis > 5 and c.a("afantibiotics") < 1 then
		add(sepsis > 40 and 1 or 2, "sepsis", L("sepsis"), { "antibiotics" }, nil, { sev = sepsis })
	end

	local cavity = c.a("infectedcavity")
	if cavity > 0 then
		if cavity > 20 then
			surgery(cavity >= 70 and 2 or 3, "cavity", L("infected_cavity"), LT.Torso, "cavity", { sev = cavity })
		elseif c.a("afantibiotics") < 0.1 then
			add(3, "cavity", L("infected_cavity"), { "antibiotics" }, nil, { note = L("note_cavity_antibiotics"), sev = cavity })
		end
	end

	local husk = c.a("huskinfection")
	local huskGene = c.a("husktransformimmunity")
	if husk >= 1 and (husk < 100 or huskGene >= G.HUSK_BLOCK) then
		local items = { "calyxanide" }
		if husk < 75 and c.a("afantibiotics") < 1 then table.insert(items, "antibiotics") end
		local note = L("note_husk")
		if huskGene >= G.HUSK_BLOCK then
			note = L("note_husk_blocked")
		elseif huskGene > 0 then
			note = L("note_husk_slowed")
		end
		if husk > 60 and c.skill < 38 then note = note .. "; " .. L("note_husk_chance", itemChance(c, 38)) end
		add(husk >= 50 and 1 or 2, "husk", L("husk"), items, nil, { note = note, sev = husk })
	end

	local overdose = c.a("opiateoverdose")
	if overdose > 30 then add(overdose > 60 and 1 or 2, "overdose", L("overdose"), { "antinarc" }, nil, { sev = overdose }) end

	for aff, textKey in pairs(POISONS) do
		local s = c.a(aff)
		if s > 10 then
			local items = R.SuitableItems(aff)
			if textKey == "poisoning" then table.insert(items, "stabilozine") end
			add(s > 50 and 1 or 2, "poison_" .. aff, L(textKey), items, nil, { sev = s })
		end
	end

	local psychosis = c.a("psychosis")
	if psychosis >= 20 then
		local note = c.a("outsideinfluence") > 0 and L("note_psychosis_gene") or nil
		add(4, "psychosis", L("psychosis"), R.SuitableItems("psychosis"), nil, { note = note, sev = psychosis })
	end
	for _, gene in ipairs(G.ActiveDebuffs(c)) do
		add(4, "gene_" .. gene.id, L("gene_row", gene.name), {}, nil, { note = L("note_gene", gene.text), sev = gene.strength })
	end
	local paralysis = c.a("paralysis")
	if paralysis >= 20 then
		local note = c.a("anesthesia") > 0 and L("note_antiparalysis_propofol") or nil
		add(3, "paralysis", L("paralysis"), R.SuitableItems("paralysis"), nil, { note = note, sev = paralysis })
	end

	local session = S.Session
	local harvesting = session ~= nil and session.patientId == patient.ID and session.opId:sub(1, 8) == "extract_"
	for _, o in ipairs(S.Organs) do
		local name = L(ORGAN_TEXT[o.id])
		local vital = o.id == "heart" or o.id == "lungs"
		if c.a(o.removed) >= 0.1 then
			surgery(vital and 1 or 2, "organ_" .. o.id, L("organ_removed", name), LT.Torso, "organ_" .. o.id, { sev = 200 })
		elseif c.a(o.swap) >= 0.1 and harvesting and session.opId == "extract_" .. o.id then
		elseif c.a(o.swap) >= 0.1 then
			surgery(vital and 1 or 2, "organ_" .. o.id, L("organ_swap", name), LT.Torso, "organ_" .. o.id, { sev = 150 })
		elseif c.a(o.damage) >= 99 then
			surgery(vital and 1 or 2, "organ_" .. o.id, L("organ_failure", name), LT.Torso, "organ_" .. o.id,
				{ sev = c.a(o.damage) })
		end
	end
	if c.a("brainremoved") > 0 then
		surgery(1, "brainremoved", L("brain_removed"), LT.Head, "brain", { sev = 200 })
	end

	local bonedamage = c.a("bonedamage")
	if bonedamage > 20 then
		local items = {}
		if bonedamage < 99 and c.a("afthiamine") < 1 then items = { "thiamine" } end
		local note = bonedamage >= 90 and L("note_bonedamage_all") or L("note_bonedamage")
		add(bonedamage >= 90 and 3 or 4, "bonedamage", L("bonedamage"), items, nil, { note = note, sev = bonedamage })
	end

	local paralysed = c.a("t_paralysis")
	if paralysed >= 0.1 then
		surgery(2, "t_paralysis", L("t_paralysis"), LT.Head, "spinal", { sev = paralysed })
	end

	local glueSafe = c.skill >= 55

	local function skinCare(lt)
		local items = {}
		if c.la(lt, "bandaged") < 0.1 and c.la(lt, "dirtybandage") <= 0 then
			table.insert(items, "antibleeding1")
			table.insert(items, "antibleeding2")
		end
		if c.la(lt, "skinointmented") < 1 then table.insert(items, "skinaid") end
		return items
	end

	for _, lt in ipairs(R.Limbs) do
		local amputated = U.Amputated(c, lt)
		local art = ARTERIAL[lt]
		local artcut = art ~= nil and c.a(art) or 0
		local artsev = 100 + artcut
		if artcut >= 0.5 then
			if lt == LT.Torso then
				add(1, "aorta", L("aortic"), { "stasisbag" }, nil, { note = L("note_aorta"), rank = 1, sev = artsev })
				surgery(2, "aorta_surgery", L("aortic"), lt, "aorta", { sev = artcut })
			elseif lt == LT.Head then
				surgery(1, "art_head", L("arterial_head"), lt, "artery", { note = L("note_no_tourniquet_head"), rank = 1, sev = artsev })
			elseif c.la(lt, "arteriesclamp") < 1 then
				add(1, "art" .. tostring(lt), L("arterial"), { "tourniquet" }, lt, { note = L("note_tourniquet"), rank = 1, sev = artsev })
			else
				surgery(2, "artsurg" .. tostring(lt), L("arterial_clamped"), lt, "artery", { sev = artcut })
			end
		elseif c.la(lt, "arteriesclamp") >= 1 and lt ~= LT.Head and lt ~= LT.Torso then
			local items = { "traumashears", "divingknife*" }
			if c.la(lt, "gypsumcast") > 0 then items = { "divingknife*", "traumashears" } end
			add(3, "clamp" .. tostring(lt), L("tourniquet_left"), items, lt, { note = L("note_tourniquet_left") })
		end

		local bleed = c.la(lt, "bleeding")
		if bleed > 1 then
			local items = { "antibleeding2", "antibleeding1", "suture" }
			if glueSafe then table.insert(items, 1, "antibleeding3") end
			local note = c.a("afstreptokinase") > 0 and L("note_no_clotting") or nil
			add(bleed > 40 and 1 or (bleed > 15 and 2 or 3), "bleed" .. tostring(lt), L("bleeding"), items, lt,
				{ rank = 1, sev = bleed, note = note })
		end

		local fracture = FRACTURE[lt]
		local broken = fracture ~= nil and c.a(fracture) or 0
		if broken >= 1 and not amputated and c.la(lt, "gypsumcast") < 0.1 then
			if c.la(lt, "surgeryincision") >= 1 then
			elseif c.la(lt, "bandaged") < 0.1 then
				add(2, "fracture" .. tostring(lt), L("fracture"), { "antibleeding1", "antibleeding2" }, lt,
					{ note = L("step_bandage_first"), sev = broken })
			else
				local note = L("step_cast")
				if U.Risky(c, 40) then note = note .. "; " .. L("note_skill_chance", chance(c, 40)) end
				add(2, "fracture" .. tostring(lt), L("fracture"), { "gypsum" }, lt, { note = note, sev = broken })
			end
		end

		local dislocation = DISLOCATION[lt]
		local dislocated = dislocation ~= nil and c.a(dislocation) or 0
		if dislocated >= 1 and not amputated then
			local relieved = c.a("analgesia") >= 0.5 or c.a("afadrenaline") >= 0.5
			local needed = relieved and 30 or 60
			if not relieved and U.Risky(c, 60) then
				add(2, "dislocation_pain" .. tostring(lt), L("dislocation"), { "antidama1", "antidama2" }, nil,
					{ note = L("note_painkiller_first"), sev = dislocated })
			end
			local note = L("note_wrench", needed)
			if U.Risky(c, needed) then note = note .. "; " .. L("note_wrench_chance", chance(c, needed)) end
			add(2, "dislocation" .. tostring(lt), L("dislocation"), { "wrench*", "heavywrench", "repairpack" }, lt,
				{ note = note, sev = dislocated })
		end

		local amputation = AMPUTATION[lt]
		local amputatedT = amputation ~= nil and c.a(amputation) or 0
		local stump = U.S_AMPUTATION[lt] ~= nil and c.a(U.S_AMPUTATION[lt]) or 0
		if amputatedT > 0 then
			add(3, "amputation" .. tostring(lt), L("amputation"), {}, lt, { note = L("note_amputation"), sev = amputatedT })
		elseif stump >= 0.1 then
			local limbItem = U.LIMB_ITEM[lt]
			add(4, "stump" .. tostring(lt), L("stump"), { limbItem, limbItem .. "p" }, lt, { note = L("note_stump") })
		end

		local burn = c.la(lt, "burn")
		if burn > 1 then
			if burn > 50 or c.la(lt, "burn_deg3") > 0 then
				local items = glueSafe and { "antibleeding3" } or {}
				add(2, "burn" .. tostring(lt), L("burn3"), items, lt, { sev = burn })
				surgery(3, "burn_surgery" .. tostring(lt), L("burn3"), lt, "burn", { sev = burn })
			else
				local items = { "ointment" }
				for _, id in ipairs(skinCare(lt)) do table.insert(items, id) end
				add(burn > 20 and 3 or 4, "burn" .. tostring(lt), L("burn"), items, lt, { sev = burn })
			end
		end

		local infection = c.la(lt, "infectedwound")
		if infection > 5 then
			local items = { "ointment", "antisepticspray" }
			if glueSafe then table.insert(items, "antibleeding3") end
			add(infection > 40 and 2 or 3, "infection" .. tostring(lt), L("infected"), items, lt, { sev = infection })
		end

		if c.la(lt, "dirtybandage") > 0 then
			add(3, "dirty" .. tostring(lt), L("dirtybandage"), { "antibleeding1", "antibleeding2" }, lt)
		end

		local wound, stuck = 0, nil
		for _, id in ipairs(WOUNDS) do
			local v = c.la(lt, id)
			wound = wound + v
			local limit = id == "bitewounds" and 100 or 50
			if v >= limit and (stuck == nil or limit < stuck) then stuck = limit end
		end
		if wound > 1 then
			local items = { "suture" }
			if wound <= 10 then
				items = skinCare(lt)
				table.insert(items, "suture")
			end
			add(stuck ~= nil and 2 or (wound > 10 and 3 or 4), "wound" .. tostring(lt), L("wounds"), items, lt,
				{ note = stuck ~= nil and L("note_no_selfheal", stuck) or nil, sev = wound })
		end

		local blunt = c.la(lt, "blunttrauma")
		if blunt >= 100 then
			surgery(3, "blunt_surgery" .. tostring(lt), L("blunt"), lt, "tweezers", { note = L("note_no_selfheal", 100), sev = blunt })
		elseif blunt > 1 then
			local items = skinCare(lt)
			if c.la(lt, "iced") < 1 and infection <= 0 then table.insert(items, 1, "gelipack") end
			if #items > 0 then
				add(blunt > 40 and 3 or 4, "blunt" .. tostring(lt), L("blunt"), items, lt, { note = L("note_blunt"), sev = blunt })
			end
		end

		local internalDamage = c.la(lt, "internaldamage")
		if internalDamage >= 50 then
			surgery(3, "internaldamage" .. tostring(lt), L("internal_damage"), lt, "tweezers",
				{ note = L("note_no_selfheal", 50), sev = internalDamage })
		end

		local foreign = c.la(lt, "foreignbody")
		if foreign >= 15 then
			surgery(3, "foreign" .. tostring(lt), L("foreignbody"), lt, "tweezers", { sev = foreign })
		elseif foreign > 0 and (c.la(lt, "gunshotwound") >= 1 or c.la(lt, "explosiondamage") >= 1)
			and c.la(lt, "retractedskin") < 99 then
			local note = L("note_foreign_small")
			if U.Risky(c, 30, true) then note = note .. "; " .. L("note_surgery_chance", chance(c, 30, true)) end
			add(4, "foreign" .. tostring(lt), L("foreignbody"), { "tweezers" }, lt, { note = note, sev = foreign })
		end

		local gangrene = c.la(lt, "gangrene")
		if gangrene > 15 and U.S_AMPUTATION[lt] ~= nil then
			surgery(3, "gangrene" .. tostring(lt), L("gangrene"), lt, "amputate", { note = L("note_gangrene"), sev = gangrene })
		end
	end

	local ribs = c.a("t_fracture")
	if ribs >= 1 then
		if c.la(LT.Torso, "bandaged") < 0.1 and c.la(LT.Torso, "dirtybandage") <= 0 then
			add(3, "ribs", L("fracture_ribs"), { "antibleeding1", "antibleeding2" }, LT.Torso, { sev = ribs, note = L("note_ribs_bandage") })
		end
		surgery(3, "ribs_surgery", L("fracture_ribs"), LT.Torso, "osteo", { sev = ribs })
	end
	local skull, neck = c.a("h_fracture"), c.a("n_fracture")
	if neck >= 1 then
		if c.la(LT.Head, "bandaged") < 0.1 and c.la(LT.Head, "dirtybandage") <= 0 then
			add(neck >= 60 and 1 or 2, "neck_bandage", L("fracture_neck"), { "antibleeding1", "antibleeding2" }, LT.Head,
				{ note = L("note_neck_bandage"), rank = 3, sev = neck })
		end
		local text = skull >= 1 and L("fracture_skull_neck") or L("fracture_neck")
		surgery(neck >= 60 and 2 or 3, "neck", text, LT.Head, "osteo", { sev = math.max(skull, neck) })
	elseif skull >= 1 then
		surgery(3, "skull", L("fracture_skull"), LT.Head, "osteo", { sev = skull })
	end

	local seizure = c.a("seizure")
	if seizure >= 0.1 then
		local causes = {}
		if stroke > 1 then table.insert(causes, L("stroke")) end
		if acid > 60 then table.insert(causes, L("acidosis")) end
		if alkal > 60 then table.insert(causes, L("alkalosis")) end
		if c.a("alcoholwithdrawal") > 50 then table.insert(causes, L("withdrawal")) end
		if overdose > 60 then table.insert(causes, L("overdose")) end
		if c.a("radiationsickness") > 0 then table.insert(causes, L("radiation")) end
		local note = #causes > 0 and L("note_seizure_cause", table.concat(causes, ", ")) or L("note_seizure")
		add(2, "seizure", L("seizure"), R.SuitableItems("seizure"), nil, { note = note, sev = seizure })
	end
	local coma = c.a("coma")
	if coma >= 1 then
		local slow = {}
		if acid >= 20 then table.insert(slow, L("acidosis")) end
		if alkal >= 20 then table.insert(slow, L("alkalosis")) end
		if c.a("heartdamage") >= 30 then table.insert(slow, L("organ_heart")) end
		if c.a("lungdamage") >= 40 then table.insert(slow, L("organ_lungs")) end
		if hypox > 40 then table.insert(slow, L("hypoxemia")) end
		local note = #slow > 0 and L("note_coma_slow", table.concat(slow, ", ")) or L("note_coma")
		add(2, "coma", L("coma"), {}, nil, { note = note, sev = coma })
	end
	local concussion = c.a("concussion")
	if concussion >= 1 then
		add(4, "concussion", L("concussion"), {}, nil, { note = L("note_concussion"), sev = concussion })
	end

	for _, lt in ipairs(R.Limbs) do
		if c.la(lt, "surgeryincision") >= 1 or c.la(lt, "bonecut") >= 1 then
			for _, opDef in ipairs(S.Pending(c, lt, nil)) do
				if not surgeryOps[tostring(lt) .. ":" .. opDef.id] then
					surgery(3, "pending_" .. opDef.id .. tostring(lt), L(opDef.title), lt, opDef.id)
				end
			end
			local amputate = S.Get("amputate")
			local sawn = c.la(lt, "bonecut") >= 1 and U.S_AMPUTATION[lt] ~= nil
			if sawn and U.Amputated(c, lt) and not surgeryOps[tostring(lt) .. ":reattach"] then
				surgery(3, "pending_reattach" .. tostring(lt), L("op_reattach"), lt, "reattach")
			end
			if sawn and c.a(U.S_AMPUTATION[lt]) < 0.1 and amputate.recommended(c, lt)
				and not surgeryOps[tostring(lt) .. ":amputate"] then
				surgery(3, "pending_amputate" .. tostring(lt), L("op_amputate"), lt, "amputate")
			elseif sawn and c.a(U.S_AMPUTATION[lt]) >= 0.1 then
				add(3, "stump_close" .. tostring(lt), L("stump_close"), { "suture" }, lt, { note = L("note_close_stump") })
				local rec = out[#out]
				if rec.key == "stump_close" .. tostring(lt) then rec.op, rec.opLimb = "open", lt end
			elseif sawn and not U.Amputated(c, lt) then
				local limbItem = U.LIMB_ITEM[lt]
				add(3, "sawn" .. tostring(lt), L("bone_sawn"), { limbItem, limbItem .. "p", "suture" }, lt,
					{ note = L("note_bone_sawn_options") })
				local rec = out[#out]
				if rec.key == "sawn" .. tostring(lt) then rec.op, rec.opLimb = "open", lt end
			end
		end
	end

	local function sutureOffered(lt)
		for _, rec in ipairs(out) do
			if rec.opLimb == lt then
				for _, id in ipairs(rec.items) do
					if id == "suture" then return true end
				end
			end
		end
		return false
	end
	local shock = c.a("traumaticshock")
	for _, lt in ipairs(R.Limbs) do
		if c.la(lt, "surgeryincision") >= 1 and not sutureOffered(lt) then
			if shock > 20 then
				add(2, "open" .. tostring(lt), L("traumatic_shock"), { "suture" }, lt, { note = L("note_shock"), sev = shock })
			else
				add(3, "open" .. tostring(lt), L("surgery_open"), { "suture" }, lt)
			end
			local rec = out[#out]
			if rec.key == "open" .. tostring(lt) then rec.op, rec.opLimb = "open", lt end
		end
	end
	if shock > 20 and not incisionOpen then
		add(shock > 30 and 2 or 3, "shock", L("traumatic_shock"), { "propofol" }, nil, { note = L("note_shock_calm"), sev = shock })
	end

	local pain = math.max(c.a("severepain"), c.a("pain_chest") / 5, c.a("pain_abdominal") / 5)
	if pain > 0.5 and c.a("analgesia") < 5 and overdose < 20 then
		add(4, "pain", L("pain"), { "antidama1", "antidama2" }, nil, { sev = pain })
	end

	local organ = 0
	for _, id in ipairs(ORGANS) do
		local v = c.a(id)
		if v < 99 then organ = math.max(organ, v) end
	end
	if organ > 30 and c.a("afthiamine") < 1 then add(4, "organs", L("organ_damage"), { "thiamine" }, nil, { sev = organ }) end

	local withdrawal = c.a("alcoholwithdrawal")
	if withdrawal > 20 then add(4, "withdrawal_alc", L("withdrawal"), { "antipsychosis" }, nil, { sev = withdrawal }) end
	local chem = c.a("chemwithdrawal")
	if chem > 20 then
		add(4, "withdrawal_chem", L("withdrawal_chem"), R.SuitableItems("chemwithdrawal"), nil,
			{ note = L("note_withdrawal_chem"), sev = chem })
	end

	local opWithdrawal, opAddiction = c.a("opiatewithdrawal"), c.a("opiateaddiction")
	if (opWithdrawal > 20 or opAddiction >= 20) and not incisionOpen then
		local text = opWithdrawal > 20 and L("withdrawal_opiate") or L("addiction_opiate")
		add(opWithdrawal > 40 and 3 or 4, "withdrawal_opiate", text, { "antinarc" }, nil,
			{ note = L("note_naloxone"), sev = math.max(opWithdrawal, opAddiction) })
	end

	local risks = {}
	for _, rec in ipairs(out) do
		local lt = rec.limb or rec.opLimb
		local hasSuture = false
		for _, id in ipairs(rec.items) do
			if id == "suture" then hasSuture = true end
		end
		if lt ~= nil and hasSuture and (rec.op == nil or rec.op == "open") then
			if risks[lt] == nil then
				local warning, pending = S.SutureRisk(c, lt, nil)
				risks[lt] = { warning = warning, pending = pending }
			end
			local risk = risks[lt]
			if risk.warning ~= nil and (rec.note == nil or rec.note:find(risk.warning, 1, true) == nil) then
				rec.note = rec.note ~= nil and (rec.note .. "; " .. risk.warning) or risk.warning
				rec.warnOps = risk.pending
				rec.opLimb = rec.opLimb or lt
			end
		end
	end

	for _, rec in ipairs(out) do
		if rec.warnOps ~= nil then
			for _, opDef in ipairs(rec.warnOps) do
				for _, other in ipairs(out) do
					if other.op == opDef.id and other.opLimb == rec.opLimb and other.single then
						other.prio = math.min(other.prio, rec.prio)
						other.rank = math.min(other.rank, rec.rank)
						other.sev = math.max(other.sev, rec.sev + 1)
						if other.order > rec.order then other.order = rec.order - 0.5 end
					end
				end
			end
		end
	end

	table.sort(out, function(a, b)
		if a.prio ~= b.prio then return a.prio < b.prio end
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.sev ~= b.sev then return a.sev > b.sev end
		return a.order < b.order
	end)
	return out
end

local suitableCache = {}
function R.SuitableItems(afflictionId)
	local cached = suitableCache[afflictionId]
	if cached == nil then
		cached = {}
		local scored = {}
		local key = Identifier(afflictionId)
		for prefab in ItemPrefab.Prefabs do
			local ok, value = pcall(function() return prefab.GetTreatmentSuitability(key) end)
			if ok and value ~= nil and value > 0 and prefab.UseInHealthInterface then
				table.insert(scored, { id = prefab.Identifier.Value, value = value })
			end
		end
		table.sort(scored, function(a, b) return a.value > b.value end)
		for i = 1, math.min(#scored, 4) do table.insert(cached, scored[i].id) end
		suitableCache[afflictionId] = cached
	end
	local copy = {}
	for _, id in ipairs(cached) do table.insert(copy, id) end
	return copy
end
