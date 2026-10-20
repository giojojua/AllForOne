-- AllForOne: spell data for WotLK 3.3.5
-- Spells are listed by one spell ID and matched by localized NAME at login,
-- so every rank of a spell is covered and the addon works on any client language.
local _, ns = ...

----------------------------------------------------------------------
-- Crowd control: DR category, PvP duration, dispel type
----------------------------------------------------------------------
-- category priority: higher = more important to show as the "big" icon
ns.ccPriority = {
	cyclone = 9, mc = 9, banish = 9,
	stun = 8, kidney = 8, incap = 8, fear = 8, horror = 8,
	disorient = 7, sleep = 7,
	silence = 6, disarm = 4, root = 3,
}

-- Text for the loss-of-control alert
ns.ccLabel = {
	cyclone = "CYCLONED", mc = "CHARMED", banish = "BANISHED",
	stun = "STUNNED", kidney = "STUNNED", incap = "INCAPACITATED", fear = "FEARED",
	horror = "HORRIFIED", disorient = "DISORIENTED", sleep = "ASLEEP",
	silence = "SILENCED", disarm = "DISARMED", root = "ROOTED",
}

-- categories that share diminishing returns (shown on enemy arena frames)
ns.drCategories = {
	stun = true, kidney = true, incap = true, fear = true, horror = true,
	disorient = true, cyclone = true, silence = true, disarm = true, root = true,
	mc = true, banish = true, sleep = true,
}

local ccList = {
	-- { category, duration, dispel type or false, spellIDs... }
	{ "stun", 6, "Magic", 10308 },            -- Hammer of Justice
	{ "kidney", 6, false, 8643 },             -- Kidney Shot
	{ "stun", 4, false, 1833 },               -- Cheap Shot
	{ "stun", 4, false, 8983 },               -- Bash
	{ "stun", 5, false, 49802 },              -- Maim
	{ "stun", 3, false, 49803 },              -- Pounce
	{ "stun", 1.5, false, 20253 },            -- Intercept
	{ "stun", 1.5, false, 7922 },             -- Charge Stun
	{ "stun", 5, false, 12809 },              -- Concussion Blow
	{ "stun", 4, false, 46968 },              -- Shockwave
	{ "stun", 2, false, 20549 },              -- War Stomp
	{ "stun", 5, "Magic", 44572 },            -- Deep Freeze
	{ "stun", 3, false, 47481 },              -- Gnaw
	{ "stun", 3, false, 24394 },              -- Intimidation
	{ "stun", 3, "Magic", 47847 },            -- Shadowfury
	{ "stun", 2, false, 12355 },              -- Impact
	{ "incap", 10, "Magic", 118, 28271, 28272, 61305, 61721, 61780 }, -- Polymorph (all)
	{ "incap", 10, false, 51724 },            -- Sap
	{ "incap", 4, false, 1776 },              -- Gouge
	{ "incap", 10, "Curse", 51514 },          -- Hex
	{ "incap", 6, "Magic", 20066 },           -- Repentance
	{ "incap", 10, "Magic", 14309 },          -- Freezing Trap Effect
	{ "incap", 10, "Magic", 60210 },          -- Freezing Arrow Effect
	{ "incap", 6, "Poison", 49012 },          -- Wyvern Sting
	{ "sleep", 10, "Magic", 18658 },          -- Hibernate
	{ "disorient", 4, false, 19503 },         -- Scatter Shot
	{ "disorient", 5, "Magic", 42950 },       -- Dragon's Breath
	{ "fear", 8, "Magic", 6215 },             -- Fear
	{ "fear", 8, "Magic", 10890 },            -- Psychic Scream
	{ "fear", 8, "Magic", 17928 },            -- Howl of Terror
	{ "fear", 8, false, 5246, 20511 },        -- Intimidating Shout
	{ "fear", 10, "Magic", 6358 },            -- Seduction
	{ "fear", 10, false, 2094 },              -- Blind
	{ "fear", 10, "Magic", 10326 },           -- Turn Evil
	{ "horror", 3, "Magic", 47860 },          -- Death Coil
	{ "horror", 3, "Magic", 64044 },          -- Psychic Horror
	{ "cyclone", 6, false, 33786 },           -- Cyclone
	{ "banish", 10, "Magic", 18647 },         -- Banish
	{ "mc", 10, "Magic", 605 },               -- Mind Control
	{ "silence", 5, "Magic", 15487 },         -- Silence
	{ "silence", 5, "Magic", 47476 },         -- Strangulate
	{ "silence", 2, false, 28730 },           -- Arcane Torrent
	{ "silence", 3, false, 1330 },            -- Garrote - Silence
	{ "silence", 3, "Magic", 24259 },         -- Spell Lock
	{ "silence", 3, "Magic", 34490 },         -- Silencing Shot
	{ "silence", 4, "Magic", 55021, 18469 },  -- Silenced - Improved Counterspell
	{ "silence", 3, "Magic", 18498 },         -- Silenced - Gag Order
	{ "silence", 3, "Magic", 63529 },         -- Silenced - Shield of the Templar
	{ "disarm", 10, false, 676 },             -- Disarm
	{ "disarm", 10, false, 51722 },           -- Dismantle
	{ "disarm", 10, false, 53543 },           -- Snatch
	{ "root", 8, "Magic", 42917 },            -- Frost Nova
	{ "root", 10, "Magic", 53308 },           -- Entangling Roots
	{ "root", 8, "Magic", 33395 },            -- Freeze (Water Elemental)
	{ "root", 5, "Magic", 12494 },            -- Frostbite
	{ "root", 8, "Magic", 55080 },            -- Shattered Barrier
	{ "root", 5, false, 23694 },              -- Improved Hamstring
}

----------------------------------------------------------------------
-- Cooldowns tracked on arena and team frames
-- { spellID, cooldown seconds, always shown? }
-- "always" spells show from the start; the rest appear once used.
----------------------------------------------------------------------
local cdList = {
	WARRIOR = {
		{ 6552, 10, true },   -- Pummel
		{ 5246, 120, true },  -- Intimidating Shout
		{ 676, 60, true },    -- Disarm
		{ 23920, 10, true },  -- Spell Reflection
		{ 72, 12 },           -- Shield Bash
		{ 46924, 90 },        -- Bladestorm
		{ 64382, 300 },       -- Shattering Throw
		{ 18499, 30 },        -- Berserker Rage
		{ 20252, 15 },        -- Intercept
		{ 871, 300 },         -- Shield Wall
	},
	PALADIN = {
		{ 642, 300, true },   -- Divine Shield
		{ 10308, 40, true },  -- Hammer of Justice
		{ 1044, 25, true },   -- Hand of Freedom
		{ 10278, 300, true }, -- Hand of Protection
		{ 64205, 120 },       -- Divine Sacrifice
		{ 20066, 60 },        -- Repentance
		{ 31821, 120 },       -- Aura Mastery
		{ 31884, 180 },       -- Avenging Wrath
		{ 498, 180 },         -- Divine Protection
	},
	HUNTER = {
		{ 19503, 30, true },  -- Scatter Shot
		{ 19263, 90, true },  -- Deterrence
		{ 14311, 28, true },  -- Freezing Trap
		{ 53271, 60, true },  -- Master's Call
		{ 34490, 20 },        -- Silencing Shot
		{ 19574, 120 },       -- Bestial Wrath
		{ 49012, 60 },        -- Wyvern Sting
		{ 60192, 28 },        -- Freezing Arrow
	},
	ROGUE = {
		{ 1766, 10, true },   -- Kick
		{ 2094, 120, true },  -- Blind
		{ 31224, 90, true },  -- Cloak of Shadows
		{ 26889, 120, true }, -- Vanish
		{ 8643, 20 },         -- Kidney Shot
		{ 36554, 20 },        -- Shadowstep
		{ 14185, 300 },       -- Preparation
		{ 26669, 180 },       -- Evasion
		{ 51722, 60 },        -- Dismantle
		{ 51713, 60 },        -- Shadow Dance
	},
	PRIEST = {
		{ 10890, 26, true },  -- Psychic Scream
		{ 6346, 180, true },  -- Fear Ward
		{ 34433, 300, true }, -- Shadowfiend
		{ 33206, 144 },       -- Pain Suppression
		{ 47585, 120 },       -- Dispersion
		{ 15487, 45 },        -- Silence
		{ 64044, 120 },       -- Psychic Horror
		{ 47788, 180 },       -- Guardian Spirit
		{ 10060, 120 },       -- Power Infusion
	},
	DRUID = {
		{ 29166, 180, true }, -- Innervate
		{ 22812, 60, true },  -- Barkskin
		{ 8983, 60, true },   -- Bash
		{ 17116, 180 },       -- Nature's Swiftness
		{ 16979, 15 },        -- Feral Charge - Bear
		{ 49376, 30 },        -- Feral Charge - Cat
		{ 50334, 180 },       -- Berserk
		{ 61336, 180 },       -- Survival Instincts
		{ 61384, 20 },        -- Typhoon
		{ 53201, 90 },        -- Starfall
	},
	SHAMAN = {
		{ 57994, 6, true },   -- Wind Shear
		{ 8177, 15, true },   -- Grounding Totem
		{ 51514, 45, true },  -- Hex
		{ 16188, 120 },       -- Nature's Swiftness
		{ 30823, 60 },        -- Shamanistic Rage
		{ 51533, 180 },       -- Feral Spirit
		{ 59159, 35 },        -- Thunderstorm
		{ 16190, 300 },       -- Mana Tide Totem
	},
	MAGE = {
		{ 2139, 24, true },   -- Counterspell
		{ 45438, 300, true }, -- Ice Block
		{ 1953, 15, true },   -- Blink
		{ 42917, 20, true },  -- Frost Nova
		{ 44572, 30 },        -- Deep Freeze
		{ 11958, 384 },       -- Cold Snap
		{ 43039, 30 },        -- Ice Barrier
		{ 12051, 240 },       -- Evocation
		{ 42950, 20 },        -- Dragon's Breath
		{ 55342, 180 },       -- Mirror Image
		{ 12043, 120 },       -- Presence of Mind
	},
	WARLOCK = {
		{ 47860, 120, true }, -- Death Coil
		{ 17928, 32, true },  -- Howl of Terror
		{ 19647, 24, true },  -- Spell Lock (Felhunter)
		{ 47847, 20 },        -- Shadowfury
		{ 48020, 30 },        -- Demonic Circle: Teleport
		{ 47241, 180 },       -- Metamorphosis
		{ 48011, 8 },         -- Devour Magic
	},
	DEATHKNIGHT = {
		{ 47528, 10, true },  -- Mind Freeze
		{ 47476, 120, true }, -- Strangulate
		{ 48707, 45, true },  -- Anti-Magic Shell
		{ 48792, 120, true }, -- Icebound Fortitude
		{ 49039, 120 },       -- Lichborne
		{ 49576, 25 },        -- Death Grip
		{ 49203, 60 },        -- Hungering Cold
		{ 47481, 60 },        -- Gnaw (Ghoul)
		{ 49206, 180 },       -- Summon Gargoyle
		{ 51052, 120 },       -- Anti-Magic Zone
	},
}

-- Racials: tracked for anyone
local racialList = {
	{ 7744, 120 },   -- Will of the Forsaken
	{ 20594, 120 },  -- Stoneform
	{ 20589, 105 },  -- Escape Artist
	{ 20549, 120 },  -- War Stomp
	{ 28730, 120 },  -- Arcane Torrent
	{ 58984, 120 },  -- Shadowmeld
}

-- Spells that reset other cooldowns: { reset spell, list of spells it resets } ("all" = every tracked cooldown of that class)
local resetList = {
	{ 14185, { 26669, 11305, 26889, 14177, 36554, 14183 } },               -- Preparation: Evasion, Sprint, Vanish, Cold Blood, Shadowstep, Premeditation
	{ 11958, { 45438, 42917, 43039, 42931, 44572, 12472, 31687 } },        -- Cold Snap: Ice Block, Frost Nova, Ice Barrier, Cone of Cold, Deep Freeze, Icy Veins, Water Elemental
	{ 23989, "all" },                                                      -- Readiness
}

-- PvP trinket and the Human racial that does the same thing
ns.trinketSpells = { 42292, 59752 }
ns.trinketCooldown = 120

----------------------------------------------------------------------
-- Spec detection: a spell seen from a player tells us their spec
----------------------------------------------------------------------
local specList = {
	WARRIOR = { Arms = { 47486, 46924 }, Fury = { 23881, 60970 }, Protection = { 47498, 46968, 50720 } },
	PALADIN = { Holy = { 48825, 53563, 31842 }, Retribution = { 35395, 53385, 20066 }, Protection = { 53595, 48827 } },
	HUNTER = { ["Beast Mastery"] = { 19574, 19577 }, Marksmanship = { 53209, 34490 }, Survival = { 60053, 49012 } },
	ROGUE = { Assassination = { 48666, 14177 }, Combat = { 51690, 13750 }, Subtlety = { 36554, 51713, 14183 } },
	PRIEST = { Discipline = { 53007, 33206, 10060 }, Holy = { 48089, 47788 }, Shadow = { 15473, 48160, 47585, 64044 } },
	DRUID = { Restoration = { 18562, 53251, 17116 }, Feral = { 48566, 48564, 50334 }, Balance = { 53201, 24858, 61384 } },
	SHAMAN = { Restoration = { 49284, 61301, 16190 }, Enhancement = { 17364, 51533, 60103, 30823 }, Elemental = { 59159, 16166, 57722 } },
	MAGE = { Arcane = { 44781, 12042 }, Fire = { 55360, 42950, 11129 }, Frost = { 44572, 43039, 31687 } },
	WARLOCK = { Affliction = { 59164, 47843 }, Demonology = { 47241, 30146 }, Destruction = { 59172, 47847, 17962 } },
	DEATHKNIGHT = { Blood = { 55262, 49016, 49028 }, Frost = { 51411, 49203, 55268 }, Unholy = { 55271, 49206, 49222, 51052 } },
}

----------------------------------------------------------------------
-- Procs shown next to your character
----------------------------------------------------------------------
-- Proc suggestions shown in the /afo procs window (nothing is tracked until you add it)
local procSuggestions = {
	MAGE = { 44544, 57761, 48108, 44401 },            -- Fingers of Frost, Brain Freeze, Hot Streak, Missile Barrage
	DRUID = { 69369, 48517, 48518, 16870 },           -- Predator's Swiftness, Eclipse (Solar/Lunar), Clearcasting
	WARLOCK = { 17941, 34936, 71165, 63167, 54277 },  -- Shadow Trance, Backlash, Molten Core, Decimation, Backdraft
	PALADIN = { 59578, 54149 },                       -- The Art of War, Infusion of Light
	SHAMAN = { 53817, 53390, 16246 },                 -- Maelstrom Weapon, Tidal Waves, Clearcasting
	PRIEST = { 33151, 63735, 59888 },                 -- Surge of Light, Serendipity, Borrowed Time
	WARRIOR = { 52437, 46916, 60503, 50227 },         -- Sudden Death, Bloodsurge, Taste for Blood, Sword and Board
	DEATHKNIGHT = { 51124, 59052 },                   -- Killing Machine, Freezing Fog
	HUNTER = { 56453, 53220 },                        -- Lock and Load, Improved Steady Shot
	ROGUE = {},
}

----------------------------------------------------------------------
-- Build name-keyed lookups (runs at login, when spell names are known)
----------------------------------------------------------------------
ns.CC, ns.CD, ns.Racial, ns.Spec, ns.ProcSuggest, ns.Trinket, ns.Resets = {}, {}, {}, {}, {}, {}, {}
ns.classCooldowns = {}  -- class -> ordered list of cooldown records

-- Shaman totems: the totem NPC has the same name as the spell that drops it, so the
-- nameplate can show the right icon. (Ranked totems end in "VI", "X"...; we strip that.)
local totemSpells = {
	8143,  -- Tremor Totem
	8177,  -- Grounding Totem
	2484,  -- Earthbind Totem
	8170,  -- Cleansing Totem
	16190, -- Mana Tide Totem
	5394,  -- Healing Stream Totem
	5675,  -- Mana Spring Totem
	3599,  -- Searing Totem
	8190,  -- Magma Totem
	30706, -- Totem of Wrath
	8227,  -- Flametongue Totem
	5730,  -- Stoneclaw Totem
	8071,  -- Stoneskin Totem
	8075,  -- Strength of Earth Totem
	8512,  -- Windfury Totem
	3738,  -- Wrath of Air Totem
	8181,  -- Frost Resistance Totem
	8184,  -- Fire Resistance Totem
	10595, -- Nature Resistance Totem
	6495,  -- Sentry Totem
	2062,  -- Earth Elemental Totem
	2894,  -- Fire Elemental Totem
}
-- English names work even before spell data is cached
ns.Totems = {
	["Tremor Totem"] = "Interface\\Icons\\Spell_Nature_TremorTotem",
	["Grounding Totem"] = "Interface\\Icons\\Spell_Nature_GroundingTotem",
	["Earthbind Totem"] = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
	["Cleansing Totem"] = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",
	["Mana Tide Totem"] = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
}

local function Info(id)
	local name, _, icon = GetSpellInfo(id)
	return name, icon
end

ns:Listen("LOGIN", function()
	for _, e in ipairs(ccList) do
		for i = 4, #e do
			local name, icon = Info(e[i])
			if name and not ns.CC[name] then
				ns.CC[name] = { cat = e[1], dur = e[2], dispel = e[3] or nil, icon = icon, id = e[i] }
			end
		end
	end
	for class, list in pairs(cdList) do
		local ordered = {}
		for _, e in ipairs(list) do
			local name, icon = Info(e[1])
			if name then
				local rec = { name = name, icon = icon, cd = e[2], always = e[3] or false, class = class }
				ns.CD[class .. ":" .. name] = rec
				ordered[#ordered + 1] = rec
			end
		end
		ns.classCooldowns[class] = ordered
	end
	for _, e in ipairs(racialList) do
		local name, icon = Info(e[1])
		if name then ns.Racial[name] = { name = name, icon = icon, cd = e[2] } end
	end
	for class, specs in pairs(specList) do
		for spec, ids in pairs(specs) do
			for _, id in ipairs(ids) do
				local name = Info(id)
				if name then ns.Spec[name] = { class = class, spec = spec } end
			end
		end
	end
	for class, ids in pairs(procSuggestions) do
		local list = {}
		for _, id in ipairs(ids) do
			local name, icon = Info(id)
			if name then list[#list + 1] = { name = name, icon = icon, id = id } end
		end
		ns.ProcSuggest[class] = list
	end
	for _, e in ipairs(resetList) do
		local name = Info(e[1])
		if name then
			if e[2] == "all" then
				ns.Resets[name] = "all"
			else
				local list = {}
				for _, id in ipairs(e[2]) do
					local n = Info(id)
					if n then list[#list + 1] = n end
				end
				ns.Resets[name] = list
			end
		end
	end
	for _, id in ipairs(ns.trinketSpells) do
		local name = Info(id)
		if name then ns.Trinket[name] = true end
	end
	for _, id in ipairs(totemSpells) do
		local name, icon = Info(id)
		if name then ns.Totems[name] = icon end
	end
end)

-- The PvP trinket *spell* has a dispel-style icon in 3.3.5, so show the actual item:
-- Medallion of the Alliance / Medallion of the Horde, by the player's faction.
ns.trinketIcons = {
	Alliance = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01",
	Horde = "Interface\\Icons\\INV_Jewelry_TrinketPVP_02",
}
ns.trinketIcon = ns.trinketIcons.Alliance

function ns:TrinketIcon(faction)
	return ns.trinketIcons[faction or ""] or ns.trinketIcon
end

----------------------------------------------------------------------
-- Icons for non-players, by creature type (UnitCreatureType); skull when unknown
----------------------------------------------------------------------
ns.creatureIcons = {
	Beast = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
	Humanoid = "Interface\\Icons\\INV_Misc_Head_Human_01",
	Undead = "Interface\\Icons\\Spell_Shadow_RaiseDead",
	Demon = "Interface\\Icons\\Spell_Shadow_SummonFelHunter",
	Elemental = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
	Dragonkin = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
	Mechanical = "Interface\\Icons\\INV_Gizmo_02",
	Giant = "Interface\\Icons\\Ability_Racial_Avatar",
	Totem = "Interface\\Icons\\Spell_Nature_StoneClawTotem",
	Critter = "Interface\\Icons\\Ability_Hunter_Pet_Rat",
	["Non-combat Pet"] = "Interface\\Icons\\INV_Box_PetCarrier_01",
	["Gas Cloud"] = "Interface\\Icons\\Spell_Nature_Cyclone",
}
ns.creatureFallback = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"

function ns:CreatureIcon(unit)
	local kind = unit and UnitCreatureType(unit)
	return (kind and ns.creatureIcons[kind]) or ns.creatureFallback
end
