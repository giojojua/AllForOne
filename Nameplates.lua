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

-- player name -> class token, from everything that tells us a class by name:
-- anyone you target, mouse over or focus, your party / raid, guild, friends list,
-- the battleground scoreboard, and players seen in the combat log.
local classByName = {}
ns.classByName = classByName
local function Learn(unit)
	if unit and UnitExists(unit) and UnitIsPlayer(unit) then
		local name = UnitName(unit)
		local _, c = UnitClass(unit)
		if name and c then classByName[name] = c end
	end
end
local function LearnGroup()
	for i = 1, 4 do Learn("party" .. i) end
	for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do Learn("raid" .. i) end
end
local LOCAL_TO_TOKEN
local function Token(localized)
	if not localized then return nil end
	if not LOCAL_TO_TOKEN then
		LOCAL_TO_TOKEN = {}
		for token, l in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do LOCAL_TO_TOKEN[l] = token end
		for token, l in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do LOCAL_TO_TOKEN[l] = token end
	end
	return LOCAL_TO_TOKEN[localized]
end
local function LearnGuild()
	if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return end
	for i = 1, GetNumGuildMembers(true) do
		local name, _, _, _, class, _, _, _, _, _, token = GetGuildRosterInfo(i)
		token = token or Token(class)
		if name and token then classByName[name] = token end
	end
end
local function LearnFriends()
	if not (GetNumFriends and GetFriendInfo) then return end
	for i = 1, GetNumFriends() do
		local name, _, class = GetFriendInfo(i)
		local token = Token(class)
		if name and token then classByName[name] = token end
	end
end
local function LearnScoreboard()
	if not (GetNumBattlefieldScores and GetBattlefieldScore) then return end
	for i = 1, GetNumBattlefieldScores() do
		local name, _, _, _, _, _, _, _, _, token = GetBattlefieldScore(i)
		if name and token then classByName[(name:match("^[^%-]+")) or name] = token end
	end
end
ns:On("UPDATE_MOUSEOVER_UNIT", function() Learn("mouseover") end)
ns:On("PLAYER_TARGET_CHANGED", function() Learn("target") end)
ns:On("PLAYER_FOCUS_CHANGED", function() Learn("focus") end)
ns:On("PARTY_MEMBERS_CHANGED", LearnGroup)
ns:On("RAID_ROSTER_UPDATE", LearnGroup)
ns:On("GUILD_ROSTER_UPDATE", LearnGuild)
ns:On("FRIENDLIST_UPDATE", LearnFriends)
ns:On("UPDATE_BATTLEFIELD_SCORE", LearnScoreboard)
ns:Listen("LOGIN", function()
	LearnGroup()
	if GuildRoster then GuildRoster() end -- asks the server; GUILD_ROSTER_UPDATE follows
	if ShowFriends then ShowFriends() end
end)

local function IsPlate(f)
	if f:GetName() then return false end
	local _, border = f:GetRegions()
	return border and border.GetObjectType and border:GetObjectType() == "Texture"
		and border:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

-- What is this plate? Blizzard colors the health bar by reaction / class.
-- plate size: bigger, modern-looking bars (your target a bit bigger still)
local PLATE_W, PLATE_H = 160, 16
local PLATE_W_TARGET, PLATE_H_TARGET = 180, 19
local logCasts -- set below (combat-log casts by name)
local CAST_H, CAST_H_TARGET = 6, 7 -- the cast strip always sits under the health bar

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

-- pets on your side (yours, your party's and raid's): blue plates, so they never look like enemies
local friendlyPets = {}
local function ScanPets()
	wipe(friendlyPets)
	local function Add(u) if UnitExists(u) then local n = UnitName(u); if n then friendlyPets[n] = true end end end
	Add("pet")
	for i = 1, 4 do Add("partypet" .. i) end
	for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do Add("raidpet" .. i) end
end
ns:On("UNIT_PET", ScanPets)
ns:On("PARTY_MEMBERS_CHANGED", ScanPets)
ns:On("RAID_ROSTER_UPDATE", ScanPets)
ns:On("PLAYER_ENTERING_WORLD", ScanPets)

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

	local d = { health = health, cast = cast, shield = castShield, spellIcon = spellIcon, nameText = nameText, raidIcon = raidIcon }
	local f = CreateFrame("Frame", nil, plate)
	f:SetSize(200, 70)
	f:SetPoint("CENTER", health, "CENTER", 0, 0)
	f:SetScale(ns.root:GetEffectiveScale() / plate:GetEffectiveScale())
	d.frame = f

	d.hp = ns:CreateBar(f, PLATE_W, PLATE_H)
	d.hp:SetPoint("CENTER", f, "CENTER", 0, 0)
	-- health: "31.2k · 74%" inside the bar (kept clear of the round icon)
	d.hpText = ns:CreateText(d.hp, 12, true, "RIGHT")
	d.hpText:SetPoint("RIGHT", d.hp, "RIGHT", -4, 0)
	-- kill target helper mark (red cross / blue square), left of the health text
	d.mark = d.hp:CreateTexture(nil, "OVERLAY")
	d.mark:SetSize(18, 18)
	d.mark:SetPoint("RIGHT", d.hpText, "LEFT", -2, 0)
	d.mark:Hide()

	d.name = ns:CreateText(f, 15, true, "LEFT")
	d.name:SetPoint("BOTTOMLEFT", d.hp, "TOPLEFT", 1, 4)
	d.num = ns:CreateText(f, 15, true, "RIGHT")
	d.num:SetPoint("BOTTOMRIGHT", d.hp, "TOPRIGHT", 0, 4)
	d.name:SetPoint("RIGHT", d.num, "LEFT", -4, 0)

	-- cast strip: always there, joined to the bottom of the health bar (one framed block);
	-- the fill only shows while the unit casts
	d.track = CreateFrame("Frame", nil, f)
	ns:Skin(d.track)
	ns:BarBackground(d.track)
	d.track:SetPoint("TOPLEFT", d.hp, "BOTTOMLEFT", 0, -1)
	d.track:SetPoint("TOPRIGHT", d.hp, "BOTTOMRIGHT", 0, -1)
	d.track:SetHeight(CAST_H)
	d.castbar = CreateFrame("StatusBar", nil, d.track)
	d.castbar:SetAllPoints(d.track)
	d.castbar:SetStatusBarTexture(ns.media.flat)
	d.castbar:SetMinMaxValues(0, 1)
	ns:Gloss(d.castbar)
	d.castbar:Hide()
	d.castbar:SetScript("OnHide", function()
		d.castIcon:Hide()
		d.raidIcon:ClearAllPoints()
		d.raidIcon:SetPoint("LEFT", d.hp, "RIGHT", 4, -3)
	end)
	-- smooth fill between plate updates
	d.castbar:SetScript("OnUpdate", function(bar)
		if not d.castStart then return bar:Hide() end
		local now = GetTime()
		if now >= d.castEnd then d.castStart = nil return bar:Hide() end
		local pct = (now - d.castStart) / (d.castEnd - d.castStart)
		bar:SetValue(d.castChannel and (1 - pct) or pct)
	end)

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
	d.big = ns:CreateIcon(f, 40, 15)
	d.mine = {}
	for i = 1, 5 do d.mine[i] = ns:CreateIcon(f, 24, 12) end

	-- square class / creature icon on the left, as tall as the health bar + cast strip
	d.classIcon = ns:CreateIcon(f, 24)
	d.classIcon.tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")

	-- raid markers (skull, X...) go on the right so they never cover the class icon
	raidIcon:ClearAllPoints()
	raidIcon:SetPoint("LEFT", d.hp, "RIGHT", 4, -3)

	-- what the enemy is casting: spell icon on the right, as tall as the bar + cast strip
	-- (the raid marker moves out of its way while it shows)
	d.castIcon = ns:CreateIcon(f, 24)
	d.castIcon:SetPoint("TOPLEFT", d.hp, "TOPRIGHT", 3, 0)
	raidIcon:SetSize(20, 20)

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
			icon:SetPoint("BOTTOMLEFT", anchorTop, "TOPLEFT", (i - 1) * 27, y)
			icon:Set(a.icon, nil, a.dur, (not a.noTimer) and a.expires or nil)
		else
			icon:Clear()
		end
	end
	if #mine > 0 then y = y + 24 + 5 end
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

-- Casts seen in the combat log, by caster name (for plates we have no unit for)
logCasts = {}
local function Short(n) return n and n:match("^[^-]+") end
ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, event, _, srcName, _, _, dstName, _, spellId)
	if event == "SPELL_CAST_START" then
		local castTime = srcName and spellId and select(7, GetSpellInfo(spellId))
		if castTime and castTime > 0 then
			local now = GetTime()
			local c = { start = now, finish = now + castTime / 1000, icon = select(3, GetSpellInfo(spellId)) }
			-- plates show names without the realm, the combat log may add "-Realm"
			logCasts[srcName], logCasts[Short(srcName)] = c, c
		end
	elseif event == "SPELL_CAST_SUCCESS" or event == "SPELL_CAST_FAILED" then
		if srcName then logCasts[srcName], logCasts[Short(srcName)] = nil, nil end
	elseif event == "SPELL_INTERRUPT" or event == "UNIT_DIED" then
		if dstName then logCasts[dstName], logCasts[Short(dstName)] = nil, nil end
	end
end)

local function ShortHP(n)
	if n >= 1e6 then return format("%.1fm", n / 1e6) end
	if n >= 1e3 then return format("%.1fk", n / 1e3) end
	return tostring(floor(n))
end

local function UpdateTotem(d, icon, friendly, r, g, b)
	d.isTotem = true
	d.hp:SetSize(PLATE_W / 2, 8) -- totems: half-size plate
	d.track:Hide()
	if friendly then
		d.hp:SetStatusBarColor(colors.friendly[1], colors.friendly[2], colors.friendly[3])
	else
		d.hp:SetStatusBarColor(ns:Soften(r, g, b))
	end
	ns:SetHighlight(d.hp, false)
	local min, max = d.health:GetMinMaxValues()
	d.hp:SetMinMaxValues(min, max)
	d.hp:SetValue(d.health:GetValue())
	-- the icon is the important part: big and centered above the small bar
	d.classIcon:SetSize(28, 28)
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
	-- a pet on your side: friendly, whatever color the game gave its bar
	-- (unless an enemy arena pet has the same name, e.g. two Water Elementals: then trust the bar color)
	if name and friendlyPets[name] then
		local clash = false
		for i = 1, 5 do if UnitExists("arenapet" .. i) and UnitName("arenapet" .. i) == name then clash = true end end
		if not clash then kind, class = "friendlyPet", nil end
	end
	local friendly = (kind == "friendlyPlayer" or kind == "friendlyNPC" or kind == "friendlyPet")

	local totem = TotemIcon(name)
	if totem then return UpdateTotem(d, totem, friendly, r, g, b) end
	if d.isTotem then
		-- plate frames get reused: put the normal layout back
		d.isTotem = nil
		d.track:Show()
		d.classIcon:SetBorder()
	end
	local isTarget = UnitExists("target") and plate:GetAlpha() == 1 and name == UnitName("target")
	local arena = (not friendly) and ArenaNumber(name)
	local unit = name and PlateUnit(name, isTarget, arena)

	-- Class: ask the game directly whenever we can, the bar color is only a fallback
	-- (it only carries class when the class-color nameplate setting is active).
	-- Friendly players: their bar is plain blue (no class), so look them up the same way:
	-- your target / party / raid by name, else any player the combat log has seen.
	do
		local u = isTarget and "target" or (arena and ("arena" .. arena)) or (friendly and unit) or nil
		if friendly and not u and name and kind == "friendlyPlayer" and GetNumRaidMembers then
			for i = 1, GetNumRaidMembers() do
				if UnitName("raid" .. i) == name then u = "raid" .. i break end
			end
		end
		local playerKind = friendly and "friendlyPlayer" or "enemyPlayer"
		if u and UnitIsPlayer(u) then
			local _, c = UnitClass(u)
			if c then kind, class = playerKind, c end
		elseif (friendly or not class) and name and ns.nameToGUID[name] and GetPlayerInfoByGUID then
			local _, c = GetPlayerInfoByGUID(ns.nameToGUID[name])
			if c then kind, class = playerKind, c; classByName[name] = c end
		end
		if (friendly or not class) and not (u and UnitIsPlayer(u)) and name and classByName[name] then
			kind, class = playerKind, classByName[name]
		end
	end

	-- size + color
	-- same size for friends and enemies (bigger when targeted); friends are always green
	local w, h = PLATE_W, PLATE_H
	if isTarget then w, h = PLATE_W_TARGET, PLATE_H_TARGET end
	d.hp:SetSize(w, h)
	local castH = isTarget and CAST_H_TARGET or CAST_H
	d.track:SetHeight(castH)
	if kind == "friendlyPet" then
		d.hp:SetStatusBarColor(colors.channel[1], colors.channel[2], colors.channel[3]) -- friendly pets: blue
	elseif friendly then
		d.hp:SetStatusBarColor(colors.friendly[1], colors.friendly[2], colors.friendly[3])
	elseif kind == "enemyPlayer" then
		d.hp:SetStatusBarColor(ns:BarColor(class))
	else
		d.hp:SetStatusBarColor(ns:Soften(r, g, b))
	end
	ns:SetHighlight(d.hp, isTarget)
	ns:SetHighlight(d.track, isTarget)

	-- square icon on the left for everyone: class icon for players, creature-type icon for NPCs;
	-- exactly as tall as the health bar + cast strip block
	local size = h + 1 + castH
	d.classIcon:SetSize(size, size)
	d.classIcon:ClearAllPoints()
	d.classIcon:SetPoint("TOPRIGHT", d.hp, "TOPLEFT", -3, 0)
	ns:SetHighlight(d.classIcon, isTarget)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if not coords and unit and UnitIsPlayer(unit) then
		local _, c = UnitClass(unit)
		coords = c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c]
	end
	if coords then
		d.classIcon.tex:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
		d.classIcon.tex:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
	elseif friendly then
		-- friendly NPCs (vendors, guards...) and players whose class we don't know yet: no icon
		d.classIcon:Hide()
	else
		-- NPCs: learn the creature type when you target/mouse over one, then reuse it by name
		if unit and not UnitIsPlayer(unit) and name then npcIcons[name] = ns:CreatureIcon(unit) end
		d.classIcon.tex:SetTexture((name and npcIcons[name]) or ns.creatureFallback)
		d.classIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	if coords or not friendly then d.classIcon:Show() end
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
			ns:Font(d.hpText, isTarget and 13 or 12, true)
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
			ns:Font(d.name, isTarget and 16 or 15, true)
		end
	end

	-- cast strip: Blizzard only fills its own plate cast bar for your target, so read the cast
	-- from the unit when we have one (target / focus / arena / mouseover / party), else from the
	-- combat log by name (any enemy that starts a cast)
	if not d.isTotem then
		local spell, start, finish, locked, channel, tex
		local u = unit or (isTarget and "target") or nil
		if u then
			local _, _, _, t1, s1, e1, _, _, nk = UnitCastingInfo(u)
			if s1 then
				spell, start, finish, locked, tex = true, s1 / 1000, e1 / 1000, nk, t1
			else
				local _, _, _, t2, s2, e2, _, nk2 = UnitChannelInfo(u)
				if s2 then spell, start, finish, locked, channel, tex = true, s2 / 1000, e2 / 1000, nk2, true, t2 end
			end
		end
		if not spell and d.cast:IsShown() then
			local cmin, cmax = d.cast:GetMinMaxValues()
			local v = d.cast:GetValue()
			if cmax and cmax > cmin then
				-- Blizzard bar counts in seconds (min 0, max cast time)
				spell, start, finish = true, GetTime() - (v - cmin), GetTime() + (cmax - v)
				locked = d.shield:IsShown()
				tex = d.spellIcon:GetTexture()
			end
		end
		local lc = not spell and name and logCasts[name]
		if lc and lc.finish > GetTime() then
			spell, start, finish, locked, tex = true, lc.start, lc.finish, false, lc.icon
		end
		if spell and finish > start then
			d.castStart, d.castEnd, d.castChannel = start, finish, channel
			local c = locked and colors.locked or (channel and colors.channel) or colors.kick
			local size = h + 1 + castH
			d.castIcon:SetSize(size, size)
			d.castIcon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
			d.castIcon:SetBorder(c[1], c[2], c[3])
			d.castIcon:Show()
			d.raidIcon:ClearAllPoints()
			d.raidIcon:SetPoint("LEFT", d.castIcon, "RIGHT", 4, 0)
			d.castbar:SetStatusBarColor(c[1], c[2], c[3])
			d.castbar:SetMinMaxValues(0, 1)
			if not d.castbar:IsShown() then d.castbar:Show() end
		else
			d.castStart = nil
			d.castbar:Hide()
		end
	end

	-- combo points under your target's plate: 5 red segments as wide as the health bar
	local points = isTarget and GetComboPoints("player", "target") or 0
	local gap = 2
	local pipW = (w - 4 * gap) / 5
	for i, pip in ipairs(d.pips) do
		if points > 0 then
			pip:SetSize(pipW, 5)
			pip:ClearAllPoints()
			pip:SetPoint("TOPLEFT", d.track, "BOTTOMLEFT", (i - 1) * (pipW + gap), -3)
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
