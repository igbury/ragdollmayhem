local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local punchRemote = remotes:WaitForChild("Punch")
local grabRemote = remotes:WaitForChild("Grab")
local actionRemote = remotes:WaitForChild("Action")
local attackRemote = remotes:WaitForChild("Attack")
local weaponRemote = remotes:WaitForChild("Weapon")
local fxRemote = remotes:WaitForChild("Fx")
local dummyFolder = workspace:WaitForChild("Dummies")

local Attacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attacks"))
local Weapons = require(ReplicatedStorage.Shared:WaitForChild("Weapons"))
local Fx = require(script:WaitForChild("Fx"))
local WeaponMeshes = require(script:WaitForChild("WeaponMeshes"))
local Menu = require(script:WaitForChild("Menu"))

-- Sprint run cycle (assets/anims/SprintFlail.json), built in memory, no upload.
-- ponytail: a registered id is session-local, so other players see the default run; upload
-- assets/anims/SprintFlail.rbxmx from the Animation Editor and use that id if they should see it.
local sprintAnim = Instance.new("Animation")
sprintAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("SprintFlail")))
local sprintTrack: AnimationTrack? = nil

local PUNCH_RANGE = 9
local PUNCH_INTERVAL = 0.28
local GRAB_RANGE = 13
local THROW_SPEED = 90
local SKIN = Color3.fromRGB(240, 240, 240)
local WALK_SPEED = 16
local SPRINT_SPEED = 28

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local holding = nil -- { part, dist, since }
local punching = false
local lastPunch = 0
local nextHand = "right"
local weaponIndex = 1 -- Weapons[1] is fists
local lastWeaponUse = 0
local recoil = 0
local sprint = 0 -- eased 0..1
local nextLine, nextStep = 0, 0

player.CameraMode = Enum.CameraMode.LockFirstPerson

-- HUD -------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RagdollHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local function label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.6
	for k, v in props do
		l[k] = v
	end
	l.Parent = gui
	return l
end

local crosshair = label({ Text = "+", TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20) })
local hint = label({
	TextSize = 16,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 50),
	Size = UDim2.fromOffset(500, 28),
	BackgroundTransparency = 0.4,
	BackgroundColor3 = Color3.fromRGB(20, 20, 20),
})
label({
	Text = "Shift  Sprint\nQ  Next weapon\nF  Previous weapon\nE  Grab / drop\nC  Fall\nG  Spawn dummy\nR  Revive\nV  Camera",
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(200, 140),
})
local weaponLabel = label({
	TextSize = 18,
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 84),
	Size = UDim2.fromOffset(300, 22),
})
local attackByKey = {}
for i, attack in Attacks do
	attackByKey[attack.key] = attack
	attack.readyAt = 0
	attack.label = label({
		Text = `{i}  {attack.name}`,
		TextSize = 15,
		TextColor3 = attack.color,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16 - (#Attacks - i) * 22),
		Size = UDim2.fromOffset(220, 20),
	})
end
local targetTitle = label({
	TextSize = 16,
	TextColor3 = Color3.fromRGB(255, 190, 70),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -48),
	Size = UDim2.fromOffset(600, 20),
})
local targetInfo = label({
	TextSize = 14,
	Font = Enum.Font.Gotham,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -28),
	Size = UDim2.fromOffset(600, 18),
})
gui.Parent = player:WaitForChild("PlayerGui")

-- Aiming ----------------------------------------------------------------------
local function aim(range: number)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	rayParams.FilterDescendantsInstances = { char, camera }
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	-- in third person the camera sits behind the head, so extend the ray by that gap
	local extra = head and (camera.CFrame.Position - head.Position).Magnitude or 0
	return workspace:Raycast(ray.Origin, ray.Direction * (range + extra), rayParams), ray
end

local function dummyOf(inst: Instance?): Model?
	while inst and inst.Parent ~= dummyFolder do
		inst = inst.Parent
	end
	return inst :: Model?
end

local function isFirstPerson(): boolean
	return (camera.Focus.Position - camera.CFrame.Position).Magnitude < 1.5
end

-- Fists viewmodel -------------------------------------------------------------
local function part(shape, size)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = SKIN
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = camera
	return p
end

local hands = {}
for _, side in { "left", "right" } do
	hands[side] = {
		fist = part(Enum.PartType.Ball, Vector3.new(0.45, 0.45, 0.45)),
		arm = part(Enum.PartType.Block, Vector3.new(0.3, 0.3, 2.4)),
		t = 1,
		x = side == "left" and -1 or 1,
	}
end

-- First-person arms are clones of the character's own hand / lower arm / upper arm, so they carry
-- the avatar's skin, shape and sleeves. The ball-and-block fists above stay as the anchor the
-- weapons hang off, and as the fallback for a rig without R15 arms.
-- Where a tool sits in an R15 hand: in the palm, turned so the tool's -Z runs out along the fingers.
local DEFAULT_GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
local armModel: Model? = nil
local arms = {} -- [side] = { pieces = { { part, offset from the hand } }, wrist = Vector3, grip = CFrame }

local function buildArms(char: Model)
	if armModel then
		armModel:Destroy()
	end
	arms = {}
	local model = Instance.new("Model")
	model.Name = "Arms"
	for side, prefix in { left = "Left", right = "Right" } do
		-- WaitForChild: the appearance can report loaded before every part and attachment has
		-- replicated to this client. Yields, so this runs in its own thread.
		local hand = char:WaitForChild(prefix .. "Hand", 5)
		local lower = char:WaitForChild(prefix .. "LowerArm", 5)
		local upper = char:WaitForChild(prefix .. "UpperArm", 5)
		-- Rest pose of a straight arm, read off the rig attachments both parts of a joint share.
		-- (Not Motor6D C0/C1: newer avatars use AnimationConstraints and have none.)
		local function joint(a: Instance?, b: Instance?, name: string): CFrame?
			local onA = a and a:WaitForChild(prefix .. name .. "RigAttachment", 5) :: Attachment?
			local onB = b and b:WaitForChild(prefix .. name .. "RigAttachment", 5) :: Attachment?
			return onA and onB and onA.CFrame * onB.CFrame:Inverse()
		end
		local lowerOffset = joint(hand, lower, "Wrist")
		local elbowOffset = joint(lower, upper, "Elbow")
		if not (lowerOffset and elbowOffset) then
			continue
		end
		local upperOffset = lowerOffset * elbowOffset
		local list = {}
		for _, entry in { { hand, CFrame.identity }, { lower, lowerOffset }, { upper, upperOffset } } do
			local clone = entry[1]:Clone()
			for _, child in clone:GetChildren() do
				if not child:IsA("SurfaceAppearance") then
					child:Destroy() -- joints, ragdoll constraints, attachments
				end
			end
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanQuery = false
			clone.CanTouch = false
			clone.CastShadow = false
			clone.Parent = model
			table.insert(list, { part = clone, offset = entry[2] })
		end
		local wrist = hand:FindFirstChild(prefix .. "WristRigAttachment") :: Attachment
		local grip = hand:FindFirstChild(prefix .. "GripAttachment") :: Attachment?
		arms[side] = { pieces = list, wrist = wrist.Position, grip = grip and grip.CFrame or DEFAULT_GRIP }
	end
	-- clothing only renders on body parts that sit in a model with a Humanoid
	for _, child in char:GetChildren() do
		if child:IsA("Shirt") then
			child:Clone().Parent = model
		end
	end
	local dummy = Instance.new("Humanoid")
	dummy.RigType = Enum.HumanoidRigType.R15 -- a new Humanoid defaults to R6
	dummy.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	dummy.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	dummy.Parent = model
	model.Parent = camera
	armModel = model
end

-- Weapon viewmodels: a few blocks each, positioned relative to the right fist (-Z = forward).
local GREY, DARK, WOOD, STEEL = Color3.fromRGB(70, 72, 78), Color3.fromRGB(25, 25, 28), Color3.fromRGB(150, 100, 60), Color3.fromRGB(200, 205, 215)
local BLOCK, BALL, CYL = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
local VIEWMODELS = { -- { shape, size, offset, color, transparency? }
	Bat = { { CYL, Vector3.new(3.6, 0.34, 0.34), CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.pi / 2), WOOD } },
	Axe = {
		{ BLOCK, Vector3.new(0.18, 2.8, 0.18), CFrame.new(0, 1.1, 0), WOOD },
		{ BLOCK, Vector3.new(0.14, 0.85, 0.95), CFrame.new(0, 2.2, -0.45), STEEL },
	},
	Knife = {
		{ BLOCK, Vector3.new(0.06, 0.22, 1), CFrame.new(0, 0.1, -0.7), STEEL },
		{ BLOCK, Vector3.new(0.14, 0.24, 0.45), CFrame.new(0, 0.1, 0), DARK },
	},
	Handgun = {
		{ BLOCK, Vector3.new(0.22, 0.28, 1), CFrame.new(0, 0.25, -0.4), GREY },
		{ BLOCK, Vector3.new(0.2, 0.5, 0.25), CFrame.new(0, -0.05, -0.05), DARK },
	},
	Revolver = {
		{ BLOCK, Vector3.new(0.18, 0.2, 1.3), CFrame.new(0, 0.3, -0.75), STEEL },
		{ BLOCK, Vector3.new(0.36, 0.36, 0.42), CFrame.new(0, 0.24, -0.1), GREY },
		{ BLOCK, Vector3.new(0.2, 0.5, 0.25), CFrame.new(0, -0.1, 0.1), WOOD },
	},
	Rifle = {
		{ BLOCK, Vector3.new(0.25, 0.35, 2.8), CFrame.new(0, 0.25, -1.1), DARK },
		{ BLOCK, Vector3.new(0.22, 0.42, 0.9), CFrame.new(0, 0.12, 0.7), WOOD },
		{ BLOCK, Vector3.new(0.18, 0.6, 0.3), CFrame.new(0, -0.2, -0.7), GREY },
	},
	Grenade = {
		{ BALL, Vector3.one * 0.75, CFrame.new(0, 0.3, -0.1), Color3.fromRGB(60, 80, 50) },
		{ BLOCK, Vector3.new(0.2, 0.25, 0.2), CFrame.new(0, 0.75, -0.1), GREY },
	},
	Molotov = {
		{ BLOCK, Vector3.new(0.42, 0.9, 0.42), CFrame.new(0, 0.5, 0), Color3.fromRGB(200, 120, 40), 0.3 },
		{ BLOCK, Vector3.new(0.18, 0.35, 0.18), CFrame.new(0, 1.1, 0), Color3.fromRGB(200, 120, 40), 0.3 },
		{ BLOCK, Vector3.new(0.2, 0.3, 0.2), CFrame.new(0, 1.4, 0), Color3.new(1, 1, 1) },
	},
}
local viewParts = {} -- { part, weaponId, offset, transparency }
for id, specs in VIEWMODELS do
	for _, spec in specs do
		local p = part(spec[1], spec[2])
		p.Color = spec[4]
		p.Transparency = 1
		table.insert(viewParts, { part = p, id = id, offset = spec[3], transparency = spec[5] or 0 })
	end
end

-- Detailed meshes take over from the blocks above as soon as they are built; the blocks stay as
-- the fallback for a client that cannot build them.
-- How each weapon is held.
-- grip: the mesh relative to the hand's grip attachment (-Z = where the camera looks, +Y = up out
--       of the fist), i.e. which point of the model the palm closes around.
-- scale: optional, shrinks the in-hand mesh only.
-- hand: where the right hand moves to for this weapon, relative to its fist position (camera space).
local HOLD = {
	Handgun = { grip = CFrame.new(0, 0.24, 0.08), hand = Vector3.new(-0.25, 0.2, 0.1) },
	Revolver = { grip = CFrame.new(0, 0.23, -0.08), hand = Vector3.new(-0.25, 0.2, 0.1) },
	Rifle = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45) },
	Knife = { grip = CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, 0, -0.32), hand = Vector3.new(0, 0.15, 0) }, -- blade up
	Bat = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Axe = { grip = CFrame.new(0, 0.15, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Grenade = { grip = CFrame.new(0, 0.2, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.7 }, -- full size overflows the hand
	Molotov = { grip = CFrame.new(0, 0.38, 0), hand = Vector3.new(0, 0.1, 0) },
}
local viewMeshes = {} -- [weaponId] = MeshPart
task.spawn(function()
	for id in HOLD do
		local mesh = WeaponMeshes.create(id)
		if mesh then
			mesh.Size *= HOLD[id].scale or 1
			mesh.Transparency = 1
			mesh.Parent = camera
			viewMeshes[id] = mesh
		end
	end
end)

-- Thrown grenades / molotovs are plain server parts; dress them in the same meshes locally.
workspace.ChildAdded:Connect(function(child)
	if not child:GetAttribute("Projectile") then
		return
	end
	local mesh = WeaponMeshes.create(child.Name)
	if not mesh or not child.Parent then
		return
	end
	child.LocalTransparencyModifier = 1
	mesh.Parent = camera
	local follow
	follow = RunService.RenderStepped:Connect(function()
		if child.Parent then
			mesh.CFrame = child.CFrame
		else
			follow:Disconnect()
			mesh:Destroy()
		end
	end)
end)

local function useWeapon(weapon)
	local now = os.clock()
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if now - lastWeaponUse < weapon.cd or not head or char:GetAttribute("Ragdolled") then
		return
	end
	lastWeaponUse = now
	local result, ray = aim(300)
	local target = result and result.Position or ray.Origin + ray.Direction * 300
	weaponRemote:FireServer(weapon.id, (target - head.Position).Unit)
	if weapon.kind == "gun" then
		recoil = 1
	else
		hands.right.t = 0 -- the punch motion doubles as the swing / throw
	end
end

local function cycleWeapon(step: number)
	weaponIndex = (weaponIndex - 1 + step) % #Weapons + 1
	lastWeaponUse = 0
end

-- Actions ---------------------------------------------------------------------
local function punch()
	local now = os.clock()
	if now - lastPunch < PUNCH_INTERVAL then
		return
	end
	lastPunch = now
	hands[nextHand].t = 0
	nextHand = nextHand == "right" and "left" or "right"
	local result = aim(PUNCH_RANGE)
	if result and dummyOf(result.Instance) then
		punchRemote:FireServer(result.Instance)
		Fx.hit(result.Position)
	end
end

local function drop(velocity: Vector3)
	grabRemote:FireServer("release", velocity)
	holding = nil
end

local function toggleGrab()
	if holding then
		drop(Vector3.zero)
		return
	end
	local result = aim(GRAB_RANGE)
	if result and dummyOf(result.Instance) then
		grabRemote:FireServer("grab", result.Instance)
		local head = player.Character and player.Character:FindFirstChild("Head")
		local dist = head and (result.Position - head.Position).Magnitude or 5
		holding = { part = result.Instance, dist = math.clamp(dist, 3, 8), since = os.clock() }
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or Menu.active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if holding then
			drop(camera.CFrame.LookVector * THROW_SPEED)
			return
		end
		punching = true
		local weapon = Weapons[weaponIndex]
		while punching and not holding and Weapons[weaponIndex] == weapon do
			if not weapon.kind then
				punch()
			else
				useWeapon(weapon)
			end
			task.wait(weapon.cd or PUNCH_INTERVAL)
			if weapon.kind and not weapon.auto then
				break -- one use per click
			end
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		cycleWeapon(1)
	elseif input.KeyCode == Enum.KeyCode.F then
		cycleWeapon(-1)
	elseif attackByKey[input.KeyCode] then
		local attack = attackByKey[input.KeyCode]
		if os.clock() >= attack.readyAt and not holding then
			attack.readyAt = os.clock() + attack.cd
			attackRemote:FireServer(attack.id)
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		toggleGrab()
	elseif input.KeyCode == Enum.KeyCode.C then
		actionRemote:FireServer("fall")
	elseif input.KeyCode == Enum.KeyCode.G then
		local result = aim(150)
		if result then
			actionRemote:FireServer("spawn", result.Position)
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		local result = aim(60)
		actionRemote:FireServer("revive", result and dummyOf(result.Instance) and result.Instance)
	elseif input.KeyCode == Enum.KeyCode.V then
		if player.CameraMode == Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.Classic
			player.CameraMinZoomDistance = 10
			task.wait()
			player.CameraMinZoomDistance = 0.5
		else
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		punching = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if holding and input.UserInputType == Enum.UserInputType.MouseWheel then
		holding.dist = math.clamp(holding.dist + input.Position.Z, 3, 16)
	end
end)

fxRemote.OnClientEvent:Connect(Fx.play)
-- Sky light (environment diffuse/specular) is not blocked by the factory roof and floods the
-- inside, so switch it off in there and let the lamps plus a little ambient do the work.
local Lighting = game:GetService("Lighting")
local OUTSIDE = { Ambient = Lighting.Ambient, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale, EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale }
local INSIDE = { Ambient = Color3.fromRGB(20, 20, 20), EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0 }
player:GetAttributeChangedSignal("Map"):Connect(function()
	for prop, value in player:GetAttribute("Map") == "FACTORY" and INSIDE or OUTSIDE do
		Lighting[prop] = value
	end
end)
remotes:WaitForChild("Hazard").OnClientEvent:Connect(function(velocity: Vector3)
	-- a factory machine hit us; we own our physics, so the server cannot fling us itself
	local char = player.Character
	for _, part in char and char:GetDescendants() or {} do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = velocity
		end
	end
end)

-- Own ragdoll: the client owns its humanoid, so it switches the state itself.
local function onCharacter(char: Model)
	local humanoid = char:WaitForChild("Humanoid") :: Humanoid
	sprintTrack = humanoid:WaitForChild("Animator"):LoadAnimation(sprintAnim)
	sprintTrack.Priority = Enum.AnimationPriority.Movement -- over the default run (Core)
	sprintTrack.Looped = true
	task.spawn(function()
		if not player:HasAppearanceLoaded() then
			player.CharacterAppearanceLoaded:Wait()
		end
		if player.Character == char then
			buildArms(char)
		end
	end)
	char:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if char:GetAttribute("Ragdolled") then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end
if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- Per frame -------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head") :: BasePart?

	-- drive the held body part (we own its physics while holding)
	if holding then
		local align = holding.part:FindFirstChild("GrabAlign", true) :: AlignPosition?
		if align and head then
			local _, ray = aim(0)
			align.Position = head.Position + ray.Direction.Unit * holding.dist
		elseif not holding.part.Parent or os.clock() - holding.since > 1 then
			holding = nil -- server let go (revive, despawn, rejected grab)
		end
	end

	gui.Enabled = not Menu.active

	-- fists
	local show = isFirstPerson() and not holding and humanoid and humanoid.Health > 0 and not (char and char:GetAttribute("Ragdolled"))
	local moving = humanoid and humanoid.MoveDirection.Magnitude > 0 and 1 or 0
	UserInputService.MouseIconEnabled = not isFirstPerson()
	crosshair.Visible = isFirstPerson()

	-- sprint
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and moving == 1 and not holding and root
		and humanoid.Health > 0 and not char:GetAttribute("Ragdolled")
	if humanoid then
		humanoid.WalkSpeed = sprinting and SPRINT_SPEED or WALK_SPEED
	end
	local running = sprinting and humanoid.FloorMaterial ~= Enum.Material.Air
	if sprintTrack and running and not sprintTrack.IsPlaying then
		sprintTrack:Play(0.15)
	elseif sprintTrack and not running and sprintTrack.IsPlaying then
		sprintTrack:Stop(0.2)
	end
	sprint += ((sprinting and 1 or 0) - sprint) * math.min(dt * 8, 1)
	Fx.fovBoost = 14 * sprint
	local now = os.clock()
	if sprinting and now > nextLine then
		nextLine = now + 0.03
		Fx.speedLine()
	end
	if sprinting and now > nextStep and humanoid.FloorMaterial ~= Enum.Material.Air then
		nextStep = now + 0.25
		Fx.dust(root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0), 3, 2, 0.6)
	end

	local bob = math.sin(os.clock() * (9 + 5 * sprint)) * 0.05 * (1 + 1.5 * sprint) * moving
	local weapon = Weapons[weaponIndex]
	local hold = HOLD[weapon.id]
	recoil = math.max(recoil - dt / 0.15, 0)
	local weaponCF = nil
	for side, h in hands do
		h.t = math.min(h.t + dt / 0.2, 1)
		local ext = math.sin(h.t * math.pi)
		-- the right hand moves to where this weapon is held, and kicks back with recoil
		local move = (side == "right" and hold) and hold.hand + Vector3.new(0, 0, 0.25 * recoil) or Vector3.zero
		local fist = camera.CFrame
			* CFrame.new(h.x * (0.85 - 0.6 * ext) + move.X, -0.85 + 0.35 * ext + bob * h.x + move.Y, -2 - 1.2 * ext + move.Z)
		h.fist.CFrame = fist
		h.arm.CFrame = fist * CFrame.Angles(math.rad(25), math.rad(14 * h.x), 0) * CFrame.new(0, 0, 1.3)
		local real = arms[side]
		h.fist.Transparency = (show and not real) and 0 or 1
		h.arm.Transparency = (show and not real) and 0 or 1
		-- fingers forward, forearm running back, down and outward past the camera
		local arm = fist * CFrame.Angles(math.rad(25), math.rad(14 * h.x), 0) * CFrame.Angles(math.rad(90), 0, 0)
		local hand = arm
		if side == "right" and hold then
			-- The wrist bends so the hand is square to the view whatever the forearm is doing:
			-- guns point at the crosshair, melee and throwables stand upright and tip forward to swing.
			local tilt = weapon.kind == "gun" and 14 * recoil or -25 - 75 * ext
			local pivot = real and real.wrist or Vector3.zero
			hand = CFrame.new(arm * pivot)
				* camera.CFrame.Rotation
				* CFrame.Angles(math.rad(tilt), 0, 0)
				* CFrame.Angles(math.rad(90), 0, 0)
				* CFrame.new(-pivot)
			weaponCF = hand * (real and real.grip or DEFAULT_GRIP)
		end
		if real then
			for i, piece in real.pieces do
				piece.part.CFrame = (i == 1 and hand or arm) * piece.offset
				piece.part.LocalTransparencyModifier = show and 0 or 1
			end
		end
	end

	-- weapon in the right hand
	local thrown = weapon.kind == "thrown" or weapon.kind == "knife"
	local inHand = show and weaponCF and not (thrown and os.clock() - lastWeaponUse < weapon.cd) -- it left the hand
	for _, v in viewParts do
		local active = v.id == weapon.id and inHand and not viewMeshes[v.id]
		v.part.Transparency = active and v.transparency or 1
		if active then
			v.part.CFrame = weaponCF * v.offset
		end
	end
	for id, mesh in viewMeshes do
		local active = id == weapon.id and inHand
		mesh.Transparency = active and 0 or 1
		if active then
			mesh:PivotTo(weaponCF * HOLD[id].grip)
		end
	end
	weaponLabel.Text = weapon.name

	for _, attack in Attacks do
		attack.label.TextTransparency = os.clock() < attack.readyAt and 0.65 or 0
	end

	-- hints + target info
	hint.Text = holding and "Click: throw   Scroll: distance   E: drop" or (weapon.kind and "Click: use weapon   Q / F: switch" or "Click: punch, hold to keep going   Q / F: weapons")
	local result = aim(60)
	local dummy = result and dummyOf(result.Instance)
	if dummy then
		local injuries = dummy:GetAttribute("Injuries")
		targetTitle.Text = injuries ~= "" and injuries or "No injuries"
		targetInfo.Text = `{dummy.Name} · {dummy:GetAttribute("State")} · {dummy:GetAttribute("HP")}% health`
	else
		targetTitle.Text = ""
		targetInfo.Text = ""
	end
end)
