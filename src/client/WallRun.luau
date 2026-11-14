-- Wall run cycle | 0.5 s loop | built in memory like SprintFlail (no upload).
-- The body faces the run direction and leans away from the wall, feet planted toward it: the
-- near arm reaches forward along the wall, the far arm swings out for balance, long strides.
-- Returns build(side): side = 1 when the wall is on the character's right, -1 on the left.
-- Joint signs as in RollForward: hip +X swings the thigh forward, knee -X bends it, shoulder +X
-- swings the arm forward, elbow +X bends it; LowerTorso +Z tips the head toward -X (left).

local LEAN = 32 -- degrees the body tips away from the wall
local REACH = 55 -- how far the arms are raised out to the sides

-- [time] = { near thigh, near knee, far thigh, far knee, arm swing }
local KEYS = {
	{ 0.000, 60, -35, -35, -95, 1 }, -- near leg reaching forward, far leg pushing off behind
	{ 0.125, 15, -25, 30, -115, 0 }, -- passing: far knee comes through high
	{ 0.250, -35, -95, 60, -35, -1 }, -- mirrored stride
	{ 0.375, 30, -115, 15, -25, 0 },
	{ 0.500, 60, -35, -35, -95, 1 },
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

return function(side: number): KeyframeSequence
	local near = side > 0 and "Right" or "Left"
	local far = side > 0 and "Left" or "Right"
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = "WallRun" .. near
	sequence.Loop = true
	sequence.Priority = Enum.AnimationPriority.Action
	for _, k in KEYS do
		local t, nearHip, nearKnee, farHip, farKnee, swing = table.unpack(k)
		local poses = {
			HumanoidRootPart = CFrame.identity,
			-- shift toward the wall a little so the feet meet it, then tip the head away
			LowerTorso = CFrame.new(0.4 * side, -0.2, 0) * rot(-8, 0, LEAN * side),
			UpperTorso = rot(-18, -10 * side * swing, -6 * side), -- leaning into the run
			Head = rot(12, 0, -14 * side), -- head stays closer to level than the body
			[near .. "UpperArm"] = rot(70 + 15 * swing, 0, REACH * side), -- reaching ahead along the wall
			[near .. "LowerArm"] = rot(20),
			[far .. "UpperArm"] = rot(-30 - 20 * swing, 0, -(REACH + 20) * side), -- out and back for balance
			[far .. "LowerArm"] = rot(35),
			[near .. "UpperLeg"] = rot(nearHip, 0, 6 * side),
			[near .. "LowerLeg"] = rot(nearKnee),
			[far .. "UpperLeg"] = rot(farHip, 0, 6 * side),
			[far .. "LowerLeg"] = rot(farKnee),
		}
		local frame = Instance.new("Keyframe")
		frame.Time = t
		local byName = {}
		for _, name in ORDER do
			local pose = Instance.new("Pose")
			pose.Name = name
			pose.CFrame = poses[name]
			pose.EasingStyle = Enum.PoseEasingStyle.Cubic
			pose.EasingDirection = Enum.PoseEasingDirection.InOut
			pose.Parent = byName[PARENT[name]] or frame
			byName[name] = pose
		end
		frame.Parent = sequence
	end
	return sequence
end
