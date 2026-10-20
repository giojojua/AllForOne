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

----------------------------------------------------------------------
-- Range / power colors: the whole icon is tinted, so you see it without reading anything
--   red   = target out of range
--   blue  = not enough mana / rage / energy / runic power
--   dark  = can't be used right now
-- Works for macros too (the game resolves a macro to the spell it would cast).
----------------------------------------------------------------------
local ACTION_PREFIXES = { "ActionButton", "BonusActionButton", "MultiBarBottomLeftButton",
	"MultiBarBottomRightButton", "MultiBarRightButton", "MultiBarLeftButton" }
local TINT = {
	range = { 0.95, 0.25, 0.25 },
	power = { 0.30, 0.45, 1.00 },
	unusable = { 0.35, 0.35, 0.35 },
	normal = { 1, 1, 1 },
}

local function Tint(b)
	local icon = b.afoIcon
	if not icon then
		icon = _G[b:GetName() .. "Icon"]
		b.afoIcon = icon
	end
	local action = b.action
	if not icon or not action or not HasAction(action) then return end
	local state = "normal"
	if ns.db.usableColors ~= false then
		local usable, noPower = IsUsableAction(action)
		if IsActionInRange(action) == 0 then state = "range"
		elseif noPower then state = "power"
		elseif not usable then state = "unusable" end
	end
	if b.afoTint ~= state or state ~= "normal" then
		local c = TINT[state]
		icon:SetVertexColor(c[1], c[2], c[3])
		b.afoTint = state
	end
end

function ns.SetupUsableColors()
	local buttons = {}
	for _, prefix in ipairs(ACTION_PREFIXES) do
		for i = 1, 12 do
			local b = _G[prefix .. i]
			if b then buttons[#buttons + 1] = b end
		end
	end
	-- Blizzard repaints the icon on its own updates; paint ours right after
	if ActionButton_UpdateUsable then
		hooksecurefunc("ActionButton_UpdateUsable", function(self) self.afoTint = nil; Tint(self) end)
	end
	-- range has no event: check every 0.2s (only buttons that are shown and hold something)
	local t = CreateFrame("Frame")
	local acc = 0
	t:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.2 then return end
		acc = 0
		for _, b in ipairs(buttons) do
			if b:IsVisible() then Tint(b) end
		end
	end)
	ns:Listen("REFRESH_ALL", function()
		for _, b in ipairs(buttons) do b.afoTint = nil; if b:IsVisible() then Tint(b) end end
	end)
end

local macroTexts = {}
ns:Listen("REFRESH_ALL", function()
	for _, m in ipairs(macroTexts) do m:SetAlpha(ns.db.macroNames == false and 0 or 1) end
end)

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
	-- macro name: small, along the bottom edge of the button (can be turned off in /afo settings)
	local macro = _G[name .. "Name"]
	if macro then
		ns:Font(macro, 10, true)
		macro:ClearAllPoints()
		macro:SetPoint("BOTTOMLEFT", 2, 2)
		macro:SetPoint("BOTTOMRIGHT", -2, 2)
		macro:SetJustifyH("CENTER")
		macro:SetTextColor(1, 1, 1)
		macro:SetAlpha(ns.db.macroNames == false and 0 or 1)
		macroTexts[#macroTexts + 1] = macro
	end
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
	ns:Backing(b)
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
			local ok, err = pcall(SkinButton, b)
			if not ok then ns:Report(err) end
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
			local ok, err = pcall(SkinButton, b)
			if not ok then ns:Report(err) end
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
			local ok, err = pcall(SkinButton, b)
			if not ok then ns:Report(err) end
		end
	end
end

local function DoReanchor()
	AnchorSmallBar("ShapeshiftButton", 10, holders.AFOStanceBar)
	AnchorSmallBar("PossessButton", 2, holders.AFOStanceBar)
	AnchorPetBar()
end
-- one shared function: during combat it's queued once, not once per Blizzard update
local function Reanchor()
	ns:SafeCall(DoReanchor)
end

-- Blizzard bar artwork that would otherwise travel along with the bars we move
local ART = {
	"MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
	"MainMenuBarLeftEndCap", "MainMenuBarRightEndCap", "MainMenuBarPageNumber",
	"BonusActionBarTexture0", "BonusActionBarTexture1",
	"ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
	"SlidingActionBarTexture0", "SlidingActionBarTexture1",
	"PossessBackground1", "PossessBackground2",
}

local function HideBlizzardBar()
	-- the whole default bar: gryphons, page arrows, XP/rep bars, micro menu, bag buttons
	MainMenuBar:SetParent(ns.hider)
	MainMenuBar:Hide()
	for _, name in ipairs({ "ActionBarUpButton", "ActionBarDownButton", "MainMenuExpBar",
		"MainMenuBarMaxLevelBar", "ReputationWatchBar", "ExhaustionTick" }) do
		local f = _G[name]
		if f then f:SetParent(ns.hider) end
	end
	for _, name in ipairs(ART) do
		local t = _G[name]
		if t then
			if t.SetTexture then t:SetTexture(nil) end -- MainMenuBarPageNumber is a text label
			t:SetAlpha(0)
			t:Hide()
		end
	end
end

-- run each step on its own: if one fails, the rest still happen and the error is reported
local function Step(fn)
	local ok, err = pcall(fn)
	if not ok then ns:Report(err) end
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

	-- 1. main bar buttons out of the Blizzard bar, then hide the Blizzard bar
	Step(function() Row("ActionButton", main, false, true) end)
	Step(function()
		MultiBarBottomLeft:SetParent(bar2)
		MultiBarBottomRight:SetParent(bar3)
		MultiBarRight:SetParent(right1)
		MultiBarLeft:SetParent(right2)
		BonusActionBarFrame:SetParent(main)
		BonusActionBarFrame:SetFrameLevel(main:GetFrameLevel() + 4)
		ShapeshiftBarFrame:SetParent(stance)
		if PossessBarFrame then PossessBarFrame:SetParent(stance) end
		PetActionBarFrame:SetParent(pet)
	end)
	Step(HideBlizzardBar)

	-- 2. turn on all four extra bars
	Step(function()
		SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2, SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4 = "1", "1", "1", "1"
		ALWAYS_SHOW_MULTIBARS = "1"
		SetActionBarToggles(1, 1, 1, 1, 1)
		if MultiActionBar_Update then MultiActionBar_Update() end
	end)

	-- 3. lay out and restyle the buttons
	Step(function()
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
	end)
	Step(function() Row("MultiBarBottomLeftButton", bar2) end)
	Step(function() Row("MultiBarBottomRightButton", bar3) end)
	Step(function() Row("MultiBarRightButton", right1, true) end)
	Step(function() Row("MultiBarLeftButton", right2, true) end)

	-- 4. keep Blizzard from moving bars back
	Step(function()
		if UIPARENT_MANAGED_FRAME_POSITIONS then
			for _, n in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
				"ShapeshiftBarFrame", "PossessBarFrame", "PetActionBarFrame", "MainMenuBar" }) do
				UIPARENT_MANAGED_FRAME_POSITIONS[n] = nil
			end
		end
		hooksecurefunc("UIParent_ManageFramePositions", Reanchor)
		if ShapeshiftBar_Update then hooksecurefunc("ShapeshiftBar_Update", Reanchor) end
		if PetActionBar_Update then hooksecurefunc("PetActionBar_Update", Reanchor) end
	end)
	Step(Reanchor)

	-- 5. short keybind labels
	Step(function()
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
	end)

	-- 6. range + power colors on spells and macros
	Step(ns.SetupUsableColors)
end

ns:Listen("LOGIN", function()
	if CooldownFrame_SetTimer then hooksecurefunc("CooldownFrame_SetTimer", OnCooldownSet) end
	if not ns.db.actionbars then return end
	ns:SafeCall(Build)
	-- learning a new form/stance changes how many buttons there are
	ns:On("UPDATE_SHAPESHIFT_FORMS", Reanchor)
end)
