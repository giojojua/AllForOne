-- AllForOne: kill target helper (arena 2s / 3s / solo queue)
-- Scores every enemy and marks one KILL (and, when it matters, their healer CC), with the
-- reasons next to the enemy frame and on the nameplate. It can announce changes in party chat.
--
-- What raises a score: low health, PvP trinket used, big defensives on cooldown, weak
-- defensive kit (class/spec), no stun diminishing returns yet, their healer crowd-controlled.
-- What lowers it: immune right now (Divine Shield, Ice Block, Deterrence...), a defensive up.
-- It only knows what the addon can see (cooldowns, auras, health, DR) — no positioning or
-- line of sight — so it's a strong hint, not an order.
local _, ns = ...
local colors = ns.colors
local U = ns.U
local GetTime = GetTime

local HEALER_SPECS = { Holy = true, Discipline = true, Restoration = true }

-- How easy each spec is to kill on its own (higher = squishier / fewer escapes)
local BASE = {
	WARLOCK = { _ = 26 },
	HUNTER = { _ = 22 },
	MAGE = { _ = 18 },
	ROGUE = { _ = 12 },
	WARRIOR = { _ = 20, Fury = 22, Protection = 4 },
	DEATHKNIGHT = { _ = 8 },
	PALADIN = { _ = 8, Retribution = 12, Holy = 0, Protection = 2 },
	PRIEST = { _ = 15, Shadow = 24, Discipline = 0, Holy = 6 },
	DRUID = { _ = 14, Balance = 22, Feral = 12, Restoration = 0 },
	SHAMAN = { _ = 18, Elemental = 25, Enhancement = 18, Restoration = 10 },
}

-- Big defensives per class: each one we've seen used (on cooldown) makes them easier to kill
local DEFENSIVES = {
	WARRIOR = { 871 },                    -- Shield Wall
	PALADIN = { 642, 498 },               -- Divine Shield, Divine Protection
	HUNTER = { 19263 },                   -- Deterrence
	ROGUE = { 31224, 26669, 26889 },      -- Cloak of Shadows, Evasion, Vanish
	PRIEST = { 33206, 47585, 47788 },     -- Pain Suppression, Dispersion, Guardian Spirit
	DRUID = { 22812, 61336 },             -- Barkskin, Survival Instincts
	SHAMAN = { 30823 },                   -- Shamanistic Rage
	MAGE = { 45438 },                     -- Ice Block
	DEATHKNIGHT = { 48792, 48707, 49039 }, -- Icebound Fortitude, Anti-Magic Shell, Lichborne
	WARLOCK = {},
}

-- Active right now: hard immunities force a SWAP; the rest just lower the score
local IMMUNE = { 642, 45438, 19263, 10278 } -- Divine Shield, Ice Block, Deterrence, Hand of Protection
local REDUCERS = {
	[31224] = 30, [47585] = 40, [33206] = 40, [47788] = 30, [48792] = 20, [871] = 30,
	[26669] = 15, [22812] = 10, [61336] = 20, [498] = 25, [30823] = 15,
}

local names = {}   -- built at login: spell id -> localized name
local function N(id)
	if not names[id] then names[id] = GetSpellInfo(id) or tostring(id) end
	return names[id]
end

----------------------------------------------------------------------
-- Reading an enemy
----------------------------------------------------------------------
local function Enemies()
	local list = {}
	for i = 1, 5 do
		local u = "arena" .. i
		if U.Exists(u) and not U.Dead(u) then list[#list + 1] = { unit = u, n = i } end
	end
	return list
end

local function HasAura(unit, id, filter)
	if ns.testing then
		local f = ns.fakeKillAuras and ns.fakeKillAuras[unit]
		return f and f[id]
	end
	return UnitAura(unit, N(id), nil, filter) ~= nil
end

local function IsCCd(unit)
	if ns.testing then return ns.fakeKillCC and ns.fakeKillCC[unit] end
	for i = 1, 40 do
		local name = UnitAura(unit, i, "HARMFUL")
		if not name then break end
		local cc = ns.CC[name]
		if cc and (ns.ccPriority[cc.cat] or 0) >= 6 then return true end
	end
end

local function Read(e)
	local u = e.unit
	e.guid = U.GUID(u)
	e.class = U.Class(u)
	e.name = U.Name(u) or ("arena" .. e.n)
	e.full = (not ns.testing and ns.FullName and ns:FullName(u)) or e.name
	e.history = ns.EnemyHistory and ns:EnemyHistory(e.full) or nil
	e.spec = e.guid and ns.specs[e.guid]
	e.healer = e.spec and HEALER_SPECS[e.spec] or false
	local cur, max = U.Health(u)
	e.hp = (max and max > 0) and (cur / max) or 1
	local used = e.guid and ns.trinkets[e.guid]
	e.trinketDown = used and (used + ns.trinketCooldown > GetTime()) or false
	e.ccd = IsCCd(u)
	e.drinking = U.Drinking(u)
	-- defensives on cooldown
	e.downs = {}
	local cds = e.guid and ns.cds[e.guid]
	local now = GetTime()
	for _, id in ipairs(DEFENSIVES[e.class or ""] or {}) do
		local c = cds and cds[N(id)]
		if c and c.start and c.start + c.dur > now then e.downs[#e.downs + 1] = N(id) end
	end
	-- immune / defensive up right now
	e.immune, e.reduce, e.upName = nil, 0, nil
	for _, id in ipairs(IMMUNE) do
		if HasAura(u, id) then e.immune = N(id) break end
	end
	for id, amount in pairs(REDUCERS) do
		if amount > e.reduce and HasAura(u, id) then e.reduce, e.upName = amount, N(id) end
	end
	-- stun diminishing returns
	e.stunDR = 0
	for _, d in ipairs(ns:GetDR(e.guid)) do
		if d.cat == "stun" or d.cat == "kidney" then e.stunDR = math.max(e.stunDR, d.count) end
	end
end

local function Bracket(n)
	return n <= 2 and 2 or 3
end

----------------------------------------------------------------------
-- Scoring
----------------------------------------------------------------------
local function Score(e, enemies)
	local reasons = {}
	local base = BASE[e.class or ""] or { _ = 15 }
	local s = base[e.spec or "_"] or base._
	if e.healer then s = s - 12 end
	-- 2s: a sturdy DPS next to a healer makes the healer the better kill
	if e.healer and Bracket(#enemies) == 2 then
		for _, o in ipairs(enemies) do
			if o ~= e and not o.healer then
				local ob = BASE[o.class or ""] or { _ = 15 }
				if (ob[o.spec or "_"] or ob._) <= 12 then s = s + 14; reasons[#reasons + 1] = "partner too tanky" end
			end
		end
	end
	s = s + (1 - e.hp) * 60
	if e.hp < 0.6 then reasons[#reasons + 1] = floor(e.hp * 100 + 0.5) .. "%" end
	if e.trinketDown then s = s + 20; reasons[#reasons + 1] = "trinket down" end
	for _, d in ipairs(e.downs) do s = s + 12; reasons[#reasons + 1] = d .. " down" end
	if e.stunDR == 0 then s = s + 6 elseif e.stunDR >= 2 then s = s - 8 end
	for _, o in ipairs(enemies) do
		if o ~= e and o.healer and o.ccd then s = s + 15; reasons[#reasons + 1] = "healer CC'd" break end
	end
	if e.healer and e.drinking then s = s + 30; reasons[#reasons + 1] = "drinking" end
	-- what you've seen from this player in your last 50 arenas (arena analyzer)
	if e.history then
		s = s + e.history.bonus
		if e.history.reason then reasons[#reasons + 1] = e.history.reason end
	end
	if e.reduce > 0 then s = s - e.reduce end
	if e.immune then s = s - 1000 end
	if #reasons == 0 then reasons[1] = e.healer and "healer" or "fewest defensives" end
	e.score, e.reasons = s, reasons
end

----------------------------------------------------------------------
-- Markers on the enemy frames + nameplates
----------------------------------------------------------------------
-- A raid-marker style sign on the enemy's health bar: red cross = KILL, blue square = CC.
-- Switching the kill target simply moves the cross. Hover the frame to see why.
local KILL_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" -- red cross
local CC_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6"   -- blue square
ns.KILL_ICON, ns.CC_ICON = KILL_ICON, CC_ICON

local marks = {}
local function Mark(row)
	if marks[row] then return marks[row] end
	local holder = CreateFrame("Frame", nil, row.health or row)
	holder:SetAllPoints(row.health or row)
	holder:SetFrameLevel((row.health or row):GetFrameLevel() + 3)
	local m = holder:CreateTexture(nil, "OVERLAY")
	m:SetSize(26, 26)
	m:SetPoint("CENTER", holder, "CENTER", 0, 0)
	m:Hide()
	m.holder = holder
	marks[row] = m
	-- the reasons go in the frame's tooltip
	row:HookScript("OnEnter", function(self)
		if self.killWhy and self.killWhy ~= "" and GameTooltip:IsOwned(self) then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(self.killKind and ("|T" .. (self.killKind == "CC" and CC_ICON or KILL_ICON) .. ":14|t " .. self.killKind) or "AllForOne", 1, 1, 1)
			GameTooltip:AddLine(self.killWhy, 0.75, 0.76, 0.78, true)
			GameTooltip:Show()
		end
	end)
	return m
end

local function ShowMark(row, kind, why)
	local m = Mark(row)
	row.killWhy, row.killKind = why, kind
	if not kind then m:Hide() return end
	m:SetTexture(kind == "CC" and CC_ICON or KILL_ICON)
	m:Show()
end

----------------------------------------------------------------------
-- Party chat
----------------------------------------------------------------------
-- Messages are short on purpose:  "Kill Warrior"  /  "Switch Priest"
--   Kill   = the first call of the match
--   Switch = only when YOU target the helper's new kill target (you confirm the swap)
local lastSent, lastOther = 0, 0
local announced -- GUID of the enemy we last called

local function Say(msg)
	if ns.db.announceKill == false or ns.testing then return end
	if not ns:InArena() then return end
	local now = GetTime()
	-- a teammate with AllForOne just called it: don't double up
	if now - lastOther < 3 or now - lastSent < 2 then return end
	if (GetNumPartyMembers and GetNumPartyMembers() or 0) == 0 then return end
	lastSent = now
	SendChatMessage(msg, "PARTY")
	return true
end

ns:On("CHAT_MSG_PARTY", function(_, msg, author)
	if msg and (msg:find("^Kill ") or msg:find("^Switch ")) and author ~= UnitName("player") then lastOther = GetTime() end
end)

-- "Warrior", or "Grimtusk Warrior" when the enemy team has two of that class
local function Label(e)
	local _, class = UnitClass(e.unit)
	local text = UnitClass(e.unit) or e.class or "?"
	local same = 0
	for i = 1, 5 do
		local u = "arena" .. i
		if UnitExists(u) and select(2, UnitClass(u)) == class then same = same + 1 end
	end
	if same > 1 then text = (UnitName(e.unit) or "") .. " " .. text end
	return text
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------
local killUnit, ccUnit
local SWITCH_MARGIN = 15

-- full = new match / left the arena: forget what was called too
local function Clear(full)
	killUnit, ccUnit = nil, nil
	if full then announced = nil end
	ns.killName, ns.ccName = nil, nil
	for row, m in pairs(marks) do m:Hide(); row.killWhy = nil end
end

local function Update()
	if ns.db.killHelper == false or not ns.frames or not ns.frames.arena then Clear() return end
	if not ns:InArena() and not ns.testing then Clear(true) return end
	local enemies = Enemies()
	if #enemies == 0 then Clear() return end
	for _, e in ipairs(enemies) do Read(e) end
	for _, e in ipairs(enemies) do Score(e, enemies) end

	local best, current
	for _, e in ipairs(enemies) do
		if not best or e.score > best.score then best = e end
		if e.unit == killUnit then current = e end
	end
	local pick, swapReason = best, nil
	if current and current ~= best then
		if current.immune then
			swapReason = current.immune .. " on #" .. current.n
		elseif best.score < current.score + SWITCH_MARGIN then
			pick = current -- not clearly better: don't flip-flop
		end
	end
	if pick.immune then pick = nil end -- everyone immune: no call

	-- CC: their healer, when your kill target is getting low
	local cc
	if pick and pick.hp < 0.6 then
		for _, e in ipairs(enemies) do
			if e ~= pick and e.healer and not e.immune and not e.ccd then cc = e break end
		end
	end

	-- first call of the match goes out right away; later changes wait for you to target them
	local newKill = pick and pick.unit or nil
	if pick and not announced then
		if Say("Kill " .. Label(pick)) then announced = pick.guid end
	end
	local newCC = cc and cc.unit or nil
	killUnit, ccUnit = newKill, newCC
	ns.killName = pick and pick.name or nil
	ns.ccName = cc and cc.name or nil

	-- markers
	for i, row in ipairs(ns.frames.arena) do
		local u = "arena" .. i
		if pick and u == pick.unit then
			ShowMark(row, "KILL", swapReason and ("swap: " .. swapReason) or table.concat(pick.reasons, " · "))
		elseif cc and u == cc.unit then
			ShowMark(row, "CC", "healer · your kill target is low")
		else
			-- known player: a note from past games, in the tooltip
			local note
			for _, x in ipairs(enemies) do
				if x.unit == u and x.history then note = format("faced %d× · died first %d×", x.history.games, x.history.diedFirst) end
			end
			ShowMark(row, nil, note)
		end
	end
end
ns.UpdateKillTarget = Update

local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, e)
	acc = acc + e
	if acc < 0.5 then return end
	acc = 0
	local ok, err = pcall(Update)
	if not ok then ns:Report(err) end
end)
ticker:Hide()

ns:Listen("LOGIN", function()
	ticker:Show()
end)
ns:On("PLAYER_ENTERING_WORLD", function() Clear(true) end)

-- you targeted the helper's new kill target: tell the party to switch
ns:On("PLAYER_TARGET_CHANGED", function()
	if not killUnit or not UnitExists("target") or not UnitIsUnit("target", killUnit) then return end
	local guid = UnitGUID(killUnit)
	if not announced or guid == announced then return end
	local e = { unit = killUnit, name = UnitName(killUnit) or killUnit, class = select(2, UnitClass(killUnit)) }
	if Say("Switch " .. Label(e)) then announced = guid end
end)
