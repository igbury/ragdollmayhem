-- Slide and crouch poses, built in memory like RollForward (same joint signs: LowerTorso -X
-- pitches forward, hip +X swings the thigh forward, knee -X bends it, shoulder +X swings the arm
-- forward, elbow +X bends it, neck -X tucks the chin). Both are played with the Humanoid's
-- HipHeight lowered (see Slide and crouch in init.client), so the legs fold up by about that much.
-- Returns build(kind): "slide" is one held pose, "crouch" a slow shuffle that is frozen while
-- standing still.

-- [time] = { torso pitch, chest, neck, L shoulder, L elbow, R shoulder, R elbow, L hip, L knee, R hip, R knee }
local KEYS = {
	-- leaning back on the left hand, right leg out in front, left leg tucked under
	slide = {
		{ 0.0, 35, 8, -30, -55, 10, 45, 40, 100, -115, 58, -8 },
		{ 0.5, 35, 8, -30, -55, 10, 45, 40, 100, -115, 58, -8 },
	},
	-- knees up, chest over them, hands in front
	crouch = {
		{ 0.00, -20, -12, 28, 30, 65, 20, 65, 95, -130, 75, -108 },
		{ 0.35, -20, -12, 28, 20, 65, 30, 65, 75, -108, 95, -130 },
		{ 0.70, -20, -12, 28, 30, 65, 20, 65, 95, -130, 75, -108 },
	},
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

return function(kind: string): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = kind
	sequence.Loop = true
	sequence.Priority = Enum.AnimationPriority.Action
	for _, k in KEYS[kind] do
		local t, torso, chest, neck, lShoulder, lElbow, rShoulder, rElbow, lHip, lKnee, rHip, rKnee = table.unpack(k)
		local poses = {
			HumanoidRootPart = CFrame.identity,
			LowerTorso = pitch(torso),
			UpperTorso = pitch(chest),
			Head = pitch(neck),
			LeftUpperArm = pitch(lShoulder),
			LeftLowerArm = pitch(lElbow),
			RightUpperArm = pitch(rShoulder),
			RightLowerArm = pitch(rElbow),
			LeftUpperLeg = pitch(lHip),
			LeftLowerLeg = pitch(lKnee),
			RightUpperLeg = pitch(rHip),
			RightLowerLeg = pitch(rKnee),
		}
		local frame = Instance.new("Keyframe")
		frame.Time = t
		local byName = {}
		for _, name in ORDER do
			local pose = Instance.new("Pose")
			pose.Name = name
			pose.CFrame = poses[name]
			pose.Parent = byName[PARENT[name]] or frame
			byName[name] = pose
		end
		frame.Parent = sequence
	end
	return sequence
end
