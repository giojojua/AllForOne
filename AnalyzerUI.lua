-- AllForOne: arena analyzer — report window, after-match popup, /afo analyze
local _, ns = ...
local colors = ns.colors
local A = ns.Analyzer
if not A then return end

local W, H, LIST_W, PAD = 780, 600, 220, 16
local win, popup
local selected -- match shown in the report

local KIND_LABEL = {
	trinket_early = "Trinket used early / on weak crowd control",
	trinket_held = "Sat in crowd control with trinket ready while a teammate was dying",
	died_trinket = "Died with trinket ready",
	died_def = "Died with a defensive ready",
	def_early = "Defensive used at high health",
	kick_missed = "Missed interrupts",
	kicked_ready = "Long casts into a ready interrupt",
	cc_wasted = "Wasted crowd control (immune / reflected / grounded)",
	cc_quarter = "Crowd control at a quarter duration",
	cc_broken = "Your crowd control broken early by your team",
	cc_overlap = "Overlapped a teammate's crowd control",
	out_of_range = "Out of healer range",
	focus_low = "Low damage on the kill target",
}

local function ClassHex(class)
	local r, g, b = ns:ClassColor(class)
	return format("%02x%02x%02x", r * 255, g * 255, b * 255)
end
local function ClassName(token)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token or ""]) or token or "?"
end
local function Who(p)
	local spec = p.spec and (" " .. p.spec) or ""
	return format("|cff%s%s|r", ClassHex(p.class), ClassName(p.class) .. spec)
end
local function Short(n)
	n = n or 0
	if n >= 1e6 then return format("%.1fm", n / 1e6) end
	if n >= 1e3 then return format("%.1fk", n / 1e3) end
	return tostring(floor(n))
end
local function Top(tbl, n)
	local list = {}
	for k, v in pairs(tbl or {}) do list[#list + 1] = { k = k, v = v } end
	table.sort(list, function(a, b) return a.v > b.v end)
	while #list > n do table.remove(list) end
	return list
end
local RESULT = { win = "|cff4dc764WIN|r", loss = "|cffe5484dLOSS|r", draw = "|cffd9d9d9DRAW|r", left = "|cff8b8f96LEFT|r" }

----------------------------------------------------------------------
-- Report text (a list of lines, also used by the tests)
----------------------------------------------------------------------
function A:ReportLines(m)
	local L = {}
	local function H(t) L[#L + 1] = { text = t, header = true } end
	local function T(t, muted) L[#L + 1] = { text = t, muted = muted } end
	local function Gap() L[#L + 1] = { gap = true } end

	L[#L + 1] = { text = format("%s  ·  %s  ·  %s  ·  %s", RESULT[m.result or "left"] or "?", m.map or "?",
		m.bracket and (m.bracket .. "v" .. m.bracket) or "arena", A.Fmt(m.duration or 0)), title = true }
	T(m.date or "", true)
	local us, them = {}, {}
	for _, p in ipairs(m.teamInfo or {}) do us[#us + 1] = Who(p) end
	for _, e in ipairs(m.enemies or {}) do them[#them + 1] = Who(e) end
	T("You: " .. table.concat(us, ", "))
	T("Them: " .. table.concat(them, ", "))
	Gap()

	H("NOTES")
	if #(m.notes or {}) == 0 then
		T("No mistakes spotted in what the addon can see.", true)
	else
		for _, n in ipairs(m.notes) do T("• " .. n.text) end
	end
	Gap()

	H("DEATHS")
	if #(m.deaths or {}) == 0 then T("Nobody died.", true) end
	for _, d in ipairs(m.deaths or {}) do
		local side = d.side == "us" and "|cffe5484d(your team)|r" or "|cff4dc764(enemy)|r"
		T(format("%s  %s died %s%s", A.Fmt(d.t), d.class and format("|cff%s%s|r", ClassHex(d.class), d.name) or d.name, side, d.first and "  · first death" or ""))
		local r = d.recap
		if r then
			if r.total > 0 then
				local parts = {}
				for _, x in ipairs(Top(r.dmg, 3)) do parts[#parts + 1] = x.k .. " " .. Short(x.v) end
				T("    last 10s: " .. Short(r.total) .. " damage — " .. table.concat(parts, ", "), true)
			end
			if #r.cc > 0 then T("    crowd control: " .. table.concat(r.cc, ", "), true) end
			if #r.cds > 0 then T("    cooldowns used: " .. table.concat(r.cds, ", "), true) end
			if r.trinket then T("    used their trinket", true) end
		end
	end
	Gap()

	local cc = m.cc or {}
	H("CROWD CONTROL")
	local parts = {}
	for _, x in ipairs(Top(cc.onMe, 6)) do parts[#parts + 1] = format("%s %ds", x.k, floor(x.v + 0.5)) end
	T(format("On you: %ds%s", floor((cc.onMeTime or 0) + 0.5), #parts > 0 and ("  (" .. table.concat(parts, ", ") .. ")") or ""))
	T(format("Yours: %d landed, %ds total  ·  wasted %d  ·  quarter duration %d  ·  broken by team %d  ·  overlaps %d",
		cc.mine or 0, floor((cc.mineTime or 0) + 0.5), cc.wasted or 0, cc.quarter or 0, cc.broken or 0, cc.overlap or 0))
	Gap()

	H("TRINKET AND DEFENSIVES")
	local tr = m.trinket or {}
	if #(tr.uses or {}) == 0 then T("Trinket not used.", true) end
	for _, u in ipairs(tr.uses or {}) do
		T(format("%s  trinket%s", A.Fmt(u.t), u.cc and format(" on %s%s", u.cc, u.left and format(" (%.1fs left)", u.left) or "") or " (no crowd control)"))
	end
	for _, d in ipairs((m.defs and m.defs.used) or {}) do
		T(format("%s  %s at %d%% health", A.Fmt(d.t), d.spell, floor(d.hp * 100 + 0.5)))
	end
	Gap()

	local k = m.kicks or {}
	H("INTERRUPTS")
	local avg
	if k.reaction and #k.reaction > 0 then
		local s = 0
		for _, v in ipairs(k.reaction) do s = s + v end
		avg = s / #k.reaction
	end
	T(format("Yours: %d used  ·  %d landed (%d heals, %d crowd control, %d damage)  ·  %d missed%s",
		k.cast or 0, k.landed or 0, k.onHeal or 0, k.onCC or 0, k.onDamage or 0, k.missed or 0,
		avg and format("  ·  on average %d%% into the cast", floor(avg * 100 + 0.5)) or ""))
	T(format("On you: %d  ·  %d were long casts started while their interrupt was ready", k.taken or 0, k.takenIntoReady or 0))
	Gap()

	local dmg, heal = m.dmg or {}, m.heal or {}
	H("DAMAGE AND HEALING")
	parts = {}
	for _, x in ipairs(Top(dmg.doneOn, 4)) do
		parts[#parts + 1] = format("%s %d%%", x.k, dmg.done > 0 and floor(x.v / dmg.done * 100 + 0.5) or 0)
	end
	T(format("Done: %s%s", Short(dmg.done), #parts > 0 and ("  (" .. table.concat(parts, ", ") .. ")") or ""))
	if dmg.onKillPct then T(format("On the marked kill target: %d%%", floor(dmg.onKillPct * 100 + 0.5))) end
	parts = {}
	for _, x in ipairs(Top(dmg.takenFrom, 4)) do parts[#parts + 1] = x.k .. " " .. Short(x.v) end
	T(format("Taken: %s%s", Short(dmg.taken), #parts > 0 and ("  (" .. table.concat(parts, ", ") .. ")") or ""))
	if (dmg.burst or 0) > 0 then
		parts = {}
		for _, x in ipairs(Top(dmg.burstSpells, 3)) do parts[#parts + 1] = x.k end
		T(format("Biggest burst on you: %s in 3s at %s (%s)", Short(dmg.burst), A.Fmt(dmg.burstAt or 0), table.concat(parts, ", ")))
	end
	T(format("Healing: %s done (%d%% overheal)  ·  %s received", Short(heal.done),
		(heal.done or 0) > 0 and floor((heal.over or 0) / heal.done * 100 + 0.5) or 0, Short(heal.received)))
	local dp = m.dispels or {}
	T(format("Dispels: %d on your team  ·  %d purges  ·  %d by the enemy on your team", dp.cleanse or 0, dp.purge or 0, dp.enemy or 0))
	Gap()

	local rg = m.range or {}
	H("RANGE")
	T(format("In combat %ds  ·  out of your healer's range %ds  ·  teammates out of your range %ds  ·  no enemy targeted %ds",
		rg.combat or 0, rg.outHealer or 0, rg.mateOut or 0, rg.noTarget or 0))
	Gap()

	H("ENEMIES")
	for _, e in ipairs(m.enemies or {}) do
		local bits = {}
		if e.died then bits[#bits + 1] = e.diedFirst and "died first" or "died" end
		if e.ttd then bits[#bits + 1] = format("went down in %ds", floor(e.ttd + 0.5)) end
		if (e.trinkets or 0) > 0 then bits[#bits + 1] = (e.trinketEarly or 0) > 0 and "trinketed early" or "trinketed" end
		local defs = {}
		for s in pairs(e.defUsed or {}) do defs[#defs + 1] = s end
		if #defs > 0 then bits[#bits + 1] = "used " .. table.concat(defs, ", ") end
		if e.unusedDef then bits[#bits + 1] = "died with a defensive unused" end
		if (e.ccTime or 0) > 0 then bits[#bits + 1] = format("crowd-controlled %ds", floor(e.ccTime + 0.5)) end
		T(format("#%s %s %s — %s", e.n or "?", e.name or "?", Who(e), #bits > 0 and table.concat(bits, " · ") or "nothing notable"))
	end
	Gap()

	H("TIMELINE")
	if #(m.timeline or {}) == 0 then T("—", true) end
	for _, t in ipairs(m.timeline or {}) do T(A.Fmt(t.t) .. "  " .. t.text, true) end
	Gap()

	local tr2 = A:Trends()
	if tr2.games > 0 then
		H(format("TRENDS  (your last %d arenas)", tr2.games))
		T(format("Win rate %d%%  ·  %d wins, %d losses", floor(tr2.wins / tr2.games * 100 + 0.5), tr2.wins, tr2.games - tr2.wins))
		T(format("Crowd-controlled %ds per game on average  ·  interrupts landed %d%%",
			floor(tr2.ccOnMe / tr2.games + 0.5), tr2.kicksCast > 0 and floor(tr2.kicksLanded / tr2.kicksCast * 100 + 0.5) or 0))
		local comps = {}
		for comp, c in pairs(tr2.comps) do comps[#comps + 1] = { comp = comp, c = c } end
		table.sort(comps, function(a, b) return a.c.games > b.c.games end)
		for i = 1, math.min(6, #comps) do
			local x = comps[i]
			local names = {}
			for token in x.comp:gmatch("[^+]+") do names[#names + 1] = format("|cff%s%s|r", ClassHex(token), ClassName(token)) end
			T(format("vs %s: %d–%d", table.concat(names, " + "), x.c.wins, x.c.games - x.c.wins))
		end
		local reps = {}
		for kind, n in pairs(tr2.mistakes) do if n >= 2 then reps[#reps + 1] = { kind = kind, n = n } end end
		table.sort(reps, function(a, b) return a.n > b.n end)
		for _, r in ipairs(reps) do
			T(format("|cfff2b33dRepeat:|r %s — %d of your last %d games", KIND_LABEL[r.kind] or r.kind, r.n, tr2.last))
		end
	end
	return L
end

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local lines, listButtons = {}, {}
local content, list

local function Button(parent, label, w, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, 24)
	ns:Skin(b)
	b.text = ns:CreateText(b, 12, true, "CENTER")
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function() b.text:SetTextColor(colors.kick[1], colors.kick[2], colors.kick[3]) end)
	b:SetScript("OnLeave", function() b.text:SetTextColor(1, 1, 1) end)
	return b
end

-- A scroll area with a thin scroll bar on its right edge (drag it, click the track,
-- or use the mouse wheel anywhere over the area).
local BAR_W = 8
local function Scroll(parent, w, h)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	sf:SetSize(w - BAR_W - 6, h)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(w - BAR_W - 6, 10)
	sf:SetScrollChild(child)

	local bar = CreateFrame("Slider", nil, parent)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(BAR_W)
	bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 0)
	ns:Skin(bar)
	local thumb = bar:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(colors.muted[1], colors.muted[2], colors.muted[3], 1)
	thumb:SetSize(BAR_W, 40)
	bar:SetThumbTexture(thumb)
	bar:SetValueStep(1)
	bar:SetMinMaxValues(0, 0)
	bar:SetValue(0)
	bar:EnableMouseWheel(true)
	bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)

	-- range + thumb size follow the content height
	function sf:UpdateBar()
		local max = math.max(0, child:GetHeight() - self:GetHeight())
		bar:SetMinMaxValues(0, max)
		thumb:SetHeight(math.max(24, h * h / math.max(h, child:GetHeight())))
		if max == 0 then bar:Hide() else bar:Show() end
		if bar:GetValue() > max then bar:SetValue(max) end
	end
	function sf:ScrollTo(v)
		bar:SetValue(v)
		self:SetVerticalScroll(v)
	end
	local function Wheel(_, delta)
		local _, max = bar:GetMinMaxValues()
		local v = math.max(0, math.min(max, bar:GetValue() - delta * 40))
		bar:SetValue(v)
	end
	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", Wheel)
	bar:SetScript("OnMouseWheel", Wheel)
	sf.child, sf.bar = child, bar
	return sf
end

local function ShowReport(m)
	selected = m
	local child = content.child
	local width = child:GetWidth()
	for _, fs in ipairs(lines) do fs:Hide() end
	if not m then content:UpdateBar(); content:ScrollTo(0) return end
	local y = 0
	local i = 0
	for _, l in ipairs(A:ReportLines(m)) do
		if l.gap then
			y = y + 10
		else
			i = i + 1
			local fs = lines[i]
			if not fs then
				fs = child:CreateFontString(nil, "OVERLAY")
				fs:SetJustifyH("LEFT")
				fs:SetJustifyV("TOP")
				lines[i] = fs
			end
			ns:Font(fs, l.title and 18 or (l.header and 12 or 13), l.title or l.header)
			fs:SetWidth(width)
			fs:SetText(l.text)
			if l.header then fs:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
			elseif l.muted then fs:SetTextColor(0.72, 0.73, 0.75)
			else fs:SetTextColor(1, 1, 1) end
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
			local lineH = (l.title and 22) or (l.header and 16) or 17
			local wraps = math.max(1, ceil((fs:GetStringWidth() or 0) / math.max(1, width)))
			fs:SetHeight(lineH * wraps)
			fs:Show()
			y = y + lineH * wraps + (l.header and 4 or 1)
		end
	end
	child:SetHeight(y + 10)
	content:UpdateBar()
	content:ScrollTo(0)
	for _, b in ipairs(listButtons) do
		if b.match == m then b.fill:SetTexture(0.16, 0.17, 0.19, 1) else b.fill:SetTexture(colors.bg[1], colors.bg[2], colors.bg[3], 1) end
	end
end

local function FillList(extra)
	local matches = {}
	if extra then matches[1] = extra end
	local stored = A:Matches()
	for i = #stored, 1, -1 do matches[#matches + 1] = stored[i] end
	local child = list.child
	for _, b in ipairs(listButtons) do b:Hide() end
	for i, m in ipairs(matches) do
		local b = listButtons[i]
		if not b then
			b = CreateFrame("Button", nil, child)
			b:SetSize(LIST_W - BAR_W - 8, 40)
			ns:Skin(b)
			b.top = ns:CreateText(b, 13, true, "LEFT")
			b.top:SetPoint("TOPLEFT", 6, -5)
			b.top:SetPoint("RIGHT", -6, 0)
			b.bottom = ns:CreateText(b, 11, false, "LEFT")
			b.bottom:SetPoint("BOTTOMLEFT", 6, 5)
			b.bottom:SetPoint("RIGHT", -6, 0)
			b:SetScript("OnClick", function(self) ShowReport(self.match) end)
			listButtons[i] = b
		end
		b.match = m
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 44)
		b.top:SetText(format("%s  %s  %s", RESULT[m.result or "left"] or "?", A.Fmt(m.duration or 0), m.test and "|cfff2b33dSAMPLE|r" or (m.map or "")))
		local names = {}
		for _, e in ipairs(m.enemies or {}) do names[#names + 1] = format("|cff%s%s|r", ClassHex(e.class), ClassName(e.class)) end
		b.bottom:SetText(table.concat(names, " "))
		b:Show()
	end
	child:SetHeight(math.max(10, #matches * 44))
	list:UpdateBar()
	return matches
end

local function Build()
	win = CreateFrame("Frame", "AllForOneAnalyzer", UIParent)
	win:SetSize(W, H)
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	win:SetScale((768 / 1080) / UIParent:GetEffectiveScale())
	win:SetFrameStrata("DIALOG")
	win:EnableMouse(true)
	win:SetMovable(true)
	win:SetClampedToScreen(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	ns:Skin(win)
	win.fill:SetTexture(0.04, 0.045, 0.05, 0.97)
	tinsert(UISpecialFrames, "AllForOneAnalyzer")

	local title = ns:CreateText(win, 18, true, "LEFT")
	title:SetPoint("TOPLEFT", PAD, -PAD)
	title:SetText("ARENA ANALYZER")
	local sub = ns:CreateText(win, 12, false, "LEFT")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	sub:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	sub:SetText("Your last 50 arenas · notes are hints from what the addon can see, not a grade")
	local close = Button(win, "×", 24, function() win:Hide() end)
	close:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 4)

	local top = 62
	list = Scroll(win, LIST_W, H - top - PAD)
	list:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -top)
	content = Scroll(win, W - LIST_W - 3 * PAD, H - top - PAD)
	content:SetPoint("TOPLEFT", list, "TOPRIGHT", PAD + BAR_W + 6, 0)
	content.child:SetWidth(W - LIST_W - 3 * PAD - BAR_W - 6)

	win.empty = ns:CreateText(content.child, 14, false, "LEFT")
	win.empty:SetPoint("TOPLEFT", 0, 0)
	win.empty:SetWidth(W - LIST_W - 3 * PAD - BAR_W - 6)
	win.empty:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
	win.empty:SetText("No arenas recorded yet. Play an arena match and the report shows up here.\n\n/afo analyze test shows a sample report.")
	win:Hide()
end

function A:Open(m, extra)
	if not win then Build() end
	local matches = FillList(extra)
	m = m or matches[1]
	if m then win.empty:Hide() else win.empty:Show() end
	ShowReport(m)
	win:Show()
end

function A:Toggle()
	if win and win:IsShown() then win:Hide() else A:Open() end
end

----------------------------------------------------------------------
-- After a match: a small popup with the headline
----------------------------------------------------------------------
local function ShowPopup(m)
	if ns.db.analyzerPopup == false then return end
	if not popup then
		popup = CreateFrame("Frame", nil, ns.root)
		popup:SetSize(420, 34)
		popup:SetPoint("TOP", ns.root, "TOP", 0, -160)
		popup:SetFrameStrata("HIGH")
		ns:Skin(popup)
		popup.fill:SetTexture(0.04, 0.045, 0.05, 0.95)
		popup.text = ns:CreateText(popup, 14, true, "LEFT")
		popup.text:SetPoint("LEFT", 12, 0)
		popup.open = Button(popup, "OPEN REPORT", 110, function() popup:Hide(); A:Open(popup.match) end)
		popup.open:SetPoint("RIGHT", -38, 0)
		popup.close = Button(popup, "×", 24, function() popup:Hide() end)
		popup.close:SetPoint("RIGHT", -6, 0)
		popup:SetScript("OnUpdate", function(self, e)
			self.left = (self.left or 0) - e
			if self.left <= 0 then self:Hide() end
		end)
	end
	popup.match = m
	local n = #(m.notes or {})
	popup.text:SetText(format("MATCH REPORT  ·  %s  %s  ·  %d note%s", RESULT[m.result or "left"] or "?", A.Fmt(m.duration or 0), n, n == 1 and "" or "s"))
	popup.left = 30
	popup:Show()
end

ns:Listen("ANALYZER_MATCH", function(m) ShowPopup(m) end)

----------------------------------------------------------------------
-- Sample report (/afo analyze test): not saved
----------------------------------------------------------------------
function A:Sample()
	local _, myClass = UnitClass("player")
	local m = {
		test = true, date = date("%Y-%m-%d %H:%M"), map = "Nagrand Arena", bracket = 3, duration = 163, result = "loss",
		myClass = myClass, mySpec = nil, comp = "PALADIN+ROGUE+WARRIOR",
		teamInfo = { { name = UnitName("player"), class = myClass }, { name = "Lumen", class = "PRIEST", spec = "Discipline" }, { name = "Shade", class = "ROGUE", spec = "Subtlety" } },
		enemies = {
			{ n = 1, name = "Grimtusk", class = "WARRIOR", spec = "Arms", died = false, trinkets = 1, trinketEarly = 1, defUsed = {}, ccTime = 14, dmgTaken = 52000 },
			{ n = 2, name = "Vex", class = "ROGUE", spec = "Subtlety", trinkets = 1, trinketEarly = 0, defUsed = { ["Cloak of Shadows"] = true }, ccTime = 9, dmgTaken = 31000 },
			{ n = 3, name = "Valor", class = "PALADIN", spec = "Holy", trinkets = 0, trinketEarly = 0, defUsed = {}, ccTime = 22, dmgTaken = 18000 },
		},
		notes = {
			{ kind = "trinket_held", text = "Sat in Fear (8s) with your trinket ready while Lumen was at 21% (2:31)", w = 3 },
			{ kind = "died_def", text = "You died with Ice Block ready", w = 3 },
			{ kind = "kicked_ready", text = "You were interrupted 3 times; 2 were long casts started while their interrupt was ready - fake-cast first", w = 2 },
			{ kind = "cc_wasted", text = "1 of your crowd controls were wasted: 1 immune (diminishing returns)", w = 2 },
		},
		deaths = {
			{ name = "Lumen", class = "PRIEST", side = "us", t = 158, first = true,
				recap = { total = 24800, dmg = { ["Mortal Strike (Grimtusk)"] = 9100, ["Eviscerate (Vex)"] = 7400, ["Melee (Grimtusk)"] = 5200 },
					cc = { "Fear on " .. (UnitName("player") or "you"), "Kidney Shot on them" }, cds = { "Pain Suppression" } } },
		},
		cc = { onMe = { fear = 12, stun = 7, incap = 4 }, onMeTime = 23, mine = 7, mineTime = 26, wasted = 1, immune = 1, reflected = 0, grounded = 0, quarter = 1, broken = 1, overlap = 0 },
		trinket = { uses = { { t = 41, cc = "Kidney Shot", left = 3.2 } } },
		defs = { used = {} },
		kicks = { cast = 5, landed = 3, missed = 2, onHeal = 2, onCC = 1, onDamage = 0, reaction = { 0.55, 0.7, 0.62 }, taken = 3, takenIntoReady = 2 },
		dmg = { done = 61000, doneOn = { Grimtusk = 30000, Vex = 21000, Valor = 10000 }, onKill = 30000, onKillPct = 0.49, taken = 47000,
			takenFrom = { ["Mortal Strike"] = 14000, Eviscerate = 9000, Melee = 12000 }, burst = 11800, burstAt = 154, burstSpells = { ["Mortal Strike"] = 6000, Overpower = 3000, Melee = 2800 } },
		heal = { done = 4000, over = 900, received = 38000 },
		dispels = { cleanse = 0, purge = 2, enemy = 3 },
		range = { combat = 150, outHealer = 31, mateOut = 0, noTarget = 6 },
		timeline = { { t = 0, text = "Gates open" }, { t = 41, text = "You trinketed Kidney Shot" }, { t = 77, text = "#2 Vex used Cloak of Shadows" },
			{ t = 120, text = "#1 Grimtusk trinketed" }, { t = 151, text = "You interrupted Flash of Light" }, { t = 158, text = "Lumen died" } },
	}
	A:Open(m, m)
end

----------------------------------------------------------------------
-- /afo analyze [test | reset]
----------------------------------------------------------------------
local resetAsked = 0
function ns:AnalyzeCommand(arg)
	arg = strlower(strtrim(arg or ""))
	if arg == "test" then
		A:Sample()
	elseif arg == "reset" then
		if GetTime() - resetAsked < 10 then
			A:Reset()
			resetAsked = 0
			ns:Print("arena history deleted")
			if win and win:IsShown() then A:Open() end
		else
			resetAsked = GetTime()
			ns:Print("this deletes all recorded arenas - type /afo analyze reset again within 10 seconds to confirm")
		end
	else
		A:Toggle()
	end
end
