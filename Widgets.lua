-- AllForOne: building blocks (bars, icons, text, cast bars)
local _, ns = ...
local media, colors = ns.media, ns.colors
local GetTime = GetTime

----------------------------------------------------------------------
-- Flat panel look: 1px black outline + dark fill
----------------------------------------------------------------------
function ns:Skin(frame, noFill)
	local outline = frame:CreateTexture(nil, "BACKGROUND")
	outline:SetTexture(0, 0, 0, 1)
	outline:SetPoint("TOPLEFT", -1, 1)
	outline:SetPoint("BOTTOMRIGHT", 1, -1)
	frame.outline = outline
	if not noFill then
		local fill = frame:CreateTexture(nil, "BORDER")
		fill:SetTexture(colors.bg[1], colors.bg[2], colors.bg[3], 1)
		fill:SetAllPoints(frame)
		frame.fill = fill
	end
end

-- Flat look for a Blizzard button WITHOUT touching its own textures:
-- a separate frame one level below the button holds the 1px outline, the dark fill and
-- an optional colored ring. It follows the button around and shows/hides with it.
-- (Blizzard draws icons on the BACKGROUND layer, so anything we add inside the button
-- on that layer can end up covering the icon.)
function ns:Backing(button, parent)
	local bg = CreateFrame("Frame", nil, parent or button:GetParent())
	bg:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
	bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
	bg:SetFrameStrata(button:GetFrameStrata())
	bg:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
	local outline = bg:CreateTexture(nil, "BACKGROUND")
	outline:SetTexture(0, 0, 0, 1)
	outline:SetAllPoints(bg)
	bg.ring = bg:CreateTexture(nil, "BORDER")
	bg.ring:SetPoint("TOPLEFT", -1, 1)
	bg.ring:SetPoint("BOTTOMRIGHT", 1, -1)
	bg.ring:Hide()
	local fill = bg:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(colors.bg[1], colors.bg[2], colors.bg[3], 1)
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	button:HookScript("OnShow", function() bg:Show() end)
	button:HookScript("OnHide", function() bg:Hide() end)
	if not button:IsShown() then bg:Hide() end
	return bg
end

-- Thin white ring used for "this is your target"
function ns:SetHighlight(frame, on)
	if not frame.outline then return end
	if on then
		frame.outline:SetTexture(1, 1, 1, 1)
	else
		frame.outline:SetTexture(0, 0, 0, 1)
	end
end

function ns:CreateText(parent, size, bold, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	ns:Font(fs, size or 14, bold)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetTextColor(1, 1, 1)
	return fs
end

function ns:CreateBar(parent, w, h)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(w, h)
	bar:SetStatusBarTexture(media.flat)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	ns:Skin(bar)
	return bar
end

----------------------------------------------------------------------
-- Timers: one shared ticker updates every visible countdown text
----------------------------------------------------------------------
local timed = {}
local ticker = CreateFrame("Frame")
local elapsedAcc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	elapsedAcc = elapsedAcc + elapsed
	if elapsedAcc < 0.1 then return end
	elapsedAcc = 0
	local now = GetTime()
	for icon in pairs(timed) do
		local left = icon.expires - now
		if left <= 0 then
			timed[icon] = nil
			icon.timer:SetText("")
			if icon.onExpire then icon:onExpire() end
		else
			icon.timer:SetText(ns:FormatTime(left))
		end
	end
end)

----------------------------------------------------------------------
-- Icon: spell texture, colored border, countdown text, stack count
----------------------------------------------------------------------
local Icon = {}

function Icon:SetBorder(r, g, b)
	if r then
		self.ring:SetTexture(r, g, b, 1)
		self.ring:Show()
		self.tex:SetPoint("TOPLEFT", 2, -2)
		self.tex:SetPoint("BOTTOMRIGHT", -2, 2)
	else
		self.ring:Hide()
		self.tex:SetPoint("TOPLEFT", 0, 0)
		self.tex:SetPoint("BOTTOMRIGHT", 0, 0)
	end
end

-- duration/expires in GetTime() seconds; cooldown=true shows a dark sweep
function Icon:Set(texture, count, duration, expires, cooldown)
	self.tex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
	self.count:SetText((count and count > 1) and count or "")
	if expires and expires > GetTime() then
		self.expires = expires
		timed[self] = true
		if cooldown and duration and duration > 0 then
			self.cd:SetCooldown(expires - duration, duration)
			self.cd:Show()
		else
			self.cd:Hide()
		end
	else
		self.expires = nil
		timed[self] = nil
		self.timer:SetText("")
		self.cd:Hide()
	end
	self:Show()
end

function Icon:Clear()
	timed[self] = nil
	self.expires = nil
	self.timer:SetText("")
	self.cd:Hide()
	self:Hide()
end

function ns:CreateIcon(parent, size, timerSize)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	ns:Skin(f)
	f.ring = f:CreateTexture(nil, "BORDER", nil)
	f.ring:SetAllPoints(f)
	f.ring:Hide()
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.tex:SetPoint("TOPLEFT")
	f.tex:SetPoint("BOTTOMRIGHT")
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f.tex)
	f.cd.noCooldownCount = true -- keep OmniCC from adding a second number
	f.cd:Hide()
	local overlay = CreateFrame("Frame", nil, f)
	overlay:SetAllPoints(f)
	overlay:SetFrameLevel(f.cd:GetFrameLevel() + 2)
	f.timer = ns:CreateText(overlay, timerSize or math.max(11, floor(size * 0.42)), true, "CENTER")
	f.timer:SetPoint("CENTER", 0, 0)
	f.count = ns:CreateText(overlay, math.max(10, floor(size * 0.38)), true, "RIGHT")
	f.count:SetPoint("BOTTOMRIGHT", 2, -2)
	for k, v in pairs(Icon) do f[k] = v end
	f:Hide()
	return f
end

-- Icons placed in a row; grows "RIGHT" or "LEFT" from the anchor
function ns:CreateIconRow(parent, count, size, gap, grow)
	local row = {}
	for i = 1, count do
		local icon = ns:CreateIcon(parent, size)
		row[i] = icon
	end
	row.Layout = function(_, anchor, point, x, y)
		for i, icon in ipairs(row) do
			icon:ClearAllPoints()
			local offset = (i - 1) * (size + gap)
			if grow == "LEFT" then
				icon:SetPoint("TOPRIGHT", anchor, point, x - offset, y)
			else
				icon:SetPoint("TOPLEFT", anchor, point, x + offset, y)
			end
		end
	end
	row.ClearAll = function()
		for _, icon in ipairs(row) do icon:Clear() end
	end
	return row
end

----------------------------------------------------------------------
-- Cast bars
----------------------------------------------------------------------
local castbars = {} -- unit -> { bar, ... }
local Cast = {}

function Cast:Paint()
	local c
	if self.failed then
		c = colors.danger
	elseif self.notInterruptible then
		c = colors.locked
	elseif self.channel then
		c = colors.channel
	else
		c = self.baseColor or colors.kick
	end
	self.bar:SetStatusBarColor(c[1], c[2], c[3])
	-- white text with a black outline reads on both the filled and the unfilled part
	self.spell:SetTextColor(1, 1, 1)
	self.time:SetTextColor(1, 1, 1)
	if self.lock then
		if self.notInterruptible and not self.failed then self.lock:Show() else self.lock:Hide() end
	end
end

local function CastOnUpdate(self)
	local now = GetTime()
	if self.failed then
		if now > self.failed then
			self.failed = nil
			self:Stop()
		end
		return
	end
	if not self.endTime then return end
	if now >= self.endTime then
		self:Stop()
		return
	end
	local total = self.endTime - self.startTime
	local done = now - self.startTime
	if self.channel then
		self.bar:SetValue((total - done) / total)
	else
		self.bar:SetValue(done / total)
	end
	self.time:SetText(format("%.1f", self.endTime - now))
end

function Cast:Begin()
	if self.fake then return end
	local unit = self.unit
	if not unit or not UnitExists(unit) then self:Stop() return end
	local name, _, text, icon, startMS, endMS, _, _, notInt = UnitCastingInfo(unit)
	local channel = false
	if not name then
		name, _, text, icon, startMS, endMS, _, notInt = UnitChannelInfo(unit)
		channel = name and true or false
	end
	if not name then self:Stop() return end
	self.failed = nil
	self.channel = channel
	self.notInterruptible = notInt and true or false
	self.startTime = startMS / 1000
	self.endTime = endMS / 1000
	self.spell:SetText(text ~= "" and text or name)
	if self.icon then self.icon.tex:SetTexture(icon); self.icon:Show() end
	self.bar:Show()
	self:Paint()
	self:SetScript("OnUpdate", CastOnUpdate)
	CastOnUpdate(self)
end

function Cast:Stop()
	if self.failed then return end
	self.endTime = nil
	self:SetScript("OnUpdate", nil)
	self.bar:Hide()
	if self.icon then self.icon:Hide() end
end

function Cast:Interrupted(by)
	if not self.bar:IsShown() and not by then return end
	self.failed = GetTime() + 0.6
	self.endTime = nil
	self.bar:SetValue(1)
	self.bar:Show()
	self.spell:SetText(by and ("INTERRUPTED · " .. by) or "INTERRUPTED")
	self.time:SetText("")
	self:Paint()
	self:SetScript("OnUpdate", CastOnUpdate)
end

-- Sample cast for test mode
function Cast:Fake(name, icon, progress, notInterruptible, channel)
	self.fake = name and true or nil
	if not name then self:Stop() return end
	self:SetScript("OnUpdate", nil)
	self.failed, self.channel, self.notInterruptible = nil, channel, notInterruptible
	self.spell:SetText(name)
	self.time:SetText(format("%.1f", 1.5 * (1 - progress)))
	self.bar:SetValue(progress)
	if self.icon then self.icon.tex:SetTexture(icon); self.icon:Show() end
	self.bar:Show()
	self:Paint()
end

-- WoW also sends STOP / FAILED / INTERRUPTED for things that don't end the current cast:
-- the start of a channel (Penance), or pressing another spell while casting/channeling.
-- Blizzard's own cast bar checks first, and so do we.
local function StillCasting(unit)
	return unit and (UnitCastingInfo(unit) or UnitChannelInfo(unit))
end

function Cast:StopIfDone()
	if self.fake then return end
	if StillCasting(self.unit) then self:Begin() else self:Stop() end
end

function Cast:InterruptedIfDone(by)
	if self.fake then return end
	if StillCasting(self.unit) then self:Begin() else self:Interrupted(by) end
end

function Cast:SetUnit(unit)
	if self.unit and castbars[self.unit] then
		for i, b in ipairs(castbars[self.unit]) do
			if b == self then table.remove(castbars[self.unit], i) break end
		end
	end
	self.unit = unit
	if unit then
		castbars[unit] = castbars[unit] or {}
		table.insert(castbars[unit], self)
		self:Begin()
	end
end

-- opts: iconSize (0 = no icon), fontSize, color
function ns:CreateCastbar(parent, w, h, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	local iconSize = opts.iconSize or 0
	local barW = w
	if iconSize > 0 then
		f.icon = ns:CreateIcon(f, iconSize)
		f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
		barW = w - iconSize - 3
	end
	f.bar = ns:CreateBar(f, barW, h)
	f.bar:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.fontSize = opts.fontSize or math.max(11, floor(h * 0.7))
	f.spell = ns:CreateText(f.bar, f.fontSize, true, "LEFT")
	f.spell:SetPoint("LEFT", 6, 0)
	f.spell:SetPoint("RIGHT", -34, 0)
	f.time = ns:CreateText(f.bar, f.fontSize, true, "RIGHT")
	f.time:SetPoint("RIGHT", -6, 0)
	if opts.lock ~= false then
		f.lock = f.bar:CreateTexture(nil, "OVERLAY")
		f.lock:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
		f.lock:SetSize(h - 4, h - 4)
		f.lock:SetPoint("RIGHT", f.time, "LEFT", -4, 0)
		f.lock:Hide()
	end
	f.baseColor = opts.color
	for k, v in pairs(Cast) do f[k] = v end
	f.bar:Hide()
	if f.icon then f.icon:Hide() end
	return f
end

local function ForUnit(unit, method, ...)
	local list = castbars[unit]
	if not list then return end
	for _, b in ipairs(list) do b[method](b, ...) end
end

for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do
	ns:On(ev, function(_, unit) ForUnit(unit, "Begin") end)
end
for _, ev in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
	ns:On(ev, function(_, unit) ForUnit(unit, "StopIfDone") end)
end
ns:On("UNIT_SPELLCAST_INTERRUPTED", function(_, unit) ForUnit(unit, "InterruptedIfDone") end)

-- Re-check casts when a unit token points at someone new
local function RecheckAll(unit) ForUnit(unit, "Begin") end
ns:On("PLAYER_TARGET_CHANGED", function() RecheckAll("target") end)
ns:On("PLAYER_FOCUS_CHANGED", function() RecheckAll("focus") end)
ns:On("ARENA_OPPONENT_UPDATE", function(_, unit) if unit then RecheckAll(unit) end end)

-- Combat log tells us WHO interrupted
ns:Listen("INTERRUPTED", function(guid, by)
	for unit, list in pairs(castbars) do
		if UnitGUID(unit) == guid then
			for _, b in ipairs(list) do b:InterruptedIfDone(by) end
		end
	end
end)
