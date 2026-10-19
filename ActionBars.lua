-- AllForOne: action bars
-- Reuses Blizzard's own buttons (your keybinds and macros keep working), moved and restyled:
--   3 rows bottom-center: bar 1 (main) at the bottom, bar 2 (bottom-left) above it, bar 3 (bottom-right) on top
--   2 columns bottom-right above the bags: right bar (inner), right bar 2 (outer)
--   above the 3 rows: stance/forms/auras in the left corner, pet bar in the right corner
-- Every bar is movable and resizable with /afo unlock.
local _, ns = ...
local media = ns.media
local BTN, GAP = 36, 3
local STEP = BTN + GAP

local holders = {}

local function Holder(name, label, w, h, point, x, y)
	local f = CreateFrame("Frame", name, ns.root, "SecureHandlerStateTemplate")
	f:SetSize(w, h)
	RegisterStateDriver(f, "visibility", "[vehicleui] hide; show")
	holders[name] = f
	ns:Mover(name, label, f, point, point, x, y)
	return f
end

----------------------------------------------------------------------
-- Button skin
----------------------------------------------------------------------
local function Shorten(text)
	if not text or text == "" or text == RANGE_INDICATOR then return text end
	text = text:gsub("Mouse Button ", "M"):gsub("Middle Mouse", "M3"):gsub("Mouse Wheel Up", "WU")
		:gsub("Mouse Wheel Down", "WD"):gsub("Num Pad ", "N"):gsub("Spacebar", "Spc")
		:gsub("s%-", "S"):gsub("c%-", "C"):gsub("a%-", "A")
		:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
	return strupper(text)
end

local function SkinButton(b)
	if not b or b.afoSkinned then return end
	b.afoSkinned = true
	local name = b:GetName()
	local icon = _G[name .. "Icon"]
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:ClearAllPoints()
		icon:SetAllPoints(b)
	end
	for _, suffix in ipairs({ "NormalTexture", "NormalTexture2", "FloatingBG" }) do
		local t = _G[name .. suffix]
		if t then t:SetAlpha(0) end
	end
	local nt = b:GetNormalTexture()
	if nt then nt:SetAlpha(0) end
	local macro = _G[name .. "Name"]
	if macro then macro:SetAlpha(0) end
	local hotkey = _G[name .. "HotKey"]
	if hotkey then
		ns:Font(hotkey, 10, true)
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", -2, -2)
		hotkey:SetJustifyH("RIGHT")
	end
	local count = _G[name .. "Count"]
	if count then
		ns:Font(count, 12, true)
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", -1, 2)
	end
	local border = _G[name .. "Border"]
	if border then
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", -1, 1)
		border:SetPoint("BOTTOMRIGHT", 1, -1)
	end
	local outline = b:CreateTexture(nil, "BACKGROUND")
	outline:SetTexture(0, 0, 0, 1)
	outline:SetPoint("TOPLEFT", -1, 1)
	outline:SetPoint("BOTTOMRIGHT", 1, -1)
	local fill = b:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(ns.colors.bg[1], ns.colors.bg[2], ns.colors.bg[3], 1)
	fill:SetAllPoints(b)
	local hl = b:GetHighlightTexture()
	if hl then hl:SetTexture(1, 1, 1, 0.15); hl:SetAllPoints(b) end
	local pushed = b:GetPushedTexture()
	if pushed then pushed:SetTexture(1, 1, 1, 0.25); pushed:SetAllPoints(b) end
	if b.GetCheckedTexture and b:GetCheckedTexture() then
		local c = b:GetCheckedTexture()
		c:SetTexture(ns.colors.kick[1], ns.colors.kick[2], ns.colors.kick[3], 0.35)
		c:SetAllPoints(b)
	end
end

----------------------------------------------------------------------
-- Cooldown numbers on action buttons (3.3.5 has none built in)
----------------------------------------------------------------------
local active = {}
local cdTicker = CreateFrame("Frame")
local acc = 0
cdTicker:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.1 then return end
	acc = 0
	local now = GetTime()
	for cd, ends in pairs(active) do
		local left = ends - now
		if left <= 0 or not cd:IsVisible() then
			if left <= 0 then active[cd] = nil end
			cd.afoText:SetText("")
		else
			cd.afoText:SetText(ns:FormatTime(left))
		end
	end
end)

local function OnCooldownSet(cd, start, duration, enable)
	if not cd or cd.noCooldownCount then return end
	if not cd.afoText then
		local overlay = CreateFrame("Frame", nil, cd)
		overlay:SetAllPoints(cd)
		overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
		cd.afoText = ns:CreateText(overlay, 15, true, "CENTER")
		cd.afoText:SetPoint("CENTER", 0, 0)
	end
	if enable == 1 and duration and duration > 2 and start > 0 then
		active[cd] = start + duration
	else
		active[cd] = nil
		cd.afoText:SetText("")
	end
end

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------
-- reparent=true only for the main bar: the extra bars read their action page from
-- their own Blizzard parent frame, so those buttons keep their parent and are only re-anchored.
local function Row(prefix, holder, vertical, reparent)
	for i = 1, 12 do
		local b = _G[prefix .. i]
		if b then
			if reparent then b:SetParent(holder) end
			b:ClearAllPoints()
			if vertical then
				b:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * STEP)
			else
				b:SetPoint("LEFT", holder, "LEFT", (i - 1) * STEP, 0)
			end
			SkinButton(b)
		end
	end
end

-- Left-aligned from the left corner of the action bars
-- (Druid forms, Warrior stances, Rogue stealth, DK presences, Paladin auras...)
local function AnchorSmallBar(prefix, count, holder)
	local first = _G[prefix .. "1"]
	if not first then return end
	first:ClearAllPoints()
	first:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
	for i = 1, count do
		local b = _G[prefix .. i]
		if b then
			if i > 1 then
				b:ClearAllPoints()
				b:SetPoint("LEFT", _G[prefix .. (i - 1)], "RIGHT", 3, 0)
			end
			SkinButton(b)
		end
	end
end

local function AnchorPetBar()
	local first = PetActionButton1
	if not first then return end
	first:ClearAllPoints()
	first:SetPoint("BOTTOMLEFT", holders.AFOPetBar, "BOTTOMLEFT", 0, 0)
	for i = 1, 10 do
		local b = _G["PetActionButton" .. i]
		if b then
			if i > 1 then
				b:ClearAllPoints()
				b:SetPoint("LEFT", _G["PetActionButton" .. (i - 1)], "RIGHT", 3, 0)
			end
			SkinButton(b)
		end
	end
end

local function Reanchor()
	ns:SafeCall(function()
		AnchorSmallBar("ShapeshiftButton", 10, holders.AFOStanceBar)
		AnchorSmallBar("PossessButton", 2, holders.AFOStanceBar)
		AnchorPetBar()
	end)
end

local function Build()
	-- three middle rows: bar 1 at the bottom (30px up, the XP bar goes under), bar 2, then bar 3 on top
	local rowW = 12 * STEP - GAP
	local main = Holder("AFOMainBar", "ACTION BAR 1", rowW, BTN, "BOTTOM", 0, 30)
	local bar2 = Holder("AFOBar2", "ACTION BAR 2", rowW, BTN, "BOTTOM", 0, 69)
	local bar3 = Holder("AFOBar3", "ACTION BAR 3", rowW, BTN, "BOTTOM", 0, 108)
	-- two columns bottom-right, above the bags
	local right1 = Holder("AFORight1", "RIGHT BAR 1", BTN, rowW, "BOTTOMRIGHT", -24 - STEP, 96)
	local right2 = Holder("AFORight2", "RIGHT BAR 2", BTN, rowW, "BOTTOMRIGHT", -24, 96)
	-- above the top row: stance bar in the left corner, pet bar in the right corner
	local smallW = 10 * 33 - 3
	local above = 108 + BTN + 5
	local stance = Holder("AFOStanceBar", "STANCES / FORMS", smallW, 30, "BOTTOM", -(rowW - smallW) / 2, above)
	local pet = Holder("AFOPetBar", "PET BAR", smallW, 30, "BOTTOM", (rowW - smallW) / 2, above)

	-- make sure all four extra bars are turned on
	SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2, SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4 = "1", "1", "1", "1"
	ALWAYS_SHOW_MULTIBARS = "1"
	SetActionBarToggles(1, 1, 1, 1, 1)
	if MultiActionBar_Update then MultiActionBar_Update() end

	Row("ActionButton", main, false, true)
	BonusActionBarFrame:SetParent(main)
	BonusActionBarFrame:SetFrameLevel(main:GetFrameLevel() + 4)
	Row("BonusActionButton", main)
	-- while a stance page is up, the stance buttons cover the normal ones
	BonusActionBarFrame:HookScript("OnShow", function()
		for i = 1, 12 do _G["ActionButton" .. i]:SetAlpha(0) end
	end)
	BonusActionBarFrame:HookScript("OnHide", function()
		for i = 1, 12 do _G["ActionButton" .. i]:SetAlpha(1) end
	end)
	if BonusActionBarFrame:IsShown() then
		for i = 1, 12 do _G["ActionButton" .. i]:SetAlpha(0) end
	end

	MultiBarBottomLeft:SetParent(bar2)
	Row("MultiBarBottomLeftButton", bar2)
	MultiBarBottomRight:SetParent(bar3)
	Row("MultiBarBottomRightButton", bar3)
	MultiBarRight:SetParent(right1)
	Row("MultiBarRightButton", right1, true)
	MultiBarLeft:SetParent(right2)
	Row("MultiBarLeftButton", right2, true)

	ShapeshiftBarFrame:SetParent(stance)
	if PossessBarFrame then PossessBarFrame:SetParent(stance) end
	PetActionBarFrame:SetParent(pet)

	-- keep Blizzard from moving bars back
	if UIPARENT_MANAGED_FRAME_POSITIONS then
		for _, n in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
			"ShapeshiftBarFrame", "PossessBarFrame", "PetActionBarFrame", "MainMenuBar" }) do
			UIPARENT_MANAGED_FRAME_POSITIONS[n] = nil
		end
	end
	hooksecurefunc("UIParent_ManageFramePositions", Reanchor)
	if ShapeshiftBar_Update then hooksecurefunc("ShapeshiftBar_Update", Reanchor) end
	if PetActionBar_Update then hooksecurefunc("PetActionBar_Update", Reanchor) end
	Reanchor()

	-- the old bar art, XP bars, micro menu and bag buttons go away (replaced in HUD.lua)
	MainMenuBar:SetParent(ns.hider)

	hooksecurefunc("ActionButton_UpdateHotkeys", function(self)
		local hk = _G[self:GetName() .. "HotKey"]
		if hk then hk:SetText(Shorten(hk:GetText())) end
	end)
	for _, prefix in ipairs({ "ActionButton", "BonusActionButton", "MultiBarBottomLeftButton",
		"MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }) do
		for i = 1, 12 do
			local b = _G[prefix .. i]
			if b and ActionButton_UpdateHotkeys then ActionButton_UpdateHotkeys(b, b.buttonType) end
		end
	end
end

ns:Listen("LOGIN", function()
	if CooldownFrame_SetTimer then hooksecurefunc("CooldownFrame_SetTimer", OnCooldownSet) end
	if not ns.db.actionbars then return end
	ns:SafeCall(Build)
	-- learning a new form/stance changes how many buttons there are
	ns:On("UPDATE_SHAPESHIFT_FORMS", Reanchor)
end)
