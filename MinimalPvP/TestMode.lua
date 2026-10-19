-- MinimalPvP: /mpvp test — fills every frame with sample arena data (out of combat only)
local _, ns = ...
local GetTime = GetTime

local function Icon(id)
	local _, _, icon = GetSpellInfo(id)
	return icon
end

local function UseCooldown(guid, class, index, ago)
	local list = ns.classCooldowns[class]
	local rec = list and list[index]
	if not rec then return end
	ns.cds[guid] = ns.cds[guid] or {}
	ns.cds[guid][rec.name] = { start = GetTime() - ago, dur = rec.cd, icon = rec.icon }
end

local function Start()
	local now = GetTime()
	local _, myClass = UnitClass("player")
	ns.fake = {
		player = { name = UnitName("player"), class = myClass, hp = 72, pw = 64, ptype = UnitPowerType("player") },
		pet = { name = "Water Elemental", class = myClass, hp = 90 },
		party1 = { name = "Rogue", class = "ROGUE", hp = 88, pw = 70, ptype = 3 },
		party2 = { name = "Priest", class = "PRIEST", hp = 64, pw = 58, ptype = 0 },
		arena1 = { name = "Warrior", class = "WARRIOR", hp = 41, pw = 55, ptype = 1 },
		arena2 = { name = "Death Knight", class = "DEATHKNIGHT", hp = 77, pw = 30, ptype = 6 },
		arenapet2 = { name = "Ghoul", class = "DEATHKNIGHT", hp = 64 },
		arena3 = { name = "Paladin", class = "PALADIN", hp = 58, pw = 81, ptype = 0 },
		target = { name = "Paladin", class = "PALADIN", hp = 58, pw = 81, ptype = 0 },
		targettarget = { name = "Rogue", class = "ROGUE", hp = 88 },
		focus = { name = "Death Knight", class = "DEATHKNIGHT", hp = 77 },
	}
	ns.specs["test-party1"] = "Subtlety"
	ns.specs["test-party2"] = "Discipline"
	ns.specs["test-arena1"] = "Arms"
	ns.specs["test-arena2"] = "Unholy"
	ns.specs["test-arena3"] = "Holy"
	ns.specs["test-target"] = "Holy"

	UseCooldown("test-arena1", "WARRIOR", 1, 4)
	UseCooldown("test-arena1", "WARRIOR", 3, 18)
	UseCooldown("test-arena2", "DEATHKNIGHT", 2, 9)
	UseCooldown("test-arena2", "DEATHKNIGHT", 3, 17)
	UseCooldown("test-arena3", "PALADIN", 2, 0)
	UseCooldown("test-player", myClass, 1, 10)
	UseCooldown("test-party1", "ROGUE", 2, 20)
	UseCooldown("test-party2", "PRIEST", 1, 8)
	ns.trinkets["test-arena2"] = now - 18
	ns.trinkets["test-party1"] = now - 48

	ns.dr["test-arena1"] = { stun = { count = 1, reset = now + 12, icon = Icon(10308), active = false } }
	ns.dr["test-arena2"] = {
		incap = { count = 2, reset = now + 9, icon = Icon(118), active = false },
		root = { count = 1, reset = now + 15, icon = Icon(42917), active = false },
	}

	ns.fakeDebuffs = {
		party1 = { { icon = Icon(10308), dur = 6, expires = now + 4, dispel = "Magic" } },
		party2 = { { icon = Icon(47476), dur = 5, expires = now + 3, dispel = "Magic" } },
	}
	ns.fakeTargetDebuffs = {
		{ icon = Icon(12494), dur = 5, expires = now + 4, mine = true },
		{ icon = Icon(42842), dur = 9, expires = now + 6, mine = true },
		{ icon = Icon(10890), dur = 8, expires = now + 5, cc = true },
	}
	ns.fakeTargetBuffs = {
		{ icon = Icon(48932) },
		{ icon = Icon(53601) },
	}
	ns.fakeCombo = 3

	ns.testing = true
	ns:SetFramesForced(true)

	local F = ns.frames
	F.target.castbar:Fake("Flash of Light", Icon(48785), 0.62)
	F.arena[3].castbar:Fake("Flash of Light", nil, 0.62)
	F.team[3].castbar:Fake("Penance", nil, 0.7, false, true)
	F.playerCast:Fake("Frostbolt", nil, 0.5)

	ns:ShowProcs({
		{ name = GetSpellInfo(44544) or "Fingers of Frost", icon = Icon(44544), count = 2 },
		{ name = GetSpellInfo(57761) or "Brain Freeze", icon = Icon(57761), dur = 15, expires = now + 12 },
	})
	ns:ShowLoC(Icon(118), "incap", 8, now + 6)
	ns:ShowArenaSample(true)
	ns:Print("test mode on - type /mpvp test again to turn it off")
end

local function Stop()
	ns.testing = false
	for _, t in ipairs({ ns.cds, ns.trinkets, ns.dr, ns.specs }) do
		for k in pairs(t) do
			if type(k) == "string" and k:match("^test%-") then t[k] = nil end
		end
	end
	ns.fake, ns.fakeDebuffs, ns.fakeTargetDebuffs, ns.fakeTargetBuffs, ns.fakeCombo = nil, nil, nil, nil, nil
	local F = ns.frames
	F.target.castbar:Fake(nil)
	F.arena[3].castbar:Fake(nil)
	F.team[3].castbar:Fake(nil)
	F.playerCast:Fake(nil)
	ns:ShowProcs({})
	ns:ShowLoC(nil)
	ns:ShowArenaSample(false)
	ns:SetFramesForced(false)
	ns:Print("test mode off")
end

ns:Listen("TOGGLE_TEST", function()
	if InCombatLockdown() then
		ns:Print("test mode can't change during combat")
		return
	end
	if ns.testing then Stop() else Start() end
end)
