-- AllForOne: settings window (/afo) + an entry under Interface -> AddOns
local _, ns = ...
local colors = ns.colors

local W, PAD = 420, 18
local win

----------------------------------------------------------------------
-- Small flat controls
----------------------------------------------------------------------
local function Text(parent, size, bold, color)
	local fs = ns:CreateText(parent, size, bold, "LEFT")
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
	return fs
end

local function Button(parent, label, w, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, 26)
	ns:Skin(b)
	b.text = ns:CreateText(b, 13, true, "CENTER")
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function() b.text:SetTextColor(colors.kick[1], colors.kick[2], colors.kick[3]) end)
	b:SetScript("OnLeave", function() b.text:SetTextColor(1, 1, 1) end)
	return b
end

-- checkbox: get() returns the current value, set(v) stores it
local function Check(parent, label, note, get, set)
	local c = CreateFrame("Button", nil, parent)
	c:SetSize(W - 2 * PAD, 22)
	c.box = CreateFrame("Frame", nil, c)
	c.box:SetSize(16, 16)
	c.box:SetPoint("LEFT", 0, 0)
	ns:Skin(c.box)
	c.mark = c.box:CreateTexture(nil, "OVERLAY")
	c.mark:SetPoint("TOPLEFT", 3, -3)
	c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
	c.mark:SetTexture(colors.kick[1], colors.kick[2], colors.kick[3], 1)
	c.label = Text(c, 14, true)
	c.label:SetPoint("LEFT", c.box, "RIGHT", 8, 0)
	c.label:SetText(label)
	if note then
		c.note = Text(c, 12, false, colors.muted)
		c.note:SetPoint("LEFT", c.label, "RIGHT", 8, 0)
		c.note:SetText(note)
	end
	c.Refresh = function() if get() then c.mark:Show() else c.mark:Hide() end end
	c:SetScript("OnClick", function() set(not get()); c.Refresh() end)
	c.Refresh()
	return c
end

-- slider: min/max/step, fmt(v) for the value label
local function Slider(parent, label, min, max, step, fmt, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(W - 2 * PAD, 34)
	f.label = Text(f, 14, true)
	f.label:SetPoint("TOPLEFT", 0, 0)
	f.label:SetText(label)
	f.value = ns:CreateText(f, 14, true, "RIGHT")
	f.value:SetPoint("TOPRIGHT", 0, 0)
	local s = CreateFrame("Slider", nil, f)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(W - 2 * PAD, 10)
	s:SetPoint("BOTTOMLEFT", 0, 2)
	ns:Skin(s)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(colors.kick[1], colors.kick[2], colors.kick[3], 1)
	thumb:SetSize(10, 14)
	s:SetThumbTexture(thumb)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
	f.Refresh = function()
		s.updating = true
		s:SetValue(get())
		s.updating = false
		f.value:SetText(fmt(get()))
	end
	s:SetScript("OnValueChanged", function(self, v)
		v = floor(v / step + 0.5) * step
		f.value:SetText(fmt(v))
		if not self.updating then set(v) end
	end)
	f.Refresh()
	return f
end

local function Header(parent, text)
	local h = Text(parent, 12, true, colors.muted)
	h:SetText(text)
	return h
end

----------------------------------------------------------------------
-- The window
----------------------------------------------------------------------
local controls = {}

local function Build()
	win = CreateFrame("Frame", "AllForOneSettings", UIParent)
	win:SetSize(W, 100)
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	win:SetFrameStrata("DIALOG")
	-- same size as the 1080p design, but NOT affected by the UI-size slider (so it doesn't jump while you drag)
	win:SetScale((768 / 1080) / UIParent:GetEffectiveScale())
	win:EnableMouse(true)
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	ns:Skin(win)
	win.fill:SetTexture(0.04, 0.045, 0.05, 0.96)
	tinsert(UISpecialFrames, "AllForOneSettings") -- Esc closes it

	local title = Text(win, 18, true)
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("ALLFORONE")
	local sub = Text(win, 12, false, colors.muted)
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetText("Settings · /afo help lists every command")
	local close = Button(win, "×", 26, function() win:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 4)

	local y = 64
	local function Add(widget, h)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
		y = y + (h or widget:GetHeight()) + 8
		if widget.Refresh then controls[#controls + 1] = widget end
		return widget
	end

	Add(Header(win, "LOOK"), 14)
	Add(Slider(win, "Size of the whole UI", 0.5, 2, 0.05, function(v) return format("%d%%", v * 100 + 0.5) end,
		function() return ns.db.scale end,
		function(v) ns.db.scale = v; ns:UpdateScale() end))
	Add(Check(win, "Class-colored health bars", "off = dark bars, class-colored names",
		function() return ns.db.classColoredBars end,
		function(v) ns.db.classColoredBars = v; ns:Send("REFRESH_ALL") end))
	Add(Slider(win, "Bags + menu opacity when idle", 0, 1, 0.05, function(v) return format("%d%%", v * 100 + 0.5) end,
		function() return ns.db.menuAlpha end,
		function(v) ns.db.menuAlpha = v; ns:Send("REFRESH_ALL") end))
	Add(Check(win, "Bundled font", "turn off for Cyrillic / Asian names · reload",
		function() return ns.db.useFont end,
		function(v) ns.db.useFont = v end))

	y = y + 6
	Add(Header(win, "PARTS OF THE UI  (take effect after a reload)"), 14)
	for _, m in ipairs({ { "nameplates", "Nameplates" }, { "raid", "Raid frames (battlegrounds, raids)" }, { "actionbars", "Action bars, bags, menu, XP bar" },
		{ "minimap", "Minimap" }, { "chat", "Chat cleanup" } }) do
		Add(Check(win, m[2], nil, function() return ns.db[m[1]] end, function(v) ns.db[m[1]] = v end))
	end

	y = y + 6
	Add(Header(win, "LAYOUT AND TOOLS"), 14)
	local row1 = CreateFrame("Frame", nil, win)
	row1:SetSize(W - 2 * PAD, 26)
	local bw = (W - 2 * PAD - 16) / 3
	local unlock = Button(row1, "MOVE / RESIZE", bw, function() win:Hide(); ns:Unlock() end)
	unlock:SetPoint("LEFT", 0, 0)
	local reset = Button(row1, "RESET LAYOUT", bw, function() ns:ResetLayout() end)
	reset:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
	local test = Button(row1, "ARENA TEST", bw, function() ns:Send("TOGGLE_TEST") end)
	test:SetPoint("LEFT", reset, "RIGHT", 8, 0)
	Add(row1, 26)
	local row2 = CreateFrame("Frame", nil, win)
	row2:SetSize(W - 2 * PAD, 26)
	local procs = Button(row2, "CHOOSE PROCS", bw, function()
		win:Hide()
		if ns.ToggleProcWindow then ns:ToggleProcWindow() end
	end)
	procs:SetPoint("LEFT", 0, 0)
	local reload = Button(row2, "RELOAD UI", bw, function() ReloadUI() end)
	reload:SetPoint("LEFT", procs, "RIGHT", 8, 0)
	local bgTest = Button(row2, "BG TEST", bw, function() ns:Send("TOGGLE_TEST", "bg") end)
	bgTest:SetPoint("LEFT", reload, "RIGHT", 8, 0)
	Add(row2, 26)

	----------------------------------------------------------------
	-- Profiles: save the whole UI (layout + these settings) under a name, load it back later
	----------------------------------------------------------------
	y = y + 6
	Add(Header(win, "PROFILES  (layout + settings, shared by all your characters)"), 14)
	local saveRow = CreateFrame("Frame", nil, win)
	saveRow:SetSize(W - 2 * PAD, 26)
	local box = CreateFrame("EditBox", nil, saveRow)
	box:SetSize(W - 2 * PAD - bw - 8, 26)
	box:SetPoint("LEFT", 0, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(32)
	box:SetTextInsets(8, 8, 0, 0)
	ns:Skin(box)
	ns:Font(box, 14, true)
	box.hint = Text(box, 13, false, colors.muted)
	box.hint:SetPoint("LEFT", 8, 0)
	box.hint:SetText("Profile name, e.g. Arena 3v3")
	local function Hint() if box:GetText() == "" and not box:HasFocus() then box.hint:Show() else box.hint:Hide() end end
	box:SetScript("OnEditFocusGained", Hint)
	box:SetScript("OnEditFocusLost", Hint)
	box:SetScript("OnTextChanged", Hint)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local function SaveNow()
		if ns.SaveProfile and ns:SaveProfile(box:GetText()) then
			box:SetText("")
			box:ClearFocus()
		end
	end
	box:SetScript("OnEnterPressed", SaveNow)
	local save = Button(saveRow, "SAVE CURRENT UI", bw, SaveNow)
	save:SetPoint("LEFT", box, "RIGHT", 8, 0)
	Add(saveRow, 26)

	local listTop = y
	local MAX_ROWS = 8
	local rows = {}
	local empty = Text(win, 13, false, colors.muted)
	empty:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -listTop - 4)
	empty:SetText("No profiles yet. Set the UI up the way you like, name it, and save.")
	local more = Text(win, 12, false, colors.muted)

	local function Row(i)
		if rows[i] then return rows[i] end
		local r = CreateFrame("Frame", nil, win)
		r:SetSize(W - 2 * PAD, 24)
		r:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(listTop + (i - 1) * 28))
		r.name = Text(r, 14, true)
		r.name:SetPoint("LEFT", 0, 0)
		r.info = Text(r, 12, false, colors.muted)
		r.info:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
		r.del = Button(r, "×", 26, function(self)
			-- two clicks to delete, so a misclick can't lose a profile
			if self.armed and GetTime() - self.armed < 3 then
				self.armed = nil
				ns:DeleteProfile(r.profile)
			else
				self.armed = GetTime()
				self.text:SetText("SURE?")
				self:SetWidth(56)
			end
		end)
		r.del:SetPoint("RIGHT", 0, 0)
		r.load = Button(r, "LOAD", 64, function()
			if ns:LoadProfile(r.profile) then
				for _, c in ipairs(controls) do c.Refresh() end
			end
		end)
		r.load:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
		rows[i] = r
		return r
	end

	function win.RefreshProfiles()
		local list = ns.ListProfiles and ns:ListProfiles() or {}
		for i = 1, math.max(#rows, math.min(#list, MAX_ROWS)) do
			local p = list[i]
			if p and i <= MAX_ROWS then
				local r = Row(i)
				r.profile = p.name
				r.name:SetText(p.name)
				if p.active then
					r.name:SetTextColor(colors.kick[1], colors.kick[2], colors.kick[3])
					r.info:SetText("in use · " .. (p.saved or ""))
				else
					r.name:SetTextColor(1, 1, 1)
					r.info:SetText(p.saved or "")
				end
				r.del.armed = nil
				r.del.text:SetText("×")
				r.del:SetWidth(26)
				r:Show()
			elseif rows[i] then
				rows[i]:Hide()
			end
		end
		local shown = math.min(#list, MAX_ROWS)
		if #list == 0 then empty:Show() else empty:Hide() end
		if #list > MAX_ROWS then
			more:ClearAllPoints()
			more:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(listTop + shown * 28))
			more:SetText((#list - MAX_ROWS) .. " more - /afo profile list")
			more:Show()
		else
			more:Hide()
		end
		local listH = (#list == 0) and 22 or (shown * 28 + (#list > MAX_ROWS and 18 or 0))
		win:SetHeight(listTop + listH + PAD)
	end

	win:SetScript("OnShow", function()
		for _, c in ipairs(controls) do c.Refresh() end
		win.RefreshProfiles()
	end)
	win:Hide()
end

ns:Listen("PROFILES_CHANGED", function()
	if win and win:IsShown() then win.RefreshProfiles() end
end)

function ns:ToggleSettings()
	if not win then Build() end
	if win:IsShown() then win:Hide() else win:Show() end
end

----------------------------------------------------------------------
-- Interface -> AddOns -> AllForOne: a button that opens the window
----------------------------------------------------------------------
ns:Listen("LOGIN", function()
	if not InterfaceOptions_AddCategory then return end
	local panel = CreateFrame("Frame", "AllForOneOptionsPanel", UIParent)
	panel.name = "AllForOne"
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("AllForOne")
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	text:SetText("Minimal PvP UI. Settings live in their own window.")
	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	open:SetSize(200, 24)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	open:SetText("Open AllForOne settings")
	open:SetScript("OnClick", function()
		if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
		if GameMenuFrame then HideUIPanel(GameMenuFrame) end
		ns:ToggleSettings()
	end)
	InterfaceOptions_AddCategory(panel)
end)
