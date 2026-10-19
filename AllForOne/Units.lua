-- AllForOne: unit frames
-- Left: you + party (+pets). Right: arena 1-5 (+pets), mirrored.
-- Center: target (cast, debuffs, buffs, combo points), target of target, focus, your cast bar.
local _, ns = ...
local colors = ns.colors
local GetTime = GetTime

----------------------------------------------------------------------
-- Unit data (swapped for sample data in test mode)
----------------------------------------------------------------------
local U = {}
ns.U = U
local function fake(u) return ns.testing and ns.fake and ns.fake[u] end

function U.Exists(u) local f = fake(u); if ns.testing then return f ~= nil end return UnitExists(u) end
function U.Name(u) local f = fake(u); if f then return f.name end return UnitName(u) end
function U.Class(u) local f = fake(u); if f then return f.class end local _, c = UnitClass(u); return c end
function U.IsPlayer(u) local f = fake(u); if f then return true end return UnitIsPlayer(u) end
function U.GUID(u) local f = fake(u); if f then return "test-" .. u end return UnitGUID(u) end
function U.Health(u)
	local f = fake(u)
	if f then return f.hp, 100 end
	return UnitHealth(u), UnitHealthMax(u)
end
function U.Power(u)
	local f = fake(u)
	if f then return f.pw, 100, f.ptype end
	return UnitPower(u), UnitPowerMax(u), UnitPowerType(u)
end
function U.Dead(u) if fake(u) then return false end return UnitIsDeadOrGhost(u) end
function U.Visible(u)
	if fake(u) then return true end
	if u:match("^party") then
		local inRange = UnitInRange(u)
		return inRange and true or false
	end
	return UnitIsVisible(u)
end

----------------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------------
local frames = {}  -- every unit frame
local byUnit = {}  -- unit -> frames

local function Track(f, unit)
	frames[#frames + 1] = f
	byUnit[unit] = byUnit[unit] or {}
	table.insert(byUnit[unit], f)
end

local function ShowMenu(self)
	local u, dd = self.unit, nil
	if u == "player" then dd = PlayerFrameDropDown
	elseif u == "target" then dd = TargetFrameDropDown
	elseif u == "focus" then dd = FocusFrameDropDown
	elseif u == "pet" then dd = PetFrameDropDown
	else
		local n = u:match("^party(%d)$")
		if n then dd = _G["PartyMemberFrame" .. n .. "DropDown"] end
	end
	if dd then ToggleDropDownMenu(1, nil, dd, "cursor") end
end

-- Clickable secure unit button. Left click targets, right click opens menu (or sets focus).
local function SecureUnit(parent, unit, w, h, rightClick)
	local b = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
	b:SetSize(w, h)
	b.unit = unit
	b:SetAttribute("unit", unit)
	b:SetAttribute("*type1", "target")
	if rightClick == "focus" then
		b:SetAttribute("*type2", "focus")
	else
		b:SetAttribute("*type2", "menu")
		b.menu = ShowMenu
	end
	b:RegisterForClicks("AnyUp")
	b:SetScript("OnEnter", UnitFrame_OnEnter)
	b:SetScript("OnLeave", UnitFrame_OnLeave)
	RegisterUnitWatch(b)
	return b
end

-- Four 1px white lines around a frame: "this is your target"
local function CreateRing(f, pad)
	local ring = {}
	for i = 1, 4 do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetTexture(1, 1, 1, 1)
		ring[i] = t
	end
	ring[1]:SetPoint("TOPLEFT", -pad, pad); ring[1]:SetPoint("TOPRIGHT", pad, pad); ring[1]:SetHeight(1)
	ring[2]:SetPoint("BOTTOMLEFT", -pad, -pad); ring[2]:SetPoint("BOTTOMRIGHT", pad, -pad); ring[2]:SetHeight(1)
	ring[3]:SetPoint("TOPLEFT", -pad, pad); ring[3]:SetPoint("BOTTOMLEFT", -pad, -pad); ring[3]:SetWidth(1)
	ring[4]:SetPoint("TOPRIGHT", pad, pad); ring[4]:SetPoint("BOTTOMRIGHT", pad, -pad); ring[4]:SetWidth(1)
	ring.Set = function(_, on)
		for i = 1, 4 do if on then ring[i]:Show() else ring[i]:Hide() end end
	end
	ring:Set(false)
	return ring
end

local function HealthColor(unit)
	local class = U.Class(unit)
	if U.IsPlayer(unit) and class then
		return ns:ClassColor(class)
	end
	local reaction = UnitReaction(unit, "player")
	if reaction and reaction <= 3 then return 0.85, 0.25, 0.22 end
	if reaction == 4 then return 0.95, 0.80, 0.30 end
	return colors.friendly[1], colors.friendly[2], colors.friendly[3]
end

-- Paints a health bar + its name text the way the design says
local function PaintHealth(bar, nameText, unit)
	local r, g, b = HealthColor(unit)
	if ns.db.classColoredBars then
		bar:SetStatusBarColor(r, g, b)
		nameText:SetTextColor(1, 1, 1)
	else
		bar:SetStatusBarColor(colors.missing[1], colors.missing[2], colors.missing[3])
		nameText:SetTextColor(r, g, b)
	end
end

local function Short(n)
	if n >= 1e6 then return format("%.1fm", n / 1e6) end
	if n >= 1e3 then return format("%.1fk", n / 1e3) end
	return tostring(n)
end

local function LabelFor(unit)
	local name = U.Name(unit) or ""
	local guid = U.GUID(unit)
	local spec = guid and ns.specs[guid]
	if spec then return name .. " · " .. spec end
	return name
end

local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

----------------------------------------------------------------------
-- Team / arena row
-- Layout (enemy side, left to right): class icon | health+power | trinket.
-- Team side is the exact mirror image.
----------------------------------------------------------------------
local ROW_W, ROW_STRIDE = 292, 126
local Row = {}

function Row:Place(child, x, y, w, h)
	child:ClearAllPoints()
	local px = self.mirror and (ROW_W - x - w) or x
	child:SetPoint("TOPLEFT", self, "TOPLEFT", px, -y)
end

function Row:UpdateHealth()
	local u = self.unit
	local cur, max = U.Health(u)
	if not max or max == 0 then max = 1 end
	self.health:SetMinMaxValues(0, max)
	self.health:SetValue(cur or 0)
	if U.Dead(u) then
		self.hpText:SetText("DEAD")
	elseif u == "player" then
		self.hpText:SetText(Short(cur) .. " · " .. floor(cur / max * 100 + 0.5) .. "%")
	else
		self.hpText:SetText(floor(cur / max * 100 + 0.5) .. "%")
	end
end

function Row:UpdatePower()
	local cur, max, ptype = U.Power(self.unit)
	if not max or max == 0 then max = 1 end
	local c = colors.power[ptype or 0] or colors.power[0]
	self.power:SetStatusBarColor(c[1], c[2], c[3])
	self.power:SetMinMaxValues(0, max)
	self.power:SetValue(cur or 0)
end

function Row:UpdateName()
	local u = self.unit
	self.nameText:SetText(LabelFor(u))
	PaintHealth(self.health, self.nameText, u)
	local class = U.Class(u)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		self.classIcon.tex:SetTexture(CLASS_TEX)
		self.classIcon.tex:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
	end
end

function Row:UpdateTrinket()
	local guid = U.GUID(self.unit)
	local used = guid and ns.trinkets[guid]
	if used and used + ns.trinketCooldown > GetTime() then
		self.trinket:Set(ns.trinketIcon, nil, ns.trinketCooldown, used + ns.trinketCooldown, true)
	else
		self.trinket:Set(ns.trinketIcon)
	end
end

function Row:UpdateCooldowns()
	local list = ns:GetCooldowns(U.GUID(self.unit), U.Class(self.unit), #self.cds)
	for i, icon in ipairs(self.cds) do
		local e = list[i]
		if e then
			icon:Set(e.icon, nil, e.dur, e.start and (e.start + e.dur) or nil, true)
		else
			icon:Clear()
		end
	end
end

-- Enemy side: diminishing returns. Team side: CC / dispellable debuffs.
function Row:UpdateSide()
	if self.enemy then
		local list = ns:GetDR(U.GUID(self.unit))
		for i, icon in ipairs(self.side) do
			local d = list[i]
			if d then
				local c, mark
				if d.count <= 1 then c, mark = colors.drHalf, "½"
				elseif d.count == 2 then c, mark = colors.drQuarter, "¼"
				else c, mark = colors.drImmune, "×" end
				icon:Set(d.icon, nil, ns.DR_RESET, (not d.active) and d.reset or nil)
				icon:SetBorder(c[1], c[2], c[3])
				icon.count:SetText(mark)
				icon.count:SetTextColor(c[1], c[2], c[3])
			else
				icon:Clear()
			end
		end
	else
		local shown = ns:ScanDebuffs(self.unit, #self.side)
		for i, icon in ipairs(self.side) do
			local a = shown[i]
			if a then
				icon:Set(a.icon, a.count, a.dur, a.expires)
				local c = colors.dispel[a.dispel or "none"] or colors.dispel.none
				icon:SetBorder(c[1], c[2], c[3])
				icon.count:SetTextColor(1, 1, 1)
			else
				icon:Clear()
			end
		end
	end
end

function Row:UpdateState()
	local u = self.unit
	self:SetAlpha(U.Visible(u) and 1 or 0.55)
	if self.enemy then
		self.ring:Set(not ns.testing and UnitIsUnit(u, "target") or (ns.testing and u == "arena3"))
	end
end

function Row:UpdatePet()
	local p = self.petFrame
	if not p then return end
	local u = p.unit
	if not U.Exists(u) then return end
	local cur, max = U.Health(u)
	if not max or max == 0 then max = 1 end
	p.bar:SetMinMaxValues(0, max)
	p.bar:SetValue(cur or 0)
	local r, g, b = ns:ClassColor(U.Class(self.unit))
	p.bar:SetStatusBarColor(r * 0.75, g * 0.75, b * 0.75)
	p.name:SetText(U.Name(u) or "")
	p.hp:SetText(floor((cur or 0) / max * 100 + 0.5) .. "%")
end

function Row:Update()
	if not U.Exists(self.unit) then return end
	self:UpdateName()
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateTrinket()
	self:UpdateCooldowns()
	self:UpdateSide()
	self:UpdateState()
	self:UpdatePet()
end

local function CreateRow(unit, petUnit, enemy, index, holder)
	local mirror = not enemy
	local f = SecureUnit(holder, unit, ROW_W, 40, enemy and "focus" or nil)
	f.mirror, f.enemy = mirror, enemy
	for k, v in pairs(Row) do f[k] = v end
	f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(index - 1) * ROW_STRIDE)

	f.classIcon = ns:CreateIcon(f, 40)
	f.classIcon:Show()
	f:Place(f.classIcon, 0, 0, 40, 40)
	if enemy then
		f.num = ns:CreateText(f.classIcon, 12, true, "LEFT")
		f.num:SetPoint("TOPLEFT", 3, -2)
		f.num:SetText(unit:match("%d"))
	end

	f.health = ns:CreateBar(f, 204, 32)
	f:Place(f.health, 44, 0, 204, 32)
	f.nameText = ns:CreateText(f.health, 16, true, "LEFT")
	f.hpText = ns:CreateText(f.health, 16, true, "RIGHT")
	f.hpText:SetPoint("RIGHT", -8, 0)
	f.nameText:SetPoint("LEFT", 8, 0)
	f.nameText:SetPoint("RIGHT", f.hpText, "LEFT", -6, 0)

	f.power = ns:CreateBar(f, 204, 6)
	f:Place(f.power, 44, 34, 204, 6)

	f.trinket = ns:CreateIcon(f, 40, 13)
	f:Place(f.trinket, 252, 0, 40, 40)
	f.trinket:Set(ns.trinketIcon)

	f.castbar = ns:CreateCastbar(f, 248, 14, { iconSize = 0, fontSize = 12, lock = false })
	f:Place(f.castbar, 0, 62, 248, 14)
	f.castbar:SetUnit(unit)

	f.cds = {}
	for i = 1, 6 do
		local icon = ns:CreateIcon(f, 30, 13)
		f:Place(icon, (i - 1) * 33, 80, 30, 30)
		f.cds[i] = icon
	end

	f.side = {}
	for i = 1, 4 do
		local icon = ns:CreateIcon(f, 30, 12)
		icon:ClearAllPoints()
		if mirror then
			icon:SetPoint("TOPLEFT", f, "TOPLEFT", ROW_W + 8 + (i - 1) * 34, -5)
		else
			icon:SetPoint("TOPRIGHT", f, "TOPLEFT", -8 - (i - 1) * 34, -5)
		end
		f.side[i] = icon
	end

	if enemy then f.ring = CreateRing(f, 2) end

	-- Pet: smaller bar under the owner, on the class-icon side of the health bar
	if petUnit then
		local p = SecureUnit(f, petUnit, 140, 14, enemy and "focus" or nil)
		f:Place(p, 44, 44, 140, 14)
		p.bar = ns:CreateBar(p, 140, 14)
		p.bar:SetAllPoints(p)
		p.name = ns:CreateText(p.bar, 11, true, "LEFT")
		p.name:SetPoint("LEFT", 6, 0)
		p.hp = ns:CreateText(p.bar, 11, true, "RIGHT")
		p.hp:SetPoint("RIGHT", -6, 0)
		f.petFrame = p
		p:HookScript("OnShow", function() f:UpdatePet() end)
		byUnit[petUnit] = byUnit[petUnit] or {}
		table.insert(byUnit[petUnit], { Update = function() f:UpdatePet() end, UpdateHealth = function() f:UpdatePet() end })
	end

	f:HookScript("OnShow", function(self) self:Update() end)
	Track(f, unit)
	return f
end

-- Debuffs worth showing on a teammate: crowd control first, then anything you can dispel
function ns:ScanDebuffs(unit, max)
	if ns.testing then return (ns.fakeDebuffs and ns.fakeDebuffs[unit]) or {} end
	local out = {}
	local seen = {}
	for i = 1, 40 do
		local name, _, icon, count, dispel, duration, expires = UnitAura(unit, i, "HARMFUL")
		if not name then break end
		local cc = ns.CC[name]
		if cc then
			out[#out + 1] = { icon = icon, count = count, dur = duration, expires = expires, dispel = dispel, prio = 10 + (ns.ccPriority[cc.cat] or 0) }
			seen[name] = true
		end
	end
	for i = 1, 40 do
		local name, _, icon, count, dispel, duration, expires = UnitAura(unit, i, "HARMFUL|RAID")
		if not name then break end
		if not seen[name] then
			out[#out + 1] = { icon = icon, count = count, dur = duration, expires = expires, dispel = dispel, prio = 1 }
		end
	end
	table.sort(out, function(a, b) return a.prio > b.prio end)
	while #out > max do table.remove(out) end
	return out
end

----------------------------------------------------------------------
-- Target frame (center, under the character)
----------------------------------------------------------------------
local Target = {}

function Target:UpdateHealth()
	local cur, max = U.Health("target")
	if not max or max == 0 then max = 1 end
	self.health:SetMinMaxValues(0, max)
	self.health:SetValue(cur or 0)
	self.hpText:SetText(U.Dead("target") and "DEAD" or (floor(cur / max * 100 + 0.5) .. "%"))
end

function Target:UpdatePower()
	local cur, max, ptype = U.Power("target")
	if not max or max == 0 then max = 1 end
	local c = colors.power[ptype or 0] or colors.power[0]
	self.power:SetStatusBarColor(c[1], c[2], c[3])
	self.power:SetMinMaxValues(0, max)
	self.power:SetValue(cur or 0)
end

function Target:UpdateAuras()
	local debuffs, buffs = {}, {}
	if ns.testing then
		debuffs = ns.fakeTargetDebuffs or {}
		buffs = ns.fakeTargetBuffs or {}
	else
		for i = 1, 40 do
			local name, _, icon, count, dispel, duration, expires, caster = UnitAura("target", i, "HARMFUL")
			if not name then break end
			local mine = caster == "player" or caster == "pet"
			if mine or ns.CC[name] then
				debuffs[#debuffs + 1] = { icon = icon, count = count, dur = duration, expires = expires, cc = ns.CC[name] and true, mine = mine }
			end
		end
		if UnitCanAttack("player", "target") then
			for i = 1, 40 do
				local name, _, icon, count, dispel, duration, expires, _, stealable = UnitAura("target", i, "HELPFUL")
				if not name then break end
				if stealable or dispel == "Magic" then
					buffs[#buffs + 1] = { icon = icon, count = count, dur = duration, expires = expires }
				end
			end
		end
	end
	-- crowd control first, then yours by time left
	table.sort(debuffs, function(a, b)
		if (a.cc and 1 or 0) ~= (b.cc and 1 or 0) then return a.cc and true or false end
		return (a.expires or 1e9) < (b.expires or 1e9)
	end)
	for i, icon in ipairs(self.debuffs) do
		local a = debuffs[i]
		if a then
			icon:Set(a.icon, a.count, a.dur, a.expires)
			if a.cc and not a.mine then icon:SetBorder(colors.danger[1], colors.danger[2], colors.danger[3]) else icon:SetBorder() end
		else
			icon:Clear()
		end
	end
	for i, icon in ipairs(self.buffs) do
		local a = buffs[i]
		if a then
			icon:Set(a.icon, a.count, a.dur, a.expires)
			icon:SetBorder(colors.dispel.Magic[1], colors.dispel.Magic[2], colors.dispel.Magic[3])
		else
			icon:Clear()
		end
	end
end

function Target:UpdateCombo()
	local points = ns.testing and (ns.fakeCombo or 0) or GetComboPoints("player", "target")
	local _, class = UnitClass("player")
	local show = ns.testing or points > 0 or class == "ROGUE" or class == "DRUID"
	for i, pip in ipairs(self.pips) do
		if show then
			pip:Show()
			if i <= points then
				pip.fill:SetTexture(colors.combo[1], colors.combo[2], colors.combo[3], 1)
			else
				pip.fill:SetTexture(0.14, 0.15, 0.16, 1)
			end
		else
			pip:Hide()
		end
	end
end

function Target:Update()
	if not U.Exists("target") then return end
	self.nameText:SetText(LabelFor("target"))
	PaintHealth(self.health, self.nameText, "target")
	self:UpdateHealth()
	self:UpdatePower()
	self:UpdateAuras()
	self:UpdateCombo()
end

local function CreateTarget(holder)
	local f = SecureUnit(holder, "target", 244, 44)
	f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	for k, v in pairs(Target) do f[k] = v end

	f.health = ns:CreateBar(f, 244, 36)
	f.health:SetPoint("TOPLEFT")
	ns:SetHighlight(f.health, true)
	f.nameText = ns:CreateText(f.health, 17, true, "LEFT")
	f.hpText = ns:CreateText(f.health, 17, true, "RIGHT")
	f.hpText:SetPoint("RIGHT", -8, 0)
	f.nameText:SetPoint("LEFT", 8, 0)
	f.nameText:SetPoint("RIGHT", f.hpText, "LEFT", -6, 0)

	f.power = ns:CreateBar(f, 244, 8)
	f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -2)

	f.castbar = ns:CreateCastbar(f, 244, 22, { iconSize = 22, fontSize = 15 })
	f.castbar:SetPoint("TOPLEFT", f.power, "BOTTOMLEFT", 0, -3)
	f.castbar:SetUnit("target")

	f.buffs = {}
	for i = 1, 8 do
		local icon = ns:CreateIcon(f, 20, 10)
		icon:SetPoint("TOPLEFT", f.castbar, "BOTTOMLEFT", (i - 1) * 23, -4)
		f.buffs[i] = icon
	end

	f.debuffs = {}
	for i = 1, 8 do
		local icon = ns:CreateIcon(f, 28, 12)
		icon:SetPoint("BOTTOMLEFT", f.health, "TOPLEFT", (i - 1) * 32, 8)
		f.debuffs[i] = icon
	end

	f.pips = {}
	for i = 1, 5 do
		local pip = CreateFrame("Frame", nil, f)
		pip:SetSize(14, 8)
		pip:SetPoint("BOTTOMRIGHT", f.health, "TOPRIGHT", -(5 - i) * 17, 12)
		ns:Skin(pip, true)
		pip.fill = pip:CreateTexture(nil, "ARTWORK")
		pip.fill:SetAllPoints(pip)
		f.pips[i] = pip
	end

	f:HookScript("OnShow", function(self) self:Update() end)
	Track(f, "target")
	return f
end

----------------------------------------------------------------------
-- Small frames: target of target, focus (+cast)
----------------------------------------------------------------------
local Small = {}
function Small:Update()
	local u = self.unit
	if not U.Exists(u) then return end
	local cur, max = U.Health(u)
	if not max or max == 0 then max = 1 end
	self.health:SetMinMaxValues(0, max)
	self.health:SetValue(cur or 0)
	local label = U.Name(u) or ""
	if self.prefix then label = self.prefix .. label end
	self.nameText:SetText(label)
	if self.hpText then self.hpText:SetText(floor(cur / max * 100 + 0.5) .. "%") end
	PaintHealth(self.health, self.nameText, u)
end
Small.UpdateHealth = Small.Update

local function CreateSmall(unit, w, h, holder, opts)
	local f = SecureUnit(holder, unit, w, h)
	f:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	for k, v in pairs(Small) do f[k] = v end
	f.prefix = opts.prefix
	f.health = ns:CreateBar(f, w, h)
	f.health:SetAllPoints(f)
	f.nameText = ns:CreateText(f.health, opts.font or 13, true, "LEFT")
	f.nameText:SetPoint("LEFT", 6, 0)
	if opts.percent then
		f.hpText = ns:CreateText(f.health, opts.font or 13, true, "RIGHT")
		f.hpText:SetPoint("RIGHT", -6, 0)
		f.nameText:SetPoint("RIGHT", f.hpText, "LEFT", -4, 0)
	else
		f.nameText:SetPoint("RIGHT", -6, 0)
	end
	if opts.cast then
		f.castbar = ns:CreateCastbar(f, w, 10, { iconSize = 0, fontSize = 10, lock = false })
		f.castbar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3)
		f.castbar:SetUnit(unit)
	end
	f:HookScript("OnShow", function(self) self:Update() end)
	Track(f, unit)
	return f
end

----------------------------------------------------------------------
-- Build everything
----------------------------------------------------------------------
ns.frames = {}

-- A plain frame that holds a group of parts so they move and scale together
local function Holder(w, h)
	local f = CreateFrame("Frame", nil, ns.root)
	f:SetSize(w, h)
	return f
end

ns:Listen("LOGIN", function()
	local F = ns.frames
	local groupH = 5 * ROW_STRIDE - 16

	local team = Holder(ROW_W, groupH)
	ns:Mover("team", "YOUR TEAM", team, "TOPLEFT", "TOPLEFT", 180, -320)
	F.team = {}
	F.team[1] = CreateRow("player", "pet", false, 1, team)
	for i = 1, 4 do
		F.team[i + 1] = CreateRow("party" .. i, "partypet" .. i, false, i + 1, team)
	end

	local arena = Holder(ROW_W, groupH)
	ns:Mover("arena", "ENEMY TEAM", arena, "TOPRIGHT", "TOPRIGHT", -180, -320)
	F.arena = {}
	for i = 1, 5 do
		F.arena[i] = CreateRow("arena" .. i, "arenapet" .. i, true, i, arena)
	end

	-- center column, positions from the 1920x1080 design relative to screen center
	local target = Holder(244, 44)
	ns:Mover("target", "TARGET", target, "TOPLEFT", "CENTER", -122, -218)
	F.target = CreateTarget(target)

	local tot = Holder(96, 20)
	ns:Mover("tot", "TARGET OF TARGET", tot, "TOPLEFT", "CENTER", 130, -226)
	F.tot = CreateSmall("targettarget", 96, 20, tot, { font = 13 })

	local focus = Holder(184, 35)
	ns:Mover("focus", "FOCUS", focus, "TOPLEFT", "CENTER", 130, -256)
	F.focus = CreateSmall("focus", 184, 22, focus, { font = 14, percent = true, prefix = "F · ", cast = true })

	-- your cast bar, above the swing timer and stance/pet bars
	local cast = ns:CreateCastbar(ns.root, 360, 18, { iconSize = 0, fontSize = 13, color = colors.player })
	ns:Mover("cast", "YOUR CAST BAR", cast, "TOPLEFT", "CENTER", -180, -324)
	cast:SetUnit("player")
	F.playerCast = cast

	ns:UpdateUnitMap()
	ns:RefreshAll()
end)

function ns:RefreshAll()
	for _, f in ipairs(frames) do
		if f:IsShown() then f:Update() end
	end
end

local function ForUnit(unit, method)
	local list = byUnit[unit]
	if not list then return end
	for _, f in ipairs(list) do
		if f[method] then f[method](f) end
	end
end

ns:Listen("REFRESH_ALL", function() ns:RefreshAll() end)

for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH" }) do
	ns:On(ev, function(_, unit) ForUnit(unit, "UpdateHealth") end)
end
for _, ev in ipairs({ "UNIT_MANA", "UNIT_RAGE", "UNIT_ENERGY", "UNIT_FOCUS", "UNIT_RUNIC_POWER",
	"UNIT_MAXMANA", "UNIT_MAXRAGE", "UNIT_MAXENERGY", "UNIT_MAXFOCUS", "UNIT_MAXRUNIC_POWER", "UNIT_DISPLAYPOWER" }) do
	ns:On(ev, function(_, unit) ForUnit(unit, "UpdatePower") end)
end
ns:On("UNIT_AURA", function(_, unit)
	if unit == "target" then
		if ns.frames.target then ns.frames.target:UpdateAuras() end
	else
		ForUnit(unit, "UpdateSide")
	end
end)
ns:On("UNIT_NAME_UPDATE", function(_, unit) ForUnit(unit, "Update") end)
ns:On("UNIT_PET", function(_, unit)
	local owner = unit == "player" and "pet" or (unit and unit:gsub("^party", "partypet"))
	if owner then ForUnit(owner, "Update") end
end)
ns:On("PLAYER_TARGET_CHANGED", function() ForUnit("target", "Update"); ForUnit("targettarget", "Update"); ns:RefreshAll() end)
ns:On("PLAYER_FOCUS_CHANGED", function() ForUnit("focus", "Update") end)
ns:On("UNIT_TARGET", function(_, unit) if unit == "target" then ForUnit("targettarget", "Update") end end)
ns:On("UNIT_COMBO_POINTS", function() if ns.frames.target then ns.frames.target:UpdateCombo() end end)
ns:On("PARTY_MEMBERS_CHANGED", function() ns:RefreshAll() end)
ns:On("ARENA_OPPONENT_UPDATE", function(_, unit) if unit then ForUnit(unit, "Update") end end)

local function RefreshGUID(guid, method)
	for _, f in ipairs(frames) do
		if f.unit and U.GUID(f.unit) == guid and f[method] then f[method](f) end
	end
end
ns:Listen("COOLDOWN", function(guid) RefreshGUID(guid, "UpdateCooldowns"); RefreshGUID(guid, "UpdateTrinket") end)
ns:Listen("DR", function(guid) RefreshGUID(guid, "UpdateSide") end)
ns:Listen("SPEC", function(guid) RefreshGUID(guid, "UpdateName") end)

-- Slow refresh for things without good events (target of target, range, highlight)
local acc = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.25 then return end
	acc = 0
	if ns.frames.tot and ns.frames.tot:IsShown() then ns.frames.tot:Update() end
	if ns.frames.team then
		for _, f in ipairs(ns.frames.team) do if f:IsShown() then f:UpdateState() end end
		for _, f in ipairs(ns.frames.arena) do if f:IsShown() then f:UpdateState(); f:UpdateSide() end end
	end
end)

-- Test mode support: show/hide secure frames out of combat
function ns:SetFramesForced(on)
	ns:SafeCall(function()
		for _, f in ipairs(frames) do
			if on then
				UnregisterUnitWatch(f)
				if fake(f.unit) then f:Show() else f:Hide() end
				if f.petFrame then
					UnregisterUnitWatch(f.petFrame)
					if fake(f.petFrame.unit) then f.petFrame:Show() else f.petFrame:Hide() end
				end
			else
				RegisterUnitWatch(f)
				if f.petFrame then RegisterUnitWatch(f.petFrame) end
			end
		end
		ns:RefreshAll()
	end)
end
