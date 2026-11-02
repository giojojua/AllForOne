-- AllForOne: damage / healing / dispel meter (a small Recount)
-- Counts you, your party / raid and everyone's pets and guardians (pets add to their owner).
--   modes:    DAMAGE (done), HEALING (done, no overheal), DISPELS (your side removing auras)
--   segments: CURRENT (this fight, or the last one) and ALL TIME (kept between sessions for this
--             character, until you press x while ALL TIME is shown)
-- Hover a bar: that player's top spells (dispels: what they removed).
local _, ns = ...
local colors = ns.colors
local GetTime, band = GetTime, bit.band

local ROWS, ROW_H, W = 8, 20, 250
local HEAD_H = 42
local MINE = (COMBATLOG_OBJECT_AFFILIATION_MINE or 1) + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 2)
	+ (COMBATLOG_OBJECT_AFFILIATION_RAID or 4)
local MODES = { { key = "damage", label = "DAMAGE" }, { key = "heal", label = "HEALING" }, { key = "dispel", label = "DISPELS" } }
local SEGS = { { key = "current", label = "CURRENT" }, { key = "all", label = "ALL TIME" } }

local M = { mode = "damage", seg = "current" }
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
local function NewSeg() return { start = nil, stop = nil, time = 0, players = {} } end
local current, all = NewSeg(), NewSeg()
local lastEvent = 0
function M.current() return current end
function M.all() return all end

local function Duration(seg)
	if seg == all then
		local live = (current.start and not current.stop) and (GetTime() - current.start) or 0
		return math.max(1, (all.time or 0) + live)
	end
	if not seg.start then return 1 end
	return math.max(1, (seg.stop or GetTime()) - seg.start)
end

local function Entry(seg, guid)
	local p = seg.players[guid]
	local info = group[guid]
	if not p then
		p = { name = info and info.name or "?", class = info and info.class, damage = 0, heal = 0, dispel = 0,
			spells = { damage = {}, heal = {}, dispel = {} } }
		seg.players[guid] = p
	end
	-- saved data from older versions
	p.dispel = p.dispel or 0
	p.spells.dispel = p.spells.dispel or {}
	return p
end

local dirty = false
local function Add(guid, kind, amount, spell)
	if not amount or amount <= 0 then return end
	local now = GetTime()
	if not current.start or current.stop then
		if current.stop then current = NewSeg() end -- a new fight: the old one is done
		current.start = now
	end
	lastEvent = now
	for _, seg in ipairs({ current, all }) do
		local p = Entry(seg, guid)
		p[kind] = p[kind] + amount
		local s = p.spells[kind]
		s[spell] = (s[spell] or 0) + amount
	end
	dirty = true
end

-- the fight is over when nobody in the party is in combat and nothing happened for 3 seconds
local function CheckEnd()
	if not current.start or current.stop then return end
	if GetTime() - lastEvent < 3 then return end
	if UnitAffectingCombat and UnitAffectingCombat("player") then return end
	for i = 1, 4 do
		if UnitAffectingCombat and UnitExists("party" .. i) and UnitAffectingCombat("party" .. i) then return end
	end
	current.stop = lastEvent
	all.time = (all.time or 0) + (current.stop - current.start)
	dirty = true
end

-- x resets the segment you're looking at
function M:Reset(which)
	which = which or M.seg
	if which == "all" then
		wipe(all.players)
		all.time = 0
	else
		current = NewSeg()
	end
	dirty = true
	if M.Update then M:Update() end
end

----------------------------------------------------------------------
-- Combat log
----------------------------------------------------------------------
local function Source(srcGUID)
	if group[srcGUID] then return srcGUID end
	local o = owner[srcGUID]
	if o and group[o] then return o end
end

ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	if ns.db.meter == false then return end
	-- guardians (Feral Spirit, Gargoyle, Treants, Mirror Image...) belong to whoever summoned them
	if event == "SPELL_SUMMON" then
		local o = Source(srcGUID)
		if o and dstGUID then owner[dstGUID] = o end
		return
	end
	if not srcFlags or band(srcFlags, MINE) == 0 then return end
	local who = Source(srcGUID)
	if not who then return end
	if event == "SWING_DAMAGE" then
		if group[dstGUID] then return end -- no friendly fire
		local amount, overkill = ...
		Add(who, "damage", (amount or 0) - ((overkill and overkill > 0) and overkill or 0), MELEE or "Melee")
	elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
		if group[dstGUID] then return end
		local _, spellName, _, amount, overkill = ...
		Add(who, "damage", (amount or 0) - ((overkill and overkill > 0) and overkill or 0), spellName or "?")
	elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
		local _, spellName, _, amount, over = ...
		Add(who, "heal", (amount or 0) - (over or 0), spellName or "?")
	elseif event == "SPELL_DISPEL" or event == "SPELL_STOLEN" then
		-- what was removed: Polymorph, Power Word: Shield, Fear...
		local _, _, _, _, removed = ...
		Add(who, "dispel", 1, removed or "?")
	end
end)

for _, ev in ipairs({ "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
	ns:On(ev, Roster)
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local function Short(n)
	if n >= 1e6 then return format("%.2fm", n / 1e6) end
	if n >= 1e4 then return format("%.1fk", n / 1e3) end
	return tostring(floor(n + 0.5))
end
local function Clock(s)
	s = floor(s)
	if s >= 3600 then return format("%d:%02d:%02d", floor(s / 3600), floor(s / 60) % 60, s % 60) end
	return format("%d:%02d", floor(s / 60), s % 60)
end

local win
local function Shown() return (M.seg == "all") and all or current end
local function Sorted()
	local seg = Shown()
	local list = {}
	for _, p in pairs(seg.players) do
		if (p[M.mode] or 0) > 0 then list[#list + 1] = p end
	end
	ns:Sort(list, function(a, b) return a[M.mode] > b[M.mode] end)
	return list, seg
end

local function RowTooltip(row)
	local p = row.player
	if not p then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(p.name, ns:ClassColor(p.class))
	local spells = {}
	for name, v in pairs(p.spells[M.mode] or {}) do spells[#spells + 1] = { name = name, v = v } end
	ns:Sort(spells, function(a, b) return a.v > b.v end)
	local total = p[M.mode]
	if M.mode == "dispel" then GameTooltip:AddLine("Removed:", 0.55, 0.56, 0.59) end
	for i = 1, math.min(8, #spells) do
		local s = spells[i]
		local right = (M.mode == "dispel") and ("x" .. s.v) or format("%s  %d%%", Short(s.v), floor(s.v / total * 100 + 0.5))
		GameTooltip:AddDoubleLine(s.name, right, 1, 1, 1, 0.85, 0.85, 0.85)
	end
	GameTooltip:Show()
end

function M:Update()
	if not win then return end
	if ns.db.meter == false then win:Hide() return end
	win:Show()
	dirty = false
	for _, t in ipairs(win.modeTabs) do t:SetActive(t.key == M.mode) end
	for _, t in ipairs(win.segTabs) do t:SetActive(t.key == M.seg) end
	local list, seg = Sorted()
	local secs = Duration(seg)
	win.clock:SetText((seg.start or seg == all) and Clock(secs) or "")
	local top = list[1] and list[1][M.mode] or 1
	local shown = 0
	for i, row in ipairs(win.rows) do
		local p = list[i]
		row.player = p
		if p then
			shown = i
			local v = p[M.mode]
			row:SetMinMaxValues(0, top)
			row:SetValue(v)
			-- darker class color: white text stays readable on every class (even priests)
			local r, g, b = ns:ClassColor(p.class)
			row:SetStatusBarColor(r * 0.62, g * 0.62, b * 0.62)
			row.name:SetText(i .. ". " .. (p.name or "?"))
			if M.mode == "dispel" then
				row.value:SetText(tostring(v))
			else
				row.value:SetText(format("%s |cffb4b8bf(%s)|r", Short(v), Short(v / secs)))
			end
			row:Show()
		else
			row:Hide()
		end
	end
	if shown == 0 then win.empty:Show() else win.empty:Hide() end
	win:SetHeight(HEAD_H + math.max(1, shown) * (ROW_H + 1) + 3)
end

local function Tab(parent, label, key, onClick)
	local b = CreateFrame("Button", nil, parent)
	b.key = key
	b.text = ns:CreateText(b, 13, true, "LEFT")
	b.text:SetPoint("LEFT", 0, 0)
	b.text:SetText(label)
	b:SetSize(b.text:GetStringWidth() + 4, 18)
	b.line = b:CreateTexture(nil, "ARTWORK")
	b.line:SetTexture(1, 0.82, 0.3, 1)
	b.line:SetHeight(2)
	b.line:SetPoint("BOTTOMLEFT", 0, -1)
	b.line:SetPoint("BOTTOMRIGHT", -4, -1)
	function b:SetActive(on)
		self.active = on
		if on then
			self.text:SetTextColor(1, 1, 1)
			self.line:Show()
		else
			self.text:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
			self.line:Hide()
		end
	end
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self) if not self.active then self.text:SetTextColor(0.85, 0.85, 0.85) end end)
	b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
	return b
end

local function Build()
	-- ALL TIME is kept for this character between sessions
	ns.db.meterAll = ns.db.meterAll or {}
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	ns.db.meterAll[key] = ns.db.meterAll[key] or NewSeg()
	all = ns.db.meterAll[key]
	all.players = all.players or {}
	all.start, all.stop = nil, nil

	win = CreateFrame("Frame", "AllForOneMeter", ns.root)
	win:SetSize(W, HEAD_H + ROW_H + 4)
	ns:Skin(win)
	win.fill:SetTexture(0.03, 0.035, 0.043, 0.85)
	-- top-left corner of the screen; it grows downward as players appear (max 8 rows)
	ns:Mover("meter", "DAMAGE METER", win, "TOPLEFT", "TOPLEFT", 24, -24)

	-- header line 1: DAMAGE  HEALING  DISPELS                x
	-- header line 2: CURRENT  ALL TIME                     3:42
	win.modeTabs, win.segTabs = {}, {}
	local prev
	for _, m in ipairs(MODES) do
		local t = Tab(win, m.label, m.key, function() M.mode = m.key; M:Update() end)
		if prev then t:SetPoint("LEFT", prev, "RIGHT", 10, 0) else t:SetPoint("TOPLEFT", 7, -3) end
		win.modeTabs[#win.modeTabs + 1] = t
		prev = t
	end
	prev = nil
	for _, s in ipairs(SEGS) do
		local t = Tab(win, s.label, s.key, function() M.seg = s.key; M:Update() end)
		if prev then t:SetPoint("LEFT", prev, "RIGHT", 10, 0) else t:SetPoint("TOPLEFT", 7, -22) end
		win.segTabs[#win.segTabs + 1] = t
		prev = t
	end
	local reset = CreateFrame("Button", nil, win)
	reset:SetSize(18, 18)
	reset:SetPoint("TOPRIGHT", -3, -3)
	reset.text = ns:CreateText(reset, 14, true, "CENTER")
	reset.text:SetPoint("CENTER", 0, 0)
	reset.text:SetText("x")
	reset.text:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	reset:SetScript("OnClick", function() M:Reset() end)
	reset:SetScript("OnEnter", function(self)
		self.text:SetTextColor(1, 0.35, 0.35)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(M.seg == "all" and "Reset ALL TIME" or "Reset this fight")
		GameTooltip:Show()
	end)
	reset:SetScript("OnLeave", function(self)
		self.text:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
		GameTooltip:Hide()
	end)
	win.clock = ns:CreateText(win, 12, true, "RIGHT")
	win.clock:SetPoint("TOPRIGHT", -6, -24)
	win.clock:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])

	win.rows = {}
	for i = 1, ROWS do
		local row = ns:CreateBar(win, W - 6, ROW_H)
		row:SetPoint("TOPLEFT", 3, -HEAD_H - (i - 1) * (ROW_H + 1))
		-- text on its own layer above the bar's shine, so the shine never washes it out
		local textLayer = CreateFrame("Frame", nil, row)
		textLayer:SetAllPoints(row)
		textLayer:SetFrameLevel(row:GetFrameLevel() + 3)
		row.value = ns:CreateText(textLayer, 13, true, "RIGHT")
		row.value:SetPoint("RIGHT", -5, 0)
		row.name = ns:CreateText(textLayer, 13, true, "LEFT")
		row.name:SetPoint("LEFT", 5, 0)
		row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
		for _, fs in ipairs({ row.name, row.value }) do
			fs:SetShadowColor(0, 0, 0, 1)
			fs:SetShadowOffset(1, -1)
		end
		row:EnableMouse(true)
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:Hide()
		win.rows[i] = row
	end
	win.empty = ns:CreateText(win, 12, false, "LEFT")
	win.empty:SetPoint("TOPLEFT", 8, -HEAD_H - 4)
	win.empty:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	win.empty:SetText("nothing yet")

	-- refresh twice a second when something changed (and while a fight runs: the per-second numbers move)
	local acc = 0
	win:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		CheckEnd()
		if dirty or (current.start and not current.stop) then M:Update() end
	end)
	M:Update()
end

ns:Listen("LOGIN", function()
	Roster()
	local ok, err = pcall(Build)
	if not ok then ns:Report(err) end
end)
