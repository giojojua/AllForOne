-- AllForOne: missing-buff tracker, right of the action bars
-- Pick buffs in the window (/afo buffs). Each tracked buff shows its icon; when it's
-- missing the icon turns grey with a red edge and a red "!" so you see it before the gates open.
-- Saved per character in AllForOneDB.buffWatch.chars["Name-Realm"]: lower-case name -> { name, icon }
local _, ns = ...
local colors = ns.colors

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local SIZE, GAP, PER_ROW = 46, 4, 4 -- bigger than the action buttons, so a missing buff stands out
-- the gap between the action bars (465px wide, centered) and the menu strip (276px, 24px from
-- the right edge) is about 1192..1620 on a 1920 screen: the tracker is centered in it
-- centered 100px (two icons) left of the middle of that gap; 4 per row keeps a full row
-- clear of the action bars
local AREA_W, AREA_X = 4 * (46 + 4) - 4, 346

----------------------------------------------------------------------
-- Buffs that count as the same thing (single / group version, Dalaran version...)
----------------------------------------------------------------------
local SAME = {
	{ 42995, 43002, 61024, 61316 },  -- Arcane Intellect / Brilliance / Dalaran Intellect / Brilliance
	{ 48161, 48162 },                -- Power Word / Prayer of Fortitude
	{ 48073, 48074 },                -- Divine Spirit / Prayer of Spirit
	{ 48169, 48170 },                -- Shadow Protection / Prayer of
	{ 48469, 48470 },                -- Mark / Gift of the Wild
	{ 20217, 25898 },                -- Blessing of Kings / Greater
	{ 48932, 48934 },                -- Blessing of Might / Greater
	{ 48936, 48938 },                -- Blessing of Wisdom / Greater
	{ 20911, 25899 },                -- Blessing of Sanctuary / Greater
}
local groupOf = {} -- lower-case name -> set of lower-case names that count

-- suggestions in the window: buffs your class puts on itself or the group
local SUGGEST = {
	MAGE = { 43002, 43046, 43024, 43008 },           -- Arcane Brilliance, Molten Armor, Mage Armor, Ice Armor
	PRIEST = { 48162, 48074, 48170, 48168 },         -- Prayer of Fortitude / Spirit / Shadow Protection, Inner Fire
	DRUID = { 48470, 53307 },                        -- Gift of the Wild, Thorns
	PALADIN = { 25898, 48934, 48938, 25899 },        -- Greater Blessings: Kings, Might, Wisdom, Sanctuary
	WARRIOR = { 47436, 47440 },                      -- Battle Shout, Commanding Shout
	WARLOCK = { 47893, 47889 },                      -- Fel Armor, Demon Armor
	SHAMAN = { 57960, 49281, 49284 },                -- Water Shield, Lightning Shield, Earth Shield
	DEATHKNIGHT = { 57623 },                         -- Horn of Winter
	HUNTER = { 61847, 19506 },                       -- Aspect of the Dragonhawk, Trueshot Aura
	ROGUE = {},
}
local suggest = {}

-- weapon enchants (Spellstone, Firestone, poisons, oils, shaman imbues...) are not auras:
-- one special entry per hand
local WEAPON = {
	["#mainhand"] = { slot = 16, label = "Main-hand weapon enchant" },
	["#offhand"] = { slot = 17, label = "Off-hand weapon enchant" },
}
ns.WEAPON_ENCHANT_KEYS = WEAPON

local function BuildSets()
	wipe(groupOf)
	for _, ids in ipairs(SAME) do
		local set = {}
		for _, id in ipairs(ids) do
			local name = GetSpellInfo(id)
			if name then set[strlower(name)] = true end
		end
		for n in pairs(set) do groupOf[n] = set end
	end
	wipe(suggest)
	for class, ids in pairs(SUGGEST) do
		suggest[class] = {}
		for _, id in ipairs(ids) do
			local name, _, icon = GetSpellInfo(id)
			if name then suggest[class][#suggest[class] + 1] = { name = name, icon = icon } end
		end
	end
end

----------------------------------------------------------------------
-- Saved list (per character)
----------------------------------------------------------------------
local function List()
	ns.db.buffWatch = ns.db.buffWatch or {}
	local db = ns.db.buffWatch
	db.chars = db.chars or {}
	local me = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	db.chars[me] = db.chars[me] or {}
	return db.chars[me]
end

local Update, Refresh, AddWeapon -- set below

local function AddBuff(name, icon)
	if not name or name == "" then return end
	List()[strlower(name)] = { name = name, icon = icon }
	if Update then Update() end
	if Refresh then Refresh() end
end

-- a weapon enchant entry: stored under its key, shown with its label
AddWeapon = function(key)
	local w = WEAPON[key]
	if not w then return end
	List()[key] = { name = w.label, key = key, icon = GetInventoryItemTexture("player", w.slot) }
	if Update then Update() end
	if Refresh then Refresh() end
end

local function RemoveBuff(name)
	List()[(name:sub(1, 1) == "#") and name or strlower(name)] = nil
	if Update then Update() end
	if Refresh then Refresh() end
end

-- "Arcane Brilliance" or a spell ID like "43002" -> name, icon
local function Resolve(text)
	text = strtrim(text or "")
	if text == "" then return end
	local id = tonumber(text)
	if id then
		local name, _, icon = GetSpellInfo(id)
		return name, icon
	end
	local _, class = UnitClass("player")
	for _, s in ipairs(suggest[class] or {}) do
		if strlower(s.name) == strlower(text) then return s.name, s.icon end
	end
	for i = 1, 40 do
		local name, _, icon = UnitAura("player", i, "HELPFUL")
		if not name then break end
		if strlower(name) == strlower(text) then return name, icon end
	end
	return text, nil
end

----------------------------------------------------------------------
-- Weapon enchants (Spellstone, Firestone, poisons, oils, shaman imbues...) aren't auras:
-- they're tracked as two special entries, one per hand.
----------------------------------------------------------------------

-- the enchant's name from the weapon tooltip (the green "Spellstone (1 hour)" line)
local scan
local function EnchantName(slot)
	if not scan then
		scan = CreateFrame("GameTooltip", "AllForOneEnchantScan", nil, "GameTooltipTemplate")
		scan:SetOwner(UIParent, "ANCHOR_NONE")
	end
	scan:ClearLines()
	scan:SetOwner(UIParent, "ANCHOR_NONE")
	if not scan:SetInventoryItem("player", slot) then return nil end
	for i = 2, scan:NumLines() do
		local fs = _G["AllForOneEnchantScanTextLeft" .. i]
		local text = fs and fs:GetText()
		if text then
			local name = text:match("^(.-) %(%d+ [^%)]+%)$")
			local r, g, b = fs:GetTextColor()
			if name and g > 0.9 and r < 0.2 then return name end
		end
	end
end

-- your weapon enchants right now: key -> { icon, expires, name }
local function CurrentEnchants()
	local out = {}
	if not GetWeaponEnchantInfo then return out end
	local hasMH, mhMs, _, hasOH, ohMs = GetWeaponEnchantInfo()
	local now = GetTime()
	if hasMH then out["#mainhand"] = { icon = GetInventoryItemTexture("player", 16), expires = mhMs and now + mhMs / 1000, name = EnchantName(16) } end
	if hasOH then out["#offhand"] = { icon = GetInventoryItemTexture("player", 17), expires = ohMs and now + ohMs / 1000, name = EnchantName(17) } end
	return out
end

-- your buffs right now: lower-case name -> { icon, expires }
local function CurrentBuffs()
	local have = {}
	for i = 1, 40 do
		local name, _, icon, _, _, duration, expires = UnitAura("player", i, "HELPFUL")
		if not name then break end
		have[strlower(name)] = { icon = icon, expires = (duration and duration > 0) and expires or nil }
	end
	for key, e in pairs(CurrentEnchants()) do have[key] = e end
	return have
end

-- is this tracked buff (or one that counts the same) on you?
local function Find(have, key)
	if have[key] then return have[key] end
	local set = groupOf[key]
	if set then
		for n in pairs(set) do if have[n] then return have[n] end end
	end
end

----------------------------------------------------------------------
-- The tracker: a grid of icons right of the action bars
----------------------------------------------------------------------
local holder
local icons = {}

local function MakeIcon(i)
	local icon = ns:CreateIcon(holder, SIZE, 16)
	-- missing: red wash + "!"
	icon.wash = icon:CreateTexture(nil, "OVERLAY")
	icon.wash:SetAllPoints(icon.tex)
	icon.wash:SetTexture(colors.danger[1], colors.danger[2], colors.danger[3], 0.35)
	icon.bang = ns:CreateText(icon.overlay or icon, 30, true, "CENTER")
	icon.bang:SetPoint("CENTER", 0, 0)
	icon.bang:SetText("!")
	icon.bang:SetTextColor(1, 0.25, 0.25)
	icon.onExpire = function() if Update then Update() end end -- e.g. a weapon enchant running out
	icon:EnableMouse(true)
	icon:SetScript("OnEnter", function(self)
		if not self.buffName then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.buffName)
		GameTooltip:AddLine(self.missing and "Missing" or "Active", self.missing and 1 or 0.3, self.missing and 0.3 or 0.8, self.missing and 0.3 or 0.4)
		GameTooltip:AddLine("/afo buffs to change the list", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	icons[i] = icon
	return icon
end

local function Show(icon, e, have, now)
	local key = e.key or strlower(e.name)
	local b = Find(have, key)
	icon.buffName = (b and b.name) and (e.name .. ": " .. b.name) or e.name
	if b then
		icon.missing = false
		-- time left only when it's running out (under 5 minutes)
		local exp = b.expires and (b.expires - now < 300) and b.expires or nil
		icon:Set(b.icon or e.icon or QUESTION, nil, nil, exp)
		icon.tex:SetDesaturated(false)
		icon:SetBorder()
		icon.wash:Hide()
		icon.bang:Hide()
	else
		icon.missing = true
		local w = WEAPON[key]
		icon:Set((w and GetInventoryItemTexture("player", w.slot)) or e.icon or QUESTION)
		icon.tex:SetDesaturated(true)
		icon:SetBorder(colors.danger[1], colors.danger[2], colors.danger[3])
		icon.wash:Show()
		icon.bang:Show()
	end
end

Update = function()
	if not holder then return end
	local list = {}
	if ns.testing then
		list = ns.fakeBuffWatch or {}
	else
		for _, e in pairs(List()) do list[#list + 1] = e end
		table.sort(list, function(a, b) return a.name < b.name end)
	end
	local have = ns.testing and (ns.fakeBuffHave or {}) or CurrentBuffs()
	local now = GetTime()
	-- nothing to nag about while dead
	local dead = not ns.testing and UnitIsDeadOrGhost("player")
	-- rows of PER_ROW from the bottom up, each row centered in the area
	local n = #list
	for i, e in ipairs(list) do
		local icon = icons[i] or MakeIcon(i)
		local row, col = floor((i - 1) / PER_ROW), (i - 1) % PER_ROW
		local inRow = math.min(PER_ROW, n - row * PER_ROW)
		local rowW = inRow * (SIZE + GAP) - GAP
		icon:ClearAllPoints()
		icon:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", (AREA_W - rowW) / 2 + col * (SIZE + GAP), row * (SIZE + GAP))
		if dead then icon:Hide() else Show(icon, e, have, now) end
	end
	for i = #list + 1, #icons do icons[i]:Clear() end
end
ns.UpdateBuffWatch = Update
ns.buffWatchIcons = icons

ns:Listen("LOGIN", function()
	BuildSets()
	holder = CreateFrame("Frame", nil, ns.root)
	holder:SetSize(AREA_W, 3 * (SIZE + GAP) - GAP)
	-- centered between the action bars and the menu, bottom row lined up with the bottom bar
	ns:Mover("buffwatch", "BUFF TRACKER", holder, "BOTTOM", "BOTTOM", AREA_X, 30)
	Update()
end)
ns:On("UNIT_AURA", function(_, unit) if unit == "player" then Update() end end)
ns:On("UNIT_INVENTORY_CHANGED", function(_, unit) if unit == "player" then Update(); if Refresh then Refresh() end end end)
ns:On("PLAYER_ENTERING_WORLD", function() Update() end)
ns:On("PLAYER_DEAD", function() Update() end)
ns:On("PLAYER_UNGHOST", function() Update() end)
ns:On("PLAYER_ALIVE", function() Update() end)

----------------------------------------------------------------------
-- Window (/afo buffs): same layout as the proc window
----------------------------------------------------------------------
local panel
local W, ROW_H, PAD = 380, 28, 16

local function Button(parent, label, w, h, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	ns:Skin(b)
	b.text = ns:CreateText(b, 13, true, "CENTER")
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function() b.text:SetTextColor(colors.kick[1], colors.kick[2], colors.kick[3]) end)
	b:SetScript("OnLeave", function() b.text:SetTextColor(1, 1, 1) end)
	return b
end

local function Row(parent)
	local r = CreateFrame("Frame", nil, parent)
	r:SetSize(W - 2 * PAD, ROW_H - 4)
	r.icon = ns:CreateIcon(r, ROW_H - 6)
	r.icon:SetPoint("LEFT", 0, 0)
	r.icon:Show()
	r.name = ns:CreateText(r, 14, true, "LEFT")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
	r.name:SetPoint("RIGHT", -34, 0)
	r.action = Button(r, "+", 24, 22)
	r.action:SetPoint("RIGHT", 0, 0)
	return r
end

local function Header(parent, text)
	local h = ns:CreateText(parent, 12, true, "LEFT")
	h:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	h:SetText(text)
	return h
end

local pools = { tracked = {}, suggest = {}, weapons = {}, buffs = {} }

local function Fill(pool, entries, y, actionLabel, onAction, emptyText)
	for i, e in ipairs(entries) do
		local r = pool[i]
		if not r then
			r = Row(panel)
			pool[i] = r
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
		r.icon:Set(e.icon or QUESTION)
		r.name:SetText(e.name)
		r.action.text:SetText(actionLabel)
		r.action:SetScript("OnClick", function() onAction(e) end)
		r:Show()
		y = y + ROW_H
	end
	for i = #entries + 1, #pool do pool[i]:Hide() end
	if #entries == 0 and emptyText then
		pool.empty = pool.empty or ns:CreateText(panel, 13, false, "LEFT")
		pool.empty:ClearAllPoints()
		pool.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y - 4)
		pool.empty:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
		pool.empty:SetText(emptyText)
		pool.empty:Show()
		y = y + ROW_H
	elseif pool.empty then
		pool.empty:Hide()
	end
	return y
end

Refresh = function()
	if not panel or not panel:IsShown() then return end
	local list = List()

	local tracked = {}
	for _, e in pairs(list) do tracked[#tracked + 1] = e end
	table.sort(tracked, function(a, b) return a.name < b.name end)

	local _, class = UnitClass("player")
	local sug = {}
	for _, s in ipairs(suggest[class] or {}) do
		if not list[strlower(s.name)] then sug[#sug + 1] = s end
	end

	-- buffs on you right now that you don't track yet (long ones first: those are the ones you rebuff)
	local buffs, seen = {}, {}
	for i = 1, 40 do
		local name, _, icon, _, _, duration = UnitAura("player", i, "HELPFUL")
		if not name then break end
		if not list[strlower(name)] and not seen[name] then
			seen[name] = true
			buffs[#buffs + 1] = { name = name, icon = icon, d = (duration and duration > 0) and duration or 1e9 }
		end
	end
	table.sort(buffs, function(a, b) return a.d > b.d end)
	while #buffs > 10 do table.remove(buffs) end

	local y = 96
	panel.hTracked:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.tracked, tracked, y, "×", function(e) RemoveBuff(e.key or e.name) end,
		"Nothing yet. Add a buff below or type its name above.") + 10
	panel.hSuggest:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.suggest, sug, y, "+", function(e) AddBuff(e.name, e.icon) end,
		"No more suggestions for your class.") + 10
	-- weapon enchants (Spellstone, Firestone, poisons, oils...): one entry per hand
	local weapons = {}
	local cur = CurrentEnchants()
	for key, w in pairs(WEAPON) do
		if not list[key] and GetInventoryItemLink("player", w.slot) then
			local c = cur[key]
			weapons[#weapons + 1] = { key = key, name = w.label .. ((c and c.name) and (" (now: " .. c.name .. ")") or ""),
				icon = GetInventoryItemTexture("player", w.slot) }
		end
	end
	table.sort(weapons, function(a, b) return a.key > b.key end) -- main hand first
	panel.hWeapons:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.weapons, weapons, y, "+", function(e) AddWeapon(e.key) end,
		"Both hands tracked (or no weapon equipped).") + 10
	panel.hBuffs:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.buffs, buffs, y, "+", function(e) AddBuff(e.name, e.icon) end,
		"No other buffs on you right now.") + PAD
	panel:SetHeight(y)
end

local function CreatePanel()
	panel = CreateFrame("Frame", "AllForOneBuffWindow", UIParent)
	panel:SetSize(W, 400)
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	panel:SetFrameStrata("DIALOG")
	panel:SetScale(ns.root:GetEffectiveScale() / UIParent:GetEffectiveScale())
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	ns:Skin(panel)
	panel.fill:SetTexture(0.04, 0.045, 0.05, 0.96)
	tinsert(UISpecialFrames, "AllForOneBuffWindow") -- Esc closes it

	local title = ns:CreateText(panel, 18, true, "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("BUFF TRACKER")
	local sub = ns:CreateText(panel, 12, false, "LEFT")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	sub:SetText("This character's buffs · red icon right of your bars when one is missing")
	local close = Button(panel, "×", 24, 24, function() panel:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 4)

	local box = CreateFrame("EditBox", nil, panel)
	box:SetSize(W - 2 * PAD - 70, 26)
	box:SetPoint("TOPLEFT", PAD, -60)
	box:SetAutoFocus(false)
	box:SetTextInsets(8, 8, 0, 0)
	ns:Skin(box)
	ns:Font(box, 14, false)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local function Submit()
		local name, icon = Resolve(box:GetText())
		if name then AddBuff(name, icon) end
		box:SetText("")
		box:ClearFocus()
	end
	box:SetScript("OnEnterPressed", Submit)
	local hint = ns:CreateText(box, 13, false, "LEFT")
	hint:SetPoint("LEFT", 8, 0)
	hint:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	hint:SetText("Buff name or spell ID")
	box:SetScript("OnTextChanged", function(self) if self:GetText() == "" then hint:Show() else hint:Hide() end end)
	box:SetScript("OnEditFocusGained", function() hint:Hide() end)
	box:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then hint:Show() end end)
	local add = Button(panel, "ADD", 60, 26, Submit)
	add:SetPoint("LEFT", box, "RIGHT", 10, 0)

	panel.hTracked = Header(panel, "TRACKED")
	panel.hSuggest = Header(panel, "SUGGESTED FOR YOUR CLASS")
	panel.hBuffs = Header(panel, "YOUR BUFFS RIGHT NOW")
	panel.hWeapons = Header(panel, "WEAPON ENCHANTS (SPELLSTONE, POISONS, OILS...)")

	panel:SetScript("OnShow", Refresh)
	panel:RegisterEvent("UNIT_AURA")
	panel:SetScript("OnEvent", function(_, _, unit) if unit == "player" then Refresh() end end)
	panel:Hide()
end

function ns:ToggleBuffWindow()
	if not panel then CreatePanel() end
	if panel:IsShown() then panel:Hide() else panel:Show(); Refresh() end
end

-- /afo buffs [add|remove|reset ...]  (no arguments opens the window)
function ns:BuffCommand(arg)
	local action, rest = strsplit(" ", strtrim(arg or ""), 2)
	action = strlower(action or "")
	if action == "add" and rest and rest ~= "" then
		local name, icon = Resolve(rest)
		if not name then ns:Print("no spell with that ID") return end
		AddBuff(name, icon)
		ns:Print("now tracking buff:", name)
	elseif (action == "remove" or action == "del") and rest and rest ~= "" then
		local name = Resolve(rest)
		if name then RemoveBuff(name); ns:Print("stopped tracking buff:", name) end
	elseif action == "reset" then
		wipe(List())
		Update()
		if Refresh then Refresh() end
		ns:Print("buff list of this character cleared")
	else
		ns:ToggleBuffWindow()
	end
end
