-- AllForOne: arena analyzer — recording, analysis and history
-- Records every arena match from the combat log (what 3.3.5 shows within ~50 yards) and, when
-- the match ends, turns it into a report: notes on likely mistakes, a death recap, stats and a
-- short timeline. The last 50 matches are kept (older ones are deleted); per-enemy history
-- (died first, wasted trinket, unused defensive...) is built from those same 50 matches, so it
-- ages out with them. The kill target helper reads that history.
local _, ns = ...
local GetTime = GetTime

local MAX_MATCHES = 50
local A = {}
ns.Analyzer = A

----------------------------------------------------------------------
-- Spell data (spell IDs -> localized names at login)
----------------------------------------------------------------------
local INTERRUPTS = { 1766, 6552, 72, 2139, 57994, 47528, 19647 } -- Kick, Pummel, Shield Bash, Counterspell, Wind Shear, Mind Freeze, Spell Lock
-- silences that come with an interrupt: talents (Improved Counterspell, Improved Kick, Gag Order)
-- and Spell Lock. A kick that lands one of these on a target that wasn't casting is a silence, not a miss.
local KICK_SILENCES = { 18469, 55021, 18425, 18498, 24259 }
local SILENCE_TALENTS = { 11255, 13754, 12311 } -- Improved Counterspell, Improved Kick, Gag Order
local ENEMY_KICKS = {
	ROGUE = { 1766 }, WARRIOR = { 6552, 72 }, MAGE = { 2139 }, SHAMAN = { 57994 },
	DEATHKNIGHT = { 47528, 47476 }, WARLOCK = { 19647 }, PRIEST = { 15487 }, HUNTER = { 34490 },
}
local HEALS = { 48071, 48063, 48782, 48785, 49273, 49276, 1064, 48378, 48443, 50464, 53007, 48072, 55459, 64843 }
-- your own big defensives: "early" = used at high health with little damage coming in
local EARLY_CHECK = { 45438, 642, 871, 48792, 61336, 498 } -- Ice Block, Divine Shield, Shield Wall, IBF, Survival Instincts, Divine Protection
-- what could have saved you (reported when you die with it ready)
local LIFESAVERS = {
	MAGE = { 45438 }, PALADIN = { 642, 498, 10278 }, ROGUE = { 31224, 26669, 26889 }, WARRIOR = { 871 },
	HUNTER = { 19263 }, PRIEST = { 33206, 47585, 47788 }, DRUID = { 22812, 61336 }, SHAMAN = { 30823 },
	DEATHKNIGHT = { 48792, 48707 }, WARLOCK = {},
}
-- enemy defensives (for "used early" / "died without using it")
local ENEMY_DEFENSIVES = {
	MAGE = { 45438 }, PALADIN = { 642, 498 }, ROGUE = { 31224, 26669 }, WARRIOR = { 871 }, HUNTER = { 19263 },
	PRIEST = { 33206, 47585 }, DRUID = { 22812, 61336 }, SHAMAN = { 30823 }, DEATHKNIGHT = { 48792 }, WARLOCK = {},
}
local HEALER_SPECS = { Holy = true, Discipline = true, Restoration = true }

local N = {}      -- id -> name
local IS = {}     -- set name -> kind
local function Name(id)
	if not N[id] then N[id] = GetSpellInfo(id) or ("#" .. id) end
	return N[id]
end

local function BuildSets()
	IS.interrupt, IS.heal, IS.early = {}, {}, {}
	for _, id in ipairs(INTERRUPTS) do IS.interrupt[Name(id)] = true end
	for _, id in ipairs(HEALS) do IS.heal[Name(id)] = true end
	for _, id in ipairs(EARLY_CHECK) do IS.early[Name(id)] = true end
	IS.enemyDef = {}
	for class, ids in pairs(ENEMY_DEFENSIVES) do
		IS.enemyDef[class] = {}
		for _, id in ipairs(ids) do IS.enemyDef[class][Name(id)] = true end
	end
	IS.lifesaver = {}
	for class, ids in pairs(LIFESAVERS) do
		IS.lifesaver[class] = {}
		for _, id in ipairs(ids) do IS.lifesaver[class][#IS.lifesaver[class] + 1] = Name(id) end
	end
	IS.grounding = Name(8177)
	IS.kickSilence = {}
	for _, id in ipairs(KICK_SILENCES) do IS.kickSilence[Name(id)] = true end
end

-- do you have a talent that makes your interrupt silence too?
local hasSilenceTalent = false -- checked at login and when talents change, not per match
local function HasSilenceTalent()
	if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return false end
	local want = {}
	for _, id in ipairs(SILENCE_TALENTS) do want[Name(id)] = true end
	for tab = 1, GetNumTalentTabs() do
		for i = 1, GetNumTalents(tab) do
			local name, _, _, _, rank = GetTalentInfo(tab, i)
			if name and want[name] and (rank or 0) > 0 then return true end
		end
	end
	return false
end

----------------------------------------------------------------------
-- Saved data
----------------------------------------------------------------------
local function DB()
	ns.db.analyzer = ns.db.analyzer or {}
	local d = ns.db.analyzer
	d.matches = d.matches or {}
	d.nextId = d.nextId or 1
	return d
end

function A:Matches() return DB().matches end

local function Store(m)
	local d = DB()
	m.id = d.nextId
	d.nextId = d.nextId + 1
	table.insert(d.matches, m)
	-- keep only the newest 50: older matches are deleted
	while #d.matches > MAX_MATCHES do table.remove(d.matches, 1) end
	A.historyCache = nil
end

function A:Reset()
	local d = DB()
	wipe(d.matches)
	A.historyCache = nil
end

-- "Name" or "Name-Realm" (cross-realm), the same key everywhere
function ns:FullName(unit)
	local name, realm = UnitName(unit)
	if not name then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

----------------------------------------------------------------------
-- Live match state
----------------------------------------------------------------------
local M          -- current match being recorded (nil outside arenas)
local log = {}   -- rolling log of the last 15s of events around your team (for death recaps)

local function Now() return GetTime() end
local function Clock(t)
	if not M or not M.start then return 0 end
	return math.max(0, t - M.start)
end
local function Fmt(sec)
	sec = math.max(0, floor(sec + 0.5))
	return format("%d:%02d", floor(sec / 60), sec % 60)
end
A.Fmt = Fmt

local function Timeline(text, t)
	if not M or #M.timeline >= 60 then return end
	M.timeline[#M.timeline + 1] = { t = Clock(t or Now()), text = text }
end

local function Note(kind, text, weight)
	if not M then return end
	M.notes[#M.notes + 1] = { kind = kind, text = text, w = weight or 1 }
end

local function Count(tbl, key, n) tbl[key] = (tbl[key] or 0) + (n or 1) end

local function Log(e)
	e.t = Now()
	-- keep only the last 15 seconds
	local cut, first = e.t - 15, 1
	while log[first] and log[first].t < cut do first = first + 1 end
	if first > 1 then
		local keep = {}
		for i = first, #log do keep[#keep + 1] = log[i] end
		log = keep
	end
	log[#log + 1] = e
end

-- who is who (refreshed every tick)
local team, enemies, pets = {}, {}, {}   -- guid -> unit / guid -> info
local function RefreshUnits()
	wipe(team)
	for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
		local g = UnitGUID(u)
		if g then
			team[g] = u
			-- remember who played on your team (they may leave before the report is made)
			if M then
				local t = M.teamSeen[g] or {}
				M.teamSeen[g] = t
				t.name = t.name or ns:FullName(u)
				t.class = t.class or select(2, UnitClass(u))
				t.spec = (u == "player") and M.mySpec or ns.specs[g] or t.spec
				t.order = t.order or (u == "player" and 0 or tonumber(u:match("%d")) or 9)
			end
		end
	end
	wipe(pets)
	for _, u in ipairs({ "pet", "partypet1", "partypet2", "partypet3", "partypet4" }) do
		local g = UnitGUID(u)
		if g then pets[g] = "team" end
	end
	for i = 1, 5 do
		local u = "arena" .. i
		local g = UnitGUID(u)
		if g and M then
			local e = M.enemyByGUID[g]
			if not e then
				e = { guid = g, unit = u, name = ns:FullName(u) or u, class = select(2, UnitClass(u)), n = i,
					trinkets = 0, trinketEarly = 0, defUsed = {}, defEarly = 0, ccTime = 0, interrupted = 0, dmgTaken = 0 }
				M.enemyByGUID[g] = e
				M.enemies[#M.enemies + 1] = e
			end
			e.unit = u
			e.class = e.class or select(2, UnitClass(u))
			e.spec = ns.specs[g] or e.spec
			enemies[g] = e
		end
		local pg = UnitGUID("arenapet" .. i)
		if pg then pets[pg] = "enemy" end
	end
end

local function IsTeam(g) return team[g] ~= nil or pets[g] == "team" end
local function IsEnemy(g) return enemies[g] ~= nil or pets[g] == "enemy" end
local function Me() return UnitGUID("player") end
local function MyPet() return UnitGUID("pet") end
local function FromMe(g) return g and (g == Me() or g == MyPet()) end

local function HealthPct(unit)
	local max = UnitHealthMax(unit)
	if not max or max == 0 then return 1 end
	return UnitHealth(unit) / max
end

----------------------------------------------------------------------
-- Your trinket / defensives readiness
----------------------------------------------------------------------
local function TrinketReady()
	for _, slot in ipairs({ 13, 14 }) do
		local link = GetInventoryItemLink("player", slot)
		local spell = link and GetItemSpell(link)
		if spell and ns.Trinket[spell] then
			local start, dur = GetInventoryItemCooldown("player", slot)
			return not start or start == 0 or (start + dur - GetTime() <= 0)
		end
	end
	-- Every Man for Himself (human racial) works like a trinket
	local emfh = Name(59752)
	if GetSpellInfo(emfh) then
		local start, dur = GetSpellCooldown(emfh)
		return not start or start == 0 or (start + dur - GetTime() <= 1.5)
	end
	return nil -- no trinket: never nag about it
end

local function SpellReady(name)
	if not GetSpellInfo(name) then return false end -- you don't know this spell
	local start, dur = GetSpellCooldown(name)
	if not start or start == 0 then return true end
	return dur <= 1.5 or (start + dur - GetTime() <= 1.5) -- global cooldown only
end

-- hard crowd control on you right now: name, category, time left, total duration
local function MyHardCC()
	for i = 1, 40 do
		local name, _, _, _, _, dur, expires = UnitAura("player", i, "HARMFUL")
		if not name then break end
		local cc = ns.CC[name]
		if cc and (ns.ccPriority[cc.cat] or 0) >= 7 then
			return name, cc.cat, expires and expires > 0 and (expires - GetTime()) or nil, dur
		end
	end
end

local function DamageIn(seconds)
	if not M then return 0 end
	local cut, sum = Now() - seconds, 0
	for i = #M.dmgRing, 1, -1 do
		local d = M.dmgRing[i]
		if d.t < cut then break end
		sum = sum + d.a
	end
	return sum
end

----------------------------------------------------------------------
-- Start / finish
----------------------------------------------------------------------
local function Bracket()
	for i = 1, (MAX_BATTLEFIELD_QUEUES or 3) do
		local st, _, _, _, _, size = GetBattlefieldStatus(i)
		if st == "active" and size and size > 0 then return size end
	end
end

local function MySpec()
	local best, bestPts
	for i = 1, 3 do
		local name, _, pts = GetTalentTabInfo(i)
		if name and pts and (not bestPts or pts > bestPts) then best, bestPts = name, pts end
	end
	return best
end

local function Begin()
	if M or ns.db.analyzerOn == false then return end
	M = {
		date = date("%Y-%m-%d %H:%M"), map = GetRealZoneText() or "?", bracket = Bracket(),
		start = nil, entered = Now(),
		myClass = select(2, UnitClass("player")), mySpec = MySpec(),
		enemies = {}, enemyByGUID = {}, teamInfo = {}, teamSeen = {},
		notes = {}, timeline = {}, deaths = {},
		cc = { onMe = {}, onMeTime = 0, bySource = {}, mine = 0, mineTime = 0, wasted = 0, immune = 0, reflected = 0,
			grounded = 0, quarter = 0, broken = 0, overlap = 0 },
		trinket = { uses = {}, held = {} },
		defs = { used = {}, early = {} },
		kicks = { cast = 0, landed = 0, missed = 0, silenced = 0, silenceTalent = hasSilenceTalent, onHeal = 0, onCC = 0, onDamage = 0, reaction = {}, taken = 0, takenIntoReady = 0, lockedSchools = {} },
		dmg = { done = 0, doneOn = {}, onKill = 0, taken = 0, takenFrom = {}, burst = 0, burstAt = 0, burstSpells = {} },
		heal = { done = 0, over = 0, received = 0 },
		dispels = { cleanse = 0, purge = 0, enemy = 0 },
		range = { combat = 0, outHealer = 0, mateOut = 0, noTarget = 0 },
		dmgRing = {},
		openCC = {}, myCCOn = {}, ccActive = {}, pendingKicks = {}, castStart = {}, lastCast = nil,
	}
	wipe(log)
	RefreshUnits()
end

local function GatesOpen()
	if M and not M.start then
		M.start = Now()
		Timeline("Gates open")
		-- ask for the scoreboard now, so it's there to tell the teams apart at the end
		if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
	end
end

-- team comps and per-enemy facts, then notes
local function Finish(result)
	if not M then return end
	local m = M
	M = nil
	if not m.start then return end -- never got past the gates: nothing to report
	local now = Now()
	m.duration = now - m.start
	m.result = result
	-- close open CC on you
	for spell, o in pairs(m.openCC) do
		local d = now - o.t
		m.cc.onMeTime = m.cc.onMeTime + d
		Count(m.cc.onMe, o.cat, d)
	end
	-- our team
	for g, t in pairs(m.teamSeen) do
		m.teamInfo[#m.teamInfo + 1] = { name = t.name, class = t.class, spec = t.spec or ns.specs[g], order = t.order }
	end
	table.sort(m.teamInfo, function(a, b) return (a.order or 9) < (b.order or 9) end)
	for _, e in ipairs(m.enemies) do e.spec = e.spec or ns.specs[e.guid] end
	local classes = {}
	for _, e in ipairs(m.enemies) do classes[#classes + 1] = e.class or "?" end
	table.sort(classes)
	m.comp = table.concat(classes, "+")
	A:Analyze(m)
	-- trim live-only fields before saving
	m.dmgRing, m.openCC, m.myCCOn, m.ccActive, m.pendingKicks, m.castStart, m.lastCast, m.enemyByGUID, m.teamSeen = nil, nil, nil, nil, nil, nil, nil, nil, nil
	for _, e in ipairs(m.enemies) do e.unit, e.guid, e.firstHurt = nil, nil, nil end
	Store(m)
	ns:Send("ANALYZER_MATCH", m)
end
A.Finish = Finish

----------------------------------------------------------------------
-- Combat log
----------------------------------------------------------------------
local function OnCC(event, src, srcName, dst, dstName, spell)
	local cc = ns.CC[spell]
	if not cc then return end
	local now = Now()
	if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
		-- on you
		if dst == Me() and not M.openCC[spell] then
			M.openCC[spell] = { t = now, cat = cc.cat }
			Count(M.cc.bySource, srcName or "?")
		end
		if IsTeam(dst) then Log({ k = "cc", dst = dst, spell = spell, src = srcName }) end
		-- on an enemy
		if IsEnemy(dst) then
			M.ccActive[dst] = M.ccActive[dst] or {}
			if FromMe(src) then
				M.cc.mine = M.cc.mine + 1
				-- overlapping a teammate's crowd control
				for other, o in pairs(M.ccActive[dst]) do
					if other ~= spell and not FromMe(o.src) and IsTeam(o.src) and o.expires - now > 1 then
						M.cc.overlap = M.cc.overlap + 1
						break
					end
				end
				-- landed at a quarter of its duration (diminishing returns)
				local s = ns.dr[dst] and ns.dr[dst][cc.cat]
				if s and s.count == 3 and ns.drCategories[cc.cat] then M.cc.quarter = M.cc.quarter + 1 end
				M.myCCOn[dst .. spell] = now
			end
			M.ccActive[dst][spell] = { src = src, t = now, expires = now + (cc.dur or 6) }
		end
	elseif event == "SPELL_AURA_REMOVED" or event == "SPELL_AURA_BROKEN" or event == "SPELL_AURA_BROKEN_SPELL" then
		if dst == Me() and M.openCC[spell] then
			local d = now - M.openCC[spell].t
			M.cc.onMeTime = M.cc.onMeTime + d
			Count(M.cc.onMe, M.openCC[spell].cat, d)
			M.openCC[spell] = nil
		end
		if IsEnemy(dst) and M.ccActive[dst] and M.ccActive[dst][spell] then
			local o = M.ccActive[dst][spell]
			local e = enemies[dst]
			if e then e.ccTime = e.ccTime + (now - o.t) end
			M.ccActive[dst][spell] = nil
			local mine = M.myCCOn[dst .. spell]
			if mine then
				M.cc.mineTime = M.cc.mineTime + (now - mine)
				M.myCCOn[dst .. spell] = nil
				-- broken within 3s by your own team's damage
				if event ~= "SPELL_AURA_REMOVED" and now - mine < 3 and IsTeam(src) then
					M.cc.broken = M.cc.broken + 1
				end
			end
		end
	end
end

local function OnDamage(src, srcName, dst, dstName, spell, amount)
	if not amount or amount <= 0 then return end
	local now = Now()
	if FromMe(src) then
		M.dmg.done = M.dmg.done + amount
		Count(M.dmg.doneOn, dstName or "?", amount)
		if ns.killName and dstName and (dstName == ns.killName or dstName:match("^[^-]+") == ns.killName) then
			M.dmg.onKill = M.dmg.onKill + amount
		end
	end
	if IsEnemy(dst) then
		local e = enemies[dst]
		if e and IsTeam(src) then e.dmgTaken = e.dmgTaken + amount end
	end
	if dst == Me() then
		M.dmg.taken = M.dmg.taken + amount
		Count(M.dmg.takenFrom, spell or "Melee", amount)
		local ring = M.dmgRing
		ring[#ring + 1] = { t = now, a = amount, s = spell or "Melee" }
		while ring[1] and ring[1].t < now - 3 do table.remove(ring, 1) end
		local sum, spells = 0, {}
		for _, d in ipairs(ring) do sum = sum + d.a; Count(spells, d.s, d.a) end
		if sum > M.dmg.burst then
			M.dmg.burst, M.dmg.burstAt, M.dmg.burstSpells = sum, Clock(now), spells
		end
	end
	if IsTeam(dst) then Log({ k = "dmg", dst = dst, spell = spell or "Melee", src = srcName, a = amount }) end
end

local function OnCast(src, srcName, spell)
	local now = Now()
	-- your interrupts: resolved a moment later (landed / missed)
	if FromMe(src) and IS.interrupt[spell] then
		M.kicks.cast = M.kicks.cast + 1
		M.pendingKicks[#M.pendingKicks + 1] = { t = now, spell = spell }
	end
	-- trinkets
	if ns.Trinket[spell] then
		if src == Me() then
			local ccName, cat, left = MyHardCC()
			local soft
			if not ccName then
				-- maybe a root / silence / disarm
				for i = 1, 40 do
					local name = UnitAura("player", i, "HARMFUL")
					if not name then break end
					local c = ns.CC[name]
					if c then soft = name break end
				end
			end
			local use = { t = Clock(now), cc = ccName or soft, left = left }
			M.trinket.uses[#M.trinket.uses + 1] = use
			M.lastTrinket = now
			if not ccName then
				Note("trinket_early", soft and format("Trinketed %s (not a hard crowd control) at %s", soft, Fmt(Clock(now)))
					or format("Used your trinket with no crowd control on you at %s", Fmt(Clock(now))), 3)
			elseif left and left < 1.5 then
				Note("trinket_early", format("Trinketed %s with only %.1fs left at %s", ccName, left, Fmt(Clock(now))), 2)
			end
			Timeline("You trinketed " .. (ccName or soft or "nothing"))
		elseif IsEnemy(src) then
			local e = enemies[src]
			if e then
				e.trinkets = e.trinkets + 1
				local hard = false
				for s, o in pairs(M.ccActive[src] or {}) do
					local c = ns.CC[s]
					if c and (ns.ccPriority[c.cat] or 0) >= 7 and o.expires - now > 1.5 then hard = true end
				end
				if not hard then e.trinketEarly = e.trinketEarly + 1 end
				Timeline(format("#%d %s trinketed", e.n, e.name))
			end
		elseif IsTeam(src) then
			Log({ k = "trinket", src = srcName, dst = src })
		end
	end
	-- your defensives
	if src == Me() and IS.early[spell] then
		local hp = HealthPct("player")
		local recent = DamageIn(3) / math.max(1, UnitHealthMax("player"))
		local ccName = MyHardCC()
		M.defs.used[#M.defs.used + 1] = { spell = spell, t = Clock(now), hp = hp }
		if hp > 0.7 and recent < 0.15 and not ccName then
			Note("def_early", format("Used %s at %d%% health with little damage coming in (%s)", spell, floor(hp * 100 + 0.5), Fmt(Clock(now))), 2)
		end
		Timeline(format("You used %s at %d%%", spell, floor(hp * 100 + 0.5)))
	end
	-- defensives in general (death recaps / enemy facts)
	if team[src] and ns.CD[(select(2, UnitClass(team[src])) or "") .. ":" .. spell] then
		Log({ k = "cd", src = srcName, dst = src, spell = spell })
	end
	if IsEnemy(src) then
		local e = enemies[src]
		if e and e.class and IS.enemyDef[e.class] and IS.enemyDef[e.class][spell] then
			e.defUsed[spell] = true
			if e.unit and HealthPct(e.unit) > 0.7 then e.defEarly = e.defEarly + 1 end
			Timeline(format("#%d %s used %s", e.n, e.name, spell))
		end
	end
end

local function OnInterrupt(src, dst, extraSpell, extraSchool)
	local now = Now()
	if FromMe(src) then
		-- resolve the oldest pending kick
		local p = table.remove(M.pendingKicks, 1)
		M.kicks.landed = M.kicks.landed + 1
		if IS.heal[extraSpell or ""] then M.kicks.onHeal = M.kicks.onHeal + 1
		elseif ns.CC[extraSpell or ""] then M.kicks.onCC = M.kicks.onCC + 1
		else M.kicks.onDamage = M.kicks.onDamage + 1 end
		local cs = M.castStart[dst]
		if cs and cs.finish > cs.start and now <= cs.finish + 0.3 then
			M.kicks.reaction[#M.kicks.reaction + 1] = math.max(0, math.min(1, (now - cs.start) / (cs.finish - cs.start)))
		end
		local e = enemies[dst]
		if e then e.interrupted = e.interrupted + 1 end
		Timeline("You interrupted " .. (extraSpell or "a cast"))
	end
	if dst == Me() then
		M.kicks.taken = M.kicks.taken + 1
		if extraSchool then Count(M.kicks.lockedSchools, extraSchool) end
		local c = M.lastCast
		if c and c.readyKick and now <= c.finish + 0.5 then M.kicks.takenIntoReady = M.kicks.takenIntoReady + 1 end
	end
end

local function OnMissed(src, dst, dstName, spell, missType)
	if not FromMe(src) then return end
	if IS.interrupt[spell] then
		-- the kick was dodged / parried / hit an immunity: count it once, now
		local p = table.remove(M.pendingKicks, 1)
		if p then M.kicks.missed = M.kicks.missed + 1 end
		return
	end
	if ns.CC[spell] then
		if missType == "IMMUNE" then M.cc.immune = M.cc.immune + 1; M.cc.wasted = M.cc.wasted + 1
		elseif missType == "REFLECT" then M.cc.reflected = M.cc.reflected + 1; M.cc.wasted = M.cc.wasted + 1 end
	end
end

local function OnDeath(dst, dstName)
	local now = Now()
	local who = IsTeam(dst) and "us" or (IsEnemy(dst) and "them") or nil
	if not who or pets[dst] then return end
	-- Feign Death and similar: still has health, so not really dead
	local unit = team[dst] or (enemies[dst] and enemies[dst].unit)
	if unit and UnitExists(unit) and (UnitHealth(unit) or 0) > 0 then return end
	local d = { name = dstName or "?", side = who, t = Clock(now), first = (#M.deaths == 0) }
	if who == "them" then
		local e = enemies[dst]
		if e then
			e.died = true
			e.diedFirst = d.first
			d.class = e.class
			if e.firstHurt then e.ttd = now - e.firstHurt end
			-- died with a big defensive never used this match
			local unused = {}
			for spell in pairs(IS.enemyDef[e.class or ""] or {}) do
				if not e.defUsed[spell] then unused[#unused + 1] = spell end
			end
			e.unusedDef = #unused > 0
		end
		Timeline(format("%s died", dstName or "?"))
	else
		d.class = select(2, UnitClass(team[dst] or "player"))
		-- death recap: the 10 seconds before
		local recap = { dmg = {}, cc = {}, cds = {}, total = 0, trinket = nil }
		for _, l in ipairs(log) do
			if now - l.t <= 10 then
				if l.k == "dmg" and l.dst == dst then
					recap.total = recap.total + l.a
					Count(recap.dmg, l.spell .. " (" .. (l.src or "?") .. ")", l.a)
				elseif l.k == "cc" then
					recap.cc[#recap.cc + 1] = format("%s on %s", l.spell, (l.dst == dst) and "them" or (UnitName(team[l.dst] or "") or "?"))
				elseif l.k == "cd" and l.dst == dst then
					recap.cds[#recap.cds + 1] = l.spell
				elseif l.k == "trinket" and l.dst == dst then
					recap.trinket = true
				end
			end
		end
		if dst == Me() then
			recap.trinketUsed = M.lastTrinket and (now - M.lastTrinket) < 120 or false
			local ready = {}
			for _, spell in ipairs(IS.lifesaver[M.myClass or ""] or {}) do
				if SpellReady(spell) then ready[#ready + 1] = spell end
			end
			if TrinketReady() then Note("died_trinket", "You died with your trinket ready", 3) end
			if #ready > 0 then Note("died_def", "You died with " .. table.concat(ready, ", ") .. " ready", 3) end
		end
		d.recap = recap
		Timeline(format("%s died", dstName or "?"))
	end
	M.deaths[#M.deaths + 1] = d
end

ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, event, src, srcName, _, dst, dstName, _, a1, a2, a3, a4, a5, a6)
	if not M then return end
	-- gates fallback: the first hit between the teams starts the clock
	if not M.start and (event:find("_DAMAGE$") or event == "SPELL_AURA_APPLIED") and
		((IsTeam(src) and IsEnemy(dst)) or (IsEnemy(src) and IsTeam(dst))) then
		GatesOpen()
	end
	if event == "SWING_DAMAGE" then
		OnDamage(src, srcName, dst, dstName, nil, a1)
	elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "RANGE_DAMAGE" then
		OnDamage(src, srcName, dst, dstName, a2, a4)
		if FromMe(src) and dstName == IS.grounding and ns.CC[a2 or ""] then M.cc.grounded = M.cc.grounded + 1; M.cc.wasted = M.cc.wasted + 1 end
	elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
		local amount, over = a4 or 0, a5 or 0
		if FromMe(src) then M.heal.done = M.heal.done + amount; M.heal.over = M.heal.over + over end
		if dst == Me() then M.heal.received = M.heal.received + (amount - over) end
	elseif event == "SPELL_CAST_SUCCESS" then
		OnCast(src, srcName, a2)
	elseif event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" or event == "SPELL_AURA_REMOVED"
		or event == "SPELL_AURA_BROKEN" or event == "SPELL_AURA_BROKEN_SPELL" then
		if FromMe(src) and dstName == IS.grounding and ns.CC[a2 or ""] and event == "SPELL_AURA_APPLIED" then
			M.cc.grounded = M.cc.grounded + 1; M.cc.wasted = M.cc.wasted + 1
		end
		-- your kick silenced the target (talent / Spell Lock): it did something even with no cast to stop
		if event == "SPELL_AURA_APPLIED" and FromMe(src) and IS.kickSilence[a2 or ""] and IsEnemy(dst) then
			local now = Now()
			for _, p in ipairs(M.pendingKicks) do
				if not p.silenced and now - p.t <= 0.6 then p.silenced = true break end
			end
		end
		OnCC(event, src, srcName, dst, dstName, a2)
	elseif event == "SPELL_INTERRUPT" then
		OnInterrupt(src, dst, a5, a6)
	elseif event == "SPELL_MISSED" or event == "RANGE_MISSED" then
		OnMissed(src, dst, dstName, a2, a4)
	elseif event == "SPELL_DISPEL" then
		if FromMe(src) then
			if IsTeam(dst) then M.dispels.cleanse = M.dispels.cleanse + 1 else M.dispels.purge = M.dispels.purge + 1 end
		elseif IsEnemy(src) and IsTeam(dst) then
			M.dispels.enemy = M.dispels.enemy + 1
		end
	elseif event == "UNIT_DIED" then
		OnDeath(dst, dstName)
	end
end)

-- enemy cast starts (interrupt reaction time) and your own casts (kicked into a ready interrupt)
local function CastStarted(unit)
	if not M then return end
	local _, _, _, _, startMs, endMs = UnitCastingInfo(unit)
	if not startMs then _, _, _, _, startMs, endMs = UnitChannelInfo(unit) end
	if not startMs then return end
	if unit == "player" then
		local ready = false
		if endMs - startMs >= 1500 then
			for g, e in pairs(enemies) do
				for _, id in ipairs(ENEMY_KICKS[e.class or ""] or {}) do
					local c = ns.cds[g] and ns.cds[g][Name(id)]
					if not c or (c.start + c.dur <= GetTime()) then ready = true end
				end
			end
		end
		M.lastCast = { start = startMs / 1000, finish = endMs / 1000, readyKick = ready }
	else
		local g = UnitGUID(unit)
		if g then M.castStart[g] = { start = startMs / 1000, finish = endMs / 1000 } end
	end
end
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START" }) do
	ns:On(ev, function(_, unit)
		if unit == "player" or (unit and unit:match("^arena%d$")) then CastStarted(unit) end
	end)
end

----------------------------------------------------------------------
-- Once a second: units, kicks that hit nothing, range, trinket held, enemy health
----------------------------------------------------------------------
local function Tick()
	if not M then return end
	RefreshUnits()
	local now = Now()
	-- kicks with no interrupt after 0.6s: a silence (talent / Spell Lock) if one landed, otherwise a miss
	while M.pendingKicks[1] and now - M.pendingKicks[1].t > 0.6 do
		local p = table.remove(M.pendingKicks, 1)
		if p.silenced then
			M.kicks.silenced = (M.kicks.silenced or 0) + 1
		else
			M.kicks.missed = M.kicks.missed + 1
		end
	end
	if not M.start then return end
	-- enemies: when they first got hurt (for "time to die")
	for g, e in pairs(enemies) do
		if e.unit and not e.firstHurt and UnitExists(e.unit) and HealthPct(e.unit) < 0.8 then e.firstHurt = now end
	end
	if not UnitAffectingCombat("player") then return end
	M.range.combat = M.range.combat + 1
	-- range to your healer / your teammates in range of you
	local iHeal = HEALER_SPECS[M.mySpec or ""]
	if iHeal then
		for i = 1, 4 do
			local u = "party" .. i
			if UnitExists(u) and not UnitIsDeadOrGhost(u) and not UnitInRange(u) then M.range.mateOut = M.range.mateOut + 1 break end
		end
	else
		for i = 1, 4 do
			local u = "party" .. i
			local g = UnitGUID(u)
			if g and HEALER_SPECS[ns.specs[g] or ""] and not UnitIsDeadOrGhost(u) and not UnitIsDeadOrGhost("player") then
				if not UnitInRange(u) then M.range.outHealer = M.range.outHealer + 1 end
				M.hasHealer = true
				break
			end
		end
		if not (UnitExists("target") and UnitCanAttack("player", "target")) then M.range.noTarget = M.range.noTarget + 1 end
	end
	-- sitting in a long crowd control with your trinket ready while a teammate is dying
	local ccName, _, left, dur = MyHardCC()
	if ccName and dur and dur >= 4 and left and left > 2 and TrinketReady() then
		for i = 1, 4 do
			local u = "party" .. i
			if UnitExists(u) and not UnitIsDeadOrGhost(u) and HealthPct(u) < 0.3 then
				local key = ccName .. floor(now - (dur - left))
				if not M.trinket.held[key] then
					M.trinket.held[key] = true
					Note("trinket_held", format("Sat in %s (%ds) with your trinket ready while %s was at %d%% (%s)",
						ccName, floor(dur + 0.5), UnitName(u) or "a teammate", floor(HealthPct(u) * 100 + 0.5), Fmt(Clock(now))), 3)
				end
				break
			end
		end
	end
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, e)
	acc = acc + e
	if acc < 1 then return end
	acc = 0
	local ok, err = pcall(Tick)
	if not ok then ns:Report(err) end
end)

----------------------------------------------------------------------
-- Match life cycle
----------------------------------------------------------------------
local function Zone()
	if ns:InArena() then
		Begin()
	elseif M then
		Finish("left")
	end
end
ns:On("PLAYER_ENTERING_WORLD", Zone)
ns:On("ZONE_CHANGED_NEW_AREA", Zone)
ns:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", function(_, msg)
	if M and msg and msg:find("has begun") then GatesOpen() end
end)
ns:On("ARENA_OPPONENT_UPDATE", function() if M then RefreshUnits() end end)
-- Win or loss. Servers don't all number the teams the same way, so this doesn't rely on one
-- call: first who died (everyone on one side dead = clear result), then your own team as
-- the scoreboard lists it compared with the winner, and only then the arena faction call.
local function MyScoreTeam()
	if not GetNumBattlefieldScores or not GetBattlefieldScore then return nil end
	local me = UnitName("player")
	for i = 1, GetNumBattlefieldScores() or 0 do
		local name, _, _, _, _, team = GetBattlefieldScore(i)
		if name and (name == me or name:match("^[^-]+") == me) then return team end
	end
end

local function ResultFromDeaths(m)
	local theirs, theirsDead = #m.enemies, 0
	for _, e in ipairs(m.enemies) do if e.died then theirsDead = theirsDead + 1 end end
	local oursDead = 0
	for _, d in ipairs(m.deaths) do if d.side == "us" then oursDead = oursDead + 1 end end
	local ours = 0
	for _ in pairs(m.teamSeen or {}) do ours = ours + 1 end
	if theirs > 0 and theirsDead >= theirs and oursDead < math.max(1, ours) then return "win" end
	if ours > 0 and oursDead >= ours and theirsDead < theirs then return "loss" end
end

local function DecideResult(winner)
	if winner == 255 then return "draw" end
	local byDeaths = M and ResultFromDeaths(M)
	if byDeaths then return byDeaths end
	local team = MyScoreTeam()
	if team == nil and GetBattlefieldArenaFaction then team = GetBattlefieldArenaFaction() end
	if team == nil then return "loss" end
	return (winner == team) and "win" or "loss"
end
A.DecideResult = DecideResult

ns:On("UPDATE_BATTLEFIELD_STATUS", function()
	if not M or not GetBattlefieldWinner then return end
	local winner = GetBattlefieldWinner()
	if winner == nil then return end
	Finish(DecideResult(winner))
end)

-- the report window can correct a stored result by hand
function A:SetResult(m, result)
	if m and not m.test then
		m.result = result
		A.historyCache = nil
	end
end

----------------------------------------------------------------------
-- Analysis: notes from the numbers (also used for the test report)
----------------------------------------------------------------------
function A:Analyze(m)
	local function Add(kind, text, w) m.notes[#m.notes + 1] = { kind = kind, text = text, w = w or 1 } end
	local k = m.kicks
	-- interrupts
	if k.missed >= 2 then
		Add("kick_missed", format("%d of your %d interrupts missed (%s)", k.missed, k.cast,
			k.silenceTalent and "dodged, parried or hit an immunity" or "dodged, or the target wasn't casting"), 2)
	end
	if k.taken >= 2 and k.takenIntoReady >= 2 then
		Add("kicked_ready", format("You were interrupted %d times; %d were long casts started while their interrupt was ready - fake-cast first", k.taken, k.takenIntoReady), 2)
	end
	-- your crowd control
	if m.cc.wasted >= 1 then
		local parts = {}
		if m.cc.immune > 0 then parts[#parts + 1] = m.cc.immune .. " immune (diminishing returns)" end
		if m.cc.reflected > 0 then parts[#parts + 1] = m.cc.reflected .. " reflected" end
		if m.cc.grounded > 0 then parts[#parts + 1] = m.cc.grounded .. " grounded" end
		Add("cc_wasted", format("%d of your crowd controls were wasted: %s", m.cc.wasted, table.concat(parts, ", ")), 2)
	end
	if m.cc.quarter >= 2 then Add("cc_quarter", format("%d crowd controls landed at a quarter of their duration (diminishing returns)", m.cc.quarter), 1) end
	if m.cc.broken >= 1 then Add("cc_broken", format("Your team broke your crowd control early %d time%s", m.cc.broken, m.cc.broken > 1 and "s" or ""), 2) end
	if m.cc.overlap >= 2 then Add("cc_overlap", format("You overlapped a teammate's crowd control %d times (wastes both, stacks diminishing returns)", m.cc.overlap), 1) end
	-- range
	if m.range.combat >= 20 then
		if m.hasHealer and m.range.outHealer / m.range.combat >= 0.2 then
			Add("out_of_range", format("Out of your healer's range for %ds (%d%% of the fight)", m.range.outHealer, floor(m.range.outHealer / m.range.combat * 100 + 0.5)), 2)
		end
		if HEALER_SPECS[m.mySpec or ""] and m.range.mateOut / m.range.combat >= 0.2 then
			Add("out_of_range", format("A teammate was out of your range for %ds (%d%% of the fight)", m.range.mateOut, floor(m.range.mateOut / m.range.combat * 100 + 0.5)), 2)
		end
	end
	-- focus on the marked kill target
	if m.dmg.done > 0 and m.dmg.onKill > 0 and not HEALER_SPECS[m.mySpec or ""] then
		local pct = m.dmg.onKill / m.dmg.done
		m.dmg.onKillPct = pct
		if pct < 0.4 then Add("focus_low", format("Only %d%% of your damage went to the marked kill target", floor(pct * 100 + 0.5)), 1) end
	end
	table.sort(m.notes, function(a, b) return a.w > b.w end)
end

----------------------------------------------------------------------
-- Enemy history (built from the stored matches only)
----------------------------------------------------------------------
function A:History()
	if A.historyCache then return A.historyCache end
	local h = {}
	local list = DB().matches
	local total = #list
	for i, m in ipairs(list) do
		local w = 0.5 + 0.5 * (i / math.max(1, total)) -- newer matches count more
		for _, e in ipairs(m.enemies or {}) do
			if e.name then
				local p = h[e.name] or { games = 0, w = 0, died = 0, diedFirst = 0, trinketEarly = 0, unusedDef = 0, defEarly = 0, wins = 0, ttd = {} }
				h[e.name] = p
				p.games = p.games + 1
				p.w = p.w + w
				p.class = e.class or p.class
				if e.died then p.died = p.died + w end
				if e.diedFirst then p.diedFirst = p.diedFirst + w; p.diedFirstN = (p.diedFirstN or 0) + 1 end
				if (e.trinketEarly or 0) > 0 then p.trinketEarly = p.trinketEarly + w end
				if e.unusedDef then p.unusedDef = p.unusedDef + w end
				if (e.defEarly or 0) > 0 then p.defEarly = p.defEarly + w end
				if e.ttd then p.ttd[#p.ttd + 1] = e.ttd end
				if m.result == "win" then p.wins = p.wins + 1 end
			end
		end
	end
	A.historyCache = h
	return h
end

-- For the kill target helper: a score bonus and a short reason, once you've faced someone 2+ times
function ns:EnemyHistory(name)
	if not name or ns.db.analyzerOn == false then return nil end
	local p = A:History()[name]
	if not p or p.games < 2 then return nil end
	local r = function(x) return x / p.w end
	local bonus = 14 * r(p.diedFirst) + 6 * r(p.died) + 6 * r(p.trinketEarly) + 6 * r(p.unusedDef) + 4 * r(p.defEarly)
	local reason
	if (p.diedFirstN or 0) >= 1 then
		reason = format("died first %d/%d", p.diedFirstN, p.games)
	elseif r(p.trinketEarly) >= 0.5 then
		reason = "trinkets early"
	elseif r(p.unusedDef) >= 0.5 then
		reason = "dies with defensives up"
	end
	return { games = p.games, bonus = bonus, reason = reason, diedFirst = p.diedFirstN or 0, wins = p.wins }
end

----------------------------------------------------------------------
-- Trends over the stored matches
----------------------------------------------------------------------
function A:Trends()
	local list = DB().matches
	local t = { games = #list, wins = 0, comps = {}, mistakes = {}, ccOnMe = 0, kicksCast = 0, kicksLanded = 0, takenIntoReady = 0 }
	local last10 = {}
	for i = math.max(1, #list - 9), #list do last10[i] = true end
	for i, m in ipairs(list) do
		if m.result == "win" then t.wins = t.wins + 1 end
		local c = t.comps[m.comp or "?"] or { games = 0, wins = 0 }
		t.comps[m.comp or "?"] = c
		c.games = c.games + 1
		if m.result == "win" then c.wins = c.wins + 1 end
		t.ccOnMe = t.ccOnMe + (m.cc and m.cc.onMeTime or 0)
		t.kicksCast = t.kicksCast + (m.kicks and m.kicks.cast or 0)
		t.kicksLanded = t.kicksLanded + (m.kicks and ((m.kicks.landed or 0) + (m.kicks.silenced or 0)) or 0)
		if last10[i] then
			local seen = {}
			for _, n in ipairs(m.notes or {}) do
				if not seen[n.kind] then seen[n.kind] = true; Count(t.mistakes, n.kind) end
			end
		end
	end
	t.last = math.min(10, #list)
	return t
end

----------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------
local function CheckTalents()
	local ok, has = pcall(HasSilenceTalent)
	hasSilenceTalent = ok and has or false
end
-- talent changes: spending points, a respec, or swapping dual spec
ns:On("PLAYER_TALENT_UPDATE", CheckTalents)
ns:On("ACTIVE_TALENT_GROUP_CHANGED", CheckTalents)
ns:On("PLAYER_ENTERING_WORLD", CheckTalents) -- talents aren't always readable at the very first login moment

ns:Listen("LOGIN", function()
	BuildSets()
	CheckTalents()
	DB()
	-- a /reload inside an arena: start recording again (the earlier part is lost)
	if ns:InArena() then Begin() end
end)

-- for tests / the preview report
A._Begin, A._Gates, A._State = Begin, GatesOpen, function() return M end
