-- AllForOne: combat-log trackers (trinkets, cooldowns, DR, specs, auras by GUID)
local _, ns = ...
local GetTime, UnitGUID, band = GetTime, UnitGUID, bit.band
local PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

ns.unitOf = {}     -- guid -> unit token (pets map to their owner)
ns.specs = {}      -- guid -> spec name
ns.cds = {}        -- guid -> { [spellName] = { start, dur, icon } }
ns.trinkets = {}   -- guid -> time the PvP trinket was used
ns.dr = {}         -- guid -> { [category] = { count, reset, icon, active } }
ns.auras = {}      -- guid -> { [spellName] = { icon, dur, expires, cc, mine, dispel } }
ns.nameToGUID = {} -- player name (no realm) -> guid
ns.cdOrder = {}    -- guid -> spell names in display order (icons never change slots)
ns.DR_RESET = 18

local tokens = { "player", "party1", "party2", "party3", "party4", "arena1", "arena2", "arena3", "arena4", "arena5" }
local petTokens = {
	pet = "player", partypet1 = "party1", partypet2 = "party2", partypet3 = "party3", partypet4 = "party4",
	arenapet1 = "arena1", arenapet2 = "arena2", arenapet3 = "arena3", arenapet4 = "arena4", arenapet5 = "arena5",
}
local lookupTokens = { "target", "focus", "mouseover", "player", "party1", "party2", "party3", "party4",
	"arena1", "arena2", "arena3", "arena4", "arena5", "targettarget", "focustarget" }

local function ShortName(name)
	return name and name:match("^[^%-]+") or name
end

function ns:UpdateUnitMap()
	wipe(ns.unitOf)
	for _, u in ipairs(tokens) do
		local g = UnitGUID(u)
		if g then
			ns.unitOf[g] = u
			if UnitIsPlayer(u) then ns.nameToGUID[ShortName(UnitName(u))] = g end
		end
	end
	for pet, owner in pairs(petTokens) do
		local g = UnitGUID(pet)
		if g then ns.unitOf[g] = owner end
	end
	ns:Send("UNITMAP")
end

-- Find any unit token currently pointing at this GUID
function ns:FindUnit(guid)
	if not guid then return nil end
	for _, u in ipairs(lookupTokens) do
		if UnitGUID(u) == guid then return u end
	end
end

-- Exact aura data when the unit is visible to us
local function ReadAura(unit, spellName, mineOnly)
	for i = 1, 40 do
		local name, _, icon, count, dispel, duration, expires, caster = UnitAura(unit, i, "HARMFUL")
		if not name then return end
		if name == spellName and (not mineOnly or caster == "player") then
			return icon, duration, expires, dispel, count
		end
	end
end

----------------------------------------------------------------------
-- Player spec from talents
----------------------------------------------------------------------
local function UpdatePlayerSpec()
	local best, bestPoints = nil, 0
	for i = 1, (GetNumTalentTabs() or 0) do
		local name, _, points = GetTalentTabInfo(i)
		if points and points > bestPoints then best, bestPoints = name, points end
	end
	local g = UnitGUID("player")
	if g and best then
		ns.specs[g] = best
		ns:Send("SPEC", g)
	end
end

----------------------------------------------------------------------
-- Getters used by frames and nameplates
----------------------------------------------------------------------
-- Display order for a unit: its class's "always" spells first, then other cooldowns
-- in the order they were first used. Existing icons never move.
local function OrderFor(guid, class)
	local order = ns.cdOrder[guid]
	if not order then
		order = {}
		for _, rec in ipairs(class and ns.classCooldowns[class] or {}) do
			if rec.always then order[#order + 1] = rec.name end
		end
		ns.cdOrder[guid] = order
	end
	return order
end

function ns:NoteCooldownUsed(guid, class, name)
	local order = OrderFor(guid, class)
	for _, n in ipairs(order) do
		if n == name then return end
	end
	order[#order + 1] = name
end

-- Your own cooldowns: exact, straight from the game, only spells you know
local function OwnCooldowns(class, max)
	local out = {}
	for _, rec in ipairs(class and ns.classCooldowns[class] or {}) do
		if GetSpellInfo(rec.name) then -- by name: only returns something for spells in your spellbook
			local start, duration = GetSpellCooldown(rec.name)
			local active = start and start > 0 and duration and duration > 1.5
			out[#out + 1] = { icon = rec.icon, start = active and start or nil, dur = active and duration or nil }
			if #out >= max then break end
		end
	end
	return out
end

-- Cooldowns to show under a unit's frame
function ns:GetCooldowns(guid, class, max, unit)
	if unit == "player" and not ns.testing then return OwnCooldowns(class, max) end
	local out = {}
	if not guid then return out end
	local used = ns.cds[guid] or {}
	local now = GetTime()
	for _, name in ipairs(OrderFor(guid, class)) do
		local rec = (class and ns.CD[class .. ":" .. name]) or ns.Racial[name]
		if rec then
			local u = used[name]
			local active = u and (u.start + u.dur > now)
			out[#out + 1] = { icon = rec.icon, start = active and u.start or nil, dur = active and u.dur or nil }
			if #out >= max then break end
		end
	end
	return out
end

function ns:GetDR(guid)
	local out = {}
	local states = guid and ns.dr[guid]
	if not states then return out end
	local now = GetTime()
	for cat, s in pairs(states) do
		if s.active or s.reset > now then
			-- while the crowd control is still on, the reset is an estimate: its end + 18s
			local full = s.active and s.ccEnds and (s.ccEnds + ns.DR_RESET) or (not s.active and s.reset) or nil
			out[#out + 1] = { cat = cat, count = s.count, reset = s.reset, icon = s.icon, active = s.active, full = full }
		else
			states[cat] = nil
		end
	end
	table.sort(out, function(a, b) return a.cat < b.cat end)
	return out
end

-- Highest-priority CC on a GUID, and my own debuffs on it
function ns:GetAuras(guid)
	local list = guid and ns.auras[guid]
	if not list then return nil, {} end
	local now = GetTime()
	local best, bestPrio, mine = nil, -1, {}
	for name, a in pairs(list) do
		if a.expires and a.expires < now then
			list[name] = nil
		else
			if a.cc then
				local p = ns.ccPriority[a.cc] or 0
				if p > bestPrio then best, bestPrio = a, p end
			end
			if a.mine then mine[#mine + 1] = a end
		end
	end
	ns:Sort(mine, function(x, y) return (ns:AuraTime(x.expires) or 1e9) < (ns:AuraTime(y.expires) or 1e9) end)
	return best, mine
end

----------------------------------------------------------------------
-- Combat log
----------------------------------------------------------------------
local function StartCooldown(srcGUID, spellName, spellId)
	local owner = ns.unitOf[srcGUID]
	if not owner then return end
	local ownerGUID = UnitGUID(owner)
	if not ownerGUID then return end
	local now = GetTime()
	if ns.Trinket[spellName] then
		ns.trinkets[ownerGUID] = now
		ns:Send("COOLDOWN", ownerGUID)
		return
	end
	local _, class = UnitClass(owner)
	ns.cds[ownerGUID] = ns.cds[ownerGUID] or {}
	-- Preparation / Cold Snap / Readiness: clear what they reset
	local reset = ns.Resets[spellName]
	if reset == "all" then
		wipe(ns.cds[ownerGUID])
	elseif reset then
		for _, n in ipairs(reset) do ns.cds[ownerGUID][n] = nil end
	end
	local rec = class and ns.CD[class .. ":" .. spellName] or ns.Racial[spellName]
	if rec then
		ns.cds[ownerGUID][spellName] = { start = now, dur = rec.cd, icon = rec.icon }
		ns:NoteCooldownUsed(ownerGUID, class, spellName)
	end
	if rec or reset then ns:Send("COOLDOWN", ownerGUID) end
	ns:NoteSpec(ownerGUID, class, spellName)
end

-- A spec-only spell / talent buff / proc seen from a player (or their pet) sets their spec.
function ns:NoteSpec(guid, class, spellName)
	local spec = guid and spellName and ns.Spec[spellName]
	if not spec then return end
	if not class and GetPlayerInfoByGUID then class = select(2, GetPlayerInfoByGUID(guid)) end
	if spec.class ~= class or ns.specs[guid] == spec.spec then return end
	ns.specs[guid] = spec.spec
	ns:Send("SPEC", guid)
end

-- Who really did it: pets count for their owner (arena / party pets via the unit map)
local function SpecSource(srcGUID, srcFlags)
	local owner = ns.unitOf[srcGUID]
	if owner then
		local g = UnitGUID(owner)
		if g then return g, select(2, UnitClass(owner)) end
	end
	if srcFlags and band(srcFlags, PLAYER_FLAG) > 0 then return srcGUID end
end
local SPEC_EVENTS = {
	SPELL_CAST_START = true, SPELL_CAST_SUCCESS = true, SPELL_SUMMON = true, SPELL_DAMAGE = true,
	SPELL_PERIODIC_DAMAGE = true, SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true, SPELL_AURA_APPLIED = true,
	SPELL_AURA_REFRESH = true, SPELL_MISSED = true, SPELL_ENERGIZE = true, SPELL_INTERRUPT = true,
}

-- Talent auras / forms on an enemy (Shadowform, Tree of Life, Moonkin, Trueshot...): read as
-- soon as you can see them, before they cast anything
local function ScanSpec(unit)
	if not (UnitExists(unit) and UnitIsPlayer(unit)) then return end
	for i = 1, 40 do
		local name, _, _, _, _, _, _, caster = UnitAura(unit, i, "HELPFUL")
		if not name then break end
		-- the buff tells us about whoever cast it (self-buffs: this unit; Trueshot / Moonkin
		-- auras: their teammate). Unknown caster: skip, it could be a teammate of the same class.
		if caster and ns.Spec[name] and UnitExists(caster) and UnitIsPlayer(caster) then
			ns:NoteSpec(UnitGUID(caster), select(2, UnitClass(caster)), name)
		end
	end
end
ns.ScanSpec = ScanSpec

----------------------------------------------------------------------
-- Diminishing returns icon: if YOU have a spell in that category, the DR icon is always your
-- spell (only the counter and timer change). Otherwise it's the last crowd control that landed.
----------------------------------------------------------------------
ns.myDRIcon = {} -- category -> icon of your own spell in it
-- spells you cast whose crowd control aura has a different name
local CAST_TO_AURA = { [11578] = 7922, [100] = 7922 } -- Charge -> Charge Stun
local function ScanMyCC()
	wipe(ns.myDRIcon)
	if not (ns.CC and ns.drCategories and GetNumSpellTabs and GetSpellName) then return end
	local alias = {}
	for cast, aura in pairs(CAST_TO_AURA) do
		local c, a = GetSpellInfo(cast), GetSpellInfo(aura)
		if c and a then alias[c] = a end
	end
	local function Add(name, icon)
		local cc = name and (ns.CC[name] or ns.CC[alias[name] or ""])
		if cc and ns.drCategories[cc.cat] and not ns.myDRIcon[cc.cat] then
			ns.myDRIcon[cc.cat] = icon or cc.icon
		end
	end
	-- your spellbook
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, count = GetSpellTabInfo(tab)
		for i = (offset or 0) + 1, (offset or 0) + (count or 0) do
			local name = GetSpellName(i, BOOKTYPE_SPELL or "spell")
			if name then Add(name, GetSpellTexture and GetSpellTexture(i, BOOKTYPE_SPELL or "spell")) end
		end
	end
	-- your pet (Seduction, Spell Lock...)
	local petCount = HasPetSpells and HasPetSpells()
	if petCount then
		for i = 1, petCount do
			local name = GetSpellName(i, BOOKTYPE_PET or "pet")
			if name then Add(name, GetSpellTexture and GetSpellTexture(i, BOOKTYPE_PET or "pet")) end
		end
	end
end
local function Rescan() local ok, err = pcall(ScanMyCC); if not ok then ns:Report(err) end end
ns:Listen("LOGIN", Rescan)
ns:On("SPELLS_CHANGED", Rescan)          -- learned a spell, respec, dual-spec swap
ns:On("PET_BAR_UPDATE", Rescan)          -- pet summoned / changed
ns:On("PLAYER_TALENT_UPDATE", Rescan)

local function AuraApplied(dstGUID, spellId, spellName, mine, refresh)
	local cc = ns.CC[spellName]
	if not cc and not mine then return end
	local now = GetTime()
	local unit = ns:FindUnit(dstGUID)
	local icon, duration, expires, dispel
	if unit then icon, duration, expires, dispel = ReadAura(unit, spellName, mine and not cc) end
	if not icon then
		local _, _, sicon = GetSpellInfo(spellId)
		icon = sicon
		duration = cc and cc.dur or nil
		expires = duration and (now + duration) or (now + 30)
		dispel = cc and cc.dispel or nil
	end
	if duration == 0 then duration, expires = nil, nil end
	ns.auras[dstGUID] = ns.auras[dstGUID] or {}
	local a = ns.auras[dstGUID][spellName] or {}
	a.icon, a.dur, a.expires, a.dispel = icon, duration, expires, dispel or (cc and cc.dispel)
	a.cc = cc and cc.cat or nil
	a.mine = a.mine or mine
	a.noTimer = (duration == nil)
	ns.auras[dstGUID][spellName] = a

	if cc and ns.drCategories[cc.cat] then
		ns.dr[dstGUID] = ns.dr[dstGUID] or {}
		local s = ns.dr[dstGUID][cc.cat]
		if not s or (not s.active and s.reset < now) then
			s = { count = 0 }
			ns.dr[dstGUID][cc.cat] = s
		end
		s.count = s.count + 1
		s.active = true
		s.reset = math.huge
		s.ccEnds = expires -- when this crowd control should end (the 18s reset starts then)
		s.icon = ns.myDRIcon[cc.cat] or icon -- your spell if you have one in this category
		ns:Send("DR", dstGUID)
	end
	ns:Send("AURAS", dstGUID)
end

local function AuraRemoved(dstGUID, spellName)
	local list = ns.auras[dstGUID]
	if list and list[spellName] then
		list[spellName] = nil
		ns:Send("AURAS", dstGUID)
	end
	local cc = ns.CC[spellName]
	if cc and ns.dr[dstGUID] then
		local s = ns.dr[dstGUID][cc.cat]
		if s then
			s.active = false
			s.reset = GetTime() + ns.DR_RESET
			ns:Send("DR", dstGUID)
		end
	end
end

ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName, _, extra1)
	if srcName and srcFlags and band(srcFlags, PLAYER_FLAG) > 0 then ns.nameToGUID[ShortName(srcName)] = srcGUID end
	if dstName and dstFlags and band(dstFlags, PLAYER_FLAG) > 0 then ns.nameToGUID[ShortName(dstName)] = dstGUID end

	if SPEC_EVENTS[event] and spellName and ns.Spec[spellName] then
		local g, class = SpecSource(srcGUID, srcFlags)
		if g then ns:NoteSpec(g, class, spellName) end
	end

	if event == "SPELL_CAST_SUCCESS" or event == "SPELL_SUMMON" then
		StartCooldown(srcGUID, spellName, spellId)
	elseif event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
		if extra1 == "DEBUFF" then
			AuraApplied(dstGUID, spellId, spellName, srcGUID == UnitGUID("player"), event == "SPELL_AURA_REFRESH")
		end
	elseif event == "SPELL_AURA_REMOVED" or event == "SPELL_AURA_BROKEN" or event == "SPELL_AURA_BROKEN_SPELL" then
		AuraRemoved(dstGUID, spellName)
	elseif event == "SPELL_INTERRUPT" then
		ns:Send("INTERRUPTED", dstGUID, spellName)
	elseif event == "UNIT_DIED" then
		ns.auras[dstGUID] = nil
		ns:Send("AURAS", dstGUID)
	end
end)

----------------------------------------------------------------------
-- Keep the unit map fresh; reset state for every new arena/zone
----------------------------------------------------------------------
for _, ev in ipairs({ "PARTY_MEMBERS_CHANGED", "ARENA_OPPONENT_UPDATE", "UNIT_PET", "PLAYER_TARGET_CHANGED" }) do
	ns:On(ev, function() ns:UpdateUnitMap() end)
end

ns:On("PLAYER_ENTERING_WORLD", function()
	wipe(ns.cds); wipe(ns.trinkets); wipe(ns.dr); wipe(ns.auras); wipe(ns.cdOrder)
	local mine = ns.specs[UnitGUID("player") or ""]
	wipe(ns.specs)
	ns:UpdateUnitMap()
	UpdatePlayerSpec()
	if mine and not ns.specs[UnitGUID("player")] then ns.specs[UnitGUID("player")] = mine end
	ns:Send("REFRESH_ALL")
end)
ns:On("PLAYER_TALENT_UPDATE", UpdatePlayerSpec)
ns:On("ACTIVE_TALENT_GROUP_CHANGED", UpdatePlayerSpec)

-- enemy (and party) buffs: forms and talent auras tell the spec before the first cast
ns:On("UNIT_AURA", function(_, unit)
	if unit and (unit:match("^arena%d$") or unit:match("^party%d$")) then ScanSpec(unit) end
end)
ns:On("ARENA_OPPONENT_UPDATE", function(_, unit)
	if unit and unit:match("^arena%d$") then ScanSpec(unit) end
end)
ns:On("PLAYER_TARGET_CHANGED", function() ScanSpec("target") end)
ns:On("PLAYER_FOCUS_CHANGED", function() ScanSpec("focus") end)
ns:On("UPDATE_MOUSEOVER_UNIT", function() ScanSpec("mouseover") end)
