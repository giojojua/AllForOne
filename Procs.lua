-- AllForOne: which procs to show, and the /afo procs window
-- Nothing is tracked by default. Add procs in the window (or with /afo procs add ...).
-- Saved per character in AllForOneDB.procs.chars["Name-Realm"]: lower-case name -> { name, icon }
local _, ns = ...
local colors = ns.colors

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- procs that belong to another class (so a shared old list doesn't give a warrior Hot Streak)
local function OtherClassProc(key, myClass)
	for class, list in pairs(ns.ProcSuggest or {}) do
		if class ~= myClass then
			for _, s in ipairs(list) do if strlower(s.name) == key then return true end end
		end
	end
	return false
end

local function List()
	ns.db.procs = ns.db.procs or {}
	local db = ns.db.procs
	-- the earlier command-only version
	if db.added then
		db.list = db.list or {}
		for key, name in pairs(db.added) do db.list[key] = { name = name } end
		db.added, db.removed = nil, nil
	end
	db.chars = db.chars or {}
	local me = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	local mine = db.chars[me]
	if not mine then
		-- spell names aren't known before login: don't build (and save) the list yet
		if not (ns.ProcSuggest and next(ns.ProcSuggest)) then return {} end
		-- first time on this character: start from the old shared list, minus other classes' procs
		mine = {}
		local _, class = UnitClass("player")
		for key, e in pairs(db.list or {}) do
			if not OtherClassProc(key, class) then mine[key] = { name = e.name, icon = e.icon } end
		end
		db.chars[me] = mine
	end
	return mine
end

-- Short buffs that showed up on you (trinket procs, enchant procs...), newest first, per
-- character: they're listed in the window so you can track one that isn't up right now.
local function Seen()
	ns.db.procs = ns.db.procs or {}
	local db = ns.db.procs
	db.seen = db.seen or {}
	local me = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
	db.seen[me] = db.seen[me] or {}
	return db.seen[me]
end

function ns:NoteSeenBuff(name, icon, duration)
	-- procs last a few seconds to a minute; skip long buffs and permanent ones
	if not name or not duration or duration <= 0 or duration > 60 then return end
	local seen = Seen()
	for i, e in ipairs(seen) do
		if e.name == name then table.remove(seen, i) break end
	end
	table.insert(seen, 1, { name = name, icon = icon })
	while #seen > 12 do table.remove(seen) end
end

-- the buff your equipped trinkets give when you use them (on-use trinkets)
local function TrinketBuffs()
	local out = {}
	for slot = 13, 14 do
		local link = GetInventoryItemLink("player", slot)
		local spell = link and GetItemSpell and GetItemSpell(link)
		if spell and not (ns.Trinket and ns.Trinket[spell]) then -- not the PvP trinket
			local _, _, icon = GetSpellInfo(spell)
			out[#out + 1] = { name = spell, icon = icon or GetInventoryItemTexture("player", slot) }
		end
	end
	return out
end

function ns:IsProc(name)
	return name ~= nil and List()[strlower(name)] ~= nil
end

-- the first time a tracked proc actually shows up, remember its icon for the window
function ns:RememberProcIcon(name, icon)
	local e = List()[strlower(name)]
	if e and not e.icon and icon then e.icon = icon end
end

local Refresh -- window refresh, set below

local function AddProc(name, icon)
	if not name or name == "" then return end
	List()[strlower(name)] = { name = name, icon = icon }
	if ns.ScanPlayer then ns.ScanPlayer() end
	if Refresh then Refresh() end
end

local function RemoveProc(name)
	List()[strlower(name)] = nil
	if ns.ScanPlayer then ns.ScanPlayer() end
	if Refresh then Refresh() end
end

-- "Hot Streak" or a spell ID like "48108" -> name, icon
local function Resolve(text)
	text = strtrim(text or "")
	if text == "" then return end
	local id = tonumber(text)
	if id then
		local name, _, icon = GetSpellInfo(id)
		return name, icon
	end
	-- try to find a matching icon among suggestions and your current buffs
	local _, class = UnitClass("player")
	for _, s in ipairs(ns.ProcSuggest[class] or {}) do
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
-- Window
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

-- one row: icon | name | action button (× remove or + add)
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

local pools = { tracked = {}, suggest = {}, buffs = {}, trinkets = {}, seen = {} }

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

	-- tracked, sorted by name
	local tracked = {}
	for _, e in pairs(list) do tracked[#tracked + 1] = e end
	table.sort(tracked, function(a, b) return a.name < b.name end)

	-- suggestions for your class that you don't track yet
	local _, class = UnitClass("player")
	local suggest = {}
	for _, s in ipairs(ns.ProcSuggest[class] or {}) do
		if not list[strlower(s.name)] then suggest[#suggest + 1] = s end
	end

	-- buffs on you right now that you don't track yet
	local buffs, seen = {}, {}
	for i = 1, 40 do
		local name, _, icon = UnitAura("player", i, "HELPFUL")
		if not name then break end
		if not list[strlower(name)] and not seen[name] and #buffs < 8 then
			seen[name] = true
			buffs[#buffs + 1] = { name = name, icon = icon }
		end
	end

	local y = 96
	panel.hTracked:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.tracked, tracked, y, "×", function(e) RemoveProc(e.name) end,
		"Nothing yet. Add a proc below or type its name above.") + 10
	panel.hSuggest:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.suggest, suggest, y, "+", function(e) AddProc(e.name, e.icon) end,
		"No more suggestions for your class.") + 10
	-- your trinkets (on-use) and short buffs seen on you lately (trinket / enchant procs)
	local trinkets, tseen = {}, {}
	for _, e in ipairs(TrinketBuffs()) do
		if not list[strlower(e.name)] and not tseen[e.name] then tseen[e.name] = true; trinkets[#trinkets + 1] = e end
	end
	local recent = {}
	for _, e in ipairs(Seen()) do
		if not list[strlower(e.name)] and not seen[e.name] and not tseen[e.name] then recent[#recent + 1] = e end
		if #recent >= 6 then break end
	end
	panel.hTrinkets:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.trinkets, trinkets, y, "+", function(e) AddProc(e.name, e.icon) end,
		"No on-use trinket equipped.") + 10
	panel.hSeen:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.seen, recent, y, "+", function(e) AddProc(e.name, e.icon) end,
		"Nothing yet: trinket and enchant procs show up here after they fire once.") + 10
	panel.hBuffs:SetPoint("TOPLEFT", PAD, -y); y = y + 20
	y = Fill(pools.buffs, buffs, y, "+", function(e) AddProc(e.name, e.icon) end,
		"No other buffs on you right now.") + PAD
	panel:SetHeight(y)
end

local function CreatePanel()
	panel = CreateFrame("Frame", "AllForOneProcWindow", UIParent)
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
	tinsert(UISpecialFrames, "AllForOneProcWindow") -- Esc closes it

	local title = ns:CreateText(panel, 18, true, "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("PROCS")
	local sub = ns:CreateText(panel, 12, false, "LEFT")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	sub:SetText("This character's procs · glowing icons next to your character")
	local close = Button(panel, "×", 24, 24, function() panel:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 4)

	-- add box: name or spell ID, Enter to add
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
		if name then AddProc(name, icon) end
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
	panel.hTrinkets = Header(panel, "YOUR TRINKETS (ON USE)")
	panel.hSeen = Header(panel, "PROCS SEEN ON YOU LATELY (TRINKETS, ENCHANTS)")

	panel:SetScript("OnShow", Refresh)
	panel:RegisterEvent("UNIT_AURA")
	panel:SetScript("OnEvent", function(_, _, unit) if unit == "player" then Refresh() end end)
	panel:Hide()
end

function ns:ToggleProcWindow()
	if not panel then CreatePanel() end
	if panel:IsShown() then panel:Hide() else panel:Show(); Refresh() end
end

----------------------------------------------------------------------
-- /afo procs [add|remove|reset ...]  (no arguments opens the window)
----------------------------------------------------------------------
function ns:ProcCommand(arg)
	local action, rest = strsplit(" ", strtrim(arg or ""), 2)
	action = strlower(action or "")
	if action == "add" and rest and rest ~= "" then
		local name, icon = Resolve(rest)
		if not name then ns:Print("no spell with that ID") return end
		AddProc(name, icon)
		ns:Print("now tracking proc:", name)
	elseif (action == "remove" or action == "del") and rest and rest ~= "" then
		local name = Resolve(rest)
		if name then RemoveProc(name); ns:Print("stopped tracking proc:", name) end
	elseif action == "reset" then
		wipe(List())
		if ns.ScanPlayer then ns.ScanPlayer() end
		if Refresh then Refresh() end
		ns:Print("proc list of this character cleared")
	else
		ns:ToggleProcWindow()
	end
end
