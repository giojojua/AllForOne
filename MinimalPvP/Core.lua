-- MinimalPvP: core (namespace, events, settings, pixel root, Blizzard hiding)
local ADDON, ns = ...
ns.name = ADDON

----------------------------------------------------------------------
-- Event dispatcher + internal message bus
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		eventFrame:RegisterEvent(event)
	end
	list[#list + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do list[i](event, ...) end
	end
end)

local listeners = {}
function ns:Listen(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end
function ns:Send(msg, ...)
	local list = listeners[msg]
	if list then
		for i = 1, #list do list[i](...) end
	end
end

-- Run fn now, or after combat if we are in combat lockdown.
local pending = {}
function ns:SafeCall(fn)
	if InCombatLockdown() then
		pending[#pending + 1] = fn
	else
		fn()
	end
end
ns:On("PLAYER_REGEN_ENABLED", function()
	local list = pending
	pending = {}
	for i = 1, #list do list[i]() end
end)

function ns:Print(...)
	DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0MinimalPvP|r: " .. strjoin(" ", tostringall(...)))
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
ns.defaults = {
	scale = 1,              -- extra scale on top of the 1080p layout
	classColoredBars = true, -- false = dark bars with class-colored names
	menuAlpha = 0.4,        -- idle opacity of bags + game menu
	nameplates = true,
	actionbars = true,
	minimap = true,
	chat = true,
	useFont = true,         -- false = use the client's default font (non-Latin names)
}

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if dst[k] == nil then dst[k] = v end
	end
	return dst
end

----------------------------------------------------------------------
-- Media + colors
----------------------------------------------------------------------
ns.media = {
	flat = "Interface\\Buttons\\WHITE8X8",
	font = "Interface\\AddOns\\MinimalPvP\\Media\\BarlowCondensed-600.ttf",
	fontBold = "Interface\\AddOns\\MinimalPvP\\Media\\BarlowCondensed-700.ttf",
	fallback = "Fonts\\ARIALN.TTF",
}

ns.colors = {
	text = { 0.91, 0.90, 0.88 },
	muted = { 0.55, 0.56, 0.59 },
	bg = { 0.094, 0.098, 0.11 },
	missing = { 0.23, 0.24, 0.27 },
	kick = { 0.95, 0.70, 0.24 },      -- interruptible cast
	locked = { 0.37, 0.39, 0.42 },    -- uninterruptible cast
	channel = { 0.31, 0.76, 0.69 },
	danger = { 0.90, 0.28, 0.30 },
	player = { 0.79, 0.80, 0.83 },    -- your own cast bar
	friendly = { 0.30, 0.78, 0.39 },
	drHalf = { 0.95, 0.79, 0.30 },
	drQuarter = { 0.95, 0.60, 0.29 },
	drImmune = { 0.90, 0.28, 0.30 },
	combo = { 0.95, 0.79, 0.30 },
	xp = { 0.55, 0.36, 0.85 },
	rested = { 0.24, 0.48, 1.0 },
	power = {
		[0] = { 0.24, 0.48, 1.0 },   -- mana
		[1] = { 0.88, 0.29, 0.23 },  -- rage
		[2] = { 1.0, 0.50, 0.25 },   -- focus
		[3] = { 0.95, 0.83, 0.37 },  -- energy
		[6] = { 0.25, 0.77, 0.91 },  -- runic power
	},
	dispel = {
		Magic = { 0.24, 0.61, 1.0 },
		Curse = { 0.66, 0.44, 1.0 },
		Poison = { 0.30, 0.78, 0.39 },
		Disease = { 0.73, 0.54, 0.31 },
		none = { 0.71, 0.27, 0.23 },
	},
}

function ns:ClassColor(class)
	local c = class and RAID_CLASS_COLORS[class]
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

function ns:Font(fs, size, bold)
	local path = (ns.db and not ns.db.useFont) and ns.media.fallback or (bold and ns.media.fontBold or ns.media.font)
	fs:SetFont(path, size, "OUTLINE")
	if not fs:GetFont() then
		fs:SetFont(ns.media.fallback, size, "OUTLINE")
	end
	fs:SetShadowOffset(0, 0)
end

----------------------------------------------------------------------
-- Root frame: 1 unit = 1 pixel of a 1920x1080 screen (scaled to any size)
----------------------------------------------------------------------
local root = CreateFrame("Frame", "MinimalPvPRoot", UIParent)
root:SetAllPoints(UIParent)
root:SetFrameStrata("LOW")
ns.root = root

function ns:UpdateScale()
	ns:SafeCall(function()
		local eff = UIParent:GetEffectiveScale()
		root:SetScale((768 / 1080) / eff * (ns.db and ns.db.scale or 1))
	end)
end

function ns:Place(frame, point, relPoint, x, y)
	frame:ClearAllPoints()
	frame:SetPoint(point, root, relPoint or point, x or 0, y or 0)
end

----------------------------------------------------------------------
-- Hide Blizzard frames we replace
----------------------------------------------------------------------
local hider = CreateFrame("Frame")
hider:Hide()
ns.hider = hider

function ns:Kill(frame)
	if not frame then return end
	if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
	frame:SetParent(hider)
	frame:Hide()
end

local function HideBlizzardUnitFrames()
	ns:Kill(PlayerFrame)
	ns:Kill(PetFrame)
	ns:Kill(TargetFrame)
	ns:Kill(ComboFrame)
	ns:Kill(TargetFrameToT)
	ns:Kill(FocusFrame)
	ns:Kill(FocusFrameToT)
	for i = 1, 4 do
		ns:Kill(_G["PartyMemberFrame" .. i])
	end
	if PartyMemberBackground then PartyMemberBackground:Hide() end
	ns:Kill(CastingBarFrame)
	ns:Kill(PetCastingBarFrame)
	SetCVar("showArenaEnemyFrames", "0")
	if ArenaEnemyFrames then ns:Kill(ArenaEnemyFrames) end
end

ns:On("ADDON_LOADED", function(_, name)
	if name == ADDON then
		MinimalPvPDB = CopyDefaults(ns.defaults, MinimalPvPDB or {})
		ns.db = MinimalPvPDB
	elseif name == "Blizzard_ArenaUI" and ArenaEnemyFrames then
		ns:Kill(ArenaEnemyFrames)
	end
end)

ns:On("PLAYER_LOGIN", function()
	ns:UpdateScale()
	HideBlizzardUnitFrames()
	ns:Send("LOGIN")
end)

ns:On("UI_SCALE_CHANGED", function() ns:UpdateScale() end)
ns:On("DISPLAY_SIZE_CHANGED", function() ns:UpdateScale() end)

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
function ns:FormatTime(t)
	if t >= 60 then
		return format("%d:%02d", floor(t / 60), floor(t % 60))
	elseif t >= 10 then
		return format("%d", floor(t))
	elseif t > 0 then
		return format("%.1f", t)
	end
	return ""
end

function ns:InArena()
	local _, kind = IsInInstance()
	return kind == "arena"
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_MINIMALPVP1 = "/mpvp"
SlashCmdList.MINIMALPVP = function(msg)
	local cmd, arg = strsplit(" ", strlower(strtrim(msg or "")), 2)
	if cmd == "test" then
		ns:Send("TOGGLE_TEST")
	elseif cmd == "scale" and tonumber(arg) then
		ns.db.scale = math.max(0.5, math.min(2, tonumber(arg)))
		ns:UpdateScale()
		ns:Print("scale", ns.db.scale)
	elseif cmd == "colors" then
		ns.db.classColoredBars = not ns.db.classColoredBars
		ns:Send("REFRESH_ALL")
		ns:Print("class-colored bars", ns.db.classColoredBars and "on" or "off")
	elseif cmd == "menu" and tonumber(arg) then
		ns.db.menuAlpha = math.max(0, math.min(1, tonumber(arg)))
		ns:Send("REFRESH_ALL")
		ns:Print("menu opacity", ns.db.menuAlpha)
	elseif cmd == "font" then
		ns.db.useFont = not ns.db.useFont
		ns:Print("custom font", ns.db.useFont and "on" or "off", "- type /reload to apply")
	elseif cmd == "nameplates" or cmd == "actionbars" or cmd == "minimap" or cmd == "chat" then
		ns.db[cmd] = not ns.db[cmd]
		ns:Print(cmd, ns.db[cmd] and "on" or "off", "- type /reload to apply")
	else
		ns:Print("commands:")
		ns:Print("/mpvp test - show every frame with sample data")
		ns:Print("/mpvp scale 0.9 - resize the whole UI")
		ns:Print("/mpvp colors - class-colored bars on/off")
		ns:Print("/mpvp menu 0.4 - idle opacity of bags and menu (0-1)")
		ns:Print("/mpvp font - bundled font on/off (off for Cyrillic/Asian names)")
		ns:Print("/mpvp nameplates | actionbars | minimap | chat - turn a module on/off")
	end
end
