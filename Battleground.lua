-- AllForOne: battlegrounds
--   * Blizzard's score at the top (bases, resources, flags) moved into a movable holder, flat font
--   * Flag carriers (Warsong Gulch, Eye of the Storm): who has which flag, class, health when
--     known, how long they've held it. Click a carrier to target them.
--   * Capture timers for bases / towers / graveyards being taken (Arathi Basin, Alterac Valley,
--     Isle of Conquest), colored by the faction taking it.
-- Flag and capture events come from the battleground's English system messages.
local _, ns = ...
local colors = ns.colors
local GetTime = GetTime

local FACTION_COLOR = {
	Alliance = { 0.24, 0.48, 1.0 },
	Horde = { 0.90, 0.25, 0.22 },
}
local FLAG_ICON = {
	Alliance = "Interface\\WorldStateFrame\\AllianceFlag",
	Horde = "Interface\\WorldStateFrame\\HordeFlag",
	Neutral = "Interface\\WorldStateFrame\\NeutralFlag",
}

local function InBG()
	local _, kind = IsInInstance()
	return kind == "pvp"
end

local function MyFaction()
	return UnitFactionGroup("player") or "Alliance"
end

local function Other(f) return f == "Alliance" and "Horde" or "Alliance" end

----------------------------------------------------------------------
-- Score (WorldStateAlwaysUpFrame)
----------------------------------------------------------------------
local scoreHolder, placing
local shiftX = 0 -- sideways nudge so the score lines are centered on the holder

local function PlaceScore()
	if placing or not scoreHolder or not WorldStateAlwaysUpFrame then return end
	placing = true
	if WorldStateAlwaysUpFrame:GetParent() ~= scoreHolder then WorldStateAlwaysUpFrame:SetParent(scoreHolder) end
	WorldStateAlwaysUpFrame:ClearAllPoints()
	WorldStateAlwaysUpFrame:SetPoint("TOP", scoreHolder, "TOP", shiftX, 0)
	placing = false
end

-- In arenas Blizzard's score only says "Gold Team: 3 Players Remaining", which the arena
-- timer bar already shows (3 v 3) — so it's hidden there instead of overlapping the bar.
local function ScoreVisibility()
	if not scoreHolder then return end
	if ns:InArena() then scoreHolder:Hide() else scoreHolder:Show() end
end

-- Blizzard lines the score rows up from a fixed left edge, so with our font the block sits
-- off-center. Measure the visible rows (icon to end of text) and shift the whole block so its
-- middle is the holder's middle.
local lastSignature
local function CenterScore()
	if not scoreHolder or not WorldStateAlwaysUpFrame or not scoreHolder:IsShown() then return end
	-- only re-center when the text actually changed (Blizzard refreshes this a lot)
	local sig = ""
	for i = 1, (NUM_ALWAYS_UP_UI_FRAMES or 0) do
		local text = _G["AlwaysUpFrame" .. i .. "Text"]
		local row = _G["AlwaysUpFrame" .. i]
		if row and row:IsShown() and text then sig = sig .. "|" .. (text:GetText() or "") end
	end
	if sig == lastSignature then return end
	local left, right
	for i = 1, (NUM_ALWAYS_UP_UI_FRAMES or 0) do
		local row = _G["AlwaysUpFrame" .. i]
		local text = _G["AlwaysUpFrame" .. i .. "Text"]
		if row and row:IsShown() and text and (text:GetText() or "") ~= "" then
			local l = row:GetLeft()
			local icon = _G["AlwaysUpFrame" .. i .. "Icon"]
			if icon and icon:IsShown() and icon:GetLeft() then l = math.min(l or icon:GetLeft(), icon:GetLeft()) end
			local r = text:GetLeft() and (text:GetLeft() + text:GetStringWidth())
			if l and r then
				left = left and math.min(left, l) or l
				right = right and math.max(right, r) or r
			end
		end
	end
	local cx = scoreHolder:GetCenter()
	if not left or not cx then return end
	lastSignature = sig
	-- rows are children of the moved frame, so they share the holder's scale
	local delta = cx - (left + right) / 2
	if math.abs(delta) > 0.5 then
		shiftX = math.max(-300, math.min(300, shiftX + delta))
		PlaceScore()
	end
end

-- measure one frame later, once the game has laid out the new text
local centerer = CreateFrame("Frame")
centerer:Hide()
centerer:SetScript("OnUpdate", function(self)
	self:Hide()
	CenterScore()
end)

local function StyleScore()
	for i = 1, (NUM_ALWAYS_UP_UI_FRAMES or 0) do
		local text = _G["AlwaysUpFrame" .. i .. "Text"]
		if text and not text.afo then
			text.afo = true
			ns:Font(text, 15, true)
			text:SetTextColor(1, 1, 1)
		end
	end
	centerer:Show()
end

local function SetupScore()
	scoreHolder = CreateFrame("Frame", nil, ns.root)
	scoreHolder:SetSize(260, 56)
	ns:Mover("bgscore", "BATTLEGROUND SCORE", scoreHolder, "TOP", "TOP", 0, -40)
	if not WorldStateAlwaysUpFrame then return end
	PlaceScore()
	hooksecurefunc(WorldStateAlwaysUpFrame, "SetPoint", function() if not placing then PlaceScore() end end)
	if WorldStateAlwaysUpFrame_Update then
		hooksecurefunc("WorldStateAlwaysUpFrame_Update", StyleScore)
	end
	StyleScore()
	-- re-center when the holder is moved or resized in move mode
	ns:Listen("LAYOUT_CHANGED", function(key) if key == "bgscore" then lastSignature = nil; centerer:Show() end end)
	ScoreVisibility()
	ns:On("PLAYER_ENTERING_WORLD", ScoreVisibility)
	ns:On("ZONE_CHANGED_NEW_AREA", ScoreVisibility)
end

----------------------------------------------------------------------
-- Flag carriers
----------------------------------------------------------------------
-- carriers.enemy / carriers.friendly = { name, since, flag = "Alliance"|"Horde"|"Neutral" }
local carriers = {}
local flagHolder
local rows = {}
local hpCache = {} -- name -> last known health %

local function FindUnit(name)
	if not name then return end
	for _, u in ipairs({ "target", "focus", "mouseover" }) do
		if UnitExists(u) and UnitName(u) == name then return u end
	end
	for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do
		local u = "raid" .. i
		if UnitName(u) == name then return u end
	end
end

local function ClassOf(name, unit)
	if unit and UnitIsPlayer(unit) then return select(2, UnitClass(unit)) end
	local guid = ns.nameToGUID and ns.nameToGUID[name]
	if guid and GetPlayerInfoByGUID then return select(2, GetPlayerInfoByGUID(guid)) end
end

local function SetMacro(row, name)
	ns:SafeCall(function()
		row:SetAttribute("type", "macro")
		row:SetAttribute("macrotext", name and ("/targetexact " .. name) or "")
	end)
end

local function UpdateFlags()
	if not flagHolder then return end
	local now = GetTime()
	for _, side in ipairs({ "enemy", "friendly" }) do
		local row, c = rows[side], carriers[side]
		if c then
			local unit = FindUnit(c.name)
			local class = c.class or ClassOf(c.name, unit)
			c.class = class
			row.name:SetText(c.name)
			row.name:SetTextColor(ns:ClassColor(class))
			if unit then
				local max = UnitHealthMax(unit)
				if max and max > 0 then hpCache[c.name] = floor(UnitHealth(unit) / max * 100 + 0.5) end
			end
			local hp = hpCache[c.name]
			row.hp:SetText(hp and (hp .. "%") or "")
			if hp and hp < 35 then row.hp:SetTextColor(colors.danger[1], colors.danger[2], colors.danger[3])
			else row.hp:SetTextColor(1, 1, 1) end
			local t = now - c.since
			row.time:SetText(format("%d:%02d", floor(t / 60), floor(t % 60)))
			row.flag:SetTexture(FLAG_ICON[c.flag] or FLAG_ICON.Neutral)
			row.body:Show()
		else
			row.body:Hide()
		end
	end
end

local function SetCarrier(side, name, flag)
	if name then
		carriers[side] = { name = name, since = GetTime(), flag = flag }
	else
		carriers[side] = nil
	end
	if rows[side] then SetMacro(rows[side], name) end
	UpdateFlags()
end

local function CreateFlagRow(side, y)
	local b = CreateFrame("Button", nil, flagHolder, "SecureActionButtonTemplate")
	b:SetSize(200, 22)
	b:SetPoint("TOPLEFT", flagHolder, "TOPLEFT", 0, y)
	b:RegisterForClicks("AnyUp")
	b.body = CreateFrame("Frame", nil, b)
	b.body:SetAllPoints(b)
	ns:Skin(b.body)
	b.body.fill:SetTexture(0.03, 0.035, 0.043, 0.85)
	b.flag = b.body:CreateTexture(nil, "ARTWORK")
	b.flag:SetSize(22, 22)
	b.flag:SetPoint("LEFT", 2, 0)
	b.label = ns:CreateText(b.body, 11, true, "LEFT")
	b.label:SetPoint("LEFT", b.flag, "RIGHT", 2, 0)
	b.label:SetText(side == "enemy" and "EFC" or "FFC")
	local c = side == "enemy" and colors.danger or colors.friendly
	b.label:SetTextColor(c[1], c[2], c[3])
	b.name = ns:CreateText(b.body, 14, true, "LEFT")
	b.name:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
	b.time = ns:CreateText(b.body, 12, true, "RIGHT")
	b.time:SetPoint("RIGHT", -6, 0)
	b.time:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	b.hp = ns:CreateText(b.body, 14, true, "RIGHT")
	b.hp:SetPoint("RIGHT", b.time, "LEFT", -8, 0)
	b.name:SetPoint("RIGHT", b.hp, "LEFT", -4, 0)
	b.body:Hide()
	SetMacro(b, nil)
	rows[side] = b
end

local function SetupFlags()
	flagHolder = CreateFrame("Frame", nil, ns.root)
	flagHolder:SetSize(200, 48)
	-- under the minimap (and its button row), right edges lined up
	ns:Mover("flags", "FLAG CARRIERS", flagHolder, "TOPRIGHT", "TOPRIGHT", -24, -242)
	CreateFlagRow("enemy", 0)
	CreateFlagRow("friendly", -26)
	local acc = 0
	flagHolder:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.25 then return end
		acc = 0
		UpdateFlags()
	end)
end

-- WSG: "The Alliance Flag was picked up by Name!" (the Alliance flag is carried by a Horde player)
local function FlagMessage(msg, eventFaction)
	local flag, name = msg:match("^The (%a+) [Ff]lag was picked up by (.-)!$")
	if flag and name then
		local side = (flag == MyFaction()) and "enemy" or "friendly"
		SetCarrier(side, name, flag)
		return true
	end
	flag = msg:match("^The (%a+) [Ff]lag was dropped by") or msg:match("^The (%a+) [Ff]lag was returned")
		or msg:match("captured the (%a+) [Ff]lag")
	if flag then
		SetCarrier((flag == MyFaction()) and "enemy" or "friendly", nil)
		return true
	end
	if msg:find("flags are now placed at their bases") then
		SetCarrier("enemy", nil); SetCarrier("friendly", nil)
		return true
	end
	-- Eye of the Storm: "Name has taken the flag!" (the event says which faction)
	name = msg:match("^(.-) has taken the flag!$")
	if name and eventFaction then
		local side = (eventFaction == MyFaction()) and "friendly" or "enemy"
		SetCarrier(side == "friendly" and "enemy" or "friendly", nil) -- there's only one flag
		SetCarrier(side, name, "Neutral")
		return true
	end
	if msg:find("^The flag has been dropped") or msg:find("have captured the flag") or msg:find("flag has been reset") then
		SetCarrier("enemy", nil); SetCarrier("friendly", nil)
		return true
	end
end

----------------------------------------------------------------------
-- Capture timers
----------------------------------------------------------------------
local timers = {}  -- node -> { faction, ends, dur }
local timerHolder
local bars = {}

local function UpdateTimers()
	if not timerHolder then return end
	local now = GetTime()
	local list = {}
	for node, t in pairs(timers) do
		if t.ends <= now then timers[node] = nil else list[#list + 1] = { node = node, t = t } end
	end
	table.sort(list, function(a, b) return a.t.ends < b.t.ends end)
	for i = 1, math.max(#list, #bars) do
		local e = list[i]
		local bar = bars[i]
		if e then
			if not bar then
				bar = ns:CreateBar(timerHolder, 240, 18)
				bar:SetPoint("TOP", timerHolder, "TOP", 0, -(i - 1) * 22)
				bar.text = ns:CreateText(bar, 13, true, "LEFT")
				bar.text:SetPoint("LEFT", 6, 0)
				bar.time = ns:CreateText(bar, 13, true, "RIGHT")
				bar.time:SetPoint("RIGHT", -6, 0)
				bars[i] = bar
			end
			local c = FACTION_COLOR[e.t.faction] or colors.kick
			local left = e.t.ends - now
			bar:SetStatusBarColor(c[1], c[2], c[3])
			bar:SetMinMaxValues(0, e.t.dur)
			bar:SetValue(left)
			bar.text:SetText(e.node)
			bar.time:SetText(format("%d:%02d", floor(left / 60), floor(left % 60)))
			bar:Show()
		elseif bar then
			bar:Hide()
		end
	end
end

-- "the stables" -> "Stables", "gold mine" -> "Gold Mine" (small words like "of" stay lower case)
local SMALL = { of = true, the = true, ["and"] = true }
local function Clean(node)
	node = node:gsub("^[Tt]he ", "")
	local first = true
	node = node:gsub("(%a)([%w']*)", function(a, rest)
		local word = a .. rest
		if not first and SMALL[word:lower()] then first = false return word:lower() end
		first = false
		return a:upper() .. rest
	end)
	return node
end

local function StartTimer(node, faction, dur)
	node = Clean(node)
	timers[node] = { faction = faction, ends = GetTime() + dur, dur = dur }
	UpdateTimers()
end

local function StopTimer(node)
	timers[Clean(node)] = nil
	UpdateTimers()
end

local function CaptureMessage(msg, eventFaction)
	-- Arathi Basin / Isle of Conquest: 1 minute
	local node = msg:match("claims the (.-)!") or msg:match("has assaulted the (.-)!")
	if node and eventFaction then StartTimer(node, eventFaction, 60) return true end
	node = msg:match("has defended the (.-)!") or msg:match("has taken the (.-)!")
	if node then StopTimer(node) return true end
	-- Alterac Valley: 4 minutes. "The X is under attack! If left unchallenged, the Horde will capture it!"
	local who
	node, who = msg:match("^(.-) is under attack!.-the (%a+) will")
	if node and who then StartTimer(node, who, 240) return true end
	node = msg:match("^(.-) was taken by the") or msg:match("^(.-) was destroyed by the")
	if node then StopTimer(node) return true end
end

local function SetupTimers()
	timerHolder = CreateFrame("Frame", nil, ns.root)
	timerHolder:SetSize(240, 106)
	ns:Mover("bgtimers", "CAPTURE TIMERS", timerHolder, "TOP", "TOP", 0, -104)
	local acc = 0
	timerHolder:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.2 then return end
		acc = 0
		UpdateTimers()
	end)
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local function OnSystem(event, msg)
	if not msg or ns.testing then return end
	local faction = (event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" and "Alliance")
		or (event == "CHAT_MSG_BG_SYSTEM_HORDE" and "Horde") or nil
	if FlagMessage(msg, faction) then return end
	CaptureMessage(msg, faction)
end

local function Reset()
	wipe(carriers)
	wipe(timers)
	wipe(hpCache)
	for _, side in ipairs({ "enemy", "friendly" }) do
		if rows[side] then SetMacro(rows[side], nil) end
	end
	UpdateFlags()
	UpdateTimers()
	-- the click areas only exist inside battlegrounds
	if flagHolder then
		ns:SafeCall(function()
			if InBG() or ns.testing then flagHolder:Show() else flagHolder:Hide() end
		end)
	end
end
ns.ResetBattleground = Reset
ns.bgState = { carriers = carriers, timers = timers }

ns:Listen("LOGIN", function()
	SetupScore()
	SetupFlags()
	SetupTimers()
	Reset()
	for _, ev in ipairs({ "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" }) do
		ns:On(ev, OnSystem)
	end
	ns:On("PLAYER_ENTERING_WORLD", Reset)
	ns:On("ZONE_CHANGED_NEW_AREA", function() if not InBG() then Reset() end end)
end)

-- test mode: sample carriers and timers
ns:Listen("BG_TEST", function(on)
	if not flagHolder then return end
	wipe(carriers); wipe(timers)
	if on then
		local now = GetTime()
		local mine = MyFaction()
		carriers.enemy = { name = "Swiftpaw", since = now - 74, flag = mine, class = "DRUID" }
		carriers.friendly = { name = "Ironhide", since = now - 31, flag = Other(mine), class = "WARRIOR" }
		hpCache.Swiftpaw, hpCache.Ironhide = 28, 81
		timers["Stables"] = { faction = mine, ends = now + 42, dur = 60 }
		timers["Lumber Mill"] = { faction = Other(mine), ends = now + 18, dur = 60 }
		ns:SafeCall(function() flagHolder:Show() end)
	end
	UpdateFlags()
	UpdateTimers()
	if not on then Reset() end
end)
