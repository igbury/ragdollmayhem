-- Slam mode pose: the body tips head-first toward the ground, arms straight past the head with
-- fists leading, legs straight together. Static looping pose, built in memory like RollForward
-- (same joint signs: root -X pitches forward, shoulder +X swings the arm forward/up).

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
	LowerTorso = CFrame.new(0, 1, 0) * rot(-160), -- head down, tipped a little forward
	UpperTorso = rot(-5),
	Head = rot(25), -- looking ahead at the ground
	LeftUpperArm = rot(170, -8), -- arms straight past the head, fists together
	RightUpperArm = rot(170, 8),
	LeftLowerArm = CFrame.identity,
	RightLowerArm = CFrame.identity,
	LeftUpperLeg = rot(-5, -3),
	RightUpperLeg = rot(-5, 3),
	LeftLowerLeg = rot(-8),
	RightLowerLeg = rot(-8),
}

local sequence = Instance.new("KeyframeSequence")
sequence.Name = "SupermanDive"
sequence.Loop = true
sequence.Priority = Enum.AnimationPriority.Action4
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
