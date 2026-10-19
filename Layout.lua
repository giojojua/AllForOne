-- AllForOne: move + resize mode
-- Every part of the UI registers here with its default position.
-- /afo unlock shows a box over each part: drag to move, mouse wheel to resize,
-- right-click to put that part back. /afo lock saves (per character). /afo reset restores everything.
local _, ns = ...
local colors = ns.colors

local movers = {}      -- key -> mover
local order = {}       -- keys in registration order
local unlocked = false
local startedTest = false

local function CharKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function Saved()
	ns.db.layouts = ns.db.layouts or {}
	local key = CharKey()
	ns.db.layouts[key] = ns.db.layouts[key] or {}
	return ns.db.layouts[key]
end

local function ApplyDefault(m)
	local f = m.frame
	f:SetScale(1)
	f:ClearAllPoints()
	f:SetPoint(m.point, ns.root, m.relPoint, m.x, m.y)
	ns:Send("LAYOUT_CHANGED", m.key)
end

-- saved positions are the frame's center in root units, relative to the root's center
local function Apply(m)
	local s = Saved()[m.key]
	if not s then ApplyDefault(m) return end
	local f = m.frame
	local scale = s.s or 1
	f:SetScale(scale)
	f:ClearAllPoints()
	f:SetPoint("CENTER", ns.root, "CENTER", s.x / scale, s.y / scale)
	ns:Send("LAYOUT_CHANGED", m.key)
end

local function Store(m, scale)
	local f = m.frame
	local cx, cy = f:GetCenter()
	local rx, ry = ns.root:GetCenter()
	if not cx or not rx then return end
	local k = f:GetEffectiveScale() / ns.root:GetEffectiveScale()
	Saved()[m.key] = { x = cx * k - rx, y = cy * k - ry, s = scale or f:GetScale() }
	Apply(m)
end

-- Register a movable part. point/relPoint/x/y = default anchor on the root.
function ns:Mover(key, label, frame, point, relPoint, x, y)
	local m = { key = key, label = label, frame = frame, point = point, relPoint = relPoint or point, x = x or 0, y = y or 0 }
	movers[key] = m
	order[#order + 1] = key
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	ns:SafeCall(function() Apply(m) end)
	return frame
end

function ns:ApplyLayout()
	ns:SafeCall(function()
		for _, key in ipairs(order) do Apply(movers[key]) end
	end)
end

----------------------------------------------------------------------
-- Unlock overlays
----------------------------------------------------------------------
local hint, zone

local function Overlay(m)
	if m.overlay then return m.overlay end
	local o = CreateFrame("Frame", nil, ns.root)
	o:SetFrameStrata("DIALOG")
	o:SetAllPoints(m.frame)
	o:EnableMouse(true)
	o:EnableMouseWheel(true)
	o:RegisterForDrag("LeftButton")
	local fill = o:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(o)
	fill:SetTexture(colors.kick[1], colors.kick[2], colors.kick[3], 0.18)
	o.fill = fill
	for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
		local t = o:CreateTexture(nil, "BORDER")
		t:SetTexture(colors.kick[1], colors.kick[2], colors.kick[3], 0.9)
		t:SetPoint(p[1]); t:SetPoint(p[2])
		if p[3] then t:SetHeight(1) else t:SetWidth(1) end
	end
	o.label = ns:CreateText(o, 12, true, "CENTER")
	o.label:SetPoint("CENTER")
	local function Label()
		o.label:SetText(m.label .. "  " .. format("%d%%", floor(m.frame:GetScale() * 100 + 0.5)))
	end
	o.Refresh = Label
	o:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		m.frame:StartMoving()
	end)
	o:SetScript("OnDragStop", function()
		m.frame:StopMovingOrSizing()
		if m.frame.SetUserPlaced then m.frame:SetUserPlaced(false) end
		if not InCombatLockdown() then Store(m) end
		Label()
	end)
	o:SetScript("OnMouseWheel", function(_, delta)
		if InCombatLockdown() then return end
		local scale = math.max(0.5, math.min(2, m.frame:GetScale() + delta * 0.05))
		-- keep the part centered where it is while it grows/shrinks
		local cx, cy = m.frame:GetCenter()
		local rx, ry = ns.root:GetCenter()
		local k = m.frame:GetEffectiveScale() / ns.root:GetEffectiveScale()
		if not cx then return end
		Saved()[m.key] = { x = cx * k - rx, y = cy * k - ry, s = scale }
		Apply(m)
		Label()
	end)
	o:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and not InCombatLockdown() then
			Saved()[m.key] = nil
			Apply(m)
			Label()
		end
	end)
	o:SetScript("OnEnter", function() fill:SetTexture(colors.kick[1], colors.kick[2], colors.kick[3], 0.35) end)
	o:SetScript("OnLeave", function() fill:SetTexture(colors.kick[1], colors.kick[2], colors.kick[3], 0.18) end)
	m.overlay = o
	return o
end

local function ShowHelpers(on)
	if not hint then
		hint = CreateFrame("Frame", nil, ns.root)
		hint:SetFrameStrata("DIALOG")
		hint:SetSize(900, 30)
		hint:SetPoint("TOP", ns.root, "TOP", 0, -64)
		hint.text = ns:CreateText(hint, 15, true, "CENTER")
		hint.text:SetPoint("CENTER")
		hint.text:SetText("Drag to move · mouse wheel to resize · right-click to reset a part · /afo lock when done")
		-- the keep-clear zone around your character
		zone = CreateFrame("Frame", nil, ns.root)
		zone:SetFrameStrata("BACKGROUND")
		zone:SetSize(340, 350)
		zone:SetPoint("CENTER", ns.root, "CENTER", 0, -5)
		local t = zone:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints(zone)
		t:SetTexture(1, 1, 1, 0.06)
		zone.text = ns:CreateText(zone, 12, true, "CENTER")
		zone.text:SetPoint("BOTTOM", 0, 10)
		zone.text:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
		zone.text:SetText("YOUR CHARACTER · KEEP CLEAR")
	end
	if on then hint:Show(); zone:Show() else hint:Hide(); zone:Hide() end
end

function ns:Unlock()
	if InCombatLockdown() then ns:Print("can't move frames during combat") return end
	if unlocked then return end
	unlocked = true
	if not ns.testing then
		startedTest = true
		ns:Send("TOGGLE_TEST")
	end
	for _, key in ipairs(order) do
		local o = Overlay(movers[key])
		o:Refresh()
		o:Show()
	end
	ShowHelpers(true)
	ns:Print("move mode on - drag to move, mouse wheel to resize, right-click to reset; /afo lock when done")
end

function ns:Lock()
	if not unlocked then return end
	unlocked = false
	for _, key in ipairs(order) do
		local m = movers[key]
		if m.overlay then m.overlay:Hide() end
	end
	ShowHelpers(false)
	if startedTest and ns.testing and not InCombatLockdown() then ns:Send("TOGGLE_TEST") end
	startedTest = false
	ns:Print("layout saved")
end

function ns:ResetLayout()
	if InCombatLockdown() then ns:Print("can't move frames during combat") return end
	ns.db.layouts = ns.db.layouts or {}
	ns.db.layouts[CharKey()] = {}
	ns:ApplyLayout()
	for _, key in ipairs(order) do
		local m = movers[key]
		if m.overlay then m.overlay:Refresh() end
	end
	ns:Print("layout reset to default")
end

-- combat starts while unlocked: stop moving things
ns:On("PLAYER_REGEN_DISABLED", function() if unlocked then ns:Lock() end end)
