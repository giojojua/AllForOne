-- AllForOne: your class resources, in a strip right above your own frame
--   Death Knight: 6 runes (colored by type, refill as they recharge)
--   Shaman: your 4 totems with timers (right-click one to destroy it)
--   Druid: mana while in cat / bear form
--   Warlock: soul shard count
local _, ns = ...
local colors = ns.colors
local GetTime = GetTime

local W = 248 -- same width as class icon + health bar on the rows below
local holder
local mode    -- "runes" | "totems" | "druid" | "shards" | nil

----------------------------------------------------------------------
-- Death Knight runes
----------------------------------------------------------------------
local RUNE_ORDER = { 1, 2, 5, 6, 3, 4 } -- blood, frost, unholy (like the default UI)
local RUNE_COLORS = {
	[1] = { 0.90, 0.22, 0.24 }, -- blood
	[2] = { 0.35, 0.80, 0.30 }, -- unholy
	[3] = { 0.30, 0.65, 1.00 }, -- frost
	[4] = { 0.70, 0.40, 0.95 }, -- death
}
local runes = {}

local function BuildRunes()
	local gap = 4
	local rw = (W - 5 * gap) / 6
	for i = 1, 6 do
		local bar = ns:CreateBar(holder, rw, 10)
		bar:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", (i - 1) * (rw + gap), 0)
		bar.text = ns:CreateText(bar, 10, true, "CENTER")
		bar.text:SetPoint("CENTER", 0, 0)
		bar:Hide()
		runes[i] = bar
	end
end

local function RuneState(slot)
	if ns.testing and ns.fakeRunes then
		local now = GetTime()
		local types = { 1, 1, 3, 4, 2, 2 }
		local fake = { [2] = { now - 4, 10 }, [6] = { now - 7, 10 } }
		local s = fake[slot]
		if s then return s[1], s[2], false, types[slot] end
		return 0, 10, true, types[slot]
	end
	local start, duration, ready = GetRuneCooldown(slot)
	return start, duration, ready, GetRuneType(slot)
end

local function UpdateRunes()
	local busy = false
	local now = GetTime()
	for i, bar in ipairs(runes) do
		local slot = RUNE_ORDER[i]
		local start, duration, ready, rtype = RuneState(slot)
		local c = RUNE_COLORS[rtype or 1] or RUNE_COLORS[1]
		if ready or not start or not duration or duration == 0 then
			bar:SetValue(1)
			bar:SetStatusBarColor(c[1], c[2], c[3])
			bar.text:SetText("")
		else
			local left = start + duration - now
			bar:SetValue(math.max(0, math.min(1, 1 - left / duration)))
			bar:SetStatusBarColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
			bar.text:SetText(left > 0 and floor(left + 0.99) or "")
			busy = true
		end
		bar:Show()
	end
	return busy
end

----------------------------------------------------------------------
-- Shaman totems
----------------------------------------------------------------------
local TOTEM_ORDER = { 2, 1, 3, 4 } -- earth, fire, water, air
local totems = {}

local function BuildTotems()
	for i = 1, 4 do
		local b = CreateFrame("Button", nil, holder)
		b:SetSize(24, 24)
		b:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", (i - 1) * 28, 0)
		b.icon = ns:CreateIcon(b, 24, 11)
		b.icon:SetAllPoints(b)
		b.slot = TOTEM_ORDER[i]
		b:RegisterForClicks("RightButtonUp")
		b:SetScript("OnClick", function(self)
			if DestroyTotem and not ns.testing then DestroyTotem(self.slot) end
		end)
		b:SetScript("OnEnter", function(self)
			if ns.testing or not GameTooltip.SetTotem then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetTotem(self.slot)
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:Hide()
		totems[i] = b
	end
end

local function TotemState(slot)
	if ns.testing and ns.fakeRunes then
		local now = GetTime()
		local fake = {
			[2] = { 8143, now - 30, 300 },  -- Tremor
			[1] = { 3599, now - 20, 60 },   -- Searing
			[3] = { 5675, now - 50, 300 },  -- Mana Spring
			[4] = { 8177, now - 10, 45 },   -- Grounding
		}
		local f = fake[slot]
		local name, _, icon = GetSpellInfo(f[1])
		return true, name, f[2], f[3], icon
	end
	return GetTotemInfo(slot)
end

local function UpdateTotems()
	for _, b in ipairs(totems) do
		local have, name, start, duration, icon = TotemState(b.slot)
		if have and name and name ~= "" and duration and duration > 0 then
			b.icon:Set(icon, nil, duration, start + duration, true)
			b:Show()
		else
			b.icon:Clear()
			b:Hide()
		end
	end
end

----------------------------------------------------------------------
-- Druid: mana while shapeshifted
----------------------------------------------------------------------
local manaBar

local function BuildDruid()
	manaBar = ns:CreateBar(holder, W, 8)
	manaBar:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
	local c = colors.power[0]
	manaBar:SetStatusBarColor(c[1], c[2], c[3])
	manaBar.text = ns:CreateText(manaBar, 10, true, "RIGHT")
	manaBar.text:SetPoint("BOTTOMRIGHT", manaBar, "TOPRIGHT", 0, 2)
	manaBar:Hide()
end

local function UpdateDruid()
	local shifted = ns.testing and ns.fakeRunes or UnitPowerType("player") ~= 0
	if not shifted then manaBar:Hide() return end
	local cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
	if ns.testing and ns.fakeRunes then cur, max = 63, 100 end
	if not max or max == 0 then manaBar:Hide() return end
	manaBar:SetMinMaxValues(0, max)
	manaBar:SetValue(cur)
	manaBar.text:SetText("MANA " .. floor(cur / max * 100 + 0.5) .. "%")
	manaBar:Show()
end

----------------------------------------------------------------------
-- Warlock: soul shards
----------------------------------------------------------------------
local shard
local SHARD_ITEM = 6265

local function BuildShards()
	shard = ns:CreateIcon(holder, 24, 11)
	shard:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
end

local function UpdateShards()
	local n = (ns.testing and ns.fakeRunes) and 12 or (GetItemCount(SHARD_ITEM) or 0)
	shard:Set(GetItemIcon and GetItemIcon(SHARD_ITEM) or "Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
	shard.count:SetText(n)
	shard:SetAlpha(n > 0 and 1 or 0.4)
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local function Update()
	if mode == "runes" then return UpdateRunes()
	elseif mode == "totems" then UpdateTotems()
	elseif mode == "druid" then UpdateDruid()
	elseif mode == "shards" then UpdateShards() end
end

-- runes refill smoothly; everything else only needs events (+ a slow safety tick)
local acc, fast = 0, false
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < (fast and 0.05 or 0.5) then return end
	acc = 0
	local busy = Update()
	fast = busy and true or false
end)
ticker:Hide()

local function Refresh()
	fast = true
	if mode then Update() end
end

ns:Listen("LOGIN", function()
	local _, class = UnitClass("player")
	if class == "DEATHKNIGHT" then mode = "runes"
	elseif class == "SHAMAN" then mode = "totems"
	elseif class == "DRUID" then mode = "druid"
	elseif class == "WARLOCK" then mode = "shards" end

	holder = CreateFrame("Frame", nil, ns.root)
	holder:SetSize(W, 24)
	-- right above your own row on the left (your class icon + health bar)
	ns:Mover("resources", "CLASS RESOURCES", holder, "TOPLEFT", "TOPLEFT", 180, -288)

	if mode == "runes" then
		BuildRunes()
		-- the default UI's rune frame sits on the hidden player frame, but make sure
		if RuneFrame then ns:Kill(RuneFrame) end
	elseif mode == "totems" then
		BuildTotems()
		if TotemFrame then ns:Kill(TotemFrame) end
	elseif mode == "druid" then
		BuildDruid()
	elseif mode == "shards" then
		BuildShards()
	end
	if mode then
		ticker:Show()
		Update()
	end
end)

for _, ev in ipairs({ "RUNE_POWER_UPDATE", "RUNE_TYPE_UPDATE", "PLAYER_TOTEM_UPDATE", "UPDATE_SHAPESHIFT_FORM",
	"UNIT_DISPLAYPOWER", "UNIT_MANA", "BAG_UPDATE", "PLAYER_ENTERING_WORLD" }) do
	ns:On(ev, function(_, unit)
		if ev:match("^UNIT_") and unit ~= "player" then return end
		if holder then Refresh() end
	end)
end

ns:Listen("RESOURCES_TEST", function()
	if holder then Refresh() end
end)
