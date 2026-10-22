-- AllForOne: nameplates for 3.3.5
-- 3.3.5 has no nameplate API: plates are unnamed children of WorldFrame.
-- We hide Blizzard's art and draw our own bar on top, reading values from theirs.
local _, ns = ...
local colors = ns.colors
local GetTime = GetTime

local plates = {}
ns.plates = plates
local childCount = 0
local npcIcons = {} -- npc name -> creature-type icon (learned from target/mouseover/focus)

local function IsPlate(f)
	if f:GetName() then return false end
	local _, border = f:GetRegions()
	return border and border.GetObjectType and border:GetObjectType() == "Texture"
		and border:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

-- What is this plate? Blizzard colors the health bar by reaction / class.
local function Classify(r, g, b)
	if r > 0.9 and g < 0.2 and b < 0.2 then return "hostile" end
	if r > 0.9 and g > 0.9 and b < 0.2 then return "neutral" end
	if g > 0.9 and r < 0.2 and b < 0.2 then return "friendlyNPC" end
	if b > 0.9 and r < 0.2 and g < 0.2 then return "friendlyPlayer" end
	for class, c in pairs(RAID_CLASS_COLORS) do
		if math.abs(c.r - r) < 0.03 and math.abs(c.g - g) < 0.03 and math.abs(c.b - b) < 0.03 then
			return "enemyPlayer", class
		end
	end
	return "hostile"
end

local function ArenaNumber(name)
	if not name then return nil end
	for i = 1, 5 do
		if UnitName("arena" .. i) == name then return i end
	end
end

----------------------------------------------------------------------
-- Build our overlay for one plate
----------------------------------------------------------------------
local function Setup(plate)
	local health, cast = plate:GetChildren()
	local threat, hpBorder, castBorder, castShield, spellIcon, highlight, nameText, levelText, bossIcon, raidIcon, eliteIcon = plate:GetRegions()

	-- hide Blizzard's visuals, keep the objects so we can read them
	threat:SetTexture(nil)
	hpBorder:SetTexture(nil)
	castBorder:SetTexture(nil)
	castShield:SetTexture(nil)
	highlight:SetTexture(nil)
	bossIcon:SetTexture(nil)
	eliteIcon:SetTexture(nil)
	spellIcon:SetAlpha(0)
	-- the game keeps resetting these, so park them on a hidden frame instead of fading them
	-- (we still read the name with GetText)
	for _, region in ipairs({ nameText, levelText, bossIcon, eliteIcon }) do
		if not pcall(region.SetParent, region, ns.hider) then region:SetAlpha(0) end
		region:Hide()
	end
	health:SetAlpha(0)
	cast:SetAlpha(0)

	local d = { health = health, cast = cast, shield = castShield, nameText = nameText, raidIcon = raidIcon }
	local f = CreateFrame("Frame", nil, plate)
	f:SetSize(150, 60)
	f:SetPoint("CENTER", health, "CENTER", 0, 0)
	f:SetScale(ns.root:GetEffectiveScale() / plate:GetEffectiveScale())
	d.frame = f

	d.hp = ns:CreateBar(f, 128, 12)
	d.hp:SetPoint("CENTER", f, "CENTER", 0, 0)
	-- health on enemy plates: "31.2k · 74%" inside the bar
	d.hpText = ns:CreateText(d.hp, 10, true, "RIGHT")
	d.hpText:SetPoint("RIGHT", d.hp, "RIGHT", -3, 0)
	-- kill target helper mark (red cross / blue square), left of the health text
	d.mark = d.hp:CreateTexture(nil, "OVERLAY")
	d.mark:SetSize(16, 16)
	d.mark:SetPoint("RIGHT", d.hpText, "LEFT", -2, 0)
	d.mark:Hide()

	d.name = ns:CreateText(f, 13, true, "LEFT")
	d.name:SetPoint("BOTTOMLEFT", d.hp, "TOPLEFT", 0, 3)
	d.num = ns:CreateText(f, 13, true, "RIGHT")
	d.num:SetPoint("BOTTOMRIGHT", d.hp, "TOPRIGHT", 0, 3)
	d.name:SetPoint("RIGHT", d.num, "LEFT", -4, 0)

	d.castbar = ns:CreateBar(f, 128, 6)
	d.castbar:SetPoint("TOPLEFT", d.hp, "BOTTOMLEFT", 0, -3)
	d.castbar:SetPoint("TOPRIGHT", d.hp, "BOTTOMRIGHT", 0, -3)
	d.castbar:Hide()

	d.pips = {}
	for i = 1, 5 do
		local pip = CreateFrame("Frame", nil, f)
		pip:SetSize(14, 6)
		ns:Skin(pip, true)
		pip.fill = pip:CreateTexture(nil, "ARTWORK")
		pip.fill:SetAllPoints(pip)
		pip:Hide()
		d.pips[i] = pip
	end

	-- auras: one big crowd-control icon, then a row of your debuffs
	d.big = ns:CreateIcon(f, 36, 14)
	d.mine = {}
	for i = 1, 5 do d.mine[i] = ns:CreateIcon(f, 22, 11) end

	-- class icon: always on the left of the health bar (bigger on your target)
	d.classIcon = ns:CreateIcon(f, 20)
	d.classIcon.tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
	d.classIcon:SetPoint("RIGHT", d.hp, "LEFT", -5, 0)

	-- raid markers (skull, X...) go on the right so they never cover the class icon
	raidIcon:ClearAllPoints()
	raidIcon:SetPoint("LEFT", d.hp, "RIGHT", 4, 0)
	raidIcon:SetSize(16, 16)

	health:HookScript("OnValueChanged", function() if d.update then d.update() end end)
	plates[plate] = d
	return d
end

----------------------------------------------------------------------
-- Update one plate
----------------------------------------------------------------------
-- Read debuffs directly from a unit (exact icons and timers): your debuffs, and the
-- highest-priority crowd control from anyone.
local function ScanUnit(unit)
	local best, bestPrio, mine = nil, -1, {}
	for i = 1, 40 do
		local name, _, icon, count, dispel, duration, expires, caster = UnitAura(unit, i, "HARMFUL")
		if not name then break end
		local a = { icon = icon, dur = duration, expires = (expires and expires > 0) and expires or nil, dispel = dispel }
		a.noTimer = not a.expires
		local cc = ns.CC[name]
		if cc then
			local p = ns.ccPriority[cc.cat] or 0
			if p > bestPrio then best, bestPrio = a, p end
		end
		if caster == "player" or caster == "pet" then mine[#mine + 1] = a end
	end
	table.sort(mine, function(x, y) return (x.expires or 1e9) < (y.expires or 1e9) end)
	return best, mine
end

-- Which unit token (if any) currently points at this plate's player
local function PlateUnit(name, isTarget, arena)
	if isTarget then return "target" end
	if arena then return "arena" .. arena end
	for _, u in ipairs({ "focus", "mouseover", "party1", "party2", "party3", "party4" }) do
		if UnitExists(u) and UnitName(u) == name then return u end
	end
end

local function LayoutAuras(d, anchorTop, friendly, guid, unit)
	local best, mine
	if unit then
		best, mine = ScanUnit(unit)
	else
		best, mine = ns:GetAuras(guid)
	end
	if friendly then
		mine = {}
		if best and not best.dispel then best = nil end
	end
	-- mine row sits right above the name; big icon above that
	local y = 3
	for i, icon in ipairs(d.mine) do
		local a = mine[i]
		if a then
			icon:ClearAllPoints()
			icon:SetPoint("BOTTOMLEFT", anchorTop, "TOPLEFT", (i - 1) * 25, y)
			icon:Set(a.icon, nil, a.dur, (not a.noTimer) and a.expires or nil)
		else
			icon:Clear()
		end
	end
	if #mine > 0 then y = y + 22 + 5 end
	if best then
		d.big:ClearAllPoints()
		d.big:SetPoint("BOTTOM", anchorTop, "TOP", 0, y)
		d.big:Set(best.icon, nil, best.dur, (not best.noTimer) and best.expires or nil)
		local c = friendly and (colors.dispel[best.dispel] or colors.dispel.Magic) or colors.danger
		d.big:SetBorder(c[1], c[2], c[3])
	else
		d.big:Clear()
	end
end

-- Totems: half-size plate with the totem's own icon (Tremor, Grounding, Earthbind...)
local function TotemIcon(name)
	if not name or not ns.Totems then return nil end
	return ns.Totems[name] or ns.Totems[(name:gsub("%s+[IVX]+$", ""))]
end

local function ShortHP(n)
	if n >= 1e6 then return format("%.1fm", n / 1e6) end
	if n >= 1e3 then return format("%.1fk", n / 1e3) end
	return tostring(floor(n))
end

local function UpdateTotem(d, icon, friendly, r, g, b)
	d.isTotem = true
	d.hp:SetSize(64, 5)
	if friendly then
		d.hp:SetStatusBarColor(colors.friendly[1], colors.friendly[2], colors.friendly[3])
	else
		d.hp:SetStatusBarColor(r, g, b)
	end
	ns:SetHighlight(d.hp, false)
	local min, max = d.health:GetMinMaxValues()
	d.hp:SetMinMaxValues(min, max)
	d.hp:SetValue(d.health:GetValue())
	-- the icon is the important part: big and centered above the small bar
	d.classIcon:SetSize(22, 22)
	d.classIcon:ClearAllPoints()
	d.classIcon:SetPoint("BOTTOM", d.hp, "TOP", 0, 3)
	d.classIcon.tex:SetTexture(icon)
	d.classIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local c = friendly and colors.friendly or colors.danger
	d.classIcon:SetBorder(c[1], c[2], c[3])
	d.classIcon:Show()
	d.name:SetText("")
	d.num:SetText("")
	d.hpText:SetText("")
	d.mark:Hide()
	d.castbar:Hide()
	for _, pip in ipairs(d.pips) do pip:Hide() end
	for _, icon in ipairs(d.mine) do icon:Clear() end
	d.big:Clear()
end

local function UpdatePlate(plate, d)
	local r, g, b = d.health:GetStatusBarColor()
	local kind, class = Classify(r, g, b)
	local name = d.nameText:GetText()
	local friendly = (kind == "friendlyPlayer" or kind == "friendlyNPC")

	local totem = TotemIcon(name)
	if totem then return UpdateTotem(d, totem, friendly, r, g, b) end
	if d.isTotem then
		-- plate frames get reused: put the normal layout back
		d.isTotem = nil
		d.classIcon:ClearAllPoints()
		d.classIcon:SetPoint("RIGHT", d.hp, "LEFT", -5, 0)
		d.classIcon:SetBorder()
	end
	local isTarget = UnitExists("target") and plate:GetAlpha() == 1 and name == UnitName("target")
	local arena = (not friendly) and ArenaNumber(name)
	local unit = name and PlateUnit(name, isTarget, arena)

	-- Class: ask the game directly whenever we can, the bar color is only a fallback
	-- (it only carries class when the class-color nameplate setting is active).
	if not friendly then
		local unit = isTarget and "target" or (arena and ("arena" .. arena)) or nil
		if unit and UnitIsPlayer(unit) then
			local _, c = UnitClass(unit)
			if c then kind, class = "enemyPlayer", c end
		elseif not class and name and ns.nameToGUID[name] and GetPlayerInfoByGUID then
			local _, c = GetPlayerInfoByGUID(ns.nameToGUID[name])
			if c then kind, class = "enemyPlayer", c end
		end
	end

	-- size + color
	-- same size for friends and enemies (bigger when targeted); friends are always green
	local w, h = 128, 12
	if isTarget then w, h = 150, 14 end
	d.hp:SetSize(w, h)
	if friendly then
		d.hp:SetStatusBarColor(colors.friendly[1], colors.friendly[2], colors.friendly[3])
	elseif kind == "enemyPlayer" then
		d.hp:SetStatusBarColor(ns:ClassColor(class))
	else
		d.hp:SetStatusBarColor(r, g, b)
	end
	ns:SetHighlight(d.hp, isTarget)

	-- icon on the left for everyone: class icon for players, creature-type icon for NPCs
	local size = isTarget and 24 or 20
	d.classIcon:SetSize(size, size)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if not coords and unit and UnitIsPlayer(unit) then
		local _, c = UnitClass(unit)
		coords = c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c]
	end
	if coords then
		d.classIcon.tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
		d.classIcon.tex:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
	else
		-- NPCs: learn the creature type when you target/mouse over one, then reuse it by name
		if unit and not UnitIsPlayer(unit) and name then npcIcons[name] = ns:CreatureIcon(unit) end
		d.classIcon.tex:SetTexture((name and npcIcons[name]) or ns.creatureFallback)
		d.classIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	d.classIcon:Show()
	local min, max = d.health:GetMinMaxValues()
	d.hp:SetMinMaxValues(min, max)
	d.hp:SetValue(d.health:GetValue())

	-- text: name above, health inside the bar (friends too; the arena number and kill marks are enemy-only)
	do
		d.name:SetText(name or "")
		local cur = d.health:GetValue() or 0
		local pct = (max and max > 0) and floor(cur / max * 100 + 0.5) or 0
		-- some servers only send percentages (max 100): then just show the %
		if max and max > 100 then
			d.hpText:SetText(ShortHP(cur) .. " · " .. pct .. "%")
		else
			d.hpText:SetText(pct .. "%")
		end
		if d.wasTargetFont ~= isTarget then
			d.wasTargetFont = isTarget
			ns:Font(d.hpText, isTarget and 11 or 10, true)
		end
		-- kill target helper: red cross (KILL) / blue square (CC) next to the arena number
		local icon = (not friendly) and ((name and name == ns.killName and ns.KILL_ICON) or (name and name == ns.ccName and ns.CC_ICON)) or nil
		-- the mark sits just left of the health % inside the bar
		if icon then
			d.mark:SetTexture(icon)
			d.mark:Show()
		else
			d.mark:Hide()
		end
		d.num:SetText((not friendly and arena) and tostring(arena) or "")
		if d.wasTarget ~= isTarget then
			d.wasTarget = isTarget
			ns:Font(d.name, isTarget and 14 or 13, true)
		end
	end

	-- cast bar (Blizzard shows nameplate casts for your target)
	if d.cast:IsShown() then
		local cmin, cmax = d.cast:GetMinMaxValues()
		d.castbar:SetMinMaxValues(cmin, cmax)
		d.castbar:SetValue(d.cast:GetValue())
		local c = d.shield:IsShown() and colors.locked or colors.kick
		d.castbar:SetStatusBarColor(c[1], c[2], c[3])
		d.castbar:Show()
	else
		d.castbar:Hide()
	end

	-- combo points under your target's plate: 5 red segments as wide as the health bar
	local points = isTarget and GetComboPoints("player", "target") or 0
	local gap = 2
	local pipW = (w - 4 * gap) / 5
	d.castbar:ClearAllPoints()
	if points > 0 then
		d.castbar:SetPoint("TOPLEFT", d.hp, "BOTTOMLEFT", 0, -(2 + 5 + 3))
		d.castbar:SetPoint("TOPRIGHT", d.hp, "BOTTOMRIGHT", 0, -(2 + 5 + 3))
	else
		d.castbar:SetPoint("TOPLEFT", d.hp, "BOTTOMLEFT", 0, -3)
		d.castbar:SetPoint("TOPRIGHT", d.hp, "BOTTOMRIGHT", 0, -3)
	end
	for i, pip in ipairs(d.pips) do
		if points > 0 then
			pip:SetSize(pipW, 5)
			pip:ClearAllPoints()
			pip:SetPoint("TOPLEFT", d.hp, "BOTTOMLEFT", (i - 1) * (pipW + gap), -2)
			if i <= points then
				pip.fill:SetTexture(colors.combo[1], colors.combo[2], colors.combo[3], 1)
			else
				pip.fill:SetTexture(0.14, 0.15, 0.16, 1)
			end
			pip:Show()
		else
			pip:Hide()
		end
	end

	-- auras: exact from the game when the player is your target/focus/mouseover/arena unit,
	-- otherwise from the combat-log tracker (matched by name)
	local guid = unit and UnitGUID(unit) or (name and ns.nameToGUID[name])
	local anchorTop = d.name
	LayoutAuras(d, anchorTop, friendly, guid, unit)
end

----------------------------------------------------------------------
-- Scanner
----------------------------------------------------------------------
local scanner = CreateFrame("Frame")
local acc = 0
scanner:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.1 then return end
	acc = 0
	local n = WorldFrame:GetNumChildren()
	if n ~= childCount then
		childCount = n
		local children = { WorldFrame:GetChildren() }
		for _, child in ipairs(children) do
			if not plates[child] and IsPlate(child) then
				local d = Setup(child)
				d.update = function() if child:IsShown() then UpdatePlate(child, d) end end
			end
		end
	end
	for plate, d in pairs(plates) do
		if plate:IsShown() then UpdatePlate(plate, d) end
	end
end)
scanner:Hide()

ns:Listen("LOGIN", function()
	if not ns.db.nameplates then return end
	SetCVar("ShowClassColorInNameplate", "1")
	-- enemy totems get (small) plates too
	pcall(SetCVar, "nameplateShowEnemyTotems", "1")
	scanner:Show()
end)
