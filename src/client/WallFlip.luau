-- Wall backflip | 0.7 s, played once: from the wall cling the right foot plants on the wall and
-- kicks, arms throw up overhead, then the body tucks and turns a full backflip and opens up for
-- the fall. Built in memory like RollForward (no upload). Same joint signs: LowerTorso +X pitches
-- the body backward, hip +X brings the thigh up, knee -X bends it, shoulder +X raises the arm
-- forward/up, elbow +X bends it, neck +X lifts the chin.

-- [time] = { body pitch, kick hip, kick knee, other hip, other knee, shoulder, elbow, torso, neck }
local KEYS = {
	{ 0.00, 0, 75, -100, 25, -45, 70, 40, 5, 10 }, -- foot planted on the wall, crouched in
	{ 0.10, 25, 35, -10, 10, -25, 165, 10, -20, 30 }, -- kick: leg drives straight, arms thrown up, back arched
	{ 0.24, 115, 110, -130, 110, -130, 60, 100, 15, -20 }, -- tucked, going over
	{ 0.38, 230, 115, -135, 115, -135, 55, 100, 15, -20 }, -- upside down
	{ 0.54, 320, 50, -60, 45, -55, 100, 30, 0, 0 }, -- opening out
	{ 0.70, 360, 20, -30, 15, -25, 40, 20, 0, 0 }, -- upright, ready to land
}

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg",
}
local ORDER = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }

local function rot(x: number, z: number?): CFrame
	return CFrame.Angles(math.rad(x), 0, math.rad(z or 0))
end

local sequence = Instance.new("KeyframeSequence")
sequence.Name = "WallFlip"
sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action4
for _, k in KEYS do
	local t, pitch, kickHip, kickKnee, hip, knee, shoulder, elbow, torso, neck = table.unpack(k)
	local poses = {
		HumanoidRootPart = CFrame.identity,
		-- keys are < 180 deg apart, so the shortest-path blend still turns all the way over
		LowerTorso = rot(pitch),
		UpperTorso = rot(torso),
		Head = rot(neck),
		LeftUpperArm = rot(shoulder, -15),
		RightUpperArm = rot(shoulder, 15),
		LeftLowerArm = rot(elbow),
		RightLowerArm = rot(elbow),
		RightUpperLeg = rot(kickHip), -- the kicking leg
		RightLowerLeg = rot(kickKnee),
		LeftUpperLeg = rot(hip),
		LeftLowerLeg = rot(knee),
	}
	local frame = Instance.new("Keyframe")
	frame.Time = t
	local byName = {}
	for _, name in ORDER do
		local pose = Instance.new("Pose")
		pose.Name = name
		pose.CFrame = poses[name]
		pose.EasingStyle = Enum.PoseEasingStyle.Linear
		pose.Parent = byName[PARENT[name]] or frame
		byName[name] = pose
	end
	frame.Parent = sequence
end

return sequence
