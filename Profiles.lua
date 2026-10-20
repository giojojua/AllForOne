-- AllForOne: profiles — named snapshots of your whole UI (layout + settings)
-- Saved for the account, so any character can load a profile another one saved.
--   /afo profile save <name>    save the current UI under that name (same name = overwrite)
--   /afo profile load <name>    switch to it
--   /afo profile delete <name>
--   /afo profile list
-- The settings window has the same thing under PROFILES.
local _, ns = ...

-- settings that belong to a "UI version" (everything in the settings window)
local KEYS = { "scale", "classColoredBars", "menuAlpha", "macroNames", "usableColors", "useFont", "nameplates", "raid", "actionbars", "minimap", "chat" }
-- these only take effect after a reload
local NEEDS_RELOAD = { useFont = true, nameplates = true, raid = true, actionbars = true, minimap = true, chat = true }

local function Copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = Copy(v) end
	return out
end

local function Store()
	ns.db.profiles = ns.db.profiles or {}
	return ns.db.profiles
end

local function Clean(name)
	name = name and strtrim(name) or ""
	if name == "" then return nil end
	return name:sub(1, 32)
end

-- case-insensitive lookup, returns the stored spelling
local function Find(name)
	if not name then return nil end
	local lower = strlower(name)
	for k in pairs(Store()) do
		if strlower(k) == lower then return k end
	end
end

-- Profiles sorted by name: { {name=, saved=, by=, active=}, ... }
function ns:ListProfiles()
	local list = {}
	local active = ns.db.activeProfile and ns.db.activeProfile[ns.CharKey()]
	for name, p in pairs(Store()) do
		list[#list + 1] = { name = name, saved = p.saved, by = p.by, active = (name == active) }
	end
	table.sort(list, function(a, b) return strlower(a.name) < strlower(b.name) end)
	return list
end

local function SetActive(name)
	ns.db.activeProfile = ns.db.activeProfile or {}
	ns.db.activeProfile[ns.CharKey()] = name
end

function ns:SaveProfile(name)
	name = Clean(name)
	if not name then ns:Print("give the profile a name, e.g. /afo profile save Arena") return end
	local existing = Find(name)
	if existing then name = existing end
	local settings = {}
	for _, k in ipairs(KEYS) do settings[k] = ns.db[k] end
	Store()[name] = {
		settings = settings,
		layout = Copy(ns:GetLayout()),
		saved = date("%Y-%m-%d %H:%M"),
		by = ns.CharKey(),
	}
	SetActive(name)
	ns:Print(existing and "profile updated:" or "profile saved:", name)
	ns:Send("PROFILES_CHANGED")
	return true
end

function ns:LoadProfile(name)
	local key = Find(Clean(name))
	if not key then ns:Print("no profile called", name or "?", "- /afo profile list shows them") return end
	if InCombatLockdown() then ns:Print("profiles can't be loaded during combat") return end
	local p = Store()[key]
	local reload = false
	for _, k in ipairs(KEYS) do
		local v = p.settings and p.settings[k]
		if v ~= nil then
			if NEEDS_RELOAD[k] and ns.db[k] ~= v then reload = true end
			ns.db[k] = v
		end
	end
	ns:SetLayout(Copy(p.layout or {}))
	ns:UpdateScale()
	ns:Send("REFRESH_ALL")
	SetActive(key)
	ns:Print("profile loaded:", key)
	if reload then ns:Print("some parts of this profile (font / turned-off modules) apply after /reload") end
	ns:Send("PROFILES_CHANGED")
	return true, reload
end

function ns:DeleteProfile(name)
	local key = Find(Clean(name))
	if not key then ns:Print("no profile called", name or "?") return end
	Store()[key] = nil
	for char, active in pairs(ns.db.activeProfile or {}) do
		if active == key then ns.db.activeProfile[char] = nil end
	end
	ns:Print("profile deleted:", key)
	ns:Send("PROFILES_CHANGED")
	return true
end

function ns:ProfileCommand(rest)
	local sub, name = strsplit(" ", strtrim(rest or ""), 2)
	sub = strlower(sub or "")
	if sub == "save" then
		ns:SaveProfile(name)
	elseif sub == "load" then
		ns:LoadProfile(name)
	elseif sub == "delete" or sub == "remove" then
		ns:DeleteProfile(name)
	else
		local list = ns:ListProfiles()
		if #list == 0 then
			ns:Print("no profiles yet - /afo profile save <name> saves your current UI")
		else
			ns:Print("profiles (/afo profile load <name>):")
			for _, p in ipairs(list) do
				ns:Print((p.active and "> " or "  ") .. p.name .. "  |cff8b8f96" .. (p.saved or "") .. " · " .. (p.by or "") .. "|r")
			end
		end
	end
end
