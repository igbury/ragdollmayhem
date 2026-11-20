-- How the comic set (shared/Weapons, after the Rocket) moves when it is used.
--  * Third person: upper-body clips built in memory like AimPose (same joint signs: shoulder +X raises
--    the arm forward/up, elbow +X bends it, RightUpperArm +Z / LeftUpperArm -Z spread the arms out),
--    loaded through KeyframeId (Studio plays them as they are here; a live game needs them uploaded,
--    see AnimIds). USE: the clip played on each use; HOLD: a looping pose while the weapon is in hand.
--  * First person: view(id, u, firing, now) moves the viewmodel's right hand during a use (u: 0..1
--    over VIEW_TIME[id]) in place of the generic punch-swing / throw (init.client); recoil still adds.
local WeaponAnims = {}

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm",
}
local ORDER = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand" }

local function rot(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0))
end

-- two hands at the hip, the weapon pointing ahead (the minigun, flamethrower, chainsaw)
local HIP = {
	RightUpperArm = rot(35, 0, -10), RightLowerArm = rot(55), RightHand = rot(-50),
	LeftUpperArm = rot(55, 0, 35), LeftLowerArm = rot(50),
}

-- name -> { looped, priority, { { time, { joint = CFrame } } } }; a joint missing from a frame is at
-- rest there (identity) when the clip moves it at all, untouched (left to the walk) otherwise
local CLIPS = {
	Swing_Crowbar = { false, nil, { -- one-handed overhead chop
		{ 0, {} },
		{ 0.12, { RightUpperArm = rot(165, 0, -10), RightLowerArm = rot(70), UpperTorso = rot(6, 12, 0) } },
		{ 0.24, { RightUpperArm = rot(80, 0, 10), RightLowerArm = rot(10), RightHand = rot(-70), UpperTorso = rot(-12, -8, 0) } },
		{ 0.45, {} },
	} },
	Swing_Sledgehammer = { false, nil, { -- both hands, up over the head, slammed down
		{ 0, {} },
		{ 0.3, { RightUpperArm = rot(170, 0, -15), RightLowerArm = rot(45), LeftUpperArm = rot(165, 0, 25),
			LeftLowerArm = rot(50), UpperTorso = rot(12, 0, 0) } },
		{ 0.46, { RightUpperArm = rot(55, 0, -25), RightLowerArm = rot(5), RightHand = rot(-40), LeftUpperArm = rot(60, 0, 35),
			LeftLowerArm = rot(10), UpperTorso = rot(-28, 0, 0) } },
		{ 0.62, { RightUpperArm = rot(45, 0, -25), RightLowerArm = rot(5), RightHand = rot(-40), LeftUpperArm = rot(50, 0, 35),
			LeftLowerArm = rot(10), UpperTorso = rot(-25, 0, 0) } },
		{ 0.9, {} },
	} },
	Swing_Lightsaber = { false, nil, { -- a diagonal slash, high right to low left
		{ 0, {} },
		{ 0.1, { RightUpperArm = rot(140, 0, 35), RightLowerArm = rot(45), UpperTorso = rot(0, 20, 0) } },
		{ 0.22, { RightUpperArm = rot(60, 0, -45), RightLowerArm = rot(10), RightHand = rot(-100, 0, 20), UpperTorso = rot(-6, -25, 0) } },
		{ 0.4, {} },
	} },
	Thrust_Spear = { false, nil, { -- pulled back, then driven straight ahead, the point first
		{ 0, {} },
		{ 0.12, { RightUpperArm = rot(55, 0, 5), RightLowerArm = rot(95), RightHand = rot(-140), LeftUpperArm = rot(55, 0, -20),
			LeftLowerArm = rot(70), UpperTorso = rot(0, 15, 0) } },
		{ 0.24, { RightUpperArm = rot(90, 0, -8), RightLowerArm = rot(0), RightHand = rot(-90), LeftUpperArm = rot(75, 0, -35),
			LeftLowerArm = rot(25), UpperTorso = rot(-8, -18, 0) } },
		{ 0.45, {} },
	} },
	Throw_Lasso = { false, nil, { -- swung round over the head twice, then flung ahead
		{ 0, {} },
		{ 0.08, { RightUpperArm = rot(165, 0, -25), RightLowerArm = rot(35) } },
		{ 0.16, { RightUpperArm = rot(170, 0, 10), RightLowerArm = rot(20) } },
		{ 0.24, { RightUpperArm = rot(165, 0, -25), RightLowerArm = rot(35) } },
		{ 0.32, { RightUpperArm = rot(170, 0, 10), RightLowerArm = rot(20) } },
		{ 0.44, { RightUpperArm = rot(85, 0, 0), RightLowerArm = rot(0), UpperTorso = rot(-8, -10, 0) } },
		{ 0.7, {} },
	} },
	Throw_Bomb = { false, nil, { -- an overhand lob (TNT, C4)
		{ 0, {} },
		{ 0.14, { RightUpperArm = rot(160, 0, -20), RightLowerArm = rot(95), LeftUpperArm = rot(85, 0, -15),
			LeftLowerArm = rot(5), UpperTorso = rot(8, 20, 0) } },
		{ 0.28, { RightUpperArm = rot(75, 0, -5), RightLowerArm = rot(5), LeftUpperArm = rot(20, 0, -10),
			LeftLowerArm = rot(15), UpperTorso = rot(-10, -15, 0) } },
		{ 0.5, {} },
	} },
	Detonate_C4 = { false, nil, { -- a fist brought up in front of the chest, the thumb on the button
		{ 0, {} },
		{ 0.1, { RightUpperArm = rot(55, 0, -15), RightLowerArm = rot(85) } },
		{ 0.18, { RightUpperArm = rot(50, 0, -15), RightLowerArm = rot(95), RightHand = rot(-20) } },
		{ 0.45, {} },
	} },
	Place_Landmine = { false, nil, { -- bent over, the mine set down in front of the feet
		{ 0, {} },
		{ 0.25, { UpperTorso = rot(-55, 0, 0), RightUpperArm = rot(35, 0, -5), RightLowerArm = rot(5), LeftUpperArm = rot(15, 0, -10) } },
		{ 0.45, { UpperTorso = rot(-55, 0, 0), RightUpperArm = rot(30, 0, -5), RightLowerArm = rot(5), LeftUpperArm = rot(15, 0, -10) } },
		{ 0.75, {} },
	} },
	Hold_Twohand = { true, Enum.AnimationPriority.Action, { { 0, HIP }, { 0.5, HIP } } },
	-- the crowbar's arm rip (server/Specials ripArm, RIP_TUG 3 s then RIP_HANG 1.4 s): the claw held
	-- down in the shoulder and heaved on, the body leaning back into each pull, then yanked up with the
	-- torn arm on it and held up while it hangs there
	Rip_Crowbar = { false, Enum.AnimationPriority.Action4, (function()
		local down = { RightUpperArm = rot(70, 0, 5), RightLowerArm = rot(15), RightHand = rot(-75), UpperTorso = rot(-8, 0, 0) }
		local heave = { RightUpperArm = rot(85, 0, 5), RightLowerArm = rot(35), RightHand = rot(-75), UpperTorso = rot(10, 0, 0),
			LeftUpperArm = rot(20, 0, -15) }
		local up = { RightUpperArm = rot(150, 0, 10), RightLowerArm = rot(35), RightHand = rot(-20), UpperTorso = rot(12, 0, 0) }
		local frames = { { 0, down } }
		for i, t in { 0.45, 0.8, 1.25, 1.6, 2.05, 2.4, 2.85 } do
			table.insert(frames, { t, i % 2 == 1 and heave or down })
		end
		table.insert(frames, { 3.05, up })
		table.insert(frames, { 4.35, up })
		table.insert(frames, { 4.7, {} })
		return frames
	end)() },
}
WeaponAnims.CLIPS = CLIPS

-- the clip each use plays (third person)
WeaponAnims.USE = {
	Crowbar = "Swing_Crowbar", Sledgehammer = "Swing_Sledgehammer", Lightsaber = "Swing_Lightsaber",
	Spear = "Thrust_Spear", Lasso = "Throw_Lasso", TNT = "Throw_Bomb", C4 = "Throw_Bomb", Landmine = "Place_Landmine",
}
-- C4 with aim held: the detonator, not a throw
WeaponAnims.USE_AIMED = { C4 = "Detonate_C4" }
-- looping while the weapon is in hand (third person)
WeaponAnims.HOLD = { Minigun = "Hold_Twohand", Flamethrower = "Hold_Twohand", Chainsaw = "Hold_Twohand" }

function WeaponAnims.sequence(name: string): KeyframeSequence
	local clip = CLIPS[name]
	local moved = {}
	for _, frame in clip[3] do
		for joint in frame[2] do
			moved[joint] = true
		end
	end
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = clip[1]
	sequence.Priority = clip[2] or Enum.AnimationPriority.Action3
	for _, frame in clip[3] do
		local key = Instance.new("Keyframe")
		key.Time = frame[1]
		local byName = {}
		for _, joint in ORDER do
			local p = Instance.new("Pose")
			p.Name = joint
			p.CFrame = frame[2][joint] or CFrame.identity
			p.Weight = moved[joint] and 1 or 0
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.Parent = byName[PARENT[joint]] or key
			byName[joint] = p
		end
		key.Parent = sequence
	end
	return sequence
end

-- First person -------------------------------------------------------------------------------------
-- seconds a use of these takes on screen (the viewmodel's swing timer); others keep the generic 0.2
WeaponAnims.VIEW_TIME = { Crowbar = 0.28, Sledgehammer = 0.5, Lightsaber = 0.24, Spear = 0.35, Lasso = 0.5, Landmine = 0.55, C4 = 0.3 }
-- these show held level and pointing ahead (gun style) though their kind is melee or thrown
WeaponAnims.LEVEL = { Chainsaw = true }
-- these stay in the hand after a use (the generic throw hides a thrown weapon until its cooldown is
-- over): the lasso keeps its coil, the landmine is in the hand until it is put down, C4's detonator
WeaponAnims.KEEP = { Lasso = true }

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- The right hand for a use `u` (0..1) of weapon `id`, camera space: move (studs, on the rest spot),
-- tilt / yaw / roll (degrees, replacing the generic wrist); nil keeps the generic motion. When this
-- returns a table the generic punch / swing extension is left out for that hand (init.client).
-- hookT: seconds since the crowbar's claw went into a shoulder (nil when it has not): the arm rip
function WeaponAnims.view(id: string, u: number, firing: boolean, now: number, hookT: number?): { [string]: any }?
	if id == "Crowbar" and hookT and hookT < 4.4 then
		if hookT < 3 then -- held down in the shoulder, heaved on: it judders back with each pull
			local heave = math.max(0, math.sin(hookT * math.pi * 2.6))
			return { move = Vector3.new(0.05, -0.45 + 0.08 * heave, -0.55 + 0.25 * heave)
				+ Vector3.new(math.sin(now * 70), math.sin(now * 83), 0) * 0.015, tilt = -100 + 12 * heave, yaw = 0, roll = 0 }
		end
		local yank = smooth((hookT - 3) / 0.2) -- torn free: up in front of the face with the arm on the claw
		return { move = Vector3.new(0.05 + 0.1 * yank, -0.45 + 0.75 * yank, -0.55 + 0.2 * yank), tilt = -100 + 85 * yank, yaw = 0, roll = 0 }
	end
	if u >= 1 and (id == "Spear" or id == "Lasso" or id == "Landmine") then
		return nil -- at rest: held as any melee / thrown weapon is
	end
	if id == "Spear" then -- held upright; on a use it tips point-first and is driven ahead
		local thrust = math.sin(math.clamp(u, 0, 1) * math.pi)
		local tip = smooth(u / 0.25) * (1 - smooth((u - 0.7) / 0.3))
		return { move = Vector3.new(-0.15 * thrust, 0.35 * tip, -1.1 * thrust), tilt = -25 - 65 * tip, yaw = 0, roll = 0 }
	elseif id == "Chainsaw" then -- level, ahead; it judders while the trigger is held and leans in on each cut
		local buzz = firing and 0.025 or 0.006
		local jitter = Vector3.new(math.sin(now * 91) * buzz, math.sin(now * 113) * buzz, 0)
		local lean = math.sin(math.clamp(u, 0, 1) * math.pi)
		-- low on the right, out of the middle of the view, the bar running ahead
		return { move = jitter + Vector3.new(0.45, -0.3, 0.2 - 0.25 * lean), tilt = 0, yaw = 0, roll = 0 }
	elseif id == "Lasso" then -- the loop whirls over the head, then the arm flings it forward
		if u < 0.6 then
			local a = u / 0.6 * math.pi * 4
			return { move = Vector3.new(math.cos(a) * 0.35 - 0.1, 0.45 + math.sin(a) * 0.12, -0.2), tilt = -10, yaw = 0, roll = 0 }
		end
		local fling = math.sin(math.clamp((u - 0.6) / 0.4, 0, 1) * math.pi)
		return { move = Vector3.new(0, 0.3 * (1 - fling), -0.8 * fling), tilt = -60 * fling, yaw = 0, roll = 0 }
	elseif id == "Landmine" then -- reaching down to set it on the floor ahead
		local down = math.sin(math.clamp(u, 0, 1) * math.pi)
		return { move = Vector3.new(-0.2 * down, -1.1 * down, -0.5 * down), tilt = -15, yaw = 0, roll = 0 }
	elseif id == "Minigun" or id == "Flamethrower" then -- the weight shakes in the hands while it runs
		local buzz = firing and (id == "Minigun" and 0.03 or 0.012) or 0
		return { move = Vector3.new(math.sin(now * 97) * buzz, math.sin(now * 131) * buzz, 0) }
	end
	return nil
end

return WeaponAnims
