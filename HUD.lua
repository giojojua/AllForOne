-- AllForOne: minimap, bags + game menu, XP/rep bar, chat cleanup, arena timer + gates countdown
local _, ns = ...
local colors, media = ns.colors, ns.media

----------------------------------------------------------------------
-- Minimap: square, top-right, clock + latency under it
----------------------------------------------------------------------
local function Step(fn)
	local ok, err = pcall(fn)
	if not ok then ns:Report(err) end
end

local holder
local function SetupMinimap()
	local first = not holder
	if first then
		holder = CreateFrame("Frame", nil, ns.root)
		holder:SetSize(168, 168)
		ns:Mover("minimap", "MINIMAP", holder, "TOPRIGHT", "TOPRIGHT", -24, -24)
	end
	-- 1) our square map: done first, on its own, so nothing below can stop it
	Step(function()
		Minimap:SetParent(holder)
		Minimap:ClearAllPoints()
		Minimap:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
		Minimap:SetSize(168, 168)
		Minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")
		Minimap:SetFrameStrata("LOW")
		if not Minimap.outline then ns:Skin(Minimap, true) end
	end)
	function GetMinimapShape() return "SQUARE" end

	-- 2) Blizzard's round art. MinimapBorder, MinimapBorderTop, MinimapNorthTag and the compass
	-- are textures (not frames), so each one is hidden on its own.
	-- keep these: move them onto the map itself first, so hiding Blizzard's backdrop can't take them along
	for _, name in ipairs({ "MiniMapBattlefieldFrame", "MiniMapLFGFrame", "MiniMapMailFrame", "MiniMapInstanceDifficulty" }) do
		local f = _G[name]
		if f then Step(function() f:SetParent(Minimap) end) end
	end
	-- other addons' minimap buttons sometimes sit on Blizzard's backdrop: move every frame on it
	-- (except Blizzard's own buttons we replace) onto the map too
	local replaced = { MinimapZoomIn = true, MinimapZoomOut = true, MiniMapWorldMapButton = true, MiniMapTracking = true,
		GameTimeFrame = true, MinimapToggleButton = true, MiniMapVoiceChatFrame = true, MinimapZoneTextButton = true }
	if MinimapBackdrop then
		Step(function()
			for _, child in ipairs({ MinimapBackdrop:GetChildren() }) do
				local n = child:GetName()
				if not (n and replaced[n]) then child:SetParent(Minimap) end
			end
		end)
		Step(function() ns:Kill(MinimapBackdrop) end)
	end
	for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapNorthTag", "MinimapCompassTexture",
		"MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton", "MinimapZoneTextButton", "MinimapToggleButton",
		"GameTimeFrame", "MiniMapVoiceChatFrame", "MiniMapTracking" }) do
		local f = _G[name]
		if f then Step(function() ns:Kill(f) end) end
	end
	if MinimapCluster then Step(function() MinimapCluster:EnableMouse(false) end) end

	-- keep the PvP queue eye, mail and LFD eye, tucked into corners
	Step(function()
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
	end)

	-- the queue eye, mail, LFD eye and other addons' minimap buttons must draw ABOVE the map
	local function RaiseIcons()
		local level = Minimap:GetFrameLevel() + 5
		for _, child in ipairs({ Minimap:GetChildren() }) do
			if child ~= MinimapBackdrop then
				child:SetFrameStrata("MEDIUM")
				child:SetFrameLevel(level)
			end
		end
	end
	Step(RaiseIcons)
	ns.RaiseMinimapIcons = RaiseIcons

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

	if not first then return end
	Step(function() ns:MinimapButtons(holder) end)
	-- clock + latency on the same row as the small buttons, right-aligned and vertically
	-- centered on them (the buttons take the left ~86px, the text the rest)
	local info = ns:CreateText(holder, 12, true, "RIGHT")
	info:SetPoint("RIGHT", Minimap, "BOTTOMRIGHT", 0, -25)
	info:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	local t = CreateFrame("Frame")
	local acc = 1
	t:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 1 then return end
		acc = 0
		local _, _, latency = GetNetStats()
		info:SetText(date("%H:%M") .. "  " .. (latency or 0) .. "ms")
		local n = Minimap:GetNumChildren()
		if n ~= t.children then t.children = n; pcall(RaiseIcons); if ns.ScanAddonButtons then pcall(ns.ScanAddonButtons) end end
	end)
	ns:Send("MINIMAP_PLACED")
end

-- Our own small square buttons under the map (Blizzard's round ones are hidden):
-- tracking, calendar (today's date, amber with invites), world map. Mouse wheel on the map zooms.
local function MapButton(parent, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	ns:Skin(b)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

function ns:MinimapButtons(holder)
	local row = {}

	local tracking = MapButton(holder, "Tracking (click to choose)", function(self)
		if MiniMapTrackingDropDown then ToggleDropDownMenu(1, nil, MiniMapTrackingDropDown, self, 0, 0) end
	end)
	local function TrackingIcon()
		local tex = GetTrackingTexture and GetTrackingTexture()
		tracking.icon:SetTexture(tex or "Interface\\Minimap\\Tracking\\None")
	end
	TrackingIcon()
	ns:On("MINIMAP_UPDATE_TRACKING", TrackingIcon)
	row[#row + 1] = tracking

	local calendar = MapButton(holder, "Calendar", function()
		if not CalendarFrame and LoadAddOn then LoadAddOn("Blizzard_Calendar") end
		if Calendar_Toggle then Calendar_Toggle() elseif CalendarFrame then ToggleFrame(CalendarFrame) end
	end)
	calendar.icon:SetTexture(0.10, 0.11, 0.12, 1)
	calendar.day = ns:CreateText(calendar, 12, true, "CENTER")
	calendar.day:SetPoint("CENTER", 0, 0)
	local function CalendarState()
		local day = CalendarGetDate and select(3, CalendarGetDate())
		calendar.day:SetText(day or "")
		local invites = CalendarGetNumPendingInvites and CalendarGetNumPendingInvites() or 0
		if invites > 0 then
			calendar.day:SetTextColor(colors.kick[1], colors.kick[2], colors.kick[3])
		else
			calendar.day:SetTextColor(1, 1, 1)
		end
	end
	CalendarState()
	ns:On("CALENDAR_UPDATE_PENDING_INVITES", CalendarState)
	ns:On("PLAYER_ENTERING_WORLD", CalendarState)
	row[#row + 1] = calendar

	local map = MapButton(holder, "World map", function()
		if ToggleWorldMap then ToggleWorldMap() elseif WorldMapFrame then ToggleFrame(WorldMapFrame) end
	end)
	map.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	row[#row + 1] = map

	row[#row + 1] = ns:AddonDrawer(holder)

	for i, b in ipairs(row) do
		b:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", (i - 1) * 22, -15)
	end
	ns.minimapButtons = row
end

----------------------------------------------------------------------
-- Addon drawer: one button under the map; click it for a dropdown holding every other
-- addon's minimap button (LibDBIcon and the like), so the square map stays clean.
----------------------------------------------------------------------
-- Blizzard's own minimap pieces (and ours) are never collected
local BLIZZARD = {
	MiniMapBattlefieldFrame = true, MiniMapLFGFrame = true, MiniMapMailFrame = true, MiniMapInstanceDifficulty = true,
	MinimapBackdrop = true, MiniMapTracking = true, MiniMapTrackingButton = true, MinimapZoomIn = true, MinimapZoomOut = true,
	MiniMapWorldMapButton = true, MiniMapVoiceChatFrame = true, GameTimeFrame = true, TimeManagerClockButton = true,
	MinimapPing = true, MiniMapPing = true, MinimapZoneTextButton = true, MinimapToggleButton = true,
	MiniMapCompassRing = true, MinimapNorthTag = true, MiniMapRecordingButton = true,
}

local drawer, drawerButton
local collected, order = {}, {}
local placing = false
local COLS, CELL = 5, 30

local function LayoutDrawer()
	if not drawer then return end
	placing = true
	for i, b in ipairs(order) do
		local col, r = (i - 1) % COLS, floor((i - 1) / COLS)
		b:ClearAllPoints()
		b:SetPoint("CENTER", drawer, "TOPLEFT", 6 + col * CELL + CELL / 2, -6 - r * CELL - CELL / 2)
	end
	placing = false
	local rows = math.max(1, ceil(#order / COLS))
	drawer:SetSize(12 + math.max(1, math.min(#order, COLS)) * CELL, 12 + rows * CELL)
	if #order == 0 then drawer.empty:Show() else drawer.empty:Hide() end
	drawerButton.count:SetText(#order > 0 and #order or "")
end

local function IsAddonButton(f)
	if not f or collected[f] or f == drawer then return false end
	local name = f.GetName and f:GetName()
	if not name or BLIZZARD[name] or name:find("^AllForOne") then return false end
	local kind = f.GetObjectType and f:GetObjectType()
	if kind ~= "Button" and not (f.HasScript and f:HasScript("OnClick") and f:GetScript("OnClick")) then return false end
	local w, h = f:GetWidth(), f:GetHeight()
	return w and h and w > 0 and w <= 48 and h <= 48
end

local function Collect(f)
	collected[f] = true
	order[#order + 1] = f
	f:SetParent(drawer)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(drawer:GetFrameLevel() + 2)
	-- they live in the drawer now: no dragging them around the map
	if f.RegisterForDrag then f:RegisterForDrag() end
	f:SetScript("OnDragStart", nil)
	f:SetScript("OnDragStop", nil)
	-- addons (LibDBIcon) re-anchor their button to the map now and then: put it back
	hooksecurefunc(f, "SetPoint", function() if not placing then LayoutDrawer() end end)
	if f.Show then f:Show() end
end

local function Scan()
	if not drawer then return end
	local found = false
	for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
		if parent and parent.GetChildren then
			for _, child in ipairs({ parent:GetChildren() }) do
				if IsAddonButton(child) then
					local ok = pcall(Collect, child)
					if ok then found = true end
				end
			end
		end
	end
	if found then
		table.sort(order, function(a, b) return (a:GetName() or "") < (b:GetName() or "") end)
	end
	LayoutDrawer()
end
ns.ScanAddonButtons = Scan

function ns:AddonDrawer(holder)
	drawerButton = MapButton(holder, "Addon buttons", function()
		Scan()
		if drawer:IsShown() then drawer:Hide() else drawer:Show() end
	end)
	drawerButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_02")
	drawerButton.count = ns:CreateText(drawerButton, 10, true, "RIGHT")
	drawerButton.count:SetPoint("BOTTOMRIGHT", 2, -2)

	drawer = CreateFrame("Frame", "AllForOneAddonDrawer", holder)
	drawer:SetFrameStrata("DIALOG")
	-- opens under the button row, lined up with the map so it never runs off the screen edge
	drawer:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 0, -39)
	drawer:SetSize(12 + CELL, 12 + CELL)
	drawer:EnableMouse(true)
	ns:Skin(drawer)
	drawer.fill:SetTexture(0.04, 0.045, 0.05, 0.96)
	drawer.empty = ns:CreateText(drawer, 12, false, "LEFT")
	drawer.empty:SetPoint("TOPLEFT", 8, -10)
	drawer.empty:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	drawer.empty:SetText("No addon buttons")
	drawer:Hide()
	tinsert(UISpecialFrames, "AllForOneAddonDrawer") -- Esc closes it

	-- addons create their buttons at different times: look again after login and loading screens
	local t = CreateFrame("Frame")
	local acc, tries = 0, 0
	t:SetScript("OnUpdate", function(self, e)
		acc = acc + e
		if acc < 2 then return end
		acc = 0
		tries = tries + 1
		Scan()
		if tries >= 5 then self:Hide() end
	end)
	ns:On("PLAYER_ENTERING_WORLD", function() Scan() end)
	ns:On("ADDON_LOADED", function() if drawer then Scan() end end)
	return drawerButton
end

-- Blizzard_TimeManager adds its own clock button to the minimap
ns:On("ADDON_LOADED", function(_, name)
	if name == "Blizzard_TimeManager" and TimeManagerClockButton and ns.db and ns.db.minimap then
		ns:Kill(TimeManagerClockButton)
	end
end)

----------------------------------------------------------------------
-- Red error text ("Not enough rage", "Out of range", "Spell is not ready yet") on/off.
-- Only the error event is switched off: yellow information (quest progress, "joined the
-- queue", battleground messages) comes through a different event and keeps showing.
----------------------------------------------------------------------
function ns:ApplyErrorFilter()
	if not UIErrorsFrame then return end
	if ns.db.hideErrors then
		UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	else
		UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end
ns:Listen("LOGIN", function() ns:ApplyErrorFilter() end)
ns:Listen("REFRESH_ALL", function() ns:ApplyErrorFilter() end) -- e.g. after loading a profile

----------------------------------------------------------------------
-- Bags (top row) + game menu (bottom row), bottom-right, faded until hovered
----------------------------------------------------------------------
-- { tooltip name, binding, icon, action } — icons are stock 3.3.5 textures
local menuItems = {
	{ "Character", "TOGGLECHARACTER0", "Interface\\Icons\\INV_Chest_Plate04", function() ToggleCharacter("PaperDollFrame") end },
	{ "Spellbook", "TOGGLESPELLBOOK", "Interface\\Icons\\INV_Misc_Book_09", function() ToggleSpellBook(BOOKTYPE_SPELL) end },
	{ "Talents", "TOGGLETALENTS", "Interface\\Icons\\Ability_Marksmanship", function() ToggleTalentFrame() end },
	{ "Achievements", "TOGGLEACHIEVEMENT", "Interface\\Icons\\Achievement_Level_80", function() ToggleAchievementFrame() end },
	{ "Quest log", "TOGGLEQUESTLOG", "Interface\\Icons\\INV_Misc_Note_01", function() ToggleFrame(QuestLogFrame) end },
	{ "Social", "TOGGLESOCIAL", "Interface\\Icons\\INV_Misc_GroupLooking", function() ToggleFriendsFrame() end },
	{ "PvP", "TOGGLECHARACTER4", "Interface\\Icons\\INV_BannerPVP_02", function() TogglePVPFrame() end },
	{ "Dungeon finder", "TOGGLELFGPARENT", "Interface\\Icons\\INV_Misc_GroupNeedMore", function() ToggleLFDParentFrame() end },
	{ "Game menu", nil, "Interface\\Icons\\INV_Misc_Gear_01", function()
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

	-- bottom row: game menu as small square icons (name + key in the tooltip)
	local SIZE, GAP = 28, 3
	for i = #menuItems, 1, -1 do
		local item = menuItems[i]
		local b = CreateFrame("Button", nil, f)
		b:SetSize(SIZE, SIZE)
		b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -((#menuItems - i) * (SIZE + GAP)), 0)
		b.icon = ns:CreateIcon(b, SIZE)
		b.icon:SetAllPoints(b)
		b.icon:Set(item[3])
		b:SetScript("OnClick", item[4])
		b:SetScript("OnEnter", function(self)
			self.icon:SetBorder(colors.kick[1], colors.kick[2], colors.kick[3])
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			local key = KeyLabel(item[2])
			GameTooltip:SetText(item[1] .. (key ~= "" and ("  |cff8b8f96" .. key .. "|r") or ""))
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function(self)
			self.icon:SetBorder()
			GameTooltip:Hide()
		end)
	end
	local x = #menuItems * (SIZE + GAP) - GAP
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
-- Thin scroll bar on the right edge of a chat window (3.3.5 chat only has hidden up/down
-- buttons). Drag it, click the track, or keep using the mouse wheel; the little arrow at the
-- bottom jumps back to the newest line.
local function ChatScrollBar(cf)
	if cf.afoScroll then return end
	local bar = CreateFrame("Slider", nil, cf)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(6)
	bar:SetPoint("TOPLEFT", cf, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", cf, "BOTTOMRIGHT", 6, 14)
	ns:Skin(bar)
	bar.fill:SetTexture(0, 0, 0, 0.35)
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(colors.muted[1], colors.muted[2], colors.muted[3], 0.9)
	thumb:SetSize(6, 30)
	bar:SetThumbTexture(thumb)
	bar:SetValueStep(1)
	bar:SetMinMaxValues(0, 0)
	bar:SetValue(0)

	local bottom = CreateFrame("Button", nil, cf)
	bottom:SetSize(12, 12)
	bottom:SetPoint("TOP", bar, "BOTTOM", 0, -2)
	ns:Skin(bottom)
	bottom.text = ns:CreateText(bottom, 10, true, "CENTER")
	bottom.text:SetPoint("CENTER", 0, 0)
	bottom.text:SetText("v")
	bottom:SetScript("OnClick", function() cf:ScrollToBottom() end)
	bottom:Hide()

	local function Lines()
		local n = cf.GetNumLinesDisplayed and cf:GetNumLinesDisplayed()
		if n and n > 0 then return n end
		local _, size = cf:GetFont()
		return math.max(1, floor((cf:GetHeight() or 100) / ((size or 14) + 2)))
	end
	local function Max()
		return math.max(0, (cf:GetNumMessages() or 0) - Lines())
	end

	local updating = false
	local function Sync()
		local max = Max()
		local scroll = cf:GetCurrentScroll() or 0
		updating = true
		bar:SetMinMaxValues(0, max)
		bar:SetValue(max - scroll)
		updating = false
		-- thumb size follows how much of the history is visible
		local h = bar:GetHeight() or 100
		local total = math.max(1, cf:GetNumMessages() or 1)
		thumb:SetHeight(math.max(16, math.min(h, h * Lines() / total)))
		if max == 0 then bar:SetAlpha(0.25) else bar:SetAlpha(1) end
		if scroll > 0 then bottom:Show() else bottom:Hide() end
	end

	bar:SetScript("OnValueChanged", function(_, value)
		if updating then return end
		local want = floor(Max() - value + 0.5)
		if cf.SetScrollOffset then
			cf:SetScrollOffset(want)
		else
			-- older clients: step there line by line (bounded)
			for _ = 1, 2000 do
				local now = cf:GetCurrentScroll() or 0
				if now < want then cf:ScrollUp() elseif now > want then cf:ScrollDown() else break end
				if (cf:GetCurrentScroll() or 0) == now then break end -- reached the end
			end
		end
		Sync()
	end)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnMouseWheel", function(_, delta)
		if delta > 0 then cf:ScrollUp() else cf:ScrollDown() end
		Sync()
	end)

	-- follow new messages / wheel scrolling
	local acc = 0
	bar:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.15 then return end
		acc = 0
		Sync()
	end)
	cf.afoScroll = bar
	Sync()
end

-- dark panel behind the chat text, always on (Blizzard's own background only shows on mouseover)
local chatBgs = {}
local function ChatBackground(cf)
	if cf.afoBg then return end
	local bg = CreateFrame("Frame", nil, cf)
	bg:SetFrameLevel(math.max(0, cf:GetFrameLevel() - 1))
	bg:SetPoint("TOPLEFT", cf, "TOPLEFT", -6, 6)
	bg:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 14, -6) -- covers the scroll bar too
	bg.tex = bg:CreateTexture(nil, "BACKGROUND")
	bg.tex:SetAllPoints()
	bg.tex:SetTexture(0, 0, 0, 1)
	bg:SetAlpha(ns.db.chatAlpha or 0.4)
	cf.afoBg = bg
	chatBgs[#chatBgs + 1] = bg
end

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
			local ok, err = pcall(ChatScrollBar, cf)
			if not ok then ns:Report(err) end
			ok, err = pcall(ChatBackground, cf)
			if not ok then ns:Report(err) end
		end
	end
	CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0
	CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
end

----------------------------------------------------------------------
-- Arena: map + bracket + match timer + players alive (top center); gates countdown inside the bar
----------------------------------------------------------------------
local status
local matchStart, gatesAt

local COUNTDOWN_MSGS = {
	{ "One minute", 60 }, { "Thirty seconds", 30 }, { "Fifteen seconds", 15 },
	-- battlegrounds: "The battle for Warsong Gulch begins in 1 minute."
	{ "in 2 minutes", 120 }, { "in 1 minute", 60 }, { "in 30 seconds", 30 },
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
	ns:Mover("arenastatus", "ARENA TIMER", status, "TOP", "TOP", 0, -45)
	ns:Skin(status)
	status.fill:SetTexture(0.03, 0.035, 0.043, 0.85)
	status.map = ns:CreateText(status, 15, true, "LEFT")
	status.map:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	status.time = ns:CreateText(status, 20, true, "LEFT")
	status.map:SetPoint("LEFT", 16, 0)
	status.time:SetPoint("LEFT", status.map, "RIGHT", 18, 0)
	-- players still alive: yours v theirs (replaces Blizzard's "Gold Team: 3 Players Remaining")
	status.alive = ns:CreateText(status, 18, true, "LEFT")
	status.alive:SetPoint("LEFT", status.time, "RIGHT", 18, 0)
	status:Hide()

	-- runs on its own frame: in battlegrounds the arena timer is hidden but the countdown isn't
	local driver = CreateFrame("Frame")
	local acc = 0
	driver:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.2 then return end
		acc = 0
		local now = GetTime()
		-- one countdown only, inside the bar (no second big number on screen)
		local _, kind = IsInInstance()
		if gatesAt and gatesAt > now then
			local left = ceil(gatesAt - now)
			status.time:SetText(format("|cfff2b33dGATES %d:%02d|r", floor(left / 60), left % 60))
			if kind == "pvp" and not status:IsShown() then
				status.map:SetText(strupper(GetRealZoneText() or ""))
				status:Show()
			end
		else
			-- battlegrounds: the bar is only there for the gates countdown
			if kind == "pvp" and status:IsShown() and not ns.testing then status:Hide() end
			if gatesAt and not matchStart then matchStart = gatesAt end
			if matchStart then
				local t = now - matchStart
				status.time:SetText(format("%02d:%02d", floor(t / 60), floor(t % 60)))
			else
				status.time:SetText("--:--")
			end
		end
		-- alive counts
		local mine, theirs = 0, 0
		for _, u in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
			if UnitExists(u) and not UnitIsDeadOrGhost(u) then mine = mine + 1 end
		end
		local seen = 0
		for i = 1, 5 do
			local u = "arena" .. i
			if UnitExists(u) then
				seen = seen + 1
				if not UnitIsDeadOrGhost(u) then theirs = theirs + 1 end
			end
		end
		if ns.testing then mine, theirs, seen = 3, 2, 3 end
		if seen > 0 then
			status.alive:SetText(format("|cff4dc764%d|r |cff8b8f96v|r |cffe5484d%d|r", mine, theirs))
		else
			status.alive:SetText("")
		end
		local w = status.map:GetStringWidth() + status.time:GetStringWidth() + status.alive:GetStringWidth() + 68
		status:SetWidth(w)
	end)
end

local function ArenaZone()
	if not status then return end
	if ns:InArena() then
		status.map:SetText(strupper((GetRealZoneText() or "") .. "  " .. Bracket()))
		status:Show()
	else
		-- keep a battleground's gates countdown running; anywhere else, clear it
		local _, kind = IsInInstance()
		if kind ~= "pvp" then
			status:Hide()
			matchStart, gatesAt = nil, nil
		elseif not (gatesAt and gatesAt > GetTime()) then
			status:Hide()
		end
	end
end

ns:On("PLAYER_ENTERING_WORLD", function() matchStart, gatesAt = nil, nil; ArenaZone() end)
ns:On("ZONE_CHANGED_NEW_AREA", ArenaZone)
ns:On("UPDATE_BATTLEFIELD_STATUS", ArenaZone)
ns:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", function(_, msg)
	if not msg then return end
	local _, kind = IsInInstance()
	if kind ~= "arena" and kind ~= "pvp" then return end
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
-- Make sure the square map is really in place: run the setup at login, and check again
-- after every loading screen (if anything stopped it, or the game put the map back).
local minimapDone = false
local function EnsureMinimap()
	if not ns.db or not ns.db.minimap or InCombatLockdown() then return end
	if minimapDone and Minimap:GetParent() ~= MinimapCluster then return end
	minimapDone = true
	local ok, err = pcall(SetupMinimap)
	if not ok then ns:Report(err) end
end
ns:On("PLAYER_ENTERING_WORLD", function() if ns.loaded then EnsureMinimap() end end)

ns:Listen("LOGIN", function()
	if ns.db.minimap then
		EnsureMinimap()
	else
		ns:Print("the minimap is left as Blizzard's (turned off in /afo settings - tick Minimap and /reload to use the square one)")
	end
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
	for _, bg in ipairs(chatBgs) do bg:SetAlpha(ns.db.chatAlpha or 0.4) end
end)
