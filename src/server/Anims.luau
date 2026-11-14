-- Dummy animations built in memory: getting up off the ground (from the front or the back) and
-- the stiff leg of a limp. Signs, as in DummyPoses: +X swings a limb forward and bends an elbow,
-- -X bends a knee and pitches a torso forward. The LowerTorso pose moves the body against the
-- standing root (the root is already up, invisible): at the start it lies on the ground.
-- ponytail: KeyframeSequenceProvider ids only play in Studio, like the other animations here;
-- upload them and use asset ids before publishing.
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

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

-- keys = { { time, { [part] = CFrame } } }; a part left out of a key is held straight (identity)
-- unless `partial`, where only the named parts are driven at all.
local function build(name: string, keys, loop: boolean, priority: Enum.AnimationPriority, partial: boolean?): Animation
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = loop
	sequence.Priority = priority
	for _, key in keys do
		local frame = Instance.new("Keyframe")
		frame.Time = key[1]
		local byName = {}
		for _, part in ORDER do
			local pose = Instance.new("Pose")
			pose.Name = part
			pose.CFrame = key[2][part] or CFrame.identity
			pose.Weight = (part == "HumanoidRootPart" or (partial and not key[2][part])) and 0 or 1
			pose.EasingStyle = Enum.PoseEasingStyle.CubicV2
			pose.EasingDirection = Enum.PoseEasingDirection.InOut
			pose.Parent = byName[PARENT[part]] or frame
			byName[part] = pose
		end
		frame.Parent = sequence
	end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
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
	{ 1.0, oneKnee },
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
	{ 1.0, oneKnee },
	{ Anims.LENGTH, {} },
}, false, Enum.AnimationPriority.Action4)

-- a dummy's punch: the right arm thrown forward and back, the shoulders turning into it
Anims.PUNCH_HIT = 0.12 -- when the fist lands
Anims.punch = build("DummyPunch", {
	{ 0, { RightUpperArm = rx(20), RightLowerArm = rx(70), UpperTorso = CFrame.Angles(0, math.rad(25), 0) } },
	{ Anims.PUNCH_HIT, { RightUpperArm = rx(95), RightLowerArm = rx(5), UpperTorso = CFrame.Angles(0, math.rad(-20), 0) } },
	{ 0.4, { RightUpperArm = rx(20), RightLowerArm = rx(70) } },
}, false, Enum.AnimationPriority.Action3, true)

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
