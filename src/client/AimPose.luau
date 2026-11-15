-- Third-person aiming poses (right mouse with the camera pulled back), upper body only: the legs
-- keep walking. Static looping poses built in memory like WallCling (same joint signs: shoulder +X
-- raises the arm forward/up, elbow +X bends it; LeftUpperArm -Z / RightUpperArm +Z spread the arms
-- out, so the opposite sign brings an arm in across the chest).
-- kind: "gun" both hands on the gun in the middle, "rocket" the tube on the right
-- shoulder, "throw" the throwing arm cocked back beside the head, the other pointing at the target.

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm",
}
local ORDER = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }

local function rot(x: number, z: number?): CFrame
	return CFrame.Angles(math.rad(x), 0, math.rad(z or 0))
end

local POSES = {
	gun = { -- both arms out, hands meeting in front of the middle of the chest (the gun is put between them)
		RightUpperArm = rot(86, -42),
		RightLowerArm = rot(10),
		LeftUpperArm = rot(86, 44),
		LeftLowerArm = rot(10),
	},
	rocket = {
		RightUpperArm = rot(55, -10), -- elbow out and down, hand up at the shoulder
		RightLowerArm = rot(75),
		LeftUpperArm = rot(80, 20), -- holding the front grip
		LeftLowerArm = rot(20),
	},
	throw = {
		RightUpperArm = rot(160, -25), -- up and back beside the head
		RightLowerArm = rot(80),
		LeftUpperArm = rot(90, -5), -- pointing the way
		LeftLowerArm = rot(5),
	},
}

return function(kind: string): KeyframeSequence
	local pose = POSES[kind]
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = "Aim_" .. kind
	sequence.Loop = true
	sequence.Priority = Enum.AnimationPriority.Action2
	for _, t in { 0, 0.5 } do
		local frame = Instance.new("Keyframe")
		frame.Time = t
		local byName = {}
		for _, name in ORDER do
			local p = Instance.new("Pose")
			p.Name = name
			p.CFrame = pose[name] or CFrame.identity
			p.Weight = pose[name] and 1 or 0 -- the root and torso only carry the arms: leave them to the walk
			p.Parent = byName[PARENT[name]] or frame
			byName[name] = p
		end
		frame.Parent = sequence
	end
	return sequence
end
