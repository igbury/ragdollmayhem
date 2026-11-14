-- Forward roll played on landing from a big fall: 0.65 s, the body somersaults once around
-- the hips while tucked, then stands. Built in memory like SprintFlail (no upload).
-- Joint signs measured on an R15 rig: root -X pitches forward, hip +X swings the thigh forward,
-- knee -X bends it, shoulder +X swings the arm forward, elbow +X bends it, neck -X tucks the chin.

-- [time] = { LowerTorso drop (studs), LowerTorso pitch, torso, neck, shoulder, elbow, hip, knee }
local KEYS = {
	{ 0.00, -0.6, -25, -20, -10, 60, 40, 70, -90 }, -- landing crouch
	{ 0.12, -0.3, -100, -55, -45, 100, 110, 120, -140 }, -- tucked tight, going over
	{ 0.24, -0.2, -190, -55, -45, 100, 110, 120, -140 }, -- upside down
	{ 0.36, -0.3, -280, -55, -45, 100, 110, 120, -140 },
	{ 0.50, -0.6, -360, -15, -10, 40, 30, 60, -80 }, -- back on the feet, crouched
	{ 0.65, 0, 0, 0, 0, 0, 0, 0, 0 }, -- standing
}

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg",
}
local ORDER = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }

local function pitch(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end

local sequence = Instance.new("KeyframeSequence")
sequence.Name = "RollForward"
sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action4
for _, k in KEYS do
	local t, drop, root, torso, neck, shoulder, elbow, hip, knee = table.unpack(k)
	local poses = {
		HumanoidRootPart = CFrame.identity,
		-- keys are <= 90 deg apart, so the shortest-path blend still goes all the way round
		LowerTorso = CFrame.new(0, drop, 0) * pitch(root),
		UpperTorso = pitch(torso),
		Head = pitch(neck),
		LeftUpperArm = pitch(shoulder) * CFrame.Angles(0, 0, math.rad(15)), -- hugging in a little
		RightUpperArm = pitch(shoulder) * CFrame.Angles(0, 0, math.rad(-15)),
		LeftLowerArm = pitch(elbow),
		RightLowerArm = pitch(elbow),
		LeftUpperLeg = pitch(hip),
		RightUpperLeg = pitch(hip),
		LeftLowerLeg = pitch(knee),
		RightLowerLeg = pitch(knee),
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
