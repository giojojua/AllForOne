-- AllForOne: combat meter in the style of Details!
-- Counts you, your party / raid and everyone's pets and guardians (pets add to their owner).
--
-- Title bar:  [segment] [display] [reset]   Damage Done - Current
--   segment menu: Current, Overall, and the last 10 fights ("vs <enemy>  1:23")
--   display menu: Damage Done, DPS, Damage Taken, Healing Done, HPS, Overhealing, Dispels,
--                 Interrupts, Deaths
-- Rows: class icon, "1. Name", "total (per second, percent)". Mouse wheel scrolls, drag the
-- bottom-right corner to resize. Hover a row for a quick spell list, click it for the full
-- breakdown (amount, share, hits, crit %).
-- Overall is kept between sessions for this character until you reset it.
local _, ns = ...
local colors = ns.colors
local GetTime, band = GetTime, bit.band

local ROW_H, ROW_GAP, TITLE_H = 24, 1, 28
local MAX_ROWS = 30
local HISTORY = 10
local MINE = (COMBATLOG_OBJECT_AFFILIATION_MINE or 1) + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 2)
	+ (COMBATLOG_OBJECT_AFFILIATION_RAID or 4)
local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
-- spec icons (the talent tree icons) once we know someone's spec, class icon until then
local SPEC_ICON = {
	["WARRIOR:Arms"] = "Ability_Warrior_SavageBlow", ["WARRIOR:Fury"] = "Ability_Warrior_InnerRage", ["WARRIOR:Protection"] = "INV_Shield_06",
	["PALADIN:Holy"] = "Spell_Holy_HolyBolt", ["PALADIN:Protection"] = "Spell_Holy_DevotionAura", ["PALADIN:Retribution"] = "Spell_Holy_AuraOfLight",
	["HUNTER:Beast Mastery"] = "Ability_Hunter_BeastTaming", ["HUNTER:Marksmanship"] = "Ability_Marksmanship", ["HUNTER:Survival"] = "Ability_Hunter_SwiftStrike",
	["ROGUE:Assassination"] = "Ability_Rogue_Eviscerate", ["ROGUE:Combat"] = "Ability_BackStab", ["ROGUE:Subtlety"] = "Ability_Stealth",
	["PRIEST:Discipline"] = "Spell_Holy_WordFortitude", ["PRIEST:Holy"] = "Spell_Holy_GuardianSpirit", ["PRIEST:Shadow"] = "Spell_Shadow_ShadowWordPain",
	["DRUID:Balance"] = "Spell_Nature_StarFall", ["DRUID:Feral"] = "Ability_Racial_BearForm", ["DRUID:Restoration"] = "Spell_Nature_HealingTouch",
	["SHAMAN:Elemental"] = "Spell_Nature_Lightning", ["SHAMAN:Enhancement"] = "Spell_Nature_LightningShield", ["SHAMAN:Restoration"] = "Spell_Nature_MagicImmunity",
	["MAGE:Arcane"] = "Spell_Holy_MagicalSentry", ["MAGE:Fire"] = "Spell_Fire_FireBolt02", ["MAGE:Frost"] = "Spell_Frost_FrostBolt02",
	["WARLOCK:Affliction"] = "Spell_Shadow_DeathCoil", ["WARLOCK:Demonology"] = "Spell_Shadow_Metamorphosis", ["WARLOCK:Destruction"] = "Spell_Shadow_RainOfFire",
	["DEATHKNIGHT:Blood"] = "Spell_Deathknight_BloodPresence", ["DEATHKNIGHT:Frost"] = "Spell_Deathknight_FrostPresence", ["DEATHKNIGHT:Unholy"] = "Spell_Deathknight_UnholyPresence",
}

-- what can be shown: stat = the counter, ps = per-second display, count = plain numbers
local DISPLAYS = {
	{ key = "damage", label = "Damage Done", stat = "damage", ps = true },
	{ key = "dps", label = "DPS", stat = "damage", ps = true, rate = true },
	{ key = "taken", label = "Damage Taken", stat = "taken", ps = true },
	{ key = "heal", label = "Healing Done", stat = "heal", ps = true },
	{ key = "hps", label = "HPS", stat = "heal", ps = true, rate = true },
	{ key = "overheal", label = "Overhealing", stat = "overheal" },
	{ key = "dispel", label = "Dispels", stat = "dispel", count = true },
	{ key = "interrupt", label = "Interrupts", stat = "interrupt", count = true },
	{ key = "deaths", label = "Deaths", stat = "deaths", count = true },
}
local DISPLAY = {}
for _, d in ipairs(DISPLAYS) do DISPLAY[d.key] = d end
local STATS = { "damage", "taken", "heal", "overheal", "dispel", "interrupt", "deaths" }

local M = { display = "damage", segment = "current", scroll = 0 }
ns.Meter = M

----------------------------------------------------------------------
-- Who counts: group members by GUID, pets / guardians mapped to their owner
----------------------------------------------------------------------
local group = {}   -- guid -> { name, class }
local owner = {}   -- pet / guardian guid -> owner guid
local function Roster()
	wipe(group)
	local function Add(u, petU)
		local g = UnitGUID(u)
		if g then
			local _, class = UnitClass(u)
			group[g] = { name = UnitName(u), class = class }
			local pg = petU and UnitGUID(petU)
			if pg then owner[pg] = g end
		end
	end
	Add("player", "pet")
	for i = 1, 4 do Add("party" .. i, "partypet" .. i) end
	for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do Add("raid" .. i, "raidpet" .. i) end
end
M.Roster = Roster

----------------------------------------------------------------------
-- Segments
----------------------------------------------------------------------
local function NewSeg() return { start = nil, stop = nil, time = 0, players = {}, enemies = {} } end
local current, overall = NewSeg(), NewSeg()
local history = {}      -- finished fights, newest first
local lastEvent = 0
function M.current() return current end
function M.overall() return overall end
function M.history() return history end

local function Duration(seg)
	if seg == overall then
		local live = (current.start and not current.stop) and (GetTime() - current.start) or 0
		return math.max(1, (overall.time or 0) + live)
	end
	if not seg.start then return 1 end
	return math.max(1, (seg.stop or GetTime()) - seg.start)
end

local known = {} -- guid -> { name, class } for anyone on our side seen in the combat log
local function Entry(seg, guid)
	local p = seg.players[guid]
	if not p then
		local info = group[guid] or known[guid]
		p = { name = info and info.name or "?", class = info and info.class, guid = guid, spells = {} }
		seg.players[guid] = p
	end
	for _, s in ipairs(STATS) do
		p[s] = p[s] or 0
		p.spells[s] = p.spells[s] or {}
	end
	return p
end

local dirty = false
local function Begin()
	local now = GetTime()
	if not current.start or current.stop then
		if current.stop then
			-- the last fight goes into the history list
			table.insert(history, 1, current)
			while #history > HISTORY do table.remove(history) end
			current = NewSeg()
		end
		current.start = now
	end
	lastEvent = now
end

-- amount: what's added; spell: name for the breakdown; crit: counts toward crit %
local function Add(guid, stat, amount, spell, crit, isHit)
	if not amount or amount <= 0 then return end
	Begin()
	for _, seg in ipairs({ current, overall }) do
		local p = Entry(seg, guid)
		p[stat] = p[stat] + amount
		local s = p.spells[stat][spell]
		if not s then
			s = { amount = 0, hits = 0, crits = 0 }
			p.spells[stat][spell] = s
		end
		s.amount = s.amount + amount
		if isHit ~= false then s.hits = s.hits + 1 end
		if crit then s.crits = s.crits + 1 end
	end
	dirty = true
end

local function NoteEnemy(name, amount)
	if not name or not amount or amount <= 0 then return end
	current.enemies[name] = (current.enemies[name] or 0) + amount
end

-- a fight is over when nobody in the party is in combat and nothing happened for 3 seconds
local function CheckEnd()
	if not current.start or current.stop then return end
	if GetTime() - lastEvent < 3 then return end
	if UnitAffectingCombat and UnitAffectingCombat("player") then return end
	for i = 1, 4 do
		if UnitAffectingCombat and UnitExists("party" .. i) and UnitAffectingCombat("party" .. i) then return end
	end
	current.stop = lastEvent
	overall.time = (overall.time or 0) + (current.stop - current.start)
	dirty = true
end

local function SegName(seg)
	if seg == overall then return "Overall" end
	if seg == current then return "Current" end
	local best, bestV
	for name, v in pairs(seg.enemies or {}) do
		if not bestV or v > bestV then best, bestV = name, v end
	end
	return best and ("vs " .. best) or "Fight"
end

function M:Shown()
	if M.segment == "overall" then return overall end
	if M.segment == "current" then return current end
	return history[M.segment] or current
end

function M:Reset()
	current, overall = NewSeg(), NewSeg()
	wipe(history)
	if ns.db.meterOverall and M.key then ns.db.meterOverall[M.key] = overall end
	M.segment = "current"
	M.scroll = 0
	dirty = true
	if M.Update then M:Update() end
end

----------------------------------------------------------------------
-- Combat log
----------------------------------------------------------------------
-- Who on our side did it. The combat log's own flags say "you / your party / your raid", so this
-- works even when the party / raid list isn't ready (or its GUIDs don't match).
local AFFIL = 0x7            -- mine, party, raid
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local TYPE_PET = (COMBATLOG_OBJECT_TYPE_PET or 0x1000) + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)
local AFFIL_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 1
local function NameShort(n) return n and n:match("^[^-]+") or n end
local function Learn(guid, name)
	if known[guid] or group[guid] then return end
	local class
	if GetPlayerInfoByGUID then class = select(2, GetPlayerInfoByGUID(guid)) end
	known[guid] = { name = NameShort(name) or "?", class = class }
end
local function Source(guid, flags, name)
	if group[guid] then return guid end
	local o = owner[guid]
	if o and (group[o] or known[o]) then return o end
	if not flags or band(flags, AFFIL) == 0 then return nil end
	if band(flags, TYPE_PLAYER) > 0 then
		Learn(guid, name)
		return guid
	end
	if band(flags, TYPE_PET) > 0 then
		-- your own pet / guardian: yours. A party / raid pet whose owner we don't know: its own row
		if band(flags, AFFIL_MINE) > 0 then return UnitGUID("player") end
		Learn(guid, name)
		return guid
	end
end
local function Victim(guid, flags, name)
	if group[guid] then return guid end
	if flags and band(flags, AFFIL) > 0 and band(flags, TYPE_PLAYER) > 0 then
		Learn(guid, name)
		return guid
	end
end
local lastHit = {} -- group guid -> "Spell (Source)" of the last damage taken (for Deaths)

-- what the meter has seen (hover the title to read it)
local stats = { events = 0, counted = 0, skipped = 0, lastSkip = nil, lastEventAt = 0, fixes = 0 }
M.stats = stats

ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	stats.events = stats.events + 1
	stats.lastEventAt = GetTime()
	if ns.db.meter == false then return end
	-- guardians (Feral Spirit, Gargoyle, Treants, Mirror Image...) belong to whoever summoned them
	if event == "SPELL_SUMMON" then
		local o = Source(srcGUID, srcFlags, srcName)
		if o and dstGUID then owner[dstGUID] = o end
		return
	end
	local who = Source(srcGUID, srcFlags, srcName)
	local victim = Victim(dstGUID, dstFlags, dstName)

	if event == "SWING_DAMAGE" or event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
		or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
		local spell, amount, overkill, crit
		if event == "SWING_DAMAGE" then
			local a, o, _, _, _, _, c = ...
			spell, amount, overkill, crit = MELEE or "Melee", a, o, c
		else
			local _, name, _, a, o, _, _, _, _, c = ...
			spell, amount, overkill, crit = name or "?", a, o, c
		end
		local real = (amount or 0) - ((overkill and overkill > 0) and overkill or 0)
		if not who and not victim and srcName then
			stats.skipped = stats.skipped + 1
			stats.lastSkip = format("%s from %s (flags 0x%X)", event, srcName, srcFlags or 0)
		end
		if who and not victim then
			stats.counted = stats.counted + 1
			Add(who, "damage", real, spell, crit)
			NoteEnemy(dstName and dstName:match("^[^-]+"), real)
		end
		if victim then
			Add(victim, "taken", amount or 0, spell .. " (" .. ((srcName and srcName:match("^[^-]+")) or "?") .. ")", crit)
			lastHit[victim] = spell .. " (" .. ((srcName and srcName:match("^[^-]+")) or "?") .. ")"
		end
	elseif (event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL") and who then
		local _, name, _, amount, over, _, crit = ...
		amount, over = amount or 0, over or 0
		Add(who, "heal", amount - over, name or "?", crit)
		if over > 0 then Add(who, "overheal", over, name or "?", nil) end
	elseif (event == "SPELL_DISPEL" or event == "SPELL_STOLEN") and who then
		local _, _, _, _, removed = ...
		Add(who, "dispel", 1, removed or "?")
	elseif event == "SPELL_INTERRUPT" and who then
		local _, _, _, _, stopped = ...
		Add(who, "interrupt", 1, stopped or "?")
	elseif event == "UNIT_DIED" and victim then
		Add(victim, "deaths", 1, lastHit[victim] or "?")
		lastHit[victim] = nil
	end
end)

for _, ev in ipairs({ "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
	ns:On(ev, Roster)
end

----------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------
local function Short(n)
	if n >= 1e6 then return format("%.2fM", n / 1e6) end
	if n >= 1e3 then return format("%.1fK", n / 1e3) end
	return tostring(floor(n + 0.5))
end
local function Clock(s)
	s = floor(s)
	return format("%d:%02d", floor(s / 60), s % 60)
end

-- sorted players for the display, and the segment's total for it
local function Ranking(seg, disp)
	local list, total = {}, 0
	local secs = Duration(seg)
	for _, p in pairs(seg.players) do
		local v = p[disp.stat] or 0
		if v > 0 then
			list[#list + 1] = p
			total = total + v
		end
	end
	ns:Sort(list, function(a, b) return a[disp.stat] > b[disp.stat] end)
	return list, total, secs
end

local function RowText(p, disp, total, secs)
	local v = p[disp.stat]
	local pct = total > 0 and (v / total * 100) or 0
	if disp.count then return format("%d (%.1f%%)", v, pct) end
	if disp.rate then return format("%s (%s, %.1f%%)", Short(v / secs), Short(v), pct) end
	return format("%s (%s, %.1f%%)", Short(v), Short(v / secs), pct)
end

----------------------------------------------------------------------
-- Small menus (our own, no Blizzard dropdowns)
----------------------------------------------------------------------
local menu
local function OpenMenu(anchor, items, onPick)
	if not menu then
		menu = CreateFrame("Frame", "AllForOneMeterMenu", UIParent)
		menu:SetFrameStrata("DIALOG")
		ns:Skin(menu)
		menu.fill:SetTexture(0.05, 0.055, 0.065, 0.97)
		menu.buttons = {}
		menu:EnableMouse(true)
		tinsert(UISpecialFrames, "AllForOneMeterMenu")
	end
	for _, b in ipairs(menu.buttons) do b:Hide() end
	local w = 140
	for i, it in ipairs(items) do
		local b = menu.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, menu)
			b:SetHeight(18)
			b.hl = b:CreateTexture(nil, "BACKGROUND")
			b.hl:SetAllPoints(b)
			b.hl:SetTexture(1, 1, 1, 0.08)
			b.hl:Hide()
			b.text = ns:CreateText(b, 12, true, "LEFT")
			b.text:SetPoint("LEFT", 8, 0)
			b.right = ns:CreateText(b, 11, false, "RIGHT")
			b.right:SetPoint("RIGHT", -8, 0)
			b:SetScript("OnEnter", function(self) self.hl:Show() end)
			b:SetScript("OnLeave", function(self) self.hl:Hide() end)
			menu.buttons[i] = b
		end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
		b:SetPoint("RIGHT", menu, "RIGHT", -2, 0)
		b.text:SetText(it.label)
		b.text:SetTextColor(it.active and 1 or 0.85, it.active and 0.82 or 0.85, it.active and 0.3 or 0.85)
		b.right:SetText(it.right or "")
		b.right:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
		b:SetScript("OnClick", function() menu:Hide(); onPick(it.value) end)
		b:Show()
		w = math.max(w, b.text:GetStringWidth() + b.right:GetStringWidth() + 36)
	end
	menu:SetSize(w, #items * 18 + 4)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menu:Show()
end

----------------------------------------------------------------------
-- Breakdown window (click a row)
----------------------------------------------------------------------
local breakdown
local function ShowBreakdown(p, disp)
	if not breakdown then
		breakdown = CreateFrame("Frame", "AllForOneMeterBreakdown", UIParent)
		breakdown:SetFrameStrata("DIALOG")
		breakdown:SetSize(420, 300)
		breakdown:SetPoint("CENTER")
		ns:Skin(breakdown)
		breakdown.fill:SetTexture(0.04, 0.045, 0.055, 0.96)
		breakdown:EnableMouse(true)
		breakdown:SetMovable(true)
		breakdown:RegisterForDrag("LeftButton")
		breakdown:SetScript("OnDragStart", breakdown.StartMoving)
		breakdown:SetScript("OnDragStop", breakdown.StopMovingOrSizing)
		tinsert(UISpecialFrames, "AllForOneMeterBreakdown")
		breakdown.title = ns:CreateText(breakdown, 15, true, "LEFT")
		breakdown.title:SetPoint("TOPLEFT", 10, -8)
		local close = CreateFrame("Button", nil, breakdown, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", 2, 2)
		local head = { { "SPELL", 10, "LEFT" }, { "AMOUNT", 250, "RIGHT" }, { "%", 300, "RIGHT" }, { "HITS", 350, "RIGHT" }, { "CRIT", 404, "RIGHT" } }
		for _, h in ipairs(head) do
			local t = ns:CreateText(breakdown, 11, true, h[3])
			t:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
			if h[3] == "LEFT" then t:SetPoint("TOPLEFT", h[2], -32) else t:SetPoint("TOPRIGHT", breakdown, "TOPLEFT", h[2], -32) end
			t:SetText(h[1])
		end
		breakdown.lines = {}
		for i = 1, 12 do
			local l = ns:CreateBar(breakdown, 400, 18)
			l:SetPoint("TOPLEFT", 10, -48 - (i - 1) * 20)
			local tl = CreateFrame("Frame", nil, l)
			tl:SetAllPoints(l)
			tl:SetFrameLevel(l:GetFrameLevel() + 3)
			l.cols = {}
			for c, h in ipairs(head) do
				local t = ns:CreateText(tl, 12, true, h[3])
				if h[3] == "LEFT" then t:SetPoint("LEFT", 4, 0) else t:SetPoint("RIGHT", l, "LEFT", h[2] - 10, 0) end
				l.cols[c] = t
			end
			breakdown.lines[i] = l
		end
	end
	local spells, total = {}, p[disp.stat] or 0
	for name, s in pairs(p.spells[disp.stat] or {}) do spells[#spells + 1] = { name = name, s = s } end
	ns:Sort(spells, function(a, b) return a.s.amount > b.s.amount end)
	breakdown.title:SetText(p.name .. "  |cff8b8f96" .. disp.label .. " - " .. SegName(M:Shown()) .. "|r")
	breakdown.title:SetTextColor(ns:ClassColor(p.class))
	local r, g, b = ns:ClassColor(p.class)
	for i, l in ipairs(breakdown.lines) do
		local e = spells[i]
		if e then
			l:SetMinMaxValues(0, spells[1].s.amount)
			l:SetValue(e.s.amount)
			l:SetStatusBarColor(r * 0.55, g * 0.55, b * 0.55)
			l.cols[1]:SetText(e.name)
			l.cols[2]:SetText(disp.count and tostring(e.s.amount) or Short(e.s.amount))
			l.cols[3]:SetText(total > 0 and format("%.1f%%", e.s.amount / total * 100) or "")
			l.cols[4]:SetText(disp.count and "" or tostring(e.s.hits))
			l.cols[5]:SetText((not disp.count and e.s.hits > 0) and format("%.0f%%", e.s.crits / e.s.hits * 100) or "")
			l:Show()
		else
			l:Hide()
		end
	end
	breakdown:SetHeight(56 + math.max(1, math.min(12, #spells)) * 20)
	breakdown:Show()
end

----------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------
local win

local function RowTooltip(row)
	local p = row.player
	if not p then return end
	local disp = DISPLAY[M.display]
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(p.name, ns:ClassColor(p.class))
	local spells, total = {}, p[disp.stat]
	for name, s in pairs(p.spells[disp.stat] or {}) do spells[#spells + 1] = { name = name, v = s.amount } end
	ns:Sort(spells, function(a, b) return a.v > b.v end)
	for i = 1, math.min(8, #spells) do
		local s = spells[i]
		GameTooltip:AddDoubleLine(s.name, format("%s (%.1f%%)", disp.count and tostring(s.v) or Short(s.v), s.v / total * 100), 1, 1, 1, 0.85, 0.85, 0.85)
	end
	GameTooltip:AddLine("Click for the full breakdown", 0.55, 0.56, 0.59)
	GameTooltip:Show()
end

local function VisibleRows()
	return math.max(1, math.min(MAX_ROWS, floor((win:GetHeight() - TITLE_H - 2) / (ROW_H + ROW_GAP))))
end

function M:Update()
	if not win then return end
	if ns.db.meter == false then win:Hide() return end
	win:Show()
	dirty = false
	local disp = DISPLAY[M.display] or DISPLAYS[1]
	local seg = M:Shown()
	local list, total, secs = Ranking(seg, disp)
	win.title:SetText(strupper(disp.label))
	win.seg:SetText(strupper(SegName(seg)) .. ((seg.start or seg == overall) and ("  " .. Clock(secs)) or ""))
	local n = VisibleRows()
	M.scroll = math.max(0, math.min(M.scroll, #list - n))
	-- scrollbar: only when there are more players than rows
	local maxScroll = math.max(0, #list - n)
	local sb = win.scrollbar
	if sb then
		local want = maxScroll > 0
		if want ~= sb.wanted then
			sb.wanted = want
			if want then sb:Show() else sb:Hide() end
			for _, row in ipairs(win.rows) do
				row:SetPoint("RIGHT", win, "RIGHT", want and -9 or -2, 0)
			end
		end
		if want then
			sb.updating = true
			sb:SetMinMaxValues(0, maxScroll)
			sb:SetValue(M.scroll)
			-- thumb size follows how much of the list is visible
			local h = sb:GetHeight() or 0
			sb.thumb:SetHeight(math.max(12, h * n / #list))
			sb.updating = nil
		end
	end
	local top = list[1] and list[1][disp.stat] or 1
	for i, row in ipairs(win.rows) do
		local idx = i + M.scroll
		local p = (i <= n) and list[idx] or nil
		row.player = p
		if p then
			row:SetMinMaxValues(0, top)
			row:SetValue(p[disp.stat])
			local r, g, b = ns:ClassColor(p.class)
			row:SetStatusBarColor(r * 0.72, g * 0.72, b * 0.72)
			row.edge:SetVertexColor(r, g, b, 0.9)
			local spec = p.class and p.guid and ns.specs[p.guid]
			local specIcon = spec and SPEC_ICON[p.class .. ":" .. spec]
			local coords = p.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.class]
			if specIcon then
				row.icon:SetTexture("Interface\\Icons\\" .. specIcon)
				row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			elseif coords then
				row.icon:SetTexture(CLASS_TEX)
				row.icon:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
			else
				row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
			row.name:SetText(idx .. ". " .. (p.name or "?"))
			row.value:SetText(RowText(p, disp, total, secs))
			row:Show()
		else
			row:Hide()
		end
	end
	-- nothing recorded: no background at all, only the title and buttons stay visible
	local empty = #list == 0
	win.fill:SetAlpha(empty and 0 or 1)
	win.frameLine:SetAlpha(empty and 0 or 1)
	-- the title row keeps its dark background either way (on its own it needs to be solid)
	if empty then win.barBg:SetTexture(0.025, 0.028, 0.032, 0.92) else win.barBg:SetTexture(0, 0, 0, 0.3) end
	win.empty:Hide()
end

local function IconButton(parent, texture, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(16, 16)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints(b)
	b.tex:SetTexture(texture)
	b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.tex:SetVertexColor(0.8, 0.8, 0.8)
	if b.tex.SetDesaturated then b.tex:SetDesaturated(true) end
	b.tex:SetVertexColor(1, 0.78, 0.3) -- gold toolbar icons
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		self.tex:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self) self.tex:SetVertexColor(1, 0.78, 0.3); GameTooltip:Hide() end)
	return b
end

local function SegmentItems()
	local items = {
		{ label = "CURRENT", value = "current", active = M.segment == "current", right = current.start and Clock(Duration(current)) or "" },
		{ label = "OVERALL", value = "overall", active = M.segment == "overall", right = Clock(Duration(overall)) },
	}
	for i, seg in ipairs(history) do
		items[#items + 1] = { label = "#" .. i .. "  " .. strupper(SegName(seg)), value = i, active = M.segment == i, right = Clock(Duration(seg)) }
	end
	return items
end

local function DisplayItems()
	local items = {}
	for _, d in ipairs(DISPLAYS) do items[#items + 1] = { label = strupper(d.label), value = d.key, active = M.display == d.key } end
	return items
end

local function Build()
	-- Overall is kept for this character between sessions
	ns.db.meterOverall = ns.db.meterOverall or {}
	M.key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	ns.db.meterOverall[M.key] = ns.db.meterOverall[M.key] or NewSeg()
	overall = ns.db.meterOverall[M.key]
	overall.players = overall.players or {}
	overall.enemies = overall.enemies or {}
	overall.start, overall.stop = nil, nil
	ns.db.meterAll = nil -- older version's data

	win = CreateFrame("Frame", "AllForOneMeter", ns.root)
	win:SetSize(ns.db.meterW or 320, ns.db.meterH or (TITLE_H + 8 * (ROW_H + ROW_GAP) + 3))
	ns:Skin(win)
	win.fill:SetTexture(0.035, 0.04, 0.045, 0.88)
	-- thin light frame around the window, like Details!
	local frameLine = win:CreateTexture(nil, "BACKGROUND", nil, -1)
	win.frameLine = frameLine
	frameLine:SetTexture(0.32, 0.33, 0.36, 1)
	frameLine:SetPoint("TOPLEFT", -1, 1)
	frameLine:SetPoint("BOTTOMRIGHT", 1, -1)
	if win.outline then win.outline:Hide() end
	-- position: top-left corner by default; once you drag it, wherever you left it
	-- (its own lock button, not part of /afo unlock)
	local function Place()
		win:ClearAllPoints()
		local pos = ns.db.meterPos
		if pos then
			win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
		else
			win:SetPoint("TOPLEFT", ns.root, "TOPLEFT", 24, -64)
		end
	end
	Place()
	M.Place = Place
	win:SetMovable(true)
	win:SetClampedToScreen(true)

	-- title bar
	local bar = CreateFrame("Frame", nil, win)
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", 0, 0)
	bar:SetHeight(TITLE_H)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints(bar)
	barBg:SetTexture(0, 0, 0, 0.3)
	win.barBg = barBg
	-- drag the title bar to move the window (while unlocked)
	bar:EnableMouse(true)
	-- hover the title: what the meter has received (to find out why something isn't counted)
	bar:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("Combat meter")
		GameTooltip:AddDoubleLine("Combat log events received", stats.events, 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Damage hits counted", stats.counted, 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Damage hits skipped", stats.skipped, 0.8, 0.8, 0.8, 1, 1, 1)
		local n = 0
		for _ in pairs(group) do n = n + 1 end
		GameTooltip:AddDoubleLine("Group members known", n, 0.8, 0.8, 0.8, 1, 1, 1)
		GameTooltip:AddDoubleLine("Combat log resets", stats.fixes, 0.8, 0.8, 0.8, 1, 1, 1)
		if stats.lastSkip then GameTooltip:AddLine("Last skipped: " .. stats.lastSkip, 0.6, 0.6, 0.6, true) end
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() if not ns.db.meterLocked then win:StartMoving() end end)
	bar:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		ns.db.meterPos = { x = floor(win:GetLeft() + 0.5), y = floor(win:GetTop() + 0.5) }
		Place()
	end)
	-- toolbar on the right (gold icons), title on the left
	local resetBtn = IconButton(bar, "Interface\\Icons\\Spell_Shadow_SacrificialShield", "Reset all data", function() M:Reset() end)
	-- lock: no dragging, no resizing
	local lockBtn = IconButton(bar, "Interface\\LFGFrame\\UI-LFG-ICON-LOCK", "", function(self)
		ns.db.meterLocked = not ns.db.meterLocked
		M:ApplyLock()
		if self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
	end)
	lockBtn.tex:SetTexCoord(0.1, 0.9, 0.1, 0.9)
	lockBtn:SetPoint("RIGHT", -6, 0)
	lockBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(ns.db.meterLocked and "Locked - click to unlock" or "Unlocked - drag the title to move, the corner to resize. Click to lock")
		GameTooltip:Show()
	end)
	lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	win.lockBtn = lockBtn
	resetBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)
	local dispBtn = IconButton(bar, "Interface\\Icons\\Ability_DualWield", "Display: damage, healing, dispels...",
		function(self) OpenMenu(self, DisplayItems(), function(v) M.display = v; M.scroll = 0; M:Update() end) end)
	dispBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
	local segBtn = IconButton(bar, "Interface\\Icons\\INV_Misc_PocketWatch_01", "Segment: current, overall, past fights",
		function(self) OpenMenu(self, SegmentItems(), function(v) M.segment = v; M.scroll = 0; M:Update() end) end)
	segBtn:SetPoint("RIGHT", dispBtn, "LEFT", -6, 0)
	win.title = ns:CreateText(bar, 16, true, "LEFT")
	win.title:SetPoint("LEFT", 10, 0)
	win.title:SetShadowColor(0, 0, 0, 1)
	win.title:SetShadowOffset(1, -1)
	win.seg = ns:CreateText(bar, 11, true, "LEFT")
	win.seg:SetPoint("LEFT", win.title, "RIGHT", 10, 0)
	win.seg:SetPoint("RIGHT", segBtn, "LEFT", -6, 0)
	win.seg:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	win.clock = win.seg

	-- rows
	win.rows = {}
	for i = 1, MAX_ROWS do
		local row = ns:CreateBar(win, 10, ROW_H)
		-- the bar starts right of the spec / class icon
		row:SetPoint("TOPLEFT", 2 + ROW_H + 1, -TITLE_H - 1 - (i - 1) * (ROW_H + ROW_GAP))
		row:SetPoint("RIGHT", win, "RIGHT", -2, 0)
		if row.outline then row.outline:Hide() end
		-- a thin bright line along the top of the bar in the class color
		row.edge = row:CreateTexture(nil, "OVERLAY")
		row.edge:SetTexture(1, 1, 1, 1)
		row.edge:SetPoint("TOPLEFT", row:GetStatusBarTexture(), "TOPLEFT", 0, 0)
		row.edge:SetPoint("TOPRIGHT", row:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
		row.edge:SetHeight(1)
		-- text on its own layer above the bar's shine
		local tl = CreateFrame("Frame", nil, row)
		tl:SetAllPoints(row)
		tl:SetFrameLevel(row:GetFrameLevel() + 3)
		row.icon = tl:CreateTexture(nil, "OVERLAY")
		row.icon:SetSize(ROW_H, ROW_H)
		row.icon:SetPoint("RIGHT", row, "LEFT", -1, 0)
		row.value = ns:CreateText(tl, 15, true, "RIGHT")
		row.value:SetPoint("RIGHT", -5, 0)
		row.name = ns:CreateText(tl, 15, true, "LEFT")
		row.name:SetPoint("LEFT", 6, 0)
		row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
		for _, fs in ipairs({ row.name, row.value }) do
			fs:SetShadowColor(0, 0, 0, 1)
			fs:SetShadowOffset(1, -1)
		end
		row:EnableMouse(true)
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:SetScript("OnMouseUp", function(self, button)
			if button == "LeftButton" and self.player then ShowBreakdown(self.player, DISPLAY[M.display]) end
		end)
		row:Hide()
		win.rows[i] = row
	end
	win.empty = ns:CreateText(win, 12, false, "LEFT")
	win.empty:SetPoint("TOPLEFT", 8, -TITLE_H - 6)
	win.empty:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	win.empty:SetText("no data yet")

	-- slim scrollbar on the right (drag it, or use the mouse wheel)
	local sb = CreateFrame("Slider", nil, win)
	sb:SetOrientation("VERTICAL")
	sb:SetWidth(5)
	sb:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -TITLE_H - 2)
	sb:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 16)
	local track = sb:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints(sb)
	track:SetTexture(1, 1, 1, 0.08)
	sb.thumb = sb:CreateTexture(nil, "OVERLAY")
	sb.thumb:SetTexture(1, 0.78, 0.3, 0.85)
	sb.thumb:SetSize(5, 24)
	sb:SetThumbTexture(sb.thumb)
	sb:SetValueStep(1)
	sb:SetMinMaxValues(0, 0)
	sb:SetValue(0)
	sb:SetScript("OnValueChanged", function(self, v)
		if self.updating then return end
		M.scroll = floor(v + 0.5)
		M:Update()
	end)
	sb:Hide()
	win.scrollbar = sb

	-- mouse wheel scrolls the rows
	win:EnableMouseWheel(true)
	win:SetScript("OnMouseWheel", function(_, delta)
		M.scroll = math.max(0, M.scroll - delta)
		M:Update()
	end)

	-- drag the bottom-right corner to resize
	win:SetResizable(true)
	win:SetMinResize(180, TITLE_H + 2 * (ROW_H + ROW_GAP) + 2)
	win:SetMaxResize(500, TITLE_H + MAX_ROWS * (ROW_H + ROW_GAP) + 2)
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(14, 14)
	grip:SetPoint("BOTTOMRIGHT", 0, 0)
	grip:SetFrameLevel(win:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() if not ns.db.meterLocked then win:StartSizing("BOTTOMRIGHT") end end)
	grip:SetScript("OnMouseUp", function()
		win:StopMovingOrSizing()
		ns.db.meterW, ns.db.meterH = floor(win:GetWidth() + 0.5), floor(win:GetHeight() + 0.5)
		if win:GetLeft() then ns.db.meterPos = { x = floor(win:GetLeft() + 0.5), y = floor(win:GetTop() + 0.5) } end
		Place()
		M:Update()
	end)
	win:SetScript("OnSizeChanged", function() M:Update() end)
	win.grip = grip
	function M:ApplyLock()
		local locked = ns.db.meterLocked
		if locked then win.grip:Hide() else win.grip:Show() end
		-- gold = locked, grey = unlocked
		if win.lockBtn.tex.SetDesaturated then win.lockBtn.tex:SetDesaturated(true) end
		if locked then win.lockBtn.tex:SetVertexColor(1, 0.78, 0.3) else win.lockBtn.tex:SetVertexColor(0.55, 0.56, 0.59) end
	end
	M:ApplyLock()

	-- refresh twice a second when something changed (and while a fight runs)
	local acc = 0
	win:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		-- errors here would be silent (3.3.5 hides Lua errors by default): report them in chat
		local ok, err = pcall(function()
			-- 3.3.5 bug: the combat log can stop reaching addons; clearing it brings it back
			-- (the same fix Recount / Skada use)
			if CombatLogClearEntries and UnitAffectingCombat and UnitAffectingCombat("player")
				and GetTime() - stats.lastEventAt > 5 and GetTime() - (stats.lastFix or 0) > 5 then
				stats.lastFix = GetTime()
				stats.fixes = stats.fixes + 1
				CombatLogClearEntries()
			end
			CheckEnd()
			if dirty or (current.start and not current.stop) then M:Update() end
		end)
		if not ok and err ~= M.lastErr then M.lastErr = err; ns:Report(err) end
	end)
	M:Update()
end

ns:Listen("LOGIN", function()
	Roster()
	local ok, err = pcall(Build)
	if not ok then ns:Report(err) end
end)
