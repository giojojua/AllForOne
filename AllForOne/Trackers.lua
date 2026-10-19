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
-- Cooldowns to show for a unit: the "always" spells for its class, plus any other used ones
function ns:GetCooldowns(guid, class, max)
	local out = {}
	local used = guid and ns.cds[guid] or {}
	local list = class and ns.classCooldowns[class] or {}
	local now = GetTime()
	for _, rec in ipairs(list) do
		local u = used[rec.name]
		if rec.always or u then
			local active = u and (u.start + u.dur > now)
			out[#out + 1] = { icon = rec.icon, start = active and u.start or nil, dur = active and u.dur or nil }
			if #out >= max then return out end
		end
	end
	for name, u in pairs(used) do
		if ns.Racial[name] and #out < max then
			local active = u.start + u.dur > now
			out[#out + 1] = { icon = u.icon, start = active and u.start or nil, dur = active and u.dur or nil }
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
			out[#out + 1] = { cat = cat, count = s.count, reset = s.reset, icon = s.icon, active = s.active }
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
	table.sort(mine, function(x, y) return (x.expires or 1e9) < (y.expires or 1e9) end)
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
	local rec = class and ns.CD[class .. ":" .. spellName] or ns.Racial[spellName]
	if rec then
		ns.cds[ownerGUID] = ns.cds[ownerGUID] or {}
		ns.cds[ownerGUID][spellName] = { start = now, dur = rec.cd, icon = rec.icon }
		ns:Send("COOLDOWN", ownerGUID)
	end
	local spec = ns.Spec[spellName]
	if spec and spec.class == class and ns.specs[ownerGUID] ~= spec.spec then
		ns.specs[ownerGUID] = spec.spec
		ns:Send("SPEC", ownerGUID)
	end
end

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
		s.icon = icon
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
	wipe(ns.cds); wipe(ns.trinkets); wipe(ns.dr); wipe(ns.auras)
	local mine = ns.specs[UnitGUID("player") or ""]
	wipe(ns.specs)
	ns:UpdateUnitMap()
	UpdatePlayerSpec()
	if mine and not ns.specs[UnitGUID("player")] then ns.specs[UnitGUID("player")] = mine end
	ns:Send("REFRESH_ALL")
end)
ns:On("PLAYER_TALENT_UPDATE", UpdatePlayerSpec)
ns:On("ACTIVE_TALENT_GROUP_CHANGED", UpdatePlayerSpec)
