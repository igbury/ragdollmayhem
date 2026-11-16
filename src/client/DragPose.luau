-- Holding a dummy by the chest in the right hand (F), upper body only: the legs keep walking and
-- running. Static looping poses built in memory like AimPose (same joint signs: shoulder +X swings
-- the arm forward/up, elbow +X bends it, RightUpperArm +Z / LeftUpperArm -Z spread an arm out;
-- the torso and head lean back on +X, so -X bends them forward).
-- kind: "hold" the arm down and out at your right side, the body hanging from the fist; "press"
-- (sprinting with it) bent over at the waist, the arm straight down pushing it into the ground,
-- the left arm out for balance and the head up to see where you run. The client blends the two.

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm",
}
local ORDER = {
	"HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
}

local function rot(x: number, z: number?): CFrame
	return CFrame.Angles(math.rad(x), 0, math.rad(z or 0))
end

local POSES = {
	hold = {
		RightUpperArm = rot(30, 35), -- down, a little forward and well out: the body hangs clear of your leg
		RightLowerArm = rot(12),
		RightHand = rot(-10), -- the fist turned in, round its collar
	},
	press = {
		UpperTorso = rot(-42), -- bent right over
		Head = rot(30), -- still looking ahead
		RightUpperArm = rot(58, 18), -- straight down to the ground (forward in the bent torso's frame)
		RightLowerArm = rot(0),
		RightHand = rot(-20),
		LeftUpperArm = rot(35, -40), -- out to the side for balance
		LeftLowerArm = rot(35),
	},
}

return function(kind: string): KeyframeSequence
	local pose = POSES[kind]
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = "Drag_" .. kind
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
			p.Weight = pose[name] and 1 or 0 -- what the pose leaves alone stays with the walk / run
			p.Parent = byName[PARENT[name]] or frame
			byName[name] = p
		end
		frame.Parent = sequence
	end
	return sequence
end
