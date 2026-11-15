-- The player's own avatar in the main menu, sitting on a chair swinging its legs, hands on its knees.
-- Lives in a ViewportFrame, so nothing here touches the real character. The body is anchored clones
-- of the R15 parts, placed every frame by forward kinematics over the rig attachments (works for
-- avatars with Motor6Ds and with AnimationConstraints alike).
-- Joint signs, as elsewhere in this client: shoulder / hip +X swings the limb forward, elbow +X
-- bends it, knee -X bends it, waist -X bends forward.
local MenuPuppet = {}
MenuPuppet.__index = MenuPuppet

local WOOD = Color3.fromRGB(150, 96, 56)
local DARK_WOOD = Color3.fromRGB(105, 64, 38)
local KEEP = { SurfaceAppearance = true, Decal = true, Texture = true, SpecialMesh = true }

-- part, parent, rig attachment, pose key
local JOINTS = {
	{ "UpperTorso", "LowerTorso", "WaistRigAttachment", "waist" },
	{ "Head", "UpperTorso", "NeckRigAttachment", "neck" },
	{ "LeftUpperArm", "UpperTorso", "LeftShoulderRigAttachment", "lShoulder" },
	{ "LeftLowerArm", "LeftUpperArm", "LeftElbowRigAttachment", "lElbow" },
	{ "LeftHand", "LeftLowerArm", "LeftWristRigAttachment", "lWrist" },
	{ "RightUpperArm", "UpperTorso", "RightShoulderRigAttachment", "rShoulder" },
	{ "RightLowerArm", "RightUpperArm", "RightElbowRigAttachment", "rElbow" },
	{ "RightHand", "RightLowerArm", "RightWristRigAttachment", "rWrist" },
	{ "LeftUpperLeg", "LowerTorso", "LeftHipRigAttachment", "lHip" },
	{ "LeftLowerLeg", "LeftUpperLeg", "LeftKneeRigAttachment", "lKnee" },
	{ "LeftFoot", "LeftLowerLeg", "LeftAnkleRigAttachment", "lAnkle" },
	{ "RightUpperLeg", "LowerTorso", "RightHipRigAttachment", "rHip" },
	{ "RightLowerLeg", "RightUpperLeg", "RightKneeRigAttachment", "rKnee" },
	{ "RightFoot", "RightLowerLeg", "RightAnkleRigAttachment", "rAnkle" },
}

-- Poses ------------------------------------------------------------------------------------------
-- A pose: root = CFrame of the HumanoidRootPart in the scene, plus joint angles in degrees.
type Pose = { [string]: any }

local function v(x: number, y: number?, z: number?): Vector3
	return Vector3.new(x, y or 0, z or 0)
end

-- both sides at once: the left side mirrors y and z
local function pair(pose: Pose, key: string, right: Vector3)
	pose["r" .. key] = right
	pose["l" .. key] = Vector3.new(right.X, -right.Y, -right.Z)
end

-- Build ------------------------------------------------------------------------------------------
local function anchoredClone(part: BasePart): BasePart
	local c = part:Clone()
	for _, child in c:GetChildren() do
		if not KEEP[child.ClassName] then
			child:Destroy()
		end
	end
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	return c
end

local function box(parent: Instance, size: Vector3, cf: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- viewport: the ViewportFrame to draw in. character: the live R15 character to copy (yields while
-- its parts arrive).
function MenuPuppet.new(viewport: ViewportFrame, character: Model)
	local self = setmetatable({}, MenuPuppet)
	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid
	local hrp = character:WaitForChild("HumanoidRootPart", 10) :: BasePart
	local lower = character:WaitForChild("LowerTorso", 10) :: BasePart
	assert(hum and hrp and lower, "no R15 character")

	local model = Instance.new("Model")
	model.Name = "Puppet"
	local parts, joints = {}, {}
	parts.LowerTorso = anchoredClone(lower)
	parts.LowerTorso.Parent = model
	self.rootJoint = (hrp:WaitForChild("RootRigAttachment") :: Attachment).CFrame * (lower:WaitForChild("RootRigAttachment") :: Attachment).CFrame:Inverse()
	for _, j in JOINTS do
		local live = character:WaitForChild(j[1], 10) :: BasePart
		local liveParent = character:FindFirstChild(j[2]) :: BasePart
		local onParent = liveParent:WaitForChild(j[3], 10) :: Attachment
		local onChild = live:WaitForChild(j[3], 10) :: Attachment
		parts[j[1]] = anchoredClone(live)
		parts[j[1]].Parent = model
		table.insert(joints, { part = j[1], parent = j[2], a = onParent.CFrame, b = onChild.CFrame:Inverse(), key = j[4] })
	end
	-- hats, hair, glasses: an accessory's attachment (HairAttachment...) pairs with the same-named one
	-- on a body part, whatever holds it there (AccessoryWeld or, on newer avatars, RigidConstraint).
	-- Layered clothing is skipped: it would not wrap round the puppet.
	local extras = {}
	for _, acc in character:GetChildren() do
		local handle = acc:IsA("Accessory") and acc:FindFirstChild("Handle") :: BasePart?
		if handle and not handle:FindFirstChildOfClass("WrapLayer") then
			for _, att in handle:GetChildren() do
				local on = nil
				if att:IsA("Attachment") then
					for name in parts do
						local live = character:FindFirstChild(name)
						local match = live and live:FindFirstChild(att.Name)
						if match and match:IsA("Attachment") then
							on = { name = name, offset = match.CFrame * att.CFrame:Inverse() }
							break
						end
					end
				end
				if on then
					local c = anchoredClone(handle)
					c.Parent = model
					table.insert(extras, { part = c, on = on.name, offset = on.offset })
					break
				end
			end
		end
	end
	for _, child in character:GetChildren() do
		if child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Clone().Parent = model
		end
	end
	local dummy = Instance.new("Humanoid") -- classic clothing only renders on parts under a Humanoid
	dummy.RigType = Enum.HumanoidRigType.R15
	dummy.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	dummy.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	dummy.Parent = model
	model.Parent = world
	self.parts, self.joints, self.extras = parts, joints, extras

	-- Measurements for the poses: where the hips are, how tall the legs are.
	local hipY = (self.rootJoint * joints[9].a).Y -- left hip joint, relative to the root
	local thigh = parts.LeftUpperLeg.Size
	local standY = hum.HipHeight + hrp.Size.Y / 2
	local seatTop = standY + hipY - 0.6 -- a low stool: shins angled well forward keep the feet off the floor
	self.sitRoot = CFrame.new(0, seatTop + thigh.Z / 2 - hipY, 0.45)

	-- Chair, facing -Z like the puppet.
	local chair = Instance.new("Model")
	chair.Name = "Chair"
	-- seat runs from just in front of the hips to the back, so the knees and swinging shins stay
	-- clear of it; narrow enough that the thighs cover its sides
	local W, FRONT, BACK = 1.9, -0.2, 1.3
	local mid, depth = (FRONT + BACK) / 2, BACK - FRONT
	box(chair, Vector3.new(W, 0.28, depth), CFrame.new(0, seatTop - 0.14, mid), WOOD)
	local legX = W / 2 - 0.13
	for _, x in { -legX, legX } do
		for _, z in { FRONT + 0.13, BACK - 0.13 } do
			box(chair, Vector3.new(0.22, seatTop - 0.28, 0.22), CFrame.new(x, (seatTop - 0.28) / 2, z), DARK_WOOD)
		end
		box(chair, Vector3.new(0.22, 2.4, 0.22), CFrame.new(x, seatTop + 1.2, BACK - 0.13), DARK_WOOD)
	end
	box(chair, Vector3.new(W - 0.1, 0.8, 0.18), CFrame.new(0, seatTop + 1.95, BACK - 0.13), WOOD)
	box(chair, Vector3.new(W - 0.1, 0.22, 0.18), CFrame.new(0, seatTop + 1.1, BACK - 0.13), WOOD)
	chair.Parent = world
	local shadow = box(chair, Vector3.new(0.1, 3.2, 3.2), CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.new(0, 0, 0))
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Transparency = 0.7

	-- the whole scene turns a little toward the camera
	self.base = CFrame.Angles(0, math.rad(-28), 0)
	chair:PivotTo(self.base * chair:GetPivot())

	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0.8, seatTop + 2.8, -14), Vector3.new(0, seatTop + 1.2, -0.3))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	return self
end

-- Pose ---------------------------------------------------------------------------------------------
function MenuPuppet:sitPose(t: number): Pose
	local swing = math.sin(t * 3.4)
	local pose = {
		root = self.sitRoot * CFrame.new(0, math.abs(swing) * 0.03, 0),
		waist = v(-9, math.sin(t * 0.7) * 4),
		neck = v(4 + swing * 2, math.sin(t * 0.5) * 18),
	}
	pair(pose, "Hip", v(88, 0, 4))
	pose.rKnee = v(-62 + swing * 16) -- swings forward of the seat, never back under it
	pose.lKnee = v(-62 - swing * 16)
	pair(pose, "Ankle", v(12))
	pair(pose, "Shoulder", v(27, 0, -7)) -- arms nearly straight, hands resting on the knees
	pair(pose, "Elbow", v(8))
	pair(pose, "Wrist", v(10))
	return pose
end

-- Frame ------------------------------------------------------------------------------------------
function MenuPuppet:step(t: number)
	local pose = self:sitPose(t)
	local parts = self.parts
	local root = self.base * pose.root
	parts.LowerTorso.CFrame = root * self.rootJoint
	for _, j in self.joints do
		local a = pose[j.key] or Vector3.zero
		parts[j.part].CFrame = parts[j.parent].CFrame * j.a * CFrame.Angles(math.rad(a.X), math.rad(a.Y), math.rad(a.Z)) * j.b
	end
	for _, e in self.extras do
		e.part.CFrame = parts[e.on].CFrame * e.offset
	end
end

return MenuPuppet
