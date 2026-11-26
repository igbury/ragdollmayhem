-- The player's own avatar in the main menu, sitting on a chair swinging its legs, hands on its knees.
-- Lives in a ViewportFrame, so nothing here touches the real character. The body is anchored clones
-- of the R15 parts, placed every frame by forward kinematics over the rig attachments (works for
-- avatars with Motor6Ds and with AnimationConstraints alike).
-- Joint signs, as elsewhere in this client: shoulder / hip +X swings the limb forward, elbow +X
-- bends it, knee -X bends it, waist -X bends forward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MythRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MythRig"))

local MenuPuppet = {}
-- One of the arena's bosses looms behind the avatar (shared/MythRig, the same rig and clips as in the
-- game), breathing in its chains and now and then roaring. It lives in a ViewportFrame of its own under
-- the avatar's, so it can never cover the avatar, with a camera fitted to its whole body in every pose
-- it strikes here, so nothing of it is ever cut off by the panel's edge (frameBoss()).
local BOSS_KINDS = { "Cyclops", "Minotaur", "Talos" }
local BOSS_ROAR_EVERY, BOSS_ROAR = 9, 1.8 -- a roar now and then, as long as the game's
local BOSS_FOV = 30
local BOSS_YAW = math.rad(-16) -- turned a little toward the avatar on its left
local BOSS_TILT = math.rad(7) -- the camera looks up at it a little: it looms
local BOSS_FIT = { left = -0.94, right = 0.94, bottom = -0.97, top = 0.92 } -- of the boss view, -1..1
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
-- `viewport` shows the avatar; `framing` places it there ({x, y}: where the middle of the chair sits
-- across and down the view, 0..1; zoom: how far back the camera stands, 1 = the old close-up).
-- `bossView`, an optional ViewportFrame under it, shows the boss filling it whole.
function MenuPuppet.new(viewport: ViewportFrame, character: Model, bossView: ViewportFrame?, framing: { x: number, y: number, zoom: number }?)
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

	if bossView then
		self:buildBoss(bossView)
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	self.homeFov = camera.FieldOfView
	viewport.CurrentCamera = camera
	self.camera, self.viewport, self.framing = camera, viewport, framing or { x = 0.5, y = 0.5, zoom = 1 }
	self.lookAt = Vector3.new(0, seatTop + 1.2, -0.3)
	self.lookFrom = self.lookAt + (Vector3.new(0.8, seatTop + 2.8, -14) - self.lookAt) * self.framing.zoom
	self:frameAvatar()
	viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if not self.leaveAt then
			self:frameAvatar()
		end
	end)

	return self
end

-- The avatar's camera, slid across and up so the avatar sits at framing.x, framing.y of its view at any
-- aspect.
function MenuPuppet:frameAvatar()
	local size = self.viewport.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 1
	local home = CFrame.lookAt(self.lookFrom, self.lookAt)
	local halfHigh = (self.lookAt - self.lookFrom).Magnitude * math.tan(math.rad(self.camera.FieldOfView / 2))
	local f = self.framing
	self.camHome = home + home.RightVector * (0.5 - f.x) * 2 * halfHigh * aspect + home.UpVector * (f.y - 0.5) * 2 * halfHigh
	self.camera.CFrame = self.camHome
end

function MenuPuppet:buildBoss(view: ViewportFrame)
	local world = Instance.new("WorldModel")
	world.Parent = view
	local ok, boss = pcall(MythRig.build, BOSS_KINDS[math.random(#BOSS_KINDS)])
	if not ok or not boss then
		warn("menu boss:", boss)
		return
	end
	boss:PivotTo(CFrame.Angles(0, BOSS_YAW, 0))
	boss.Parent = world
	local joints = {}
	for _, j in boss:GetDescendants() do
		if j:IsA("Motor6D") then
			joints[j.Name] = j
		end
	end
	local kind = boss:GetAttribute("MonsterKind")
	-- the room every pose the menu plays takes: a breath cycle and a whole roar, posed on a copy of
	-- the joints table (MythRig keeps its crossfade per table) and boxed as it goes
	local probe = table.clone(joints)
	local pivot = boss:GetPivot()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	local function grow()
		local cf, size = boss:GetBoundingBox()
		local at = pivot:ToObjectSpace(cf)
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = at * (size / 2 * Vector3.new(sx, sy, sz))
					lo, hi = lo:Min(corner), hi:Max(corner)
				end
			end
		end
	end
	local t = 0
	for _ = 1, 30 do
		t += 0.1
		MythRig.pose(probe, "Caged", kind, t, 0, 0, 0, true)
		grow()
	end
	local since = t
	for _ = 1, 22 do
		t += 0.1
		MythRig.pose(probe, "Taunt", kind, t, 0, math.min(1, (t - since) / BOSS_ROAR), 0, true, { since = since })
		grow()
	end
	-- a shadow under its feet, so it stands on something
	local feet = pivot * Vector3.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	local shadow = box(world, Vector3.new(0.2, hi.X - lo.X, (hi.Z - lo.Z) * 0.8), CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90)), Color3.new(0, 0, 0))
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Transparency = 0.6
	self.bossJoints, self.bossKind, self.bossView = joints, kind, view
	self.bossBox = { pivot = pivot, lo = lo, hi = hi }
	local camera = Instance.new("Camera")
	camera.FieldOfView = BOSS_FOV
	camera.Parent = view
	view.CurrentCamera = camera
	self.bossCamera = camera
	self:frameBoss()
	view:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:frameBoss()
	end)
end

-- The closest camera, tilted up at BOSS_TILT, that holds all eight corners of the boss's box inside
-- BOSS_FIT of its view: centred across, feet on the bottom margin. Per axis, each corner allows a range
-- of camera offsets at a given distance; the distance is searched for the nearest one where every
-- range still overlaps.
function MenuPuppet:frameBoss()
	local size = self.bossView.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return
	end
	local tanV = math.tan(math.rad(BOSS_FOV / 2))
	local tanH = tanV * size.X / size.Y
	local b = self.bossBox
	local turn = CFrame.lookAt(Vector3.zero, Vector3.new(0, math.sin(BOSS_TILT), math.cos(BOSS_TILT))) -- toward +Z, at the boss's face, up a little
	local corners = {}
	for _, sx in { b.lo.X, b.hi.X } do
		for _, sy in { b.lo.Y, b.hi.Y } do
			for _, sz in { b.lo.Z, b.hi.Z } do
				table.insert(corners, turn:PointToObjectSpace(b.pivot * Vector3.new(sx, sy, sz)))
			end
		end
	end
	local function ranges(d: number): (number, number, number, number)
		local xLo, xHi, yLo, yHi = -math.huge, math.huge, -math.huge, math.huge
		for _, q in corners do
			local z = d - q.Z -- depth in front of a camera at local z = d, looking down -Z
			xLo = math.max(xLo, q.X - BOSS_FIT.right * tanH * z)
			xHi = math.min(xHi, q.X - BOSS_FIT.left * tanH * z)
			yLo = math.max(yLo, q.Y - BOSS_FIT.top * tanV * z)
			yHi = math.min(yHi, q.Y - BOSS_FIT.bottom * tanV * z)
		end
		return xLo, xHi, yLo, yHi
	end
	local near, far = 0, 2000
	for _ = 1, 40 do
		local d = (near + far) / 2
		local xLo, xHi, yLo, yHi = ranges(d)
		if xLo <= xHi and yLo <= yHi then
			far = d
		else
			near = d
		end
	end
	local xLo, xHi, _, yHi = ranges(far)
	-- the highest offset in range drops the boss lowest: its feet on the bottom margin
	self.bossCamera.CFrame = turn * CFrame.new((xLo + xHi) / 2, yHi, far)
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

-- Leaving for the game (PLAY): client/PlayIntro, keyed in Blender (assets/menu/play_intro.py) and baked
-- per frame. He hears the click, pumps a fist, leans on his knees and stands (the chair fades), takes
-- the headphones off, cracks his neck, turns his back on the camera and struts off; the camera eases in
-- from its menu spot to the clip's own and from PUSH_AT pushes into the back of his head, where
-- LEAVE_TIME cuts to the game. ZOOM_AT is when he starts walking: the menu floods blue and his view
-- grows to the whole screen. In seconds since PLAY.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 1, #B64 do
	DIGIT[string.byte(B64, i)] = i - 1
end
local INTRO_JOINTS = { "waist", "neck", "lShoulder", "lElbow", "lWrist", "rShoulder", "rElbow", "rWrist", "lHip", "lKnee", "lAnkle", "rHip", "rKnee", "rAnkle" }

-- one clip frame: { root = CFrame, [joint] = CFrame, camera = CFrame, fov = number }
local function decodeIntro(clip): { { [string]: any } }
	local data, per = clip.data, clip.per
	local frames = table.create(clip.frames)
	for f = 0, clip.frames - 1 do
		local at = f * per + 1
		local function num(chars: number, lo: number, hi: number): number
			local n = 0
			for i = at, at + chars - 1 do
				n = n * 64 + DIGIT[string.byte(data, i)]
			end
			at += chars
			return lo + (hi - lo) * n / (64 ^ chars - 1)
		end
		local function quat(): CFrame
			local x, y, z = num(2, -1, 1), num(2, -1, 1), num(2, -1, 1)
			return CFrame.new(0, 0, 0, x, y, z, math.sqrt(math.max(0, 1 - x * x - y * y - z * z)))
		end
		local function pos(): Vector3
			return Vector3.new(num(3, -32, 32), num(3, -32, 32), num(3, -32, 32))
		end
		local frame = {}
		local rootAt = pos()
		frame.root = CFrame.new(rootAt) * quat()
		for _, key in INTRO_JOINTS do
			frame[key] = quat()
		end
		local camAt = pos()
		frame.camera = CFrame.new(camAt) * quat()
		frame.fov = num(2, 0, 120)
		frames[f + 1] = frame
	end
	return frames
end

local intro = require(script.Parent:WaitForChild("PlayIntro"))
local introFrames: { { [string]: any } }? = nil
local INTRO_LENGTH = (intro.frames - 1) / intro.fps
MenuPuppet.ZOOM_AT = 92 / intro.fps -- the first step of the walk
MenuPuppet.LEAVE_TIME = INTRO_LENGTH
local PUSH_AT = 116 / intro.fps -- from here the camera closes in on the game's chase camera
local CHASE_FAR = 6 -- studs behind the head the push starts from
local EASE_IN = 0.6 -- the menu camera hands over to the clip's over this long
local STAND_UP = { 0.93, 1.5 } -- seconds: the clip's root goes from the chair to the floor

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
	introFrames = introFrames or decodeIntro(intro)
end

-- the clip at `e` seconds, between its baked frames
local function introAt(e: number): { [string]: any }
	local frames = introFrames :: { { [string]: any } }
	local x = math.clamp(e * intro.fps, 0, #frames - 1)
	local i = math.floor(x)
	local a, b = frames[i + 1], frames[math.min(i + 2, #frames)]
	local w = x - i
	local out = {}
	for key, value in a do
		out[key] = if typeof(value) == "number" then value + (b[key] - value) * w else value:Lerp(b[key], w)
	end
	return out
end

function MenuPuppet:leavePose(e: number, t: number): Pose
	local clip = introAt(e)
	-- this avatar's own chair and floor heights, not the Blender proxy's: shift the root by the
	-- difference, the sitting one while he sits and the standing one once he's up
	local up = ease((e - STAND_UP[1]) / (STAND_UP[2] - STAND_UP[1]))
	local fit = (self.sitRoot.Position - intro.sitRoot):Lerp(self.standRoot.Position - intro.standRoot, up)
	local pose: Pose = { root = clip.root + fit }
	for _, key in INTRO_JOINTS do
		pose[key] = clip[key]
	end
	-- from the live sitting pose (its swing and nod) into the clip's first frames
	local w = ease(e / 0.15)
	if w < 1 then
		local sit = self:sitPose(t)
		for key, value in sit do
			local from = if typeof(value) == "Vector3" then CFrame.Angles(math.rad(value.X), math.rad(value.Y), math.rad(value.Z)) else value
			pose[key] = from:Lerp(pose[key], w)
		end
	end
	pose.camera, pose.fov = clip.camera, clip.fov
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
		if self.leaveAt and t - self.leaveAt < BOSS_ROAR then
			roar = t - self.leaveAt -- and one as he gets up to go and fight it
		end
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
		local turn = if typeof(a) == "CFrame" then a else CFrame.Angles(math.rad(a.X), math.rad(a.Y), math.rad(a.Z))
		parts[j.part].CFrame = parts[j.parent].CFrame * j.a * turn * j.b
	end
	-- the headphones fade as his hands lift them off, the chair as he gets up (the clip's moments)
	local gone = e and ease((e - intro.phonesOff[1]) / (intro.phonesOff[2] - intro.phonesOff[1])) or 0
	for _, x in self.extras do
		x.part.CFrame = parts[x.on].CFrame * x.offset
		if x.phone then
			x.part.Transparency = gone
		end
	end
	if e then
		local fade = ease((e - intro.chairFade[1]) / (intro.chairFade[2] - intro.chairFade[1]))
		for _, c in self.chairParts do
			c.part.Transparency = c.alpha + (1 - c.alpha) * fade
		end
		-- the camera: from its menu spot onto the clip's, and from PUSH_AT onto the game's chase camera
		-- behind this avatar's own head, closing in to the spot the game camera takes over at
		local k = ease(e / EASE_IN)
		local cam = self.camHome:Lerp(self.base * pose.camera, k)
		local fov = self.homeFov + (pose.fov - self.homeFov) * k
		if e > PUSH_AT then
			local head = parts.Head
			local fwd = (self.base * pose.root).LookVector * Vector3.new(1, 0, 1)
			local u = math.clamp((e - PUSH_AT) / (INTRO_LENGTH - PUSH_AT), 0, 1)
			local chase = MenuPuppet.chaseCamera(head.Position, fwd.Unit, MenuPuppet.headBack(head), CHASE_FAR * (1 - u * u))
			cam = cam:Lerp(chase, ease(u * 2) * 0.5 + u * 0.5)
		end
		self.camera.CFrame = cam
		self.camera.FieldOfView = fov
	end
end

return MenuPuppet
