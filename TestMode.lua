-- AllForOne: /afo test — fills every frame with sample arena data (out of combat only)
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
	ns:NoteCooldownUsed(guid, class, rec.name)
end

local function Start(mode)
	local bg = (mode == "bg")
	local now = GetTime()
	local _, myClass = UnitClass("player")
	ns.fake = {
		player = { name = UnitName("player"), class = myClass, hp = 72, pw = 64, ptype = UnitPowerType("player") },
		pet = { name = "Water Elemental", class = myClass, hp = 90, creature = "Elemental" },
		party1 = { name = "Rogue", class = "ROGUE", hp = 88, pw = 70, ptype = 3 },
		party2 = { name = "Priest", class = "PRIEST", hp = 64, pw = 58, ptype = 0, drinking = true },
		arena1 = { enemy = true, name = "Warrior", class = "WARRIOR", hp = 41, pw = 55, ptype = 1 },
		arena2 = { enemy = true, name = "Death Knight", class = "DEATHKNIGHT", hp = 77, pw = 30, ptype = 6 },
		arenapet2 = { name = "Ghoul", class = "DEATHKNIGHT", hp = 64, creature = "Undead" },
		arena3 = { enemy = true, name = "Paladin", class = "PALADIN", hp = 58, pw = 81, ptype = 0 },
		target = { name = "Paladin", class = "PALADIN", hp = 58, pw = 81, ptype = 0 },
		targettarget = { name = "Rogue", class = "ROGUE", hp = 88 },
		focus = { name = "Death Knight", class = "DEATHKNIGHT", hp = 77 },
	}
	if bg then
		-- battleground sample: your raid instead of party / arena enemies
		for _, u in ipairs({ "party1", "party2", "arena1", "arena2", "arenapet2", "arena3" }) do ns.fake[u] = nil end
		ns.fake.target = { name = "Swiftpaw", class = "DRUID", hp = 28, pw = 60, ptype = 3 }
		ns.fake.focus = nil
	end
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
		{ icon = Icon(48932), purge = true },              -- Blessing of Might: purgeable (blue edge)
		{ icon = Icon(53601), purge = true },              -- Sacred Shield
		{ icon = Icon(54043) },                            -- Retribution Aura: not purgeable, no edge
		{ icon = Icon(19746) },                            -- Concentration Aura
	}
	ns.fakeCombo = 3
	-- who targets whom: two of you on the Paladin, Warrior on you, DK on your Priest
	ns.fakeTargets = { player = "arena3", party1 = "arena3", arena1 = "player", arena2 = "party2", arena3 = "party1" }
	ns.fakeRunes = true

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
	if not bg then ns:ShowArenaSample(true) end
	if ns.UpdateTargets then ns:UpdateTargets() end
	ns:Send("RESOURCES_TEST", true)
	if bg then
		ns:Send("RAID_TEST", true)
		ns:Send("BG_TEST", true)
		ns:Print("battleground test mode on - type /afo test again to turn it off")
	else
		ns:Print("test mode on (arena) - /afo test bg shows a battleground; /afo test again turns it off")
	end
end

local function Stop()
	ns.testing = false
	for _, t in ipairs({ ns.cds, ns.trinkets, ns.dr, ns.specs, ns.cdOrder }) do
		for k in pairs(t) do
			if type(k) == "string" and k:match("^test%-") then t[k] = nil end
		end
	end
	ns.fake, ns.fakeDebuffs, ns.fakeTargetDebuffs, ns.fakeTargetBuffs, ns.fakeCombo = nil, nil, nil, nil, nil
	ns.fakeTargets, ns.fakeRunes = nil, nil
	local F = ns.frames
	F.target.castbar:Fake(nil)
	F.arena[3].castbar:Fake(nil)
	F.team[3].castbar:Fake(nil)
	F.playerCast:Fake(nil)
	ns:ShowProcs({})
	ns:ShowLoC(nil)
	ns:ShowArenaSample(false)
	ns:Send("RESOURCES_TEST", false)
	ns:Send("RAID_TEST", false)
	ns:Send("BG_TEST", false)
	ns:SetFramesForced(false)
	ns:Print("test mode off")
end

ns:Listen("TOGGLE_TEST", function(mode)
	if InCombatLockdown() then
		ns:Print("test mode can't change during combat")
		return
	end
	if ns.testing then
		Stop()
		-- "/afo test bg" while the arena sample is on: switch straight over
		if mode == "bg" then Start(mode) end
	else
		Start(mode)
	end
end)
