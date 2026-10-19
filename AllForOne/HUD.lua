-- AllForOne: minimap, bags + game menu, XP/rep bar, chat cleanup, arena timer + gates countdown
local _, ns = ...
local colors, media = ns.colors, ns.media

----------------------------------------------------------------------
-- Minimap: square, top-right, clock + latency under it
----------------------------------------------------------------------
local function SetupMinimap()
	local holder = CreateFrame("Frame", nil, ns.root)
	holder:SetSize(168, 168)
	ns:Mover("minimap", "MINIMAP", holder, "TOPRIGHT", "TOPRIGHT", -24, -24)
	Minimap:SetParent(holder)
	Minimap:ClearAllPoints()
	Minimap:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	Minimap:SetSize(168, 168)
	Minimap:SetMaskTexture(media.flat)
	Minimap:SetFrameStrata("LOW")
	ns:Skin(Minimap, true)
	function GetMinimapShape() return "SQUARE" end

	for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapZoomIn", "MinimapZoomOut",
		"MiniMapWorldMapButton", "MinimapZoneTextButton", "MinimapToggleButton", "GameTimeFrame",
		"MiniMapVoiceChatFrame", "MinimapNorthTag", "MiniMapTracking" }) do
		local f = _G[name]
		if f then ns:Kill(f) end
	end
	if MinimapCluster then MinimapCluster:EnableMouse(false) end
	if MinimapBackdrop then MinimapBackdrop:Hide() end

	-- keep the PvP queue eye, mail and LFD eye, tucked into corners
	if MiniMapBattlefieldFrame then
		MiniMapBattlefieldFrame:ClearAllPoints()
		MiniMapBattlefieldFrame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -4, -4)
	end
	if MiniMapLFGFrame then
		MiniMapLFGFrame:ClearAllPoints()
		MiniMapLFGFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 4, -4)
	end
	if MiniMapMailFrame then
		MiniMapMailFrame:ClearAllPoints()
		MiniMapMailFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -4, 4)
	end
	if MiniMapInstanceDifficulty then
		MiniMapInstanceDifficulty:ClearAllPoints()
		MiniMapInstanceDifficulty:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 4, 4)
	end

	-- wheel to zoom, right click for tracking
	Minimap:EnableMouseWheel(true)
	Minimap:SetScript("OnMouseWheel", function(_, delta)
		if delta > 0 then Minimap_ZoomIn() else Minimap_ZoomOut() end
	end)
	Minimap:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and MiniMapTrackingDropDown then
			ToggleDropDownMenu(1, nil, MiniMapTrackingDropDown, "cursor")
		else
			Minimap_OnClick(self)
		end
	end)

	local info = ns:CreateText(holder, 13, true, "RIGHT")
	info:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -6)
	info:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	local t = CreateFrame("Frame")
	local acc = 1
	t:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 1 then return end
		acc = 0
		local _, _, latency = GetNetStats()
		info:SetText(date("%H:%M") .. " · " .. (latency or 0) .. " ms")
	end)
	ns:Send("MINIMAP_PLACED")
end

-- Blizzard_TimeManager adds its own clock button to the minimap
ns:On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_TimeManager" and TimeManagerClockButton and ns.db and ns.db.minimap then
		ns:Kill(TimeManagerClockButton)
	end
end)

----------------------------------------------------------------------
-- Bags (top row) + game menu (bottom row), bottom-right, faded until hovered
----------------------------------------------------------------------
local menuItems = {
	{ "CHAR", "TOGGLECHARACTER0", function() ToggleCharacter("PaperDollFrame") end },
	{ "SPELLS", "TOGGLESPELLBOOK", function() ToggleSpellBook(BOOKTYPE_SPELL) end },
	{ "TALENTS", "TOGGLETALENTS", function() ToggleTalentFrame() end },
	{ "ACH", "TOGGLEACHIEVEMENT", function() ToggleAchievementFrame() end },
	{ "QUESTS", "TOGGLEQUESTLOG", function() ToggleFrame(QuestLogFrame) end },
	{ "SOCIAL", "TOGGLESOCIAL", function() ToggleFriendsFrame() end },
	{ "PVP", "TOGGLECHARACTER4", function() TogglePVPFrame() end },
	{ "LFD", "TOGGLELFGPARENT", function() ToggleLFDParentFrame() end },
	{ "MENU", nil, function()
		if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) else ShowUIPanel(GameMenuFrame) end
	end },
}

local function KeyLabel(binding)
	if not binding then return "ESC" end
	local key = GetBindingKey(binding)
	return key and (GetBindingText(key, "KEY_", 1) or key) or ""
end

local menuFrame

local function UpdateBags()
	if not menuFrame then return end
	local free = 0
	for bag = 0, 4 do
		local n, kind = GetContainerNumFreeSlots(bag)
		if n and (kind == 0 or kind == nil) then free = free + n end
	end
	local money = GetMoney() or 0
	local gold = floor(money / 10000)
	local goldText = tostring(gold):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	menuFrame.info:SetText(free .. " free · " .. goldText .. "g")
	for i, b in ipairs(menuFrame.bags) do
		local bag = b.bag
		if bag == 0 then
			b.icon.tex:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
		else
			local tex = GetInventoryItemTexture("player", ContainerIDToInventoryID(bag))
			b.icon.tex:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
		end
		b.icon:Show()
	end
end

local function SetupMenu()
	local f = CreateFrame("Frame", "AFOMenu", ns.root)
	f:SetSize(10, 60)
	menuFrame = f

	-- bottom row: game menu text buttons
	local x = 0
	local buttons = {}
	for i = #menuItems, 1, -1 do
		local item = menuItems[i]
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(26)
		ns:Skin(b)
		local label = ns:CreateText(b, 12, true, "LEFT")
		label:SetText(item[1])
		local key = ns:CreateText(b, 12, true, "LEFT")
		key:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
		key:SetText(KeyLabel(item[2]))
		label:SetPoint("LEFT", 8, 0)
		key:SetPoint("LEFT", label, "RIGHT", 4, 0)
		local w = label:GetStringWidth() + key:GetStringWidth() + 20
		b:SetWidth(w)
		b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -x, 0)
		x = x + w + 3
		b:SetScript("OnClick", item[3])
		b:SetScript("OnEnter", function() label:SetTextColor(colors.kick[1], colors.kick[2], colors.kick[3]) end)
		b:SetScript("OnLeave", function() label:SetTextColor(1, 1, 1) end)
		buttons[#buttons + 1] = b
	end
	f:SetWidth(x)
	ns:Mover("menu", "BAGS + MENU", f, "BOTTOMRIGHT", "BOTTOMRIGHT", -24, 24)

	-- top row: free slots + gold, then bags (backpack on the right)
	f.bags = {}
	for i = 0, 4 do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(28, 28)
		b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(i * 31), 32)
		b.icon = ns:CreateIcon(b, 28)
		b.icon:SetAllPoints(b)
		b.bag = i
		b:RegisterForClicks("AnyUp")
		b:SetScript("OnClick", function(self)
			if IsShiftKeyDown() then OpenAllBags() elseif self.bag == 0 then ToggleBackpack() else ToggleBag(self.bag) end
		end)
		f.bags[#f.bags + 1] = b
	end
	f.info = ns:CreateText(f, 13, true, "RIGHT")
	f.info:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	f.info:SetPoint("RIGHT", f.bags[5], "LEFT", -8, 0)

	-- fade until the mouse is over it
	local acc = 0
	f:SetScript("OnUpdate", function(self, e)
		acc = acc + e
		if acc < 0.1 then return end
		acc = 0
		local over = MouseIsOver(self, 34, 0, 0, 0)
		self:SetAlpha(over and 1 or ns.db.menuAlpha)
	end)
	f:SetAlpha(ns.db.menuAlpha)
	UpdateBags()
end

for _, ev in ipairs({ "BAG_UPDATE", "PLAYER_MONEY", "UNIT_INVENTORY_CHANGED" }) do
	ns:On(ev, UpdateBags)
end

----------------------------------------------------------------------
-- XP / reputation bar under the middle action bars
----------------------------------------------------------------------
local xp

local function UpdateXP()
	if not xp then return end
	local maxLevel = MAX_PLAYER_LEVEL_TABLE and MAX_PLAYER_LEVEL_TABLE[GetAccountExpansionLevel()] or 80
	if UnitLevel("player") < maxLevel then
		local cur, max = UnitXP("player"), UnitXPMax("player")
		local rested = GetXPExhaustion() or 0
		xp.bar:SetMinMaxValues(0, max)
		xp.bar:SetValue(cur)
		xp.bar:SetStatusBarColor(colors.xp[1], colors.xp[2], colors.xp[3])
		xp.rested:SetMinMaxValues(0, max)
		xp.rested:SetValue(math.min(max, cur + rested))
		xp.rested:Show()
		xp.tip = format("XP %d / %d (%.0f%%)%s", cur, max, cur / max * 100, rested > 0 and format(" · rested %d", rested) or "")
		xp:Show()
	else
		local name, standing, min, max, value = GetWatchedFactionInfo()
		if not name then xp:Hide() return end
		local c = FACTION_BAR_COLORS[standing] or colors.friendly
		xp.bar:SetMinMaxValues(min, max)
		xp.bar:SetValue(value)
		xp.bar:SetStatusBarColor(c.r or c[1], c.g or c[2], c.b or c[3])
		xp.rested:Hide()
		xp.tip = format("%s: %d / %d (%s)", name, value - min, max - min, _G["FACTION_STANDING_LABEL" .. standing] or "")
		xp:Show()
	end
end

local function SetupXP()
	xp = CreateFrame("Frame", nil, ns.root)
	xp:SetSize(12 * 39 - 3, 6)
	ns:Mover("xp", "XP / REP", xp, "BOTTOM", "BOTTOM", 0, 16)
	xp.rested = ns:CreateBar(xp, 1, 6)
	xp.rested:SetAllPoints(xp)
	xp.rested:SetStatusBarColor(colors.rested[1], colors.rested[2], colors.rested[3], 0.35)
	xp.bar = CreateFrame("StatusBar", nil, xp.rested)
	xp.bar:SetAllPoints(xp)
	xp.bar:SetStatusBarTexture(media.flat)
	xp:EnableMouse(true)
	xp:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.tip or "")
		GameTooltip:Show()
	end)
	xp:SetScript("OnLeave", function() GameTooltip:Hide() end)
	UpdateXP()
end

for _, ev in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }) do
	ns:On(ev, UpdateXP)
end

----------------------------------------------------------------------
-- Chat: outlined text, no button clutter, tabs fade out
----------------------------------------------------------------------
local function SetupChat()
	for _, name in ipairs({ "ChatFrameMenuButton", "FriendsMicroButton", "ChatFrame1ButtonFrame" }) do
		if _G[name] then ns:Kill(_G[name]) end
	end
	for i = 1, NUM_CHAT_WINDOWS or 7 do
		local cf = _G["ChatFrame" .. i]
		if cf then
			local _, size = cf:GetFont()
			cf:SetFont(ns.db.useFont and media.font or media.fallback, size or 14, "OUTLINE")
			cf:SetShadowOffset(0, 0)
			local bf = _G["ChatFrame" .. i .. "ButtonFrame"]
			if bf then ns:Kill(bf) end
		end
	end
	CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0
	CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
end

----------------------------------------------------------------------
-- Arena: map + bracket + match timer (top center), big gates countdown
----------------------------------------------------------------------
local status, countdown
local matchStart, gatesAt

local COUNTDOWN_MSGS = {
	{ "One minute", 60 }, { "Thirty seconds", 30 }, { "Fifteen seconds", 15 },
}

local function Bracket()
	for i = 1, (MAX_BATTLEFIELD_QUEUES or 3) do
		local st, _, _, _, _, teamSize = GetBattlefieldStatus(i)
		if st == "active" and teamSize and teamSize > 0 then return teamSize .. "V" .. teamSize end
	end
	return ""
end

local function SetupArena()
	status = CreateFrame("Frame", nil, ns.root)
	status:SetSize(300, 30)
	ns:Mover("arenastatus", "ARENA TIMER", status, "TOP", "TOP", 0, -20)
	ns:Skin(status)
	status.fill:SetTexture(0.03, 0.035, 0.043, 0.85)
	status.map = ns:CreateText(status, 15, true, "LEFT")
	status.map:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	status.time = ns:CreateText(status, 20, true, "LEFT")
	status.map:SetPoint("LEFT", 16, 0)
	status.time:SetPoint("LEFT", status.map, "RIGHT", 18, 0)
	status:Hide()

	countdown = CreateFrame("Frame", nil, ns.root)
	countdown:SetSize(400, 120)
	ns:Mover("countdown", "GATES COUNTDOWN", countdown, "TOP", "TOP", 0, -96)
	countdown.label = ns:CreateText(countdown, 16, true, "CENTER")
	countdown.label:SetPoint("TOP")
	countdown.label:SetText("GATES OPEN IN")
	countdown.label:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	countdown.time = ns:CreateText(countdown, 88, true, "CENTER")
	countdown.time:SetPoint("TOP", countdown.label, "BOTTOM", 0, -4)
	countdown:Hide()

	local acc = 0
	status:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.2 then return end
		acc = 0
		local now = GetTime()
		if gatesAt and gatesAt > now then
			local left = ceil(gatesAt - now)
			countdown.time:SetText(format("%d:%02d", floor(left / 60), left % 60))
			countdown:Show()
			status.time:SetText("PREP")
		else
			countdown:Hide()
			if gatesAt and not matchStart then matchStart = gatesAt end
			if matchStart then
				local t = now - matchStart
				status.time:SetText(format("%02d:%02d", floor(t / 60), floor(t % 60)))
			else
				status.time:SetText("--:--")
			end
		end
		local w = status.map:GetStringWidth() + status.time:GetStringWidth() + 50
		status:SetWidth(w)
	end)
end

local function ArenaZone()
	if not status then return end
	if ns:InArena() then
		status.map:SetText(strupper((GetRealZoneText() or "") .. "  " .. Bracket()))
		status:Show()
	else
		status:Hide()
		countdown:Hide()
		matchStart, gatesAt = nil, nil
	end
end

ns:On("PLAYER_ENTERING_WORLD", function() matchStart, gatesAt = nil, nil; ArenaZone() end)
ns:On("ZONE_CHANGED_NEW_AREA", ArenaZone)
ns:On("UPDATE_BATTLEFIELD_STATUS", ArenaZone)
ns:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", function(_, msg)
	if not ns:InArena() or not msg then return end
	for _, m in ipairs(COUNTDOWN_MSGS) do
		if msg:find(m[1]) then gatesAt = GetTime() + m[2] return end
	end
	if msg:find("has begun") then
		gatesAt = nil
		matchStart = GetTime()
	end
end)

-- test mode hook
function ns:ShowArenaSample(on)
	if not status then return end
	if on then
		status.map:SetText("RING OF VALOR  3V3")
		matchStart = GetTime() - 252
		status:Show()
	else
		ArenaZone()
	end
end

----------------------------------------------------------------------
ns:Listen("LOGIN", function()
	if ns.db.minimap then SetupMinimap() end
	if ns.db.actionbars then
		SetupMenu()
		SetupXP()
	end
	if ns.db.chat then SetupChat() end
	SetupArena()
	ArenaZone()
end)
ns:Listen("REFRESH_ALL", function()
	if menuFrame then menuFrame:SetAlpha(ns.db.menuAlpha) end
end)
