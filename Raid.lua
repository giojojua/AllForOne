-- AllForOne: raid frames (battlegrounds and raids)
-- A compact grid: one column per group (up to 8 x 5). Each cell: class-colored health, name,
-- the most important debuff (crowd control first, then anything you can dispel) and a white
-- ring on your target. Out-of-range players fade. In a raid, the party rows on the left hide
-- and this grid takes over under your own frame.
local _, ns = ...
local colors = ns.colors

local CELL_W, CELL_H, GAP = 70, 30, 3
local cells = {}      -- every cell (secure + preview)
local ApplyShape
local header, holder, preview

----------------------------------------------------------------------
-- One cell
----------------------------------------------------------------------
local Cell = {}

function Cell:Paint()
	local u = self.unit
	local d = self.fake
	if not d and (not u or not UnitExists(u)) then return end
	local name = d and d.name or UnitName(u) or ""
	local class = d and d.class or select(2, UnitClass(u))
	local cur, max
	if d then cur, max = d.hp, 100 else cur, max = UnitHealth(u), UnitHealthMax(u) end
	if not max or max == 0 then max = 1 end
	self.health:SetMinMaxValues(0, max)
	self.health:SetValue(cur or 0)
	local r, g, b = ns:ClassColor(class)
	if ns.db.classColoredBars then
		self.health:SetStatusBarColor(r, g, b)
		self.name:SetTextColor(1, 1, 1)
	else
		self.health:SetStatusBarColor(colors.missing[1], colors.missing[2], colors.missing[3])
		self.name:SetTextColor(r, g, b)
	end
	self.name:SetText(name)
	local state
	if d then state = d.state
	elseif not UnitIsConnected(u) then state = "OFF"
	elseif UnitIsDeadOrGhost(u) then state = "DEAD" end
	self.state:SetText(state or "")
	if state then self.health:SetValue(0) end
end

function Cell:Auras()
	local a
	if self.fake then
		a = self.fake.debuff
	elseif self.unit and UnitExists(self.unit) then
		a = ns:ScanDebuffs(self.unit, 1)[1]
	end
	if a then
		self.debuff:Set(a.icon, a.count, a.dur, a.expires)
		local c = colors.dispel[a.dispel or "none"] or colors.dispel.none
		self.debuff:SetBorder(c[1], c[2], c[3])
	else
		self.debuff:Clear()
	end
end

function Cell:State()
	local u = self.unit
	if self.fake then
		self:SetAlpha(self.fake.far and 0.45 or 1)
		ns:SetHighlight(self.health, self.fake.target)
		return
	end
	if not u or not UnitExists(u) then return end
	local inRange = UnitInRange(u)
	local near = UnitIsUnit(u, "player") or inRange
	self:SetAlpha(near and 1 or 0.45)
	ns:SetHighlight(self.health, UnitIsUnit(u, "target"))
end

function Cell:Update()
	self:Paint()
	self:Auras()
	self:State()
end

local function Style(f)
	for k, v in pairs(Cell) do f[k] = v end
	f:SetSize(CELL_W, CELL_H)
	f.health = ns:CreateBar(f, CELL_W, CELL_H)
	f.health:SetAllPoints(f)
	f.name = ns:CreateText(f.health, 12, true, "LEFT")
	f.name:SetPoint("TOPLEFT", 4, -3)
	f.name:SetPoint("RIGHT", -4, 0)
	f.name:SetHeight(12)
	f.state = ns:CreateText(f.health, 11, true, "LEFT")
	f.state:SetPoint("BOTTOMLEFT", 4, 3)
	f.state:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	f.debuff = ns:CreateIcon(f.health, 18, 9)
	f.debuff:SetPoint("BOTTOMRIGHT", -2, 2)
	f.debuff:SetFrameLevel(f.health:GetFrameLevel() + 2)
	cells[#cells + 1] = f
	return f
end

----------------------------------------------------------------------
-- Secure header (real raid members)
----------------------------------------------------------------------
local byUnit = {}

local function StyleNewChildren()
	if not header or not header.initialConfigFunction then return end
	for _, b in ipairs({ header:GetChildren() }) do
		if not b.afoStyled then header.initialConfigFunction(b) end
	end
end

local function Rebuild()
	-- some 3.3.5 builds don't call initialConfigFunction: style any button the header made on its own
	StyleNewChildren()
	wipe(byUnit)
	for _, c in ipairs(cells) do
		if not c.fake then
			c.unit = c:GetAttribute("unit") or c.unit
			if c.unit and c:IsShown() then byUnit[c.unit] = c end
		end
	end
end

-- right-click menu (whisper, invite, report...) like Blizzard's raid frames
local dropdown
function ns:RaidMenu(btn)
	local unit = btn.unit
	if not unit or not UnitExists(unit) then return end
	if not dropdown then
		dropdown = CreateFrame("Frame", "AllForOneRaidDropDown", UIParent, "UIDropDownMenuTemplate")
		UIDropDownMenu_Initialize(dropdown, function(self)
			if self.unit then UnitPopup_ShowMenu(self, "RAID_PLAYER", self.unit, self.name, self.id) end
		end, "MENU")
	end
	dropdown.unit = unit
	dropdown.name = UnitName(unit)
	dropdown.id = tonumber(unit:match("^raid(%d+)$"))
	ToggleDropDownMenu(1, nil, dropdown, "cursor")
end

local function CreateHeader()
	header = CreateFrame("Frame", "AllForOneRaid", holder, "SecureGroupHeaderTemplate")
	header:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("showRaid", true)
	header:SetAttribute("showParty", false)
	header:SetAttribute("showPlayer", true)
	header:SetAttribute("groupBy", "GROUP")
	header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
	header:SetAttribute("maxColumns", 8)
	header:SetAttribute("unitsPerColumn", 5)
	header:SetAttribute("point", "TOP")
	header:SetAttribute("yOffset", -GAP)
	header:SetAttribute("columnAnchorPoint", "LEFT")
	header:SetAttribute("columnSpacing", GAP)
	-- 3.3.5: the header calls this (in Lua) for every new button it creates
	header.initialConfigFunction = function(btn)
		if btn.afoStyled then return end
		btn.afoStyled = true
		if not InCombatLockdown() then
			btn:SetAttribute("*type1", "target")
			btn:SetAttribute("*type2", "menu")
		end
		btn.menu = function(self) ns:RaidMenu(self) end
		btn:RegisterForClicks("AnyUp")
		btn:SetScript("OnEnter", UnitFrame_OnEnter)
		btn:SetScript("OnLeave", UnitFrame_OnLeave)
		Style(btn)
		btn:HookScript("OnAttributeChanged", function(self, key, value)
			if key == "unit" then
				self.unit = value
				Rebuild()
				if value then self:Update() end
			end
		end)
		btn:HookScript("OnShow", function(self)
			self.unit = self:GetAttribute("unit")
			Rebuild()
			self:Update()
		end)
	end
	header:Show()
end

----------------------------------------------------------------------
-- Preview grid for /afo test and move mode (fake battleground raid)
----------------------------------------------------------------------
local function Icon(id) local _, _, icon = GetSpellInfo(id) return icon end

local function ShowPreview(on)
	if not preview then
		preview = CreateFrame("Frame", nil, holder)
		preview:SetAllPoints(holder)
		local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "PALADIN", "HUNTER", "SHAMAN", "WARLOCK", "DEATHKNIGHT" }
		local names = { "Brakk", "Lumen", "Frosty", "Shade", "Oakrun", "Valor", "Arrows", "Tide", "Gloom", "Rime",
			"Krag", "Solace", "Blink", "Vex", "Moonfang" }
		preview.cells = {}
		for i = 1, 15 do
			local f = Style(CreateFrame("Frame", nil, preview))
			local col, row = floor((i - 1) / 5), (i - 1) % 5
			f:SetPoint("TOPLEFT", preview, "TOPLEFT", col * (CELL_W + GAP), -row * (CELL_H + GAP))
			f.fake = { name = names[i], class = classes[(i - 1) % #classes + 1], hp = 35 + (i * 37) % 65 }
			preview.cells[i] = f
		end
		preview.cells[3].fake.far = true
		preview.cells[7].fake.state = "DEAD"
		preview.cells[12].fake.far = true
		preview.cells[5].fake.target = true
		preview.cells[2].fake.debuff = { icon = Icon(10890), dispel = "Magic" }       -- Psychic Scream
		preview.cells[9].fake.debuff = { icon = Icon(118), dispel = "Magic" }         -- Polymorph
		preview.cells[14].fake.debuff = { icon = Icon(2637), dispel = "Magic" }       -- Hibernate
		preview.cells[11].fake.debuff = { icon = Icon(11719), dispel = "Curse" }      -- Curse of Tongues
	end
	if on then
		local now = GetTime()
		for _, f in ipairs(preview.cells) do
			if f.fake.debuff then f.fake.debuff.dur, f.fake.debuff.expires = 8, now + 5 end
			f:Update()
		end
		preview:Show()
		if header then header:SetAlpha(0) end
	else
		preview:Hide()
		if header then header:SetAlpha(1) end
	end
end

----------------------------------------------------------------------
-- Shape: 5 per column normally; 10 per column in 40-player battlegrounds
-- (Alterac Valley, Isle of Conquest), so 40 players fit in 4 columns instead of 8
----------------------------------------------------------------------
local BIG_ZONES = { ["Alterac Valley"] = true, ["Isle of Conquest"] = true }
local shape

local function IsBigBattleground()
	local _, kind = IsInInstance()
	if kind ~= "pvp" then return false end
	-- zone name (English client), or simply more than 25 players in the raid (any language)
	return BIG_ZONES[GetRealZoneText() or ""] or ((GetNumRaidMembers and GetNumRaidMembers()) or 0) > 25
end

local queued, arenaMode
ApplyShape = function()
	if not header then return end
	-- the game only lets addons change this out of combat: do it right after combat
	if InCombatLockdown() then
		if not queued then
			queued = true
			ns:SafeCall(function() queued = false; ApplyShape() end)
		end
		return
	end
	-- arenas always use the party rows (trinkets, cooldowns, who-targets-whom), even when the
	-- server puts the arena team in a raid group or you come straight from a battleground raid
	local arena = ns:InArena() and true or false
	if arena ~= arenaMode then
		arenaMode = arena
		if arena then
			header:Hide()
			if ns.partyHolder then RegisterStateDriver(ns.partyHolder, "visibility", "show") end
		else
			header:Show()
			if ns.partyHolder then RegisterStateDriver(ns.partyHolder, "visibility", "[group:raid] hide; show") end
		end
	end
	local perColumn = IsBigBattleground() and 10 or 5
	if shape == perColumn then return end
	header:SetAttribute("unitsPerColumn", perColumn)
	header:SetAttribute("maxColumns", perColumn == 10 and 4 or 8)
	shape = perColumn
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local function ForUnit(unit, method)
	local c = byUnit[unit]
	if c and c:IsShown() then c[method](c) end
end

ns:Listen("LOGIN", function()
	if ns.db.raid == false then return end
	holder = CreateFrame("Frame", nil, ns.root)
	-- big enough for both layouts: 8 columns of 5, or (big battlegrounds) 4 columns of 10
	holder:SetSize(8 * CELL_W + 7 * GAP, 10 * CELL_H + 9 * GAP)
	-- under your own row on the left, where the party rows are outside raids
	ns:Mover("raid", "RAID / BATTLEGROUND", holder, "TOPLEFT", "TOPLEFT", 180, -452)
	CreateHeader()
	ApplyShape()
	for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "RAID_ROSTER_UPDATE" }) do
		ns:On(ev, ApplyShape)
	end

	for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
		ns:On(ev, function(_, unit) ForUnit(unit, "Paint") end)
	end
	ns:On("UNIT_AURA", function(_, unit) ForUnit(unit, "Auras") end)
	ns:On("UNIT_NAME_UPDATE", function(_, unit) ForUnit(unit, "Update") end)
	ns:On("UNIT_CONNECTION", function(_, unit) ForUnit(unit, "Paint") end)
	ns:On("RAID_ROSTER_UPDATE", function()
		Rebuild()
		for _, c in pairs(byUnit) do if c:IsShown() then c:Update() end end
	end)
	ns:On("PLAYER_TARGET_CHANGED", function()
		for _, c in pairs(byUnit) do if c:IsShown() then c:State() end end
	end)

	-- range fade (no event for it in 3.3.5)
	local acc = 0
	local ticker = CreateFrame("Frame")
	ticker:SetScript("OnUpdate", function(_, e)
		acc = acc + e
		if acc < 0.5 then return end
		acc = 0
		Rebuild()
		for _, c in pairs(byUnit) do if c:IsShown() then c:State() end end
	end)
end)

ns:Listen("REFRESH_ALL", function()
	for _, c in ipairs(cells) do if c:IsShown() and (c.fake or c.unit) then c:Update() end end
end)

ns:Listen("RAID_TEST", function(on)
	if holder then ShowPreview(on) end
end)
