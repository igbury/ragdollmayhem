-- The player's own avatar in the main menu, sitting on a chair swinging its legs, hands on its knees.
-- Lives in a ViewportFrame, so nothing here touches the real character. The body is anchored clones
-- of the R15 parts, placed every frame by forward kinematics over the rig attachments (works for
-- avatars with Motor6Ds and with AnimationConstraints alike).
-- Joint signs, as elsewhere in this client: shoulder / hip +X swings the limb forward, elbow +X
-- bends it, knee -X bends it, waist -X bends forward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MythRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MythRig"))

local MenuPuppet = {}
-- One of the arena's bosses looms behind the chair (shared/MythRig, the same rig and procedural poses
-- as in the game), at BOSS_SCALE, BOSS_AT in the scene's space, breathing and now and then straining.
local BOSS_KINDS = { "Cyclops", "Minotaur", "Talos" }
local BOSS_SCALE = 2.7
local BOSS_AT = CFrame.new(8.7, 0, 63.3) * CFrame.Angles(0, math.rad(14), 0) -- facing the camera
local BOSS_ROAR_EVERY, BOSS_ROAR = 9, 1.8 -- a roar now and then, as long as the game's
local BOSS_FEET = -30 -- below the panel's bottom edge, so only the top half looms
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
	-- headphones: a band over the head and a cup on each ear, carried by the head like an accessory
	local hs = parts.Head.Size
	local DARK, GREY, RED = Color3.fromRGB(30, 30, 36), Color3.fromRGB(70, 70, 80), Color3.fromRGB(232, 70, 56)
	local function phone(size: Vector3, offset: CFrame, color: Color3, cylinder: boolean?)
		local p = box(model, size, CFrame.identity, color)
		p.CanCollide = false
		if cylinder then
			p.Shape = Enum.PartType.Cylinder -- axis along X: faces out of the ears
		end
		table.insert(extras, { part = p, on = "Head", offset = offset, phone = true })
	end
	local earX = hs.X / 2 + 0.1
	phone(Vector3.new(hs.X + 0.32, 0.16, 0.26), CFrame.new(0, hs.Y / 2 + 0.06, 0), GREY)
	for _, s in { -1, 1 } do
		phone(Vector3.new(0.14, hs.Y * 0.5, 0.24), CFrame.new(s * (earX + 0.06), hs.Y * 0.28, 0), GREY)
		phone(Vector3.new(0.26, 0.66, 0.66), CFrame.new(s * earX, 0, 0), DARK, true)
		phone(Vector3.new(0.04, 0.4, 0.4), CFrame.new(s * (earX + 0.14), 0, 0), RED, true)
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
	self.standRoot = CFrame.new(0, standY, -0.3) -- a step forward, off the chair

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
	self.chairParts = {}
	for _, p in chair:GetChildren() do
		table.insert(self.chairParts, { part = p, alpha = p.Transparency })
	end

	-- the whole scene turns a little toward the camera
	self.base = CFrame.Angles(0, math.rad(-28), 0)
	chair:PivotTo(self.base * chair:GetPivot())

	local okBoss, boss = pcall(MythRig.build, BOSS_KINDS[math.random(#BOSS_KINDS)])
	if okBoss and boss then
		boss:ScaleTo(BOSS_SCALE)
		self.bossJoints = {}
		for _, j in boss:GetDescendants() do
			if j:IsA("Motor6D") then
				j:SetAttribute("RigRestC0", j.C0) -- ScaleTo moved the joints (see MythRig.build)
				self.bossJoints[j.Name] = j
			end
		end
		boss:PivotTo(self.base * BOSS_AT)
		local box, size = boss:GetBoundingBox()
		boss:PivotTo(boss:GetPivot() + Vector3.new(0, BOSS_FEET - (box.Y - size.Y / 2), 0))
		self.bossKind = boss:GetAttribute("MonsterKind")
		boss.Parent = world
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(Vector3.new(0.8, seatTop + 2.8, -14), Vector3.new(0, seatTop + 1.2, -0.3))
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	self.camera, self.camHome = camera, camera.CFrame

	return self
end

-- Pose ---------------------------------------------------------------------------------------------
function MenuPuppet:sitPose(t: number): Pose
	local swing = math.sin(t * 3.4)
	local pose = {
		root = self.sitRoot * CFrame.new(0, math.abs(swing) * 0.03, 0),
		waist = v(-9, math.sin(t * 0.7) * 4),
		-- nodding to the music in the headphones: a sharp dip on every beat (120 bpm)
		neck = v(2 - math.abs(math.sin(t * math.pi * 2)) ^ 3 * 14, math.sin(t * 0.5) * 18),
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

-- smoothstep, clamped: 0 below 0, 1 above 1
local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function blend(pose: Pose, target: Pose, w: number)
	if w <= 0 then
		return
	end
	for key, goal in target do
		pose[key] = (pose[key] or (if key == "root" then CFrame.identity else Vector3.zero)):Lerp(goal, w)
	end
end

-- Leaving for the game (PLAY), in seconds since PLAY:
--   hop off the chair (it fades), camera still -> turn round (headphones fade), walk off ->
--   ZOOM_AT the camera chases him and the menu floods blue ->
--   LEAVE_TIME the camera is at the back of his head and the menu cuts to the game.
MenuPuppet.ZOOM_AT = 1.5
MenuPuppet.LEAVE_TIME = 3.2
local WALK_FROM, WALK_SPEED = 1.15, 7
local CHASE_FAR = 6 -- studs behind the head the chase settles at before pushing in

-- Camera `d` studs behind the back of a head (centre `head`, back face `back` studs behind it),
-- looking the way `fwd` (flat) points. Shared with the game camera, so the cut lines up.
function MenuPuppet.chaseCamera(head: Vector3, fwd: Vector3, back: number, d: number): CFrame
	local pos = head - fwd * (back + d) + Vector3.yAxis * d * 0.08
	return CFrame.lookAt(pos, head + fwd * 8)
end

-- the back of the head: half its depth plus room for hair
function MenuPuppet.headBack(head: BasePart): number
	return head.Size.Z / 2 + 0.3
end

function MenuPuppet:leave()
	self.leaveAt = self.t
end

function MenuPuppet:leavePose(e: number, t: number): Pose
	local pose = self:sitPose(t)
	-- hop: an arc off the seat onto the floor, then the knees take the landing
	local u = math.clamp(e / 0.5, 0, 1)
	local stand = { waist = v(0), neck = v(0) }
	pair(stand, "Hip", v(0))
	pair(stand, "Knee", v(0))
	pair(stand, "Ankle", v(0))
	pair(stand, "Shoulder", v(0, 0, -4))
	pair(stand, "Elbow", v(10))
	pair(stand, "Wrist", v(0))
	blend(pose, stand, ease(u))
	local landing = math.sin(math.pi * math.clamp((e - 0.45) / 0.3, 0, 1))
	local crouch = {}
	pair(crouch, "Hip", v(28))
	pair(crouch, "Knee", v(-45))
	pair(crouch, "Ankle", v(17))
	pair(crouch, "Shoulder", v(20, 0, -12))
	blend(pose, crouch, landing)

	-- turn round, then walk
	local yaw = math.pi * ease((e - 0.75) / 0.5)
	local walk = math.max(0, e - WALK_FROM)
	local p = walk * 9
	local stride = {}
	stride.rHip, stride.lHip = v(math.sin(p) * 32), v(-math.sin(p) * 32)
	stride.rKnee, stride.lKnee = v(-math.max(0, math.sin(p + 1.3)) * 50), v(-math.max(0, math.sin(p + 1.3 + math.pi)) * 50)
	stride.rShoulder, stride.lShoulder = v(-math.sin(p) * 28, 0, -4), v(math.sin(p) * 28, 0, 4)
	stride.waist = v(-4)
	local w = ease(walk / 0.3)
	blend(pose, stride, w)
	local hop = self.sitRoot:Lerp(self.standRoot, ease(u)) * CFrame.new(0, math.sin(math.pi * u) * 0.7 - landing * 0.3, 0)
	pose.root = CFrame.new(0, 0, walk * WALK_SPEED) * hop * CFrame.Angles(0, yaw, 0) * CFrame.new(0, math.abs(math.sin(p)) * 0.12 * w, 0)
	return pose
end

-- Frame ------------------------------------------------------------------------------------------
-- Wave the left hand for a moment, then settle back onto the knee.
local WAVE_TIME = 1.2
function MenuPuppet:wave()
	self.waveAt = self.t
end

function MenuPuppet:applyWave(pose: Pose, t: number)
	local e = t - (self.waveAt or -math.huge)
	if e >= WAVE_TIME then
		return
	end
	local w = ease(math.min(e / 0.2, (WAVE_TIME - e) / 0.3))
	local swing = math.sin(e * 12) * 25
	local up = { lShoulder = v(165, 0, swing), lElbow = v(15), lWrist = v(0), neck = v(0, 12, 0) }
	for key, target in up do
		pose[key] = (pose[key] or Vector3.zero):Lerp(target, w)
	end
end

function MenuPuppet:step(t: number)
	self.t = t
	if self.bossJoints then
		local roar = (t + 3) % BOSS_ROAR_EVERY -- the first roar 6 s in
		if roar < BOSS_ROAR then
			MythRig.pose(self.bossJoints, "Taunt", self.bossKind, t, 0, roar / BOSS_ROAR, 0, true, { since = t - roar })
		else
			MythRig.pose(self.bossJoints, "Caged", self.bossKind, t, 0, 0, 0, true)
		end
	end
	local e = self.leaveAt and t - self.leaveAt
	local pose
	if e then
		pose = self:leavePose(e, t)
	else
		pose = self:sitPose(t)
		self:applyWave(pose, t)
	end
	local parts = self.parts
	local root = self.base * pose.root
	parts.LowerTorso.CFrame = root * self.rootJoint
	for _, j in self.joints do
		local a = pose[j.key] or Vector3.zero
		parts[j.part].CFrame = parts[j.parent].CFrame * j.a * CFrame.Angles(math.rad(a.X), math.rad(a.Y), math.rad(a.Z)) * j.b
	end
	-- headphones fade away while he turns round
	local gone = e and ease((e - 0.8) / 0.35) or 0
	for _, x in self.extras do
		x.part.CFrame = parts[x.on].CFrame * x.offset
		if x.phone then
			x.part.Transparency = gone
		end
	end
	if e then
		local fade = ease((e - 0.2) / 0.3) -- the chair goes as he lands
		for _, c in self.chairParts do
			c.part.Transparency = c.alpha + (1 - c.alpha) * fade
		end
		-- the camera holds still, then chases him and pushes straight in to the back of his head,
		-- widening to the game's field of view on the way
		local head = parts.Head
		local fwd = (self.base * pose.root).LookVector * Vector3.new(1, 0, 1)
		local push = math.clamp((e - MenuPuppet.ZOOM_AT - 0.3) / (MenuPuppet.LEAVE_TIME - MenuPuppet.ZOOM_AT - 0.3), 0, 1) ^ 2
		local d = CHASE_FAR * (1 - push)
		local chase = MenuPuppet.chaseCamera(head.Position, fwd.Unit, MenuPuppet.headBack(head), d)
		self.camera.CFrame = self.camHome:Lerp(chase, ease((e - MenuPuppet.ZOOM_AT) / 1))
		self.camera.FieldOfView = 30 + 40 * push
	end
end

return MenuPuppet
