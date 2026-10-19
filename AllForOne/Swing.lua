-- AllForOne: swing timer
-- Two thin bars right under your cast bar: main hand (top) and off hand (below).
-- Hunters see Auto Shot and wand users see Shoot in the top bar.
-- Shows only while you auto-attack.
local _, ns = ...
local colors = ns.colors
local GetTime, UnitGUID = GetTime, UnitGUID

local mh, oh            -- bar frames
local mhStart, mhSpeed  -- current main-hand swing
local ohStart, ohSpeed
local rangedMode = false
local meleeOn, rangedOn = false, false

-- abilities that replace your next main-hand swing, and casts that reset it
local nextSwing, resetSwing = {}, {}

local function Bar(h, y, c)
	local b = ns:CreateBar(ns.root, 360, h)
	b:SetPoint("TOPLEFT", ns.root, "CENTER", -180, y)
	b:SetStatusBarColor(c[1], c[2], c[3])
	b:SetMinMaxValues(0, 1)
	b:Hide()
	return b
end

local function StartMain(now, speed)
	mhStart, mhSpeed = now, speed or UnitAttackSpeed("player")
end

local function StartOff(now)
	local _, off = UnitAttackSpeed("player")
	if off then ohStart, ohSpeed = now, off end
end

-- Off-hand swings aren't labeled in the 3.3.5 combat log:
-- give the swing to whichever hand was due closest to now.
local function OnSwing()
	local now = GetTime()
	local _, off = UnitAttackSpeed("player")
	if not off or not mhStart then StartMain(now) return end
	if not ohStart then StartOff(now) return end
	local mhDue = mhStart + mhSpeed
	local ohDue = ohStart + ohSpeed
	if math.abs(now - mhDue) <= math.abs(now - ohDue) then StartMain(now) else StartOff(now) end
end

-- You parried: your next main-hand swing comes 40% sooner (never under 20% of the swing)
local function ParryHaste()
	if not mhStart then return end
	local now = GetTime()
	local remaining = mhStart + mhSpeed - now
	local cut = 0.4 * mhSpeed
	if remaining - cut < 0.2 * mhSpeed then
		mhStart = now + 0.2 * mhSpeed - mhSpeed
	else
		mhStart = mhStart - cut
	end
end

local function Update()
	local now = GetTime()
	local active = meleeOn or rangedOn or ns.testing
	local mhLeft = mhStart and (mhStart + mhSpeed - now) or -1
	if ns.testing then
		mh:SetValue(0.62); mh:Show()
		oh:SetValue(0.28); oh:Show()
		return
	end
	if active and mhStart and mhLeft > -0.5 then
		mh:SetValue(math.min(1, (now - mhStart) / mhSpeed))
		local c = rangedMode and colors.channel or ns.colors.text
		mh:SetStatusBarColor(c[1], c[2], c[3])
		mh:Show()
	else
		mh:Hide()
	end
	local _, off = UnitAttackSpeed("player")
	if active and not rangedMode and off and ohStart and (ohStart + ohSpeed - now) > -0.5 then
		oh:SetValue(math.min(1, (now - ohStart) / ohSpeed))
		oh:Show()
	else
		oh:Hide()
	end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", Update)
driver:Hide()

local lastMain, lastOff

ns:Listen("LOGIN", function()
	for _, id in ipairs({ 78, 845, 6807, 2973 }) do -- Heroic Strike, Cleave, Maul, Raptor Strike
		local name = GetSpellInfo(id)
		if name then nextSwing[name] = true end
	end
	local slam = GetSpellInfo(1464)
	if slam then resetSwing[slam] = true end
	ns.autoShot = GetSpellInfo(75)
	ns.wandShot = GetSpellInfo(5019)

	mh = Bar(5, -378, ns.colors.text)
	oh = Bar(4, -385, ns.colors.muted)
	lastMain, lastOff = UnitAttackSpeed("player")
	driver:Show()
end)

-- auto-attack on/off
ns:On("PLAYER_ENTER_COMBAT", function() meleeOn = true; rangedMode = false end)
ns:On("PLAYER_LEAVE_COMBAT", function() meleeOn = false end)
ns:On("START_AUTOREPEAT_SPELL", function() rangedOn = true; rangedMode = true end)
ns:On("STOP_AUTOREPEAT_SPELL", function() rangedOn = false end)

-- haste changes mid-swing: stretch or shrink what's left
ns:On("UNIT_ATTACK_SPEED", function(_, unit)
	if unit ~= "player" then return end
	local main, off = UnitAttackSpeed("player")
	local now = GetTime()
	if mhStart and lastMain and main and lastMain > 0 then
		local done = (now - mhStart) / mhSpeed
		mhSpeed = main
		mhStart = now - done * main
	end
	if ohStart and lastOff and off and lastOff > 0 then
		local done = (now - ohStart) / ohSpeed
		ohSpeed = off
		ohStart = now - done * off
	end
	lastMain, lastOff = main, off
end)

ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, event, srcGUID, _, _, dstGUID, _, _, a1, a2)
	local me = UnitGUID("player")
	if srcGUID == me then
		if event == "SWING_DAMAGE" or event == "SWING_MISSED" then
			rangedMode = false
			OnSwing()
		elseif (event == "SPELL_DAMAGE" or event == "SPELL_MISSED") and nextSwing[a2] then
			rangedMode = false
			StartMain(GetTime())
		end
	elseif dstGUID == me and event == "SWING_MISSED" and a1 == "PARRY" then
		ParryHaste()
	end
end)

-- Auto Shot / wand Shoot / Slam
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, spell)
	if unit ~= "player" or not spell then return end
	if spell == ns.autoShot or spell == ns.wandShot then
		rangedMode = true
		local speed = UnitRangedDamage("player")
		StartMain(GetTime(), speed)
	elseif resetSwing[spell] then
		StartMain(GetTime())
	end
end)

ns:On("PLAYER_ENTERING_WORLD", function() mhStart, ohStart = nil, nil; meleeOn, rangedOn = false, false end)
