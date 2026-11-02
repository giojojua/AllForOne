-- AllForOne: damage / healing meter (a small Recount)
-- Counts you, your party / raid and everyone's pets and guardians (pets add to their owner).
-- Two segments: CURRENT (this fight, or the last one) and OVERALL (since you zoned into the
-- battleground / arena, or since the last reset). Click the title for damage <-> healing, the
-- segment name for current <-> overall, the x to reset. Hover a bar for that player's top spells.
local _, ns = ...
local colors = ns.colors
local GetTime, band = GetTime, bit.band

local ROWS, ROW_H, W = 8, 18, 230
local MINE = (COMBATLOG_OBJECT_AFFILIATION_MINE or 1) + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 2)
	+ (COMBATLOG_OBJECT_AFFILIATION_RAID or 4)

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
local current, overall = NewSeg(), NewSeg()
local lastEvent = 0
M.current, M.overall = function() return current end, function() return overall end

local function Duration(seg)
	if seg == overall then
		local live = (current.start and not current.stop) and (GetTime() - current.start) or 0
		return math.max(1, overall.time + live)
	end
	if not seg.start then return 1 end
	return math.max(1, (seg.stop or GetTime()) - seg.start)
end

local function Entry(seg, guid)
	local p = seg.players[guid]
	if not p then
		local info = group[guid]
		p = { name = info and info.name or "?", class = info and info.class, damage = 0, heal = 0, spells = { damage = {}, heal = {} } }
		seg.players[guid] = p
	end
	return p
end

local dirty = false
local function Add(guid, kind, amount, spell)
	if amount <= 0 then return end
	local now = GetTime()
	if not current.start or current.stop then
		-- a new fight: the old "current" is done
		if current.stop then current = NewSeg() end
		current.start = now
	end
	lastEvent = now
	for _, seg in ipairs({ current, overall }) do
		local p = Entry(seg, guid)
		p[kind] = p[kind] + amount
		local s = p.spells[kind]
		s[spell] = (s[spell] or 0) + amount
	end
	dirty = true
end

-- the fight is over when nobody in the group is in combat and nothing happened for 3 seconds
local function CheckEnd()
	if not current.start or current.stop then return end
	if GetTime() - lastEvent < 3 then return end
	if UnitAffectingCombat and UnitAffectingCombat("player") then return end
	for i = 1, 4 do
		if UnitAffectingCombat and UnitExists("party" .. i) and UnitAffectingCombat("party" .. i) then return end
	end
	current.stop = lastEvent
	overall.time = overall.time + (current.stop - current.start)
	dirty = true
end

function M:Reset()
	current, overall = NewSeg(), NewSeg()
	dirty = true
	if M.Update then M:Update() end
end

----------------------------------------------------------------------
-- Combat log
----------------------------------------------------------------------
local function Source(srcGUID, srcFlags)
	if group[srcGUID] then return srcGUID end
	local o = owner[srcGUID]
	if o and group[o] then return o end
	return nil
end

ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...)
	if ns.db.meter == false then return end
	-- guardians (Feral Spirit, Gargoyle, Treants, Mirror Image...) belong to whoever summoned them
	if event == "SPELL_SUMMON" then
		local o = Source(srcGUID, srcFlags)
		if o and dstGUID then owner[dstGUID] = o end
		return
	end
	if not srcFlags or band(srcFlags, MINE) == 0 then return end
	local who = Source(srcGUID, srcFlags)
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
	end
end)

for _, ev in ipairs({ "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
	ns:On(ev, Roster)
end
-- a new battleground / arena starts a new overall
ns:On("PLAYER_ENTERING_WORLD", function()
	local _, kind = IsInInstance()
	if kind == "pvp" or kind == "arena" then M:Reset() end
end)

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local function Short(n)
	if n >= 1e6 then return format("%.2fm", n / 1e6) end
	if n >= 1e4 then return format("%.1fk", n / 1e3) end
	return tostring(floor(n + 0.5))
end

local win
local function Sorted()
	local seg = (M.seg == "overall") and overall or current
	local list = {}
	for guid, p in pairs(seg.players) do
		if p[M.mode] > 0 then list[#list + 1] = p end
	end
	ns:Sort(list, function(a, b) return a[M.mode] > b[M.mode] end)
	return list, seg
end

local function RowTooltip(row)
	local p = row.player
	if not p then return end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:AddLine(p.name, ns:ClassColor(p.class))
	local spells = {}
	for name, v in pairs(p.spells[M.mode]) do spells[#spells + 1] = { name = name, v = v } end
	ns:Sort(spells, function(a, b) return a.v > b.v end)
	local total = p[M.mode]
	for i = 1, math.min(6, #spells) do
		local s = spells[i]
		GameTooltip:AddDoubleLine(s.name, format("%s  %d%%", Short(s.v), floor(s.v / total * 100 + 0.5)), 1, 1, 1, 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end

function M:Update()
	if not win then return end
	if ns.db.meter == false then win:Hide() return end
	win:Show()
	dirty = false
	local list, seg = Sorted()
	local secs = Duration(seg)
	win.title:SetText(M.mode == "damage" and "DAMAGE" or "HEALING")
	win.seg:SetText(M.seg == "overall" and "OVERALL" or "CURRENT")
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
			row:SetStatusBarColor(ns:BarColor(p.class))
			row.left:SetText(i .. ". " .. (p.name or "?"))
			row.right:SetText(format("%s |cffc8c8c8(%s)|r", Short(v), Short(v / secs)))
			row:Show()
		else
			row:Hide()
		end
	end
	win.empty:SetShown(shown == 0)
	win:SetHeight(22 + math.max(1, shown) * (ROW_H + 1) + 3)
end

local function Build()
	win = CreateFrame("Frame", "AllForOneMeter", ns.root)
	win:SetSize(W, 22 + ROW_H + 4)
	ns:Skin(win)
	win.fill:SetTexture(0.03, 0.035, 0.043, 0.8)
	ns:Mover("meter", "DAMAGE METER", win, "BOTTOMRIGHT", "BOTTOMRIGHT", -114, 96)

	-- header: [DAMAGE] [CURRENT] ............ [x]
	local function HeaderButton(text, w, onClick)
		local b = CreateFrame("Button", nil, win)
		b:SetSize(w, 20)
		b.text = ns:CreateText(b, 12, true, "LEFT")
		b.text:SetPoint("LEFT", 0, 0)
		b.text:SetText(text)
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", function() b.text:SetTextColor(1, 0.82, 0.3) end)
		b:SetScript("OnLeave", function() b.text:SetTextColor(b.r or 1, b.g or 1, b.b or 1) end)
		return b
	end
	local title = HeaderButton("DAMAGE", 70, function() M.mode = (M.mode == "damage") and "heal" or "damage"; M:Update() end)
	title:SetPoint("TOPLEFT", 6, -1)
	win.title = title.text
	local seg = HeaderButton("CURRENT", 70, function() M.seg = (M.seg == "current") and "overall" or "current"; M:Update() end)
	seg:SetPoint("LEFT", title, "RIGHT", 4, 0)
	seg.r, seg.g, seg.b = colors.muted[1], colors.muted[2], colors.muted[3]
	seg.text:SetTextColor(seg.r, seg.g, seg.b)
	win.seg = seg.text
	local reset = HeaderButton("x", 16, function() M:Reset() end)
	reset:SetPoint("TOPRIGHT", -2, -1)
	reset.r, reset.g, reset.b = colors.muted[1], colors.muted[2], colors.muted[3]
	reset.text:SetTextColor(reset.r, reset.g, reset.b)

	win.rows = {}
	for i = 1, ROWS do
		local row = ns:CreateBar(win, W - 6, ROW_H)
		row:SetPoint("TOPLEFT", 3, -22 - (i - 1) * (ROW_H + 1))
		row.left = ns:CreateText(row, 12, true, "LEFT")
		row.left:SetPoint("LEFT", 4, 0)
		row.right = ns:CreateText(row, 12, true, "RIGHT")
		row.right:SetPoint("RIGHT", -4, 0)
		row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
		row:EnableMouse(true)
		row:SetScript("OnEnter", RowTooltip)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row:Hide()
		win.rows[i] = row
	end
	win.empty = ns:CreateText(win, 12, false, "LEFT")
	win.empty:SetPoint("TOPLEFT", 8, -26)
	win.empty:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	win.empty:SetText("nothing yet")
	if not win.empty.SetShown then
		win.empty.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
	end

	-- refresh twice a second while something changed (and the live dps keeps moving in combat)
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
