-- Holding a dummy by the collar in the right hand (F). Posed in Blender with IK on the player's own
-- rig and exported key by key (GrabAnimData):
-- "hold"   upper body only: the arm down at your side, the fist in its collar; the legs and the
--          left arm keep walking / sprinting.
-- "scrape" upper body only: leaning into it, the straight arm driving it down and back into the
--          ground beside you, juddering with the drag.
-- "punt"   the whole body: swung back, heaved up over your head and let go, front-kicked away as
--          it drops (the client times the release and the kick: PUNT_RELEASE, PUNT_KICK).
-- ponytail: built in memory like AimPose (no upload), so they play in Studio only; upload them
-- before publishing.

local DATA = require(script.Parent:WaitForChild("GrabAnimData"))

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg", RightFoot = "RightLowerLeg",
}
local ORDER = {
	"HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

return function(kind: string): KeyframeSequence
	local a = DATA[kind]
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = "Drag_" .. kind
	sequence.Loop = a.loop
	sequence.Priority = Enum.AnimationPriority.Action2
	local only = a.parts and {} or nil
	for _, name in a.parts or {} do
		only[name] = true
	end
	for _, f in a.frames do
		local frame = Instance.new("Keyframe")
		frame.Time = f.t
		local byName = {}
		for _, name in ORDER do
			local p = Instance.new("Pose")
			p.Name = name
			local c = f.pose[name]
			p.CFrame = c and CFrame.new(table.unpack(c)) or CFrame.identity
			-- 0: only there to carry its children; what the pose leaves alone stays with the walk / run
			p.Weight = (c and (not only or only[name])) and 1 or 0
			-- CubicV2: the old Cubic reverses direction between the editor and the game
			p.EasingStyle = a.loop and Enum.PoseEasingStyle.Linear or Enum.PoseEasingStyle.CubicV2
			p.EasingDirection = Enum.PoseEasingDirection.InOut
			p.Parent = byName[PARENT[name]] or frame
			byName[name] = p
		end
		frame.Parent = sequence
	end
	return sequence
end
