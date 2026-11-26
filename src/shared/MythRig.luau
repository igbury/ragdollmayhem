-- Articulated part rigs: custom Motor6Ds, local procedural poses, existing Ragdoll constraints.
local Rig = {}
local Mythology = require(script.Parent.Mythology)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Blender-made bodies (assets/myth/build_bosses.py, installed by assets/myth/install.luau). Each mesh
-- has a "Place": its CFrame in rig space, rest pose, before Model:ScaleTo.
local function kitFor(kind)
	local kit = ReplicatedStorage:FindFirstChild("MythKit")
	local k = kit and kit:FindFirstChild(kind)
	return k and k:FindFirstChild("Boss")
end
local function dress(m, kit)
	-- the part rig stays as the hit boxes, joints and ragdoll; the meshes ride on it
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then p.Transparency = 1 end
	end
	for _, group in kit:GetChildren() do
		local on = m:FindFirstChild(group.Name)
		if not (on and on:IsA("BasePart")) then continue end
		for _, src in group:GetChildren() do
			local c = src:Clone()
			c.CFrame = c:GetAttribute("Place")
			c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.Massless = false, false, false, false, true
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1, w.Parent = on, c, c
			c.Parent = on
		end
	end
	m:SetAttribute("Dressed", true)
end
local function piece(model, name, size, position, color, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, CFrame.new(position), color
	p.Shape = shape or Enum.PartType.Ball
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide, p.CanTouch, p.Massless = false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end
local function joint(name, a, b, pivot)
	local m = Instance.new("Motor6D")
	m.Name, m.Part0, m.Part1 = name, a, b
	m.C0, m.C1 = a.CFrame:ToObjectSpace(CFrame.new(pivot)), b.CFrame:ToObjectSpace(CFrame.new(pivot))
	m:SetAttribute("RigRestC0", m.C0)
	m.Parent = a
	return m
end
local function detail(model, on, name, size, offset, color, shape, query)
	local p = piece(model, name, size, Vector3.zero, color, shape)
	p.CFrame = on.CFrame * offset
	p.CanQuery, p.Massless, p.CastShadow = query == true, true, false
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1, w.Parent = on, p, p
	return p
end
-- Where the shackles' chain rings are (rig space, assets/myth/build_bosses.py shackle()): { part, ring, "Wrist" / "Ankle" }.
local function rings(wrist, ankle)
	return {
		{ "LeftLowerArm", Vector3.new(-wrist, 4.45, -0.4), "Wrist" }, { "RightLowerArm", Vector3.new(wrist, 4.45, -0.4), "Wrist" },
		{ "LeftLowerLeg", ankle * Vector3.new(-1, 1, 1), "Ankle" }, { "RightLowerLeg", ankle, "Ankle" },
	}
end
Rig.RINGS = {
	Cyclops = rings(5.555, Vector3.new(2.505, 1.05, 0)),
	Minotaur = rings(5.505, Vector3.new(2.455, 1.35, 0)),
	Talos = rings(5.505, Vector3.new(2.455, 0.95, 0.12)),
}
function Rig.build(kind)
	local def = assert(Mythology[kind])
	local m = Instance.new("Model")
	m.Name = def.name
	local root = piece(m, "HumanoidRootPart", Vector3.new(2, 2, 2), Vector3.new(0, 6, 0), def.color)
	root.Transparency, root.Anchored, root.CanQuery = 1, true, false
	local hips = piece(m, "LowerTorso", Vector3.new(3.5, 2.5, 2.4), Vector3.new(0, 5.7, 0), Color3.fromRGB(51, 44, 37))
	local chest = piece(m, "UpperTorso", Vector3.new(5.8, 4.3, 3.1), Vector3.new(0, 8.4, 0), def.color)
	local head = piece(m, "Head", Vector3.new(3.2, 3.3, 2.6), Vector3.new(0, 11.2, -0.6), def.color)
	joint("Root", root, hips, root.Position)
	joint("Waist", hips, chest, Vector3.new(0, 7, 0))
	joint("Neck", chest, head, Vector3.new(0, 10.2, -0.3))
	-- Broad shoulders and long hanging arms preserve the reference's recognizable silhouette.
	for _, side in { "Left", "Right" } do
		local sign = side == "Left" and -1 or 1
		local upper = piece(m, side .. "UpperArm", Vector3.new(2.3, 3.5, 2.4), Vector3.new(sign * 3.6, 8, 0), def.color)
		local lower = piece(m, side .. "LowerArm", Vector3.new(1.9, 3, 2), Vector3.new(sign * 3.9, 5.3, -0.3), def.color)
		local hand = piece(m, side .. "Hand", Vector3.new(2.2, 1.8, 2), Vector3.new(sign * 3.9, 3.3, -0.5), def.color)
		joint(side .. "Shoulder", chest, upper, Vector3.new(sign * 3.6, 9.6, 0))
		joint(side .. "Elbow", upper, lower, Vector3.new(sign * 3.6, 6.7, 0))
		joint(side .. "Wrist", lower, hand, Vector3.new(sign * 3.9, 4, -0.4))
		for finger = 1, 3 do
			detail(m, hand, side .. "Finger" .. finger, Vector3.new(0.5, 1.2, 0.55), CFrame.new((finger - 2) * 0.6, -0.9, -0.45), def.color)
		end
		local thigh = piece(m, side .. "UpperLeg", Vector3.new(1.7, 2.8, 2), Vector3.new(sign * 1.1, 3.6, 0), def.color)
		local shin = piece(m, side .. "LowerLeg", Vector3.new(1.5, 2.1, 1.7), Vector3.new(sign * 1.2, 1.5, 0), def.color)
		local foot = piece(m, side .. "Foot", Vector3.new(2, 1, 2.8), Vector3.new(sign * 1.2, 0.5, -0.65), def.color)
		joint(side .. "Hip", hips, thigh, Vector3.new(sign * 1.1, 5, 0))
		joint(side .. "Knee", thigh, shin, Vector3.new(sign * 1.1, 2.6, 0))
		joint(side .. "Ankle", shin, foot, Vector3.new(sign * 1.2, 0.7, 0))
		detail(m, lower, side .. "Cuff", Vector3.new(2, 0.65, 2.1), CFrame.new(0, -0.6, 0), Color3.fromRGB(53, 44, 37))
		for panel = -1, 1 do
			detail(m, hips, side .. "Tasset" .. panel, Vector3.new(1.15, 2.3, 0.35), CFrame.new(sign * 1.1, -0.5, panel == 0 and -1.35 or panel * 1.15) * CFrame.Angles(0, panel * 0.15, sign * 0.08), Color3.fromRGB(65 + panel * 8, 49, 35), Enum.PartType.Block)
		end
	end
	-- Tunic and belt are deliberately separate from the skin and follow the torso's volume.
	detail(m, chest, "Tunic", Vector3.new(4.9, 3.6, 3.25), CFrame.new(0, -0.2, 0.08), Color3.fromRGB(62, 62, 52))
	detail(m, hips, "Belt", Vector3.new(3.8, 0.65, 2.6), CFrame.new(0, 0.7, 0), Color3.fromRGB(48, 37, 27))
	detail(m, hips, "Buckle", Vector3.new(0.7, 0.65, 0.2), CFrame.new(0, 0.7, -1.35), def.accent, Enum.PartType.Block)
	if kind == "Cyclops" then
		local eye = detail(m, head, "Eye", Vector3.new(2.2, 2.2, 1), CFrame.new(0, 0.25, -1.75), Color3.fromRGB(238, 229, 201), nil, true)
		eye:SetAttribute("WeakPoint", true)
		detail(m, eye, "Iris", Vector3.new(0.85, 0.95, 0.3), CFrame.new(0, 0, -0.4), def.accent)
		detail(m, eye, "Pupil", Vector3.new(0.36, 0.65, 0.18), CFrame.new(0, 0, -0.58), Color3.fromRGB(20, 22, 20))
		detail(m, head, "Brow", Vector3.new(2.4, 0.55, 1), CFrame.new(0, 0.85, -1.1) * CFrame.Angles(0, 0, -0.1), def.color)
	elseif kind == "Minotaur" then
		detail(m, head, "Muzzle", Vector3.new(2.5, 1.5, 1.7), CFrame.new(0, -0.6, -1.2), Color3.fromRGB(70, 43, 34))
		for _, sign in { -1, 1 } do
			detail(m, head, "Horn" .. sign, Vector3.new(0.7, 2.6, 0.75), CFrame.new(sign * 1.7, 1.1, 0) * CFrame.Angles(0, 0, -sign * 0.75), Color3.fromRGB(220, 207, 172))
			detail(m, head, "HornTip" .. sign, Vector3.new(0.38, 1.4, 0.4), CFrame.new(sign * 2.35, 2.3, 0) * CFrame.Angles(0, 0, sign * 0.3), Color3.fromRGB(220, 207, 172))
			detail(m, head, "Eye" .. sign, Vector3.new(0.45, 0.35, 0.25), CFrame.new(sign * 0.9, 0.1, -1.23), def.accent)
		end
	else
		detail(m, head, "Visor", Vector3.new(2.3, 0.35, 0.3), CFrame.new(0, 0.1, -1.29), def.accent, Enum.PartType.Block)
		local ankle = m.RightLowerLeg
		local seal = detail(m, ankle, "AnkleSeal", Vector3.new(1.4, 1.4, 0.6), CFrame.new(-0.1, -0.35, -1.1), def.accent, nil, true)
		seal.Material = Enum.Material.Neon
		seal:SetAttribute("WeakPoint", true)
		for _, sign in { -1, 1 } do
			detail(m, chest, "Pauldron" .. sign, Vector3.new(2.6, 1.3, 3.5), CFrame.new(sign * 2.1, 1.6, 0), Color3.fromRGB(164, 118, 60))
		end
	end
	-- the shackle rings its lair's chains hang from (attachments scale with the model)
	for _, ring in Rig.RINGS[kind] do
		local on = m[ring[1]]
		local a = Instance.new("Attachment")
		a.Name, a.Position, a.Parent = "ChainRing", on.CFrame:PointToObjectSpace(ring[2]), on
		a:SetAttribute("Ring", ring[3])
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck, humanoid.BreakJointsOnDeath, humanoid.EvaluateStateMachine = false, false, false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = m
	Instance.new("Animator", humanoid)
	m.PrimaryPart = root
	local kit = kitFor(kind)
	if kit then dress(m, kit) end
	m:ScaleTo(def.scale)
	-- ScaleTo scales every joint's C0 but not the rest pose kept beside it: keep the scaled one, or posing
	-- pulls the limbs back to scale-1 offsets (a 3x boss floated with its feet 4 studs off the ground)
	for _, j in m:GetDescendants() do
		if j:IsA("Motor6D") then j:SetAttribute("RigRestC0", j.C0) end
	end
	m:SetAttribute("MonsterKind", kind)
	return m
end

-- Procedural posing never modifies the server hit ray or requires unpublished animation ids.
function Rig.pose(joints, state, kind, elapsed, moving, phase, hurt, authoritative)
	local stride = math.sin(elapsed * (kind == "Minotaur" and 9 or 5)) * moving
	local breath = math.sin(elapsed * 1.8) * 0.025
	local lift, bend = 0, 0
	local spread, head, sway = 0, 0, stride * 0.07 -- arms out sideways, head back, hips swaying with the steps
	if state == "Windup" then lift, bend = -1.8 * phase, -0.22 * phase
	elseif state == "Strike" then lift, bend = 0.65, 0.4
	elseif state == "Recovery" then -- follow-through: it hangs on the blow, then eases back
		local back = 1 - (1 - phase) ^ 3
		lift, bend = 0.65 * (1 - back), 0.4 * (1 - back)
	elseif state == "Charge" then lift, bend = -0.8, 0.35
	elseif state == "Eat" then -- both hands at the mouth, chewing
		local chomp = math.sin(elapsed * 9)
		lift, bend = -1.5 + chomp * 0.15, 0.25 + chomp * 0.12
	elseif state == "Roar" then -- let out: a crouch, then up and back with arms flung wide, shaking
		local crouch = math.clamp(phase / 0.2, 0, 1)
		local open = math.clamp((phase - 0.2) / 0.15, 0, 1) * (1 - math.clamp((phase - 0.85) / 0.15, 0, 1))
		local shake = math.sin(elapsed * 38) * 0.035 * open
		bend = 0.3 * crouch * (1 - open) - 0.32 * open + shake
		lift = -0.4 * crouch * (1 - open) - 1.25 * open
		spread, head = 0.75 * open, -0.55 * open + shake
	elseif state == "Caged" then -- straining at the chains now and then
		local tug = math.max(0, math.sin(elapsed * 0.9)) ^ 6
		bend, lift, head = 0.12 * tug, 0.35 * tug, 0.2 * tug
	end
	for name, j in joints do
		local x, z = 0, 0
		if name == "Waist" then x = breath + bend - hurt * 0.14; z = sway
		elseif name == "Neck" then x = -bend * 0.4 + head + hurt * 0.25; z = -sway * 0.8
		elseif name:find("Shoulder") then
			local left = name == "LeftShoulder"
			x = lift + (if left then stride else -stride) * 0.35 - hurt * 0.3
			z = (if left then -1 else 1) * (0.12 + spread)
		elseif name:find("Elbow") then x = -0.12 - math.abs(lift) * 0.25
		elseif name:find("Hip") then x = (name == "LeftHip" and stride or -stride) * 0.45
		elseif name:find("Knee") then x = math.max(0, (name == "LeftKnee" and -stride or stride)) * 0.55 end
		local rest = j:GetAttribute("RigRestC0") or j.C0
		local pose = rest * CFrame.Angles(x, 0, z)
		if authoritative then j.C0 = pose
		else j.Transform = j.C0:ToObjectSpace(pose) end
	end
end
return Rig
