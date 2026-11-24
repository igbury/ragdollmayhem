-- Dummy animations built in memory: getting up off the ground (from the front or the back), the
-- stiff leg of a limp, crawling and hopping on one leg (Body.mobility). Signs, as in DummyPoses: +X swings a limb forward and bends an elbow,
-- -X bends a knee and pitches a torso forward. The LowerTorso pose moves the body against the
-- standing root (the root is already up, invisible): at the start it lies on the ground.
-- ponytail: KeyframeSequenceProvider ids only play in Studio, like the other animations here;
-- upload them and use asset ids before publishing.
local keyframeId = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("KeyframeId"))
local clips = require(game:GetService("ReplicatedStorage").Shared:WaitForChild("AnimationClips"))

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

-- the block (boxing gloves, right mouse): a high guard, both gloves up in front of the face, elbows
-- tucked in front of the ribs, chin down. Above the guard loop, under the blows.
local BLOCK = {
	UpperTorso = rx(-14), Head = rx(12),
	LeftUpperArm = rxy(70, -12, 8), LeftLowerArm = rx(140),
	RightUpperArm = rxy(70, 12, -8), RightLowerArm = rx(140),
}
Anims.block = build("BoxingBlock", { { 0, BLOCK }, { 1, BLOCK } }, true, Enum.AnimationPriority.Action2, true)

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
local function polished(name: string): Animation?
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = keyframeId(clips.build(name))
	if animation.AnimationId == "" then
		animation:Destroy()
		return nil
	end
	return animation
end
Anims.stagger = polished("DummyStagger")
Anims.staggers = {
	front = Anims.stagger,
	back = polished("DummyStaggerBack") or Anims.stagger,
	left = polished("DummyStaggerLeft") or Anims.stagger,
	right = polished("DummyStaggerRight") or Anims.stagger,
}

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

-- down on its knees, both hands at the ground in front (tending the hurt, Body.help)
Anims.dig = polished("Dig")

-- a broken leg held stiff and a little out: the walk only moves the good one, so it drags
Anims.limp = {}
for _, side in { "Left", "Right" } do
	Anims.limp[side:lower()] = polished("Limp" .. side)
end

-- A leg in a cast (server Body.cast: the knee and ankle welded straight, so only its hip moves): on
-- crutches, swing-through. Both crutches go out ahead and plant, the body leans onto them, swings up
-- and through between them and lands on the good foot; the cast leg is held a little forward, clear
-- of the ground. `side` is the leg in the cast. A slung arm (Body.sling) is welded: the swing skips it.
Anims.crutch = {}
for _, side in { "Left", "Right" } do
	local good, cast = side == "Left" and "Right" or "Left", side
	local function crutches(shoulder: number, elbow: number)
		return { LeftUpperArm = rxy(shoulder, 0, -6), RightUpperArm = rxy(shoulder, 0, 6), LeftLowerArm = rx(elbow), RightLowerArm = rx(elbow) }
	end
	local planted = with(crutches(30, 14), { -- crutches out ahead, leaning onto them, the good foot behind
		LowerTorso = body(0.08, -8), UpperTorso = rx(-10), Head = rx(8),
		[good .. "UpperLeg"] = rx(-16), [good .. "LowerLeg"] = rx(-14), [good .. "Foot"] = rx(12),
		[cast .. "UpperLeg"] = rx(18),
	})
	local swung = with(crutches(4, 6), { -- up on the crutches, the body swinging through between them
		LowerTorso = body(-0.14, 2), UpperTorso = rx(-4),
		[good .. "UpperLeg"] = rx(26), [good .. "LowerLeg"] = rx(-34), [good .. "Foot"] = rx(-4),
		[cast .. "UpperLeg"] = rx(26),
	})
	local landed = with(crutches(-14, 4), { -- on the good foot, ahead of the crutches
		LowerTorso = body(0.1, 4), UpperTorso = rx(-2), Head = rx(-4),
		[good .. "UpperLeg"] = rx(14), [good .. "LowerLeg"] = rx(-12), [good .. "Foot"] = rx(-2),
		[cast .. "UpperLeg"] = rx(14),
	})
	Anims.crutch[side:lower()] = build("DummyCrutch" .. side, {
		{ 0, planted, "snap" }, -- the swing off the crutches is quick
		{ 0.32, swung },
		{ 0.55, landed, "load" }, -- and the crutches come round again
		{ 0.9, planted },
	}, true, Enum.AnimationPriority.Action)
end


-- No leg to stand on (server Body.mobility "crawl"): face down on the ground, pulling itself along
-- hand over hand. Lying flat like the start of GetUpFront (the root stays up, invisible), head up
-- to see where it goes; each arm in turn reaches out ahead and drags the body up to it, and the
-- shoulders roll with every pull. A lost arm simply is not there: the other one keeps pulling.
local REACH, REACH_EL = rx(150), rx(10) -- out ahead, the hand on the ground in front of the head
local PULL, PULL_EL = rx(95), rx(70) -- under the chest, elbow bent: the body has come up to it
local function prone(roll: number, lift: number): CFrame
	return body(LIE - lift, -90) * CFrame.Angles(0, math.rad(roll), 0) -- Y is along the body here: a roll
end
local DRAG = { LeftUpperLeg = rx(-6), RightUpperLeg = rx(-6), LeftLowerLeg = rx(-12), RightLowerLeg = rx(-12) }
Anims.crawl = build("DummyCrawl", {
	{ 0, with(DRAG, { LowerTorso = prone(8, 0), Head = rx(45),
		LeftUpperArm = REACH, LeftLowerArm = REACH_EL, RightUpperArm = PULL, RightLowerArm = PULL_EL }) },
	{ 0.3, with(DRAG, { LowerTorso = prone(0, 0.12), Head = rx(40),
		LeftUpperArm = rx(120), LeftLowerArm = rx(45), RightUpperArm = rx(125), RightLowerArm = rx(35) }) },
	{ 0.6, with(DRAG, { LowerTorso = prone(-8, 0), Head = rx(45),
		LeftUpperArm = PULL, LeftLowerArm = PULL_EL, RightUpperArm = REACH, RightLowerArm = REACH_EL }) },
	{ 0.9, with(DRAG, { LowerTorso = prone(0, 0.12), Head = rx(40),
		LeftUpperArm = rx(125), LeftLowerArm = rx(35), RightUpperArm = rx(120), RightLowerArm = rx(45) }) },
	{ 1.2, with(DRAG, { LowerTorso = prone(8, 0), Head = rx(45),
		LeftUpperArm = REACH, LeftLowerArm = REACH_EL, RightUpperArm = PULL, RightLowerArm = PULL_EL }) },
}, true, Enum.AnimationPriority.Action)

-- One leg left (Body.mobility "hop"): it hops along on it, crouching into every landing and
-- springing off again, the stump of the other held up out of the way and both arms flung out for
-- balance. `side` is the leg it stands on.
Anims.hop = {}
for _, side in { "Left", "Right" } do
	local stand, stump = side, side == "Left" and "Right" or "Left"
	local function arms(x: number, out: number)
		return { LeftUpperArm = rxy(x, 0, -out), RightUpperArm = rxy(x, 0, out), LeftLowerArm = rx(25), RightLowerArm = rx(25) }
	end
	local landed = with(arms(10, 65), {
		LowerTorso = body(0.3, -10), UpperTorso = rx(-6),
		[stand .. "UpperLeg"] = rx(32), [stand .. "LowerLeg"] = rx(-58), [stand .. "Foot"] = rx(26),
		[stump .. "UpperLeg"] = rx(40), [stump .. "LowerLeg"] = rx(-30),
	})
	local up = with(arms(25, 35), {
		LowerTorso = body(-0.45, -4), UpperTorso = rx(-2), Head = rx(-6),
		[stand .. "UpperLeg"] = rx(8), [stand .. "LowerLeg"] = rx(-14), [stand .. "Foot"] = rx(-18),
		[stump .. "UpperLeg"] = rx(50), [stump .. "LowerLeg"] = rx(-40),
	})
	Anims.hop[side:lower()] = build("DummyHop" .. side, {
		{ 0, landed, "snap" }, -- the spring off the bent knee is quick
		{ 0.25, up, "load" }, -- and the drop back onto it speeds up
		{ 0.55, landed },
	}, true, Enum.AnimationPriority.Action)
end

return Anims
