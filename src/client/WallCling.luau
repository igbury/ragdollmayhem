-- Wall cling pose: facing the wall, both hands up on it, one knee higher than the other like a
-- foot pressed into it. Static looping pose, built in memory like RollForward (same joint signs:
-- shoulder +X raises the arm forward/up, elbow +X bends it, hip +X brings the thigh up, knee -X
-- bends it, neck -X tucks the chin; LeftUpperArm -Z / RightUpperArm +Z spread the arms out).

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

local POSE = {
	HumanoidRootPart = CFrame.identity,
	LowerTorso = CFrame.new(0, 0, -0.35) * rot(4), -- pressed in toward the wall
	UpperTorso = rot(6),
	Head = rot(14), -- looking up the wall
	LeftUpperArm = rot(150, -22), -- hands up and apart on the wall
	RightUpperArm = rot(140, 22),
	LeftLowerArm = rot(35),
	RightLowerArm = rot(25),
	LeftUpperLeg = rot(45, -6), -- this foot pressed high into the wall
	LeftLowerLeg = rot(-75),
	RightUpperLeg = rot(8, 6),
	RightLowerLeg = rot(-35),
}

local sequence = Instance.new("KeyframeSequence")
sequence.Name = "WallCling"
sequence.Loop = true
sequence.Priority = Enum.AnimationPriority.Action
for _, t in { 0, 0.5 } do
	local frame = Instance.new("Keyframe")
	frame.Time = t
	local byName = {}
	for _, name in ORDER do
		local pose = Instance.new("Pose")
		pose.Name = name
		pose.CFrame = POSE[name]
		pose.Parent = byName[PARENT[name]] or frame
		byName[name] = pose
	end
	frame.Parent = sequence
end

return sequence
