-- R15 pose builder shared by movement, NPCs and the Studio animation preview.
-- Authoring data and matching RBXMX exports: assets/anims/polish.py.
local data = require(script.Parent:WaitForChild("AnimationData"))
local Clips = {}
local order = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local parent = { LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso" }
for _, side in { "Left", "Right" } do
	parent[side .. "UpperArm"] = "UpperTorso"
	parent[side .. "LowerArm"] = side .. "UpperArm"
	parent[side .. "Hand"] = side .. "LowerArm"
	parent[side .. "UpperLeg"] = "LowerTorso"
	parent[side .. "LowerLeg"] = side .. "UpperLeg"
	parent[side .. "Foot"] = side .. "LowerLeg"
end

function Clips.build(name: string): KeyframeSequence
	local spec = assert(data[name], "Unknown animation clip: " .. name)
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = spec.loop
	sequence.Priority = Enum.AnimationPriority[spec.priority]
	sequence:SetAttribute("Length", spec.keys[#spec.keys].time)
	sequence:SetAttribute("ReferenceSpeed", spec.referenceSpeed)
	sequence:SetAttribute("ImpactTime", spec.impactTime)
	local driven, linear = {}, {}
	for _, key in spec.keys do
		for part in key.poses do
			driven[part] = true
		end
	end
	for _, part in spec.linearParts or {} do
		linear[part] = true
	end
	for _, key in spec.keys do
		local frame = Instance.new("Keyframe")
		frame.Time = key.time
		local poses = {}
		for _, part in order do
			local pose = Instance.new("Pose")
			pose.Name = part
			local p = key.poses[part]
			pose.CFrame = p and CFrame.new(p[1], p[2], p[3])
				* CFrame.Angles(math.rad(p[4]), math.rad(p[5]), math.rad(p[6])) or CFrame.identity
			pose.Weight = (part == "HumanoidRootPart" or (spec.partial and not driven[part])) and 0 or 1
			pose.EasingStyle = Enum.PoseEasingStyle[linear[part] and "Linear" or key.easing]
			pose.EasingDirection = Enum.PoseEasingDirection[key.direction]
			pose.Parent = poses[parent[part]] or frame
			poses[part] = pose
		end
		for _, name in key.markers do
			local marker = Instance.new("KeyframeMarker")
			marker.Name = name
			marker.Parent = frame
		end
		frame.Parent = sequence
	end
	return sequence
end

function Clips.length(name: string): number
	local keys = data[name].keys
	return keys[#keys].time
end

function Clips.referenceSpeed(name: string): number
	return data[name].referenceSpeed or 1
end

function Clips.impactTime(name: string): number
	return data[name].impactTime or 0
end

return Clips
