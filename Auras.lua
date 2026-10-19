-- AllForOne: your buffs/debuffs (by the minimap), loss-of-control alert, proc alerts
local _, ns = ...
local colors, media = ns.colors, ns.media
local GetTime = GetTime

----------------------------------------------------------------------
-- Buffs + debuffs: keep Blizzard's (right-click to cancel still works),
-- move them next to the minimap and restyle them.
----------------------------------------------------------------------
local skinned = {}

local function SkinAura(button, isDebuff)
	if not button or skinned[button] then return end
	skinned[button] = true
	local name = button:GetName()
	local icon = _G[name .. "Icon"]
	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		icon:SetAllPoints(button)
	end
	-- outline + dispel-colored ring sit in a frame BEHIND the button, never over the icon
	button.afoBack = ns:Backing(button)
	local border = _G[name .. "Border"]
	if border then
		-- Blizzard colors this by debuff type; we hide it and copy its color to our ring
		border:SetAlpha(0)
		button.afoBorder = border
	end
	local duration = _G[name .. "Duration"]
	if duration then
		ns:Font(duration, isDebuff and 13 or 12, true)
		duration:ClearAllPoints()
		duration:SetPoint("TOP", button, "BOTTOM", 0, -3)
	end
	local count = _G[name .. "Count"]
	if count then
		ns:Font(count, 12, true)
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", 2, -2)
	end
end

-- Blizzard's buff frame lives in UIParent; it follows our movable "buffs" holder
local buffHolder

-- Our own grid instead of Blizzard's anchors (which offset the first row by the
-- weapon-enchant frame): rows of 8 growing left from the holder's top-right corner,
-- so the first row's top edge lines up exactly with the minimap's top edge.
local BUFF_SIZE, DEBUFF_SIZE, GAP_X, PER_ROW = 30, 36, 6, 8
local TIMER_H = 18 -- room for the countdown under each icon

local function LayoutAuras()
	if not buffHolder or not BuffFrame then return end
	local col, y, rowH = 0, 0, BUFF_SIZE + TIMER_H
	local function Place(button, size)
		if col == PER_ROW then col, y = 0, y + rowH end
		button:SetSize(size, size)
		button:ClearAllPoints()
		button:SetPoint("TOPRIGHT", BuffFrame, "TOPRIGHT", -col * (size + GAP_X), -y)
		col = col + 1
	end
	for i = 1, 2 do
		local b = _G["TempEnchant" .. i]
		if b and b:IsShown() then Place(b, BUFF_SIZE) end
	end
	for i = 1, BUFF_MAX_DISPLAY or 16 do
		local b = _G["BuffButton" .. i]
		if b and b:IsShown() then Place(b, BUFF_SIZE) end
	end
	-- debuffs start on their own row, a little bigger
	if col > 0 then col, y = 0, y + rowH end
	rowH = DEBUFF_SIZE + TIMER_H
	for i = 1, DEBUFF_MAX_DISPLAY or 8 do
		local b = _G["DebuffButton" .. i]
		if b and b:IsShown() then Place(b, DEBUFF_SIZE) end
	end
end

local function PlaceBuffFrame()
	if not buffHolder then return end
	ns:SafeCall(function()
		local scale = buffHolder:GetEffectiveScale() / UIParent:GetEffectiveScale()
		for _, f in ipairs({ BuffFrame, TemporaryEnchantFrame }) do
			if f then
				f:SetScale(scale)
				f:ClearAllPoints()
				f:SetPoint("TOPRIGHT", buffHolder, "TOPRIGHT", 0, 0)
			end
		end
	end)
end

ns:Listen("LOGIN", function()
	SetCVar("consolidateBuffs", "0")
	SetCVar("buffDurations", "1")
	-- cap your own auras at 2 rows of buffs and 1 row of debuffs,
	-- so a fully buffed character never grows down into the enemy arena frames
	local MAX_BUFFS, MAX_DEBUFFS = 16, 8
	BUFF_MAX_DISPLAY = MAX_BUFFS
	DEBUFF_MAX_DISPLAY = MAX_DEBUFFS
	if BuffFrame_Update then
		hooksecurefunc("BuffFrame_Update", function()
			for i = MAX_BUFFS + 1, 32 do
				local b = _G["BuffButton" .. i]
				if b then b:Hide() end
			end
			for i = MAX_DEBUFFS + 1, 16 do
				local b = _G["DebuffButton" .. i]
				if b then b:Hide() end
			end
		end)
		BuffFrame_Update()
	end
	for _, fn in ipairs({ "BuffFrame_Update", "BuffFrame_UpdateAllBuffAnchors", "DebuffButton_UpdateAnchors",
		"TemporaryEnchantFrame_Update" }) do
		if _G[fn] then hooksecurefunc(fn, LayoutAuras) end
	end
	hooksecurefunc("AuraButton_Update", function(buttonName, index, filter)
		local button = _G[buttonName .. index]
		SkinAura(button, filter == "HARMFUL")
		if button and button.afoBack then
			local border = button.afoBorder
			if border and filter == "HARMFUL" then
				local r, g, b = border:GetVertexColor()
				button.afoBack.ring:SetTexture(r or 0.7, g or 0.27, b or 0.23, 1)
				button.afoBack.ring:Show()
			else
				button.afoBack.ring:Hide()
			end
		end
	end)
	hooksecurefunc("AuraButton_UpdateDuration", function(button, timeLeft)
		local d = button.duration
		if d and timeLeft then
			d:SetText(ns:FormatTime(timeLeft))
			d:SetTextColor(1, 1, 1)
		end
	end)
	for i = 1, 2 do SkinAura(_G["TempEnchant" .. i], false) end
	-- default: left of the minimap (minimap is 168 wide, 24 from the edge, 14px gap)
	buffHolder = CreateFrame("Frame", nil, ns.root)
	buffHolder:SetSize(PER_ROW * (BUFF_SIZE + GAP_X) - GAP_X, 168)
	ns:Mover("buffs", "BUFFS / DEBUFFS", buffHolder, "TOPRIGHT", "TOPRIGHT", -206, -24)
	PlaceBuffFrame()
	LayoutAuras()
end)
ns:Listen("MINIMAP_PLACED", PlaceBuffFrame)
ns:Listen("LAYOUT_CHANGED", PlaceBuffFrame)
ns:On("UI_SCALE_CHANGED", PlaceBuffFrame)

----------------------------------------------------------------------
-- Loss of control: big icon above your character
----------------------------------------------------------------------
local loc

local function CreateLoC()
	loc = CreateFrame("Frame", nil, ns.root)
	loc:SetSize(220, 72)
	ns:Mover("loc", "LOSS OF CONTROL", loc, "CENTER", "CENTER", 0, 230)
	loc.icon = ns:CreateIcon(loc, 72, 1)
	loc.icon:SetPoint("LEFT")
	loc.icon.timer:Hide()
	loc.icon:SetBorder(colors.danger[1], colors.danger[2], colors.danger[3])
	loc.label = ns:CreateText(loc, 15, true, "LEFT")
	loc.label:SetPoint("TOPLEFT", loc.icon, "TOPRIGHT", 14, -2)
	loc.label:SetTextColor(colors.danger[1], colors.danger[2], colors.danger[3])
	loc.time = ns:CreateText(loc, 44, true, "LEFT")
	loc.time:SetPoint("LEFT", loc.icon, "RIGHT", 14, -2)
	loc.sub = ns:CreateText(loc, 14, true, "LEFT")
	loc.sub:SetPoint("BOTTOMLEFT", loc.icon, "BOTTOMRIGHT", 14, 2)
	loc.sub:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	loc:SetScript("OnUpdate", function(self)
		local left = (self.expires or 0) - GetTime()
		if self.expires and left <= 0 then self:Hide() return end
		self.time:SetText(self.expires and format("%.1f", left) or "")
	end)
	loc:Hide()
end

-- Your own PvP trinket (either trinket slot) or the Human racial
local function TrinketStatus()
	local start, duration
	local pvpName = GetSpellInfo(42292)
	for slot = 13, 14 do
		local link = GetInventoryItemLink("player", slot)
		if link and pvpName and GetItemSpell(link) == pvpName then
			start, duration = GetInventoryItemCooldown("player", slot)
			break
		end
	end
	if not start then
		local emfh = GetSpellInfo(59752)
		if emfh and GetSpellInfo(emfh) then start, duration = GetSpellCooldown(emfh) end
	end
	if not start then return "" end
	if start > 0 and duration > 1.5 then
		return "Trinket " .. ns:FormatTime(start + duration - GetTime())
	end
	return "Trinket ready"
end

function ns:ShowLoC(icon, cat, duration, expires)
	if not loc then return end
	if not icon then loc:Hide() return end
	loc.icon:Set(icon, nil, duration, expires, true)
	loc.icon.timer:SetText("")
	loc.label:SetText(ns.ccLabel[cat] or "")
	loc.expires = expires and expires > 0 and expires or nil
	loc.sub:SetText(TrinketStatus())
	loc:Show()
end

----------------------------------------------------------------------
-- Procs: glowing icons left and right of your character
----------------------------------------------------------------------
local procSlots = {}
local SLOT_POS = { { -247, 16 }, { 247, 16 }, { -247, -84 }, { 247, -84 } }

local function CreateProcs()
	-- one holder spanning both sides of the character, so procs move/scale as a pair
	local holder = CreateFrame("Frame", nil, ns.root)
	holder:SetSize(630, 250)
	ns:Mover("procs", "PROC ALERTS", holder, "CENTER", "CENTER", 0, -30)
	for i, pos in ipairs(SLOT_POS) do
		local s = CreateFrame("Frame", nil, holder)
		s:SetSize(134, 76)
		s:SetPoint("CENTER", holder, "CENTER", pos[1], pos[2] + 20)
		s.icon = ns:CreateIcon(s, 56, 16)
		s.icon:SetPoint("TOP")
		s.icon:SetBorder(colors.kick[1], colors.kick[2], colors.kick[3])
		s.glow = s:CreateTexture(nil, "BACKGROUND")
		s.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
		s.glow:SetBlendMode("ADD")
		s.glow:SetVertexColor(colors.kick[1], colors.kick[2], colors.kick[3], 0.8)
		s.glow:SetPoint("CENTER", s.icon, "CENTER")
		s.glow:SetSize(104, 104)
		s.label = ns:CreateText(s, 12, true, "CENTER")
		s.label:SetPoint("TOP", s.icon, "BOTTOM", 0, -6)
		s.label:SetTextColor(colors.kick[1], colors.kick[2], colors.kick[3])
		s.icon.count:ClearAllPoints()
		s.icon.count:SetPoint("BOTTOMRIGHT", 3, -4)
		ns:Font(s.icon.count, 18, true)
		s:Hide()
		procSlots[i] = s
	end
end

function ns:ShowProcs(list)
	for i, s in ipairs(procSlots) do
		local p = list[i]
		if p then
			s.icon:Set(p.icon, p.count, p.dur, p.expires)
			s.label:SetText(strupper(p.name))
			s:Show()
		else
			s.icon:Clear()
			s:Hide()
		end
	end
end

----------------------------------------------------------------------
-- Scan your auras
----------------------------------------------------------------------
local function ScanPlayer()
	if ns.testing then return end
	-- worst crowd control on you
	local best, bestPrio
	for i = 1, 40 do
		local name, _, icon, _, _, duration, expires = UnitAura("player", i, "HARMFUL")
		if not name then break end
		local cc = ns.CC[name]
		if cc then
			local p = ns.ccPriority[cc.cat] or 0
			if not best or p > bestPrio then
				best, bestPrio = { icon = icon, cat = cc.cat, dur = duration, expires = expires }, p
			end
		end
	end
	if best then ns:ShowLoC(best.icon, best.cat, best.dur, best.expires) else ns:ShowLoC(nil) end

	local procs = {}
	for i = 1, 40 do
		local name, _, icon, count, _, duration, expires = UnitAura("player", i, "HELPFUL")
		if not name then break end
		if ns:IsProc(name) then
			procs[#procs + 1] = { name = name, icon = icon, count = count, dur = duration, expires = expires }
			ns:RememberProcIcon(name, icon)
		end
	end
	ns:ShowProcs(procs)
end
ns.ScanPlayer = ScanPlayer

ns:Listen("LOGIN", function()
	CreateLoC()
	CreateProcs()
	ScanPlayer()
end)
ns:On("UNIT_AURA", function(_, unit) if unit == "player" then ScanPlayer() end end)
ns:On("PLAYER_ENTERING_WORLD", ScanPlayer)
