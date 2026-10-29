-- AllForOne: core (namespace, events, settings, pixel root, Blizzard hiding)
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

-- each handler runs on its own: one error can't stop the others (errors are still shown)
eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			local ok, err = pcall(list[i], event, ...)
			if not ok then ns:Report(err) end
		end
	end
end)

local listeners = {}
function ns:Listen(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end
-- One failing module must not stop the others from loading: each listener runs
-- protected, and errors still go to the normal Lua error display.
-- WoW hides Lua errors unless scriptErrors is on, so the first few also go to chat.
local reported = 0
function ns:Report(err)
	reported = reported + 1
	if reported <= 3 then
		ns:Print("|cffff5555error:|r", tostring(err):match("[^\n]+") or tostring(err))
	end
	local handler = geterrorhandler and geterrorhandler()
	if handler then handler(err) end
end

function ns:Send(msg, ...)
	local list = listeners[msg]
	if list then
		for i = 1, #list do
			local ok, err = pcall(list[i], ...)
			if not ok then ns:Report(err) end
		end
	end
end

-- Run fn now, or after combat if we are in combat lockdown.
-- The same function is queued only once, however often it's asked for during combat
-- (some Blizzard updates fire many times a second), and each one runs protected.
local pending, queued = {}, {}
function ns:SafeCall(fn)
	if InCombatLockdown() then
		if not queued[fn] then
			queued[fn] = true
			pending[#pending + 1] = fn
		end
	else
		fn()
	end
end
ns:On("PLAYER_REGEN_ENABLED", function()
	local list = pending
	pending, queued = {}, {}
	for i = 1, #list do
		local ok, err = pcall(list[i])
		if not ok then ns:Report(err) end
	end
end)

function ns:Print(...)
	DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0AllForOne|r: " .. strjoin(" ", tostringall(...)))
end

----------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------
ns.defaults = {
	scale = 1,              -- extra scale on top of the 1080p layout
	classColoredBars = true, -- false = dark bars with class-colored names
	menuAlpha = 0.6,        -- idle opacity of bags + game menu
	chatAlpha = 0.4,        -- dark background behind the chat text (0 = none)
	macroNames = true,      -- macro names on action buttons
	killHelper = true,      -- arena kill target helper (KILL / CC markers)
	announceKill = true,    -- announce kill target changes in party chat
	analyzerOn = true,      -- record arena matches (last 50)
	analyzerPopup = true,   -- small report popup after each arena
	usableColors = true,    -- tint action buttons: red out of range, blue no power
	hideErrors = false,     -- hide the red error text ("Not enough rage"...); yellow info stays
	nameplates = true,
	raid = true,            -- raid frames in battlegrounds / raids
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
	font = "Interface\\AddOns\\AllForOne\\Media\\BarlowCondensed-600.ttf",
	fontBold = "Interface\\AddOns\\AllForOne\\Media\\BarlowCondensed-700.ttf",
	fallback = "Fonts\\ARIALN.TTF",
}

ns.colors = {
	text = { 0.91, 0.90, 0.88 },
	muted = { 0.55, 0.56, 0.59 },
	bg = { 0.094, 0.098, 0.11 },
	missing = { 0.23, 0.24, 0.27 },
	kick = { 0.95, 0.70, 0.24 },      -- interruptible cast
	locked = { 0.37, 0.39, 0.42 },    -- uninterruptible cast
	channel = { 0.29, 0.56, 1.0 },    -- channeled spells: blue
	danger = { 0.90, 0.28, 0.30 },
	player = { 0.95, 0.58, 0.18 },    -- your own cast bar while casting: orange
	castOk = { 0.30, 0.78, 0.39 },    -- your cast went through: green
	castFail = { 0.90, 0.28, 0.30 },  -- canceled / interrupted / failed: red
	friendly = { 0.24, 0.75, 0.33 },  -- softer friendly green (#3DBF54)
	drHalf = { 0.95, 0.79, 0.30 },
	drQuarter = { 0.95, 0.60, 0.29 },
	drImmune = { 0.90, 0.28, 0.30 },
	combo = { 0.90, 0.20, 0.22 },     -- red combo points
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

-- Class colors: the modern WoW palette (what most addons and sites use today), exact hex.
-- The game's own 3.3.5 table is only used to recognise Blizzard's colored nameplate bars.
local function Hex(h) return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 end
ns.CLASS_COLORS = {}
for class, h in pairs({
	DEATHKNIGHT = "C41E3A", DRUID = "FF7C0A", HUNTER = "AAD372", MAGE = "3FC7EB", PALADIN = "F48CBA",
	PRIEST = "FFFFFF", ROGUE = "FFF468", SHAMAN = "0070DD", WARLOCK = "8788EE", WARRIOR = "C69B6D",
}) do
	local r, g, b = Hex(h)
	ns.CLASS_COLORS[class] = { r = r, g = g, b = b, hex = h }
end

function ns:ClassColor(class)
	local c = class and (ns.CLASS_COLORS[class] or RAID_CLASS_COLORS[class])
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

-- Health bar fill: the same hue a bit darker and less saturated, so big bars
-- don't glare (names and text keep the full class color)
function ns:Soften(r, g, b)
	return r * 0.78 + 0.07, g * 0.78 + 0.07, b * 0.78 + 0.07
end

function ns:BarColor(class)
	return ns:Soften(ns:ClassColor(class))
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
local root = CreateFrame("Frame", "AllForOneRoot", UIParent)
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

-- Hide a Blizzard frame for good. Textures and font strings (e.g. MinimapBorder) can't
-- always be moved to another parent in 3.3.5, so those are blanked and kept hidden instead.
local function noop() end
function ns:Kill(frame)
	if not frame then return end
	local kind = frame.GetObjectType and frame:GetObjectType()
	if kind == "Texture" or kind == "FontString" then
		if kind == "Texture" then frame:SetTexture(nil) end
		frame:SetAlpha(0)
		frame:Hide()
		frame.Show = noop
		return
	end
	if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
	if not pcall(frame.SetParent, frame, hider) then frame.Show = noop end
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
		AllForOneDB = CopyDefaults(ns.defaults, AllForOneDB or {})
		ns.db = AllForOneDB
		-- one-time: the default menu opacity went from 40% to 60%; move people still on the old default
		if not ns.db.menuAlpha60 then
			if math.abs((ns.db.menuAlpha or 0) - 0.4) < 0.001 then ns.db.menuAlpha = 0.6 end
			ns.db.menuAlpha60 = true
		end
	elseif name == "Blizzard_ArenaUI" and ArenaEnemyFrames then
		ns:Kill(ArenaEnemyFrames)
	end
end)

-- Build the UI. After a /reload in combat the game locks protected frames (unit frames,
-- action bars, hiding Blizzard's frames), so in that case wait until combat ends.
ns.loaded = false
local function Start()
	if ns.loaded then return end
	ns.loaded = true
	ns:UpdateScale()
	local ok, err = pcall(HideBlizzardUnitFrames)
	if not ok then ns:Report(err) end
	ns:Send("LOGIN")
	ns:Send("REFRESH_ALL")
end

ns:On("PLAYER_LOGIN", function()
	if InCombatLockdown() then
		ns:Print("you're in combat - the UI will load as soon as combat ends")
	end
	ns:SafeCall(Start)
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
SLASH_ALLFORONE1 = "/afo"
SLASH_ALLFORONE2 = "/allforone"
SlashCmdList.ALLFORONE = function(msg)
	local raw = strtrim(msg or "")
	local first, rawArg = strsplit(" ", raw, 2)
	if strlower(first or "") == "spec" then
		-- which spec each enemy / teammate got, and the spell that decided it
		local any
		for _, u in ipairs({ "target", "focus", "arena1", "arena2", "arena3", "arena4", "arena5", "party1", "party2", "party3", "party4" }) do
			local g = UnitExists(u) and UnitIsPlayer(u) and UnitGUID(u)
			if g then
				any = true
				local _, class = UnitClass(u)
				ns:Print(format("%s: %s %s - %s", u, UnitName(u) or "?", class or "?",
					ns.specs[g] and (ns.specs[g] .. " (from " .. (ns.specWhy[g] or "talents") .. ")") or "no spec yet"))
			end
		end
		if not any then ns:Print("target a player (or be in an arena / party) to see their spec") end
		return
	end
	if strlower(first or "") == "quests" then
		if ns.QuestDebug then ns:QuestDebug() end
		return
	end
	if strlower(first or "") == "buffs" then
		if ns.BuffCommand then ns:BuffCommand(rawArg) else ns:Print("the buff tracker needs a full game restart after updating the addon") end
		return
	end
	if strlower(first or "") == "procs" then
		if ns.ProcCommand then ns:ProcCommand(rawArg) else ns:Print("the proc window needs a full game restart after updating the addon") end
		return
	end
	if strlower(first or "") == "arena" then
		if ns.AnalyzeCommand then ns:AnalyzeCommand(rawArg) else ns:Print("the analyzer needs a full game restart after updating the addon") end
		return
	end
	if strlower(first or "") == "profile" or strlower(first or "") == "profiles" then
		if ns.ProfileCommand then ns:ProfileCommand(rawArg) else ns:Print("profiles need a full game restart after updating the addon") end
		return
	end
	local cmd, arg = strsplit(" ", strlower(raw), 2)
	if cmd == "test" then
		ns:Send("TOGGLE_TEST", arg and strtrim(arg) ~= "" and strtrim(arg) or nil)
	elseif cmd == "unlock" or cmd == "move" then
		ns:Unlock()
	elseif cmd == "lock" then
		ns:Lock()
	elseif cmd == "reset" then
		ns:ResetLayout()
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
	elseif cmd == "nameplates" or cmd == "raid" or cmd == "actionbars" or cmd == "minimap" or cmd == "chat" then
		ns.db[cmd] = not ns.db[cmd]
		ns:Print(cmd, ns.db[cmd] and "on" or "off", "- type /reload to apply")
	elseif cmd == "" and ns.ToggleSettings then
		ns:ToggleSettings()
	else
		ns:Print("commands:")
		ns:Print("/afo - open the settings window")
		ns:Print("/afo unlock - move (drag) and resize (mouse wheel) any part; /afo lock to save")
		ns:Print("/afo reset - put every part back where it started")
		ns:Print("/afo test - show every frame with sample arena data; /afo test bg - sample battleground")
		ns:Print("/afo procs - open the proc window (choose which procs show next to your character)")
		ns:Print("/afo buffs - open the buff tracker (buffs you want up; a red icon right of your bars when one is missing)")
		ns:Print("/afo profile save|load|delete <name>, /afo profile list - save and switch whole UI versions")
		ns:Print("/afo arena - arena analyzer (this character's last 50 matches); /afo arena test - sample report; /afo arena reset - delete this character's history")
		ns:Print("/afo scale 0.9 - resize the whole UI at once")
		ns:Print("/afo colors - class-colored bars on/off")
		ns:Print("/afo menu 0.6 - idle opacity of bags and menu (0-1)")
		ns:Print("/afo font - bundled font on/off (off for Cyrillic/Asian names)")
		ns:Print("/afo nameplates | raid | actionbars | minimap | chat - turn a module on/off")
	end
end
