-- The dash (X): an anime-style burst instead of the old somersault. A tiny coil (crouch, arms in,
-- 0.05 s), then the whole body thrown forward low and flat: chest pitched over, arms swept
-- straight back, the lead knee driving and the back leg trailing long; held through the burst,
-- then a quick snap back upright as the speed runs out. Built in memory like RollForward.
-- Joint signs as in RollForward: root -X pitches forward, hip +X swings the thigh forward,
-- knee -X bends it, shoulder +X swings the arm forward, elbow +X bends it, neck +X lifts the chin.

-- [time] = { drop, root pitch, torso, neck, shoulder, arm out (deg), elbow, lead hip, lead knee,
--            back hip, back knee, easing out of this key }
local KEYS = {
	{ 0.00, 0.35, -12, -8, 0, 25, 10, 80, 30, -55, 25, -55, "In" }, -- coil
	{ 0.05, 0.55, -52, -14, 38, -72, 22, 12, 42, -75, -48, -22, "Out" }, -- launched
	{ 0.22, 0.5, -46, -12, 34, -78, 26, 18, 36, -68, -42, -30, "InOut" }, -- held through the burst
	{ 0.40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "Out" }, -- upright
}
local LENGTH = 0.4

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
sequence.Name = "DashBurst"
sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action4
for _, k in KEYS do
	local t, drop, root, torso, neck, shoulder, out, elbow, leadHip, leadKnee, backHip, backKnee, ease = table.unpack(k)
	local poses = {
		HumanoidRootPart = CFrame.identity,
		LowerTorso = CFrame.new(0, -drop, 0) * rot(root),
		UpperTorso = rot(torso),
		Head = rot(neck),
		LeftUpperArm = rot(shoulder, -out), -- swept back and a little away from the body
		RightUpperArm = rot(shoulder, out),
		LeftLowerArm = rot(elbow),
		RightLowerArm = rot(elbow),
		LeftUpperLeg = rot(leadHip),
		LeftLowerLeg = rot(leadKnee),
		RightUpperLeg = rot(backHip),
		RightLowerLeg = rot(backKnee),
	}
	local frame = Instance.new("Keyframe")
	frame.Time = t
	local byName = {}
	for _, name in ORDER do
		local pose = Instance.new("Pose")
		pose.Name = name
		pose.CFrame = poses[name]
		pose.EasingStyle = Enum.PoseEasingStyle.CubicV2
		pose.EasingDirection = Enum.PoseEasingDirection[ease]
		pose.Parent = byName[PARENT[name]] or frame
		byName[name] = pose
	end
	frame.Parent = sequence
end
sequence:SetAttribute("Length", LENGTH)

return sequence
