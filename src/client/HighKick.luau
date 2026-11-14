-- High side kick | 0.7 s, played once (left click with the camera zoomed out). The hips turn
-- left so the right side faces forward, the right knee chambers, then the leg snaps out high and
-- straight while the body leans back away from it, fists up in guard; then it re-chambers and
-- comes down. Built in memory like WallFlip (no upload). Signs: LowerTorso +Y turns the body
-- left, +Z leans it left; hip +X brings the thigh forward/up, +Z swings it out to the side;
-- knee -X bends it; shoulder +X raises the arm forward, elbow +X bends it.

-- [time] = { yaw, lean, kick hip X, kick hip Z, kick knee, stand hip Z, stand knee, shoulder, elbow }
local KEYS = {
	{ 0.00, 0, 0, 0, 0, 0, 0, 0, 20, 30 },
	{ 0.10, 50, 10, 75, 30, -100, -10, -20, 70, 110 }, -- knee chambered, hips turning
	{ 0.20, 85, 35, 10, 115, -5, -30, -15, 75, 120 }, -- leg out, foot above head height
	{ 0.40, 85, 35, 10, 115, -5, -30, -15, 75, 120 }, -- hold
	{ 0.54, 50, 10, 70, 30, -100, -10, -20, 70, 110 }, -- re-chamber
	{ 0.70, 0, 0, 0, 0, 0, 0, 0, 20, 30 },
}

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg",
}
local ORDER = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }

local function rot(x: number, y: number?, z: number?): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0))
end

local sequence = Instance.new("KeyframeSequence")
sequence.Name = "HighKick"
sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action4
for _, k in KEYS do
	local t, yaw, lean, kickX, kickZ, kickKnee, standZ, standKnee, shoulder, elbow = table.unpack(k)
	local poses = {
		HumanoidRootPart = CFrame.identity,
		LowerTorso = rot(0, yaw) * rot(0, 0, lean),
		UpperTorso = rot(0, -yaw * 0.25), -- chest stays a little more square to the target
		Head = rot(0, -yaw * 0.75, -lean * 0.5), -- eyes stay on the target
		LeftUpperArm = rot(shoulder, 0, -10),
		RightUpperArm = rot(shoulder * 0.7, 0, 10),
		LeftLowerArm = rot(elbow),
		RightLowerArm = rot(elbow),
		RightUpperLeg = rot(kickX, 0, kickZ), -- the kicking leg
		RightLowerLeg = rot(kickKnee),
		LeftUpperLeg = rot(0, 0, standZ),
		LeftLowerLeg = rot(standKnee),
	}
	local frame = Instance.new("Keyframe")
	frame.Time = t
	local byName = {}
	for _, name in ORDER do
		local pose = Instance.new("Pose")
		pose.Name = name
		pose.CFrame = poses[name]
		pose.EasingStyle = Enum.PoseEasingStyle.Cubic
		pose.Parent = byName[PARENT[name]] or frame
		byName[name] = pose
	end
	frame.Parent = sequence
end

return sequence
