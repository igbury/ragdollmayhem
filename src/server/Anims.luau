-- Dummy animations built in memory: getting up off the ground (from the front or the back) and
-- the stiff leg of a limp. Signs, as in DummyPoses: +X swings a limb forward and bends an elbow,
-- -X bends a knee and pitches a torso forward. The LowerTorso pose moves the body against the
-- standing root (the root is already up, invisible): at the start it lies on the ground.
-- ponytail: KeyframeSequenceProvider ids only play in Studio, like the other animations here;
-- upload them and use asset ids before publishing.
local keyframeId = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("KeyframeId"))

local Anims = {}

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg", RightFoot = "RightLowerLeg",
}
local ORDER = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm",
	"RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }

local function rx(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end
-- the LowerTorso: `drop` studs under standing height, pitched `pitch` degrees
local function body(drop: number, pitch: number): CFrame
	return CFrame.new(0, -drop, 0) * rx(pitch)
end
local function arms(shoulder: number, elbow: number)
	return rx(shoulder), rx(elbow)
end

-- keys = { { time, { [part] = CFrame }, ease? } }; a part left out of a key is held straight
-- (identity) unless `partial`, where only the parts named in some key are driven at all.
-- `ease` shapes the move OUT of that key toward the next one: "snap" (Out: explosive start,
-- settling into the next pose: strikes), "load" (In: slow start that speeds up: wind-ups, falls),
-- "bounce" (Elastic Out: a recoil that overshoots) or "hold" (Constant: jump to the next key).
-- Left out it is a smooth InOut, as before.
local EASE = {
	snap = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.Out },
	load = { Enum.PoseEasingStyle.CubicV2, Enum.PoseEasingDirection.In },
	bounce = { Enum.PoseEasingStyle.Elastic, Enum.PoseEasingDirection.Out },
	hold = { Enum.PoseEasingStyle.Constant, Enum.PoseEasingDirection.In },
}
local function build(name: string, keys, loop: boolean, priority: Enum.AnimationPriority, partial: boolean?): Animation
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = loop
	sequence.Priority = priority
	-- partial: a part is driven in every key if any key names it (else a key that leaves it out
	-- would let go of it halfway through and the base animation would pop back in)
	local driven = {}
	for _, key in keys do
		for part in key[2] do
			driven[part] = true
		end
	end
	for _, key in keys do
		local frame = Instance.new("Keyframe")
		frame.Time = key[1]
		local ease = EASE[key[3] or ""]
		local byName = {}
		for _, part in ORDER do
			local pose = Instance.new("Pose")
			pose.Name = part
			pose.CFrame = key[2][part] or CFrame.identity
			pose.Weight = (part == "HumanoidRootPart" or (partial and not driven[part])) and 0 or 1
			pose.EasingStyle = ease and ease[1] or Enum.PoseEasingStyle.CubicV2
			pose.EasingDirection = ease and ease[2] or Enum.PoseEasingDirection.InOut
			pose.Parent = byName[PARENT[part]] or frame
			byName[part] = pose
		end
		frame.Parent = sequence
	end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = keyframeId(sequence)
	return animation
end

local LIE = 1.55 -- how far the hips sit under standing height when lying flat (rig: HipHeight 2.2)
local sh, el = arms(70, 80)
local oneKnee = { -- right foot planted, left knee down, about to push up
	LowerTorso = body(0.55, -15),
	RightUpperLeg = rx(95), RightLowerLeg = rx(-95),
	LeftUpperLeg = rx(15), LeftLowerLeg = rx(-90),
	LeftUpperArm = rx(35), RightUpperArm = rx(35), LeftLowerArm = rx(40), RightLowerArm = rx(40),
}
Anims.LENGTH = 1.45

-- face down, head forward: push up onto all fours, knees, one knee, up
Anims.fromFront = build("GetUpFront", {
	{ 0, { LowerTorso = body(LIE, -90), LeftUpperArm = sh, RightUpperArm = sh, LeftLowerArm = el, RightLowerArm = el, Head = rx(30) } },
	{ 0.35, {
		LowerTorso = body(0.75, -80), Head = rx(35),
		LeftUpperLeg = rx(80), RightUpperLeg = rx(80), LeftLowerLeg = rx(-90), RightLowerLeg = rx(-90),
		LeftUpperArm = rx(80), RightUpperArm = rx(80),
	} },
	{ 0.7, {
		LowerTorso = body(0.6, -10),
		LeftUpperLeg = rx(10), RightUpperLeg = rx(10), LeftLowerLeg = rx(-90), RightLowerLeg = rx(-90),
		LeftUpperArm = rx(20), RightUpperArm = rx(20),
	} },
	{ 1.0, oneKnee, "snap" }, -- the push up off the knee is quick, then it settles
	{ Anims.LENGTH, {} },
}, false, Enum.AnimationPriority.Action4)

-- face up, head back: sit up, tuck the feet in, one knee, up
Anims.fromBack = build("GetUpBack", {
	{ 0, { LowerTorso = body(LIE, 90) } },
	{ 0.35, {
		LowerTorso = body(1.75, 15), Head = rx(-10),
		LeftUpperLeg = rx(75), RightUpperLeg = rx(75), LeftLowerLeg = rx(-60), RightLowerLeg = rx(-60),
		LeftUpperArm = rx(-40), RightUpperArm = rx(-40),
	} },
	{ 0.7, {
		LowerTorso = body(0.95, -35),
		LeftUpperLeg = rx(125), RightUpperLeg = rx(125), LeftLowerLeg = rx(-130), RightLowerLeg = rx(-130),
		LeftUpperArm = rx(60), RightUpperArm = rx(60),
	} },
	{ 1.0, oneKnee, "snap" }, -- the push up off the knee is quick, then it settles
	{ Anims.LENGTH, {} },
}, false, Enum.AnimationPriority.Action4)

-- Fighting ------------------------------------------------------------------------------------
-- Every blow has the three beats that make it read from across the arena: a wind-up (the body
-- coils the other way, slow: "load"), the strike (fast out of the coil, settling on the target:
-- "snap") and a recovery with a little overshoot back to guard. The fists start and end in the
-- guard pose, so blows chain into each other and into the guard loop without a pop.
local function yaw(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end
local function rxy(x: number, y: number, z: number?): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z or 0))
end
-- fists up by the chin, elbows in, a slight hunch: the stance every blow starts and ends in
local GUARD = {
	UpperTorso = rx(-8), Head = rx(6),
	LeftUpperArm = rxy(55, -20, 10), LeftLowerArm = rx(115),
	RightUpperArm = rxy(45, 20, -10), RightLowerArm = rx(120),
}
local function with(base, changes)
	local out = table.clone(base)
	for k, v in changes do
		out[k] = v
	end
	return out
end

-- held while it fights: fists up, bouncing on the shoulders (arms and spine only: the legs walk)
Anims.guard = build("DummyGuard", {
	{ 0, GUARD },
	{ 0.4, with(GUARD, { UpperTorso = rx(-11), LeftUpperArm = rxy(60, -20, 10), RightUpperArm = rxy(50, 20, -10) }) },
	{ 0.8, GUARD },
}, true, Enum.AnimationPriority.Action, true)

-- the jab: the lead (left) hand straight out and back, quick, the shoulder turning into it
Anims.PUNCH_HIT = 0.14 -- when the fist lands
Anims.punch = build("DummyJab", {
	{ 0, GUARD, "load" },
	{ 0.06, with(GUARD, { UpperTorso = rx(-8) * yaw(12), LeftUpperArm = rxy(50, -15, 10), LeftLowerArm = rx(125) }), "snap" },
	{ Anims.PUNCH_HIT, with(GUARD, { UpperTorso = rx(-12) * yaw(-22), Head = rx(4) * yaw(10), LeftUpperArm = rxy(92, 0, 0), LeftLowerArm = rx(4) }) },
	{ 0.24, with(GUARD, { UpperTorso = rx(-10) * yaw(-12), LeftUpperArm = rxy(80, -8, 5), LeftLowerArm = rx(40) }), "bounce" },
	{ 0.42, GUARD },
}, false, Enum.AnimationPriority.Action3, true)

-- the haymaker: the right fist drawn far back with the whole torso turned away (the tell a
-- player can read and get out of the way of), then swung round in a wide arc
Anims.HAYMAKER_HIT = 0.5
Anims.haymaker = build("DummyHaymaker", {
	{ 0, GUARD, "load" },
	{ 0.36, with(GUARD, { -- wound up: torso turned right and back, fist by the ear, weight on the back foot
		UpperTorso = rx(6) * yaw(42), Head = yaw(-30),
		RightUpperArm = rxy(10, 60, -60), RightLowerArm = rx(120),
		LeftUpperArm = rxy(70, -10, 20), LeftLowerArm = rx(70),
	}), "snap" },
	{ Anims.HAYMAKER_HIT, with(GUARD, { -- through: torso whipped round, arm long across the front
		UpperTorso = rx(-22) * yaw(-48), Head = rx(-6) * yaw(20),
		RightUpperArm = rxy(95, -35, -10), RightLowerArm = rx(15),
		LeftUpperArm = rxy(30, -30, 20), LeftLowerArm = rx(100),
	}) },
	{ 0.68, with(GUARD, { UpperTorso = rx(-18) * yaw(-30), RightUpperArm = rxy(60, -40, 0), RightLowerArm = rx(60) }), "bounce" },
	{ 1.0, GUARD },
}, false, Enum.AnimationPriority.Action3, true)

-- a front kick: knee up (chamber), foot driven out straight, back down; the arms swing for balance
Anims.KICK_HIT = 0.32
Anims.kick = build("DummyKick", {
	{ 0, GUARD, "load" },
	{ 0.18, with(GUARD, { -- chamber: knee high, shin folded, leaning back
		UpperTorso = rx(8), RightUpperLeg = rx(85), RightLowerLeg = rx(-110), RightFoot = rx(20),
		LeftUpperLeg = rx(-5), LeftLowerLeg = rx(-12),
	}), "snap" },
	{ Anims.KICK_HIT, with(GUARD, { -- extended: the sole drives forward at belly height
		UpperTorso = rx(16), Head = rx(-8),
		RightUpperLeg = rx(95), RightLowerLeg = rx(-5), RightFoot = rx(-25),
		LeftUpperLeg = rx(-8), LeftLowerLeg = rx(-15),
		LeftUpperArm = rxy(30, -20, 35), RightUpperArm = rxy(-20, 20, -40), RightLowerArm = rx(40),
	}) },
	{ 0.5, with(GUARD, { RightUpperLeg = rx(70), RightLowerLeg = rx(-90), RightFoot = rx(15) }), "load" },
	{ 0.72, with(GUARD, { RightUpperLeg = CFrame.identity, RightLowerLeg = CFrame.identity, RightFoot = CFrame.identity,
		LeftUpperLeg = CFrame.identity, LeftLowerLeg = CFrame.identity }) },
}, false, Enum.AnimationPriority.Action4, true)

-- took a hit while still standing: the spine whips back, head after it, arms thrown out, then
-- back to where it was. Short, so it reads on every punch without stalling the fight.
Anims.stagger = build("DummyStagger", {
	{ 0, {}, "snap" },
	{ 0.09, { UpperTorso = rx(18) * yaw(-8), Head = rx(26), LeftUpperArm = rxy(25, 0, -35), RightUpperArm = rxy(25, 0, 35),
		LeftLowerArm = rx(30), RightLowerArm = rx(30) }, "bounce" },
	{ 0.45, {} },
}, false, Enum.AnimationPriority.Action2, true)

-- a sidestep out of the way of a punch: duck and lean to the left, fists still up
Anims.dodge = build("DummyDodge", {
	{ 0, GUARD, "snap" },
	{ 0.12, with(GUARD, { UpperTorso = rxy(-20, 0, 24), Head = rxy(-5, 0, 10), LowerTorso = body(0.35, 0) * rxy(0, 0, 8),
		LeftUpperLeg = rxy(20, 0, -18), LeftLowerLeg = rx(-40), RightUpperLeg = rxy(10, 0, 8), RightLowerLeg = rx(-20) }) },
	{ 0.3, with(GUARD, { UpperTorso = rxy(-14, 0, 14), LowerTorso = body(0.2, 0) }), "bounce" },
	{ 0.55, with(GUARD, { LowerTorso = CFrame.identity, LeftUpperLeg = CFrame.identity, LeftLowerLeg = CFrame.identity,
		RightUpperLeg = CFrame.identity, RightLowerLeg = CFrame.identity }) },
}, false, Enum.AnimationPriority.Action4, true)

-- "come here": the right hand beckons twice, chin up (while it circles, waiting its turn)
Anims.taunt = build("DummyTaunt", {
	{ 0, GUARD },
	{ 0.2, with(GUARD, { RightUpperArm = rxy(75, 15, -5), RightLowerArm = rx(20), Head = rx(-12) }) },
	{ 0.38, with(GUARD, { RightUpperArm = rxy(75, 15, -5), RightLowerArm = rx(95), Head = rx(-12) * yaw(-8) }), "snap" },
	{ 0.56, with(GUARD, { RightUpperArm = rxy(75, 15, -5), RightLowerArm = rx(20), Head = rx(-14) }) },
	{ 0.74, with(GUARD, { RightUpperArm = rxy(75, 15, -5), RightLowerArm = rx(95), Head = rx(-14) * yaw(8) }), "snap" },
	{ 0.92, with(GUARD, { RightUpperArm = rxy(75, 15, -5), RightLowerArm = rx(20) }) },
	{ 1.2, GUARD },
}, false, Enum.AnimationPriority.Action2, true)

-- down on its knees, both hands digging at the ground in front (burying)
local dig = {
	LowerTorso = body(0.6, -25),
	LeftUpperLeg = rx(25), RightUpperLeg = rx(25), LeftLowerLeg = rx(-90), RightLowerLeg = rx(-90),
	LeftUpperArm = rx(55), RightUpperArm = rx(55), LeftLowerArm = rx(20), RightLowerArm = rx(20),
}
local scoop = table.clone(dig)
scoop.LeftUpperArm, scoop.RightUpperArm = rx(90), rx(90)
Anims.dig = build("Dig", { { 0, dig }, { 0.5, scoop }, { 1, dig } }, true, Enum.AnimationPriority.Action3)

-- a broken leg held stiff and a little out: the walk only moves the good one, so it drags
Anims.limp = {}
for _, side in { "Left", "Right" } do
	local out = CFrame.Angles(math.rad(-8), 0, math.rad(side == "Left" and -6 or 6))
	local key = { [side .. "UpperLeg"] = out, [side .. "LowerLeg"] = rx(-4), [side .. "Foot"] = rx(10) }
	Anims.limp[side:lower()] = build("Limp" .. side, { { 0, key }, { 1, key } }, true, Enum.AnimationPriority.Action, true)
end

return Anims
