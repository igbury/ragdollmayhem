local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local punchRemote = remotes:WaitForChild("Punch")
local grabRemote = remotes:WaitForChild("Grab")
local actionRemote = remotes:WaitForChild("Action")
local attackRemote = remotes:WaitForChild("Attack")
local weaponRemote = remotes:WaitForChild("Weapon")
local fxRemote = remotes:WaitForChild("Fx")
local moveRemote = remotes:WaitForChild("Move")
local dummyFolder = workspace:WaitForChild("Dummies")

local Attacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attacks"))
local Weapons = require(ReplicatedStorage.Shared:WaitForChild("Weapons"))
local Fx = require(script:WaitForChild("Fx"))
local WeaponMeshes = require(script:WaitForChild("WeaponMeshes"))
local Menu = require(script:WaitForChild("Menu"))
require(script:WaitForChild("Music")) -- starts the background playlist
require(script:WaitForChild("Speech")).start(dummyFolder) -- comic speech bubbles over dummies

-- Sprint run cycle (assets/anims/SprintFlail.json), built in memory, no upload.
-- ponytail: a registered id is session-local, so other players see the default run; upload
-- assets/anims/SprintFlail.rbxmx from the Animation Editor and use that id if they should see it.
local sprintAnim = Instance.new("Animation")
sprintAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("SprintFlail")))
local sprintTrack: AnimationTrack? = nil
local rollAnim = Instance.new("Animation") -- same deal, see RollForward
rollAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("RollForward")))
local rollTrack: AnimationTrack? = nil
local diveAnim = Instance.new("Animation") -- slam mode pose, see SupermanDive
diveAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("SupermanDive")))
local diveTrack: AnimationTrack? = nil
-- wall run cycle, one mirror per wall side (1 = wall on the right, -1 = left), see WallRun
local wallRunAnims = {}
for _, side in { 1, -1 } do
	local anim = Instance.new("Animation")
	anim.AnimationId = game:GetService("KeyframeSequenceProvider")
		:RegisterKeyframeSequence(require(script:WaitForChild("WallRun"))(side))
	wallRunAnims[side] = anim
end
local wallRunTracks: { [number]: AnimationTrack } = {}
local clingAnim = Instance.new("Animation") -- holding on to the wall, see WallCling
clingAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("WallCling")))
local clingTrack: AnimationTrack? = nil
local flipAnim = Instance.new("Animation") -- backflip off the wall, see WallFlip
flipAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("WallFlip")))
local flipTrack: AnimationTrack? = nil
local kickAnim = Instance.new("Animation") -- left click in third person, see HighKick
kickAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("HighKick")))
local kickTrack: AnimationTrack? = nil
-- slide pose and crouch shuffle, see SlideCrouch
local lowAnims, lowTracks = {}, {} :: { [string]: AnimationTrack }
for _, kind in { "slide", "crouch" } do
	local anim = Instance.new("Animation")
	anim.AnimationId = game:GetService("KeyframeSequenceProvider")
		:RegisterKeyframeSequence(require(script:WaitForChild("SlideCrouch"))(kind))
	anim.Name = kind
	lowAnims[kind] = anim
end
local dashAnim = Instance.new("Animation") -- the dash burst, see DashBurst
dashAnim.AnimationId = game:GetService("KeyframeSequenceProvider")
	:RegisterKeyframeSequence(require(script:WaitForChild("DashBurst")))
local dashTrack: AnimationTrack? = nil
local flipUntil = 0
local aimAnims = {} -- third-person aiming poses, see AimPose
for _, kind in { "gun", "rocket", "throw" } do
	local anim = Instance.new("Animation")
	anim.AnimationId = game:GetService("KeyframeSequenceProvider")
		:RegisterKeyframeSequence(require(script:WaitForChild("AimPose"))(kind))
	aimAnims[kind] = anim
end
local aimTracks: { [string]: AnimationTrack } = {}

-- Sounds (assets/sfx/*.wav, uploaded as Audio). An empty id stays silent.
-- ponytail: played locally, so only you hear your own; add a remote if others should.
local SFX = {
	Jump = "122753128464765", -- assets/sfx/Jump.wav, wall jump / double jump / ledge launch / wall flip
	Kick = "111158906695255", -- assets/sfx/Kick.wav
	Slam = "99067212893039", -- ground slam (R in the air) hitting the ground
	Run = "112506453896973", -- assets/sfx/Run.wav, looped while sprinting on the ground or wall running
}
local sounds: { [string]: Sound } = {} -- the body keeps facing the wall it flipped off until the flip is done
-- the same animations and sounds, played here on the other players' characters as they report them
require(script:WaitForChild("Others")).start(moveRemote, {
	sprint = sprintAnim, roll = rollAnim, dive = diveAnim, wall1 = wallRunAnims[1], ["wall-1"] = wallRunAnims[-1],
	cling = clingAnim, flip = flipAnim, kick = kickAnim, slide = lowAnims.slide, crouch = lowAnims.crouch,
	dash = dashAnim,
}, SFX)

local PUNCH_RANGE = 9
local PUNCH_INTERVAL = 0.28
local KICK_INTERVAL = 0.7
local GRAB_RANGE = 13
local THROW_SPEED = 90
local SKIN = Color3.fromRGB(240, 240, 240)
local WALK_SPEED = 16
local SPRINT_SPEED = 28
local XZ = Vector3.new(1, 0, 1)
-- Tuning for the ground and air moves further down (slide, crouch, dash, momentum, dive kick).
local MOVE = {
	CROUCH_SPEED = 8,
	LOW_DROP = 1.4, -- how far the hips come down in a slide or crouch
	SLIDE_FROM = 20, -- least ground speed that turns a crouch into a slide
	SLIDE_BOOST = 1.35, -- speed multiplier on starting a slide...
	SLIDE_MIN = 40, -- ...and the least it starts at
	SLIDE_END = 12, -- slower than this the slide is over (you stay crouched)
	SLIDE_COOLDOWN = 1, -- between boosts: sliding again sooner keeps your speed but adds none
	-- how fast carried speed bleeds off, per second (exponential)
	GLIDE_DRAG = 0.35, -- sliding, rolling: a slide stays faster than a sprint for about a second
	AIR_DRAG = 0.8,
	GROUND_DRAG = 1.5, -- running on the ground
	STOP_DRAG = 10, -- on the ground with the stick let go
	GROUND_STEER = 6, -- how fast the stick turns carried speed on the ground (the air has AIR_STEER)
	DASH_SPEED = 62,
	DASH_TIME = 0.18,
	DASH_EXIT = 34, -- speed left when the dash is over
	DASH_COOLDOWN = 0.9,
	GROUND_DASH_SPEED = 58, -- on the ground: a burst along it, low and flat (no more somersault)
	GROUND_DASH_TIME = 0.2,
	DIVE_SPEED = 75, -- dive kick
	DIVE_TIME = 0.6,
	DIVE_COOLDOWN = 1.2,
	SLAM_KICK = 20, -- slam: downward shove on arming...
	SLAM_GRAVITY = 1, -- ...and extra gravity (multiples of normal) while diving
	SLAM_POWER = 0.6, -- share of the (now much higher) impact speed that counts, so a hop is not a bomb
	VAULT_TIME = 0.28, -- vault from a run: quicker than the mantle
	VAULT_MIN = 1.2, -- least rise that counts as something to vault onto
	WALL_MAX = 55, -- cap on the speed a wall run inherits
	WALL_KEEP = 0.5, -- how fast inherited speed settles back to WALL_SPEED, per second
	AIR_JUMP = 0.65, -- strength of the plain double jump, relative to the one after a wall jump
}
-- State of those moves, and the functions that start them (filled in further down).
local mv = {
	sprintHeld = false, -- Shift
	sprintToggle = false, -- gamepad / touch: press to run, stops when you stop moving
	crouchHeld = false,
	low = false, -- hips lowered: sliding or crouching
	sliding = false,
	slideBoostAt = 0,
	groundedAt = 0, -- last time on the ground, as the slide / crouch sees it
	baseHip = 2, -- the Humanoid's own HipHeight, read each time before lowering it
	blocked = 0, -- seconds the carried speed has been stopped by something solid
	dashing = false,
	dashUntil = 0, -- carried speed is left alone (no drag, no steering) until then
	dashReadyAt = 0,
	airDashUsed = false, -- one dash per airtime
	airJumpUsed = false, -- one double jump per airtime; a wall jump gives it back
	diveUntil = 0, -- a dive kick is flying until then
	diveReadyAt = 0,
	diveDir = Vector3.zAxis,
	lastWallNormal = nil :: Vector3?, -- the wall last run on this airtime
	loop = "", -- the looping movement look last reported to the server (see Others)
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local holding = nil -- { part, dist, since }
local punching = false
local lastPunch = 0
local lastKick = 0
local kickParams = OverlapParams.new()
kickParams.FilterType = Enum.RaycastFilterType.Include
kickParams.FilterDescendantsInstances = { dummyFolder }
local nextHand = "right"
local weaponIndex = 1 -- Weapons[1] is fists
local lastWeaponUse = 0
local recoil = 0
local aiming = false -- right mouse / L2 held: aim down the sights (guns) or show the throw arc (thrown)
local ads = 0 -- eased 0..1
-- [weaponId] = camera-space nudge of the right hand while aiming, learnt frame by frame so the
-- top of the held mesh ends up just under the crosshair whatever the wrist / grip offsets are
local adsFix = {}
-- [weaponId] = camera-space spot the left fist goes to while aiming (from HOLD.support, refreshed
-- every frame from where the held mesh actually is; a frame old, as the left hand is placed first)
local leftGrip = {}
-- Pulled-back camera with a weapon out: the mouse is locked to the crosshair in the middle and the
-- body turns with the camera, so every shot goes where the crosshair is and never backwards.
-- Right mouse raises the weapon (AimPose) and brings the camera over the shoulder; it stays back.
local thirdWeapon = false
local thirdAim = 0 -- eased 0..1
local mouseLocked = false -- thirdWeapon as of last frame, to unlock the mouse once when it ends
local SHOULDER = Vector3.new(1.6, 0.4, 0) -- camera offset over the right shoulder when aiming
-- The weapon in the character's own right hand, seen with the camera pulled back. BODY_GRIP turns
-- the first-person hold (HOLD.grip, -Z out along the aim, +Y up) into the R15 hand's grip frame.
local BODY_GRIP = CFrame.identity -- calibration knob; the R15 grip attachment already matches
local bodyWeapon: { id: string?, part: MeshPart? } = {}
-- Throwing-knife aim (right mouse): the knife is tossed up out of the fist, turns over and is caught
-- by the blade, while the arm bends back beside the head with the handle pointing at the crosshair.
local KNIFE_FLIP = 0.5 -- seconds for the whole toss
local KNIFE_BLADE = 0.75 -- how far up the knife slides so the palm closes on the blade, not the handle
local KNIFE_COCK = Vector3.new(-0.15, 0.55, 0.3) -- the right fist's move from rest: up beside the head, pulled back
local KNIFE_TILT = -60 -- wrist tilt when cocked (melee rests at -25; -90 lays the knife flat along the view)
local knifeT = 0
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end
-- The knife relative to its normal place in the hand at toss progress t: lifted on an arc, spun
-- one and a half turns (ends upside down), sliding down so the blade ends up in the palm.
local function knifeFlip(t: number): CFrame
	local e = smooth(t)
	return CFrame.new(0, math.sin(math.pi * t) * 0.9 + KNIFE_BLADE * e, 0) * CFrame.Angles(math.pi * 3 * e, 0, 0)
end
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
-- sniper scope: a clear circle (a huge black stroke round a round frame blacks out the rest) and a cross
local scope = Instance.new("Frame")
scope.AnchorPoint = Vector2.new(0.5, 0.5)
scope.Position = UDim2.fromScale(0.5, 0.5)
scope.Size = UDim2.fromScale(0.8, 0.8)
scope.SizeConstraint = Enum.SizeConstraint.RelativeYY
scope.BackgroundTransparency = 1
scope.Visible = false
scope.Parent = gui
do
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = scope
	local dark = Instance.new("UIStroke")
	dark.Thickness = 3000
	dark.Color = Color3.new(0, 0, 0)
	dark.Parent = scope
	for _, size in { UDim2.new(1, 0, 0, 2), UDim2.new(0, 2, 1, 0) } do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = size
		line.BackgroundColor3 = Color3.new(0, 0, 0)
		line.BorderSizePixel = 0
		line.Parent = scope
	end
end
local controls = label({
	Visible = false, -- H shows it (below); the weapons have their own bar now (WeaponBar)
	Text = "Shift  Sprint\nCtrl  Slide / crouch\nX  Dash\nSpace  Double jump (in the air)\nA / D  Wall run (in the air, at a wall)\nW  Grab a wall / climb a ledge\nS  Backflip (hanging on a wall)\nClick  Dive kick (in the air)\nQ  Next weapon (hold: weapon wheel)\nF / scroll  Previous / switch weapon\nE  Grab / drop\nC  Fall\nG  Spawn dummy\nR  Revive / slam (in the air)\nB  Scan (X-ray a dummy)\nV  Camera",
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(320, 280),
})
local controlsHint = label({
	Text = "H  Controls",
	TextSize = 13,
	TextTransparency = 0.25,
	TextXAlignment = Enum.TextXAlignment.Left,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(160, 16),
})
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.H then
		controls.Visible = not controls.Visible
		controlsHint.Visible = not controls.Visible
	end
end)
local weaponLabel = label({
	Visible = false, -- the hotbar shows the weapon's name (WeaponBar)
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
	Position = UDim2.new(0.5, 0, 1, -150), -- above the hotbar
	Size = UDim2.fromOffset(600, 20),
})
local targetInfo = label({
	TextSize = 14,
	Font = Enum.Font.Gotham,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -130),
	Size = UDim2.fromOffset(600, 18),
})
-- Movement HUD, bottom centre (clear of the body in third person): the wall run time left (shown
-- only once some is used), and the double jump and the dash, dimmed while spent.
do
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 1, -186)
	back.Size = UDim2.fromOffset(120, 4)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.BackgroundTransparency = 0.4
	back.BorderSizePixel = 0
	back.Visible = false
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 220, 255)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local function pip(text: string, x: number)
		return label({ Text = text, TextSize = 12, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 1, -176), Size = UDim2.fromOffset(50, 14) })
	end
	mv.hud = { wallBack = back, wall = fill, jump = pip("JUMP", -30), dash = pip("DASH", 30) }
end
-- Vitals panel, bottom right, for the dummy you last looked at: a body diagram seen from the front
-- (grey = fine, yellow = hurt, orange = broken, dark = cut off), its condition, pulse, blood and
-- how awake it is. Filled in from the dummy's attributes in the per-frame block.
do
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -160) -- above the attack list
	panel.Size = UDim2.fromOffset(150, 216)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local cells = {}
	local function cell(name: string, x: number, y: number, w: number, h: number)
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BorderSizePixel = 0
		f.Parent = panel
		cells[name] = f
	end
	cell("Head", 61, 8, 28, 26)
	cell("UpperTorso", 53, 37, 44, 34)
	cell("LowerTorso", 53, 73, 44, 14)
	for side, left in { Right = true, Left = false } do -- facing us: its right arm is on our left
		local arm, leg = left and 37 or 99, left and 53 or 76
		cell(side .. "UpperArm", arm, 37, 14, 24)
		cell(side .. "LowerArm", arm, 63, 14, 22)
		cell(side .. "Hand", arm, 87, 14, 10)
		cell(side .. "UpperLeg", leg, 89, 21, 26)
		cell(side .. "LowerLeg", leg, 117, 21, 24)
		cell(side .. "Foot", leg, 143, 21, 8)
	end
	local function line(y: number, size: number, color: Color3)
		local l = label({ TextSize = size, TextColor3 = color, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, size + 2) })
		l.Parent = panel
		return l
	end
	local function bar(y: number, name: string, color: Color3)
		local l = line(y - 3, 10, Color3.new(1, 1, 1))
		l.Text = name
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position = UDim2.fromOffset(8, y - 3)
		local back = Instance.new("Frame")
		back.Position = UDim2.fromOffset(50, y)
		back.Size = UDim2.fromOffset(92, 6)
		back.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		back.BorderSizePixel = 0
		back.Parent = panel
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Parent = back
		return fill
	end
	mv.vitals = {
		panel = panel,
		cells = cells,
		status = line(156, 13, Color3.fromRGB(255, 160, 60)),
		pulse = line(172, 12, Color3.fromRGB(120, 230, 150)),
		blood = bar(194, "Blood", Color3.fromRGB(150, 90, 255)),
		awake = bar(205, "Awake", Color3.fromRGB(120, 230, 150)),
		colors = { [0] = Color3.fromRGB(150, 150, 155), Color3.fromRGB(240, 200, 70), Color3.fromRGB(255, 120, 40), Color3.fromRGB(45, 30, 70) },
	}
end
gui.Parent = player:WaitForChild("PlayerGui")

-- Aiming ----------------------------------------------------------------------
local function aim(range: number)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	rayParams.FilterDescendantsInstances = { char, camera }
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	-- in third person the camera sits behind the head: start the ray level with the head, so
	-- nothing between the camera and the body (a dummy walking behind you) can be the target
	-- and a shot from the head never goes backwards
	local skip = head and math.max((head.Position - ray.Origin):Dot(ray.Direction), 0) or 0
	local start = ray.Origin + ray.Direction * skip
	return workspace:Raycast(start, ray.Direction * range, rayParams), Ray.new(start, ray.Direction)
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
-- Forearm angle off the view direction (smaller = arms point straight ahead) and how much the
-- cloned lower / upper arm is stretched along its length.
local ARM_PITCH, ARM_YAW = 12, 24
local ARM_STRETCH = 1.15
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
		local function stretch(cf: CFrame): CFrame
			return cf.Rotation + cf.Position * ARM_STRETCH
		end
		lowerOffset = stretch(lowerOffset)
		local upperOffset = lowerOffset * stretch(elbowOffset)
		local list = {}
		for _, entry in { { hand, CFrame.identity }, { lower, lowerOffset }, { upper, upperOffset } } do
			local clone = entry[1]:Clone()
			for _, child in clone:GetChildren() do
				if not child:IsA("SurfaceAppearance") then
					child:Destroy() -- joints, ragdoll constraints, attachments
				end
			end
			if entry[1] ~= hand then
				clone.Size *= Vector3.new(1, ARM_STRETCH, 1)
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
	Pan = {
		{ BLOCK, Vector3.new(0.14, 1.2, 0.14), CFrame.new(0, 0.45, 0), DARK },
		{ CYL, Vector3.new(0.12, 1.5, 1.5), CFrame.new(0, 1.75, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(46, 46, 52) },
	},
	Katana = {
		{ BLOCK, Vector3.new(0.16, 0.8, 0.16), CFrame.new(0, 0, 0), DARK },
		{ BLOCK, Vector3.new(0.5, 0.08, 0.5), CFrame.new(0, 0.42, 0), Color3.fromRGB(200, 160, 60) },
		{ BLOCK, Vector3.new(0.05, 3.2, 0.2), CFrame.new(0, 2.05, 0), STEEL },
	},
	Shotgun = {
		{ BLOCK, Vector3.new(0.26, 0.28, 2.4), CFrame.new(0, 0.3, -1.0), DARK },
		{ BLOCK, Vector3.new(0.3, 0.22, 0.7), CFrame.new(0, 0.08, -1.3), WOOD },
		{ BLOCK, Vector3.new(0.24, 0.42, 0.9), CFrame.new(0, 0.12, 0.65), WOOD },
	},
	Sniper = {
		{ BLOCK, Vector3.new(0.14, 0.16, 3.4), CFrame.new(0, 0.3, -1.6), DARK },
		{ BLOCK, Vector3.new(0.26, 0.34, 1.3), CFrame.new(0, 0.22, -0.2), GREY },
		{ CYL, Vector3.new(1.0, 0.24, 0.24), CFrame.new(0, 0.6, -0.4) * CFrame.Angles(0, math.pi / 2, 0), DARK },
		{ BLOCK, Vector3.new(0.22, 0.42, 0.9), CFrame.new(0, 0.12, 0.75), WOOD },
	},
	Rocket = {
		{ CYL, Vector3.new(3.4, 0.7, 0.7), CFrame.new(0, 0.5, -0.5) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(80, 96, 64) },
		{ BALL, Vector3.one * 0.62, CFrame.new(0, 0.5, -2.2), Color3.fromRGB(220, 60, 50) },
		{ BLOCK, Vector3.new(0.2, 0.45, 0.25), CFrame.new(0, 0, 0), DARK },
	},
	Tomato = {
		{ BALL, Vector3.one * 0.8, CFrame.new(0, 0.35, -0.1), Color3.fromRGB(215, 30, 25) },
		{ BLOCK, Vector3.new(0.3, 0.1, 0.3), CFrame.new(0, 0.76, -0.1), Color3.fromRGB(60, 140, 50) },
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
-- support: guns only, the point of the mesh (its own space, origin = grip) the left hand holds
--          while aiming: under the barrel / pump / front grip, or round the right hand on a pistol.
-- hand: where the right hand moves to for this weapon, relative to its fist position (camera space).
local HOLD = {
	Handgun = { grip = CFrame.new(0, -0.08, 0.08), hand = Vector3.new(-0.25, 0.2, 0.1), support = Vector3.new(-0.12, 0, 0.1) },
	Revolver = { grip = CFrame.new(0, -0.09, -0.08), hand = Vector3.new(-0.25, 0.2, 0.1), support = Vector3.new(-0.12, 0, 0.1) },
	Rifle = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.12, -0.9) },
	Knife = { grip = CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, 0, -0.32), hand = Vector3.new(0, 0.15, 0) }, -- blade up
	Bat = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Axe = { grip = CFrame.new(0, 0.15, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Grenade = { grip = CFrame.new(0, 0.2, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.7 }, -- full size overflows the hand
	Molotov = { grip = CFrame.new(0, 0.38, 0), hand = Vector3.new(0, 0.1, 0) },
	Pan = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Katana = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Shotgun = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.2, -1.3) },
	Sniper = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.5), support = Vector3.new(0, 0.15, -1.3) },
	Rocket = { grip = CFrame.new(0, -0.2, 0), hand = Vector3.new(-0.1, 0.35, 0.4), support = Vector3.new(0, 0, -0.85) },
	Tomato = { grip = CFrame.new(0, 0.2, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.85 },
}
-- Only the weapon in hand gets its mesh (a client may keep just 8 EditableMeshes alive); false =
-- still building or failed, the blocks show meanwhile.
local viewMeshes = {} -- [weaponId] = MeshPart | false
local function equipMesh(id: string)
	for other, mesh in viewMeshes do
		if other ~= id then
			if mesh then
				mesh:Destroy()
			end
			viewMeshes[other] = nil
		end
	end
	if viewMeshes[id] ~= nil or not HOLD[id] then
		return
	end
	viewMeshes[id] = false
	task.spawn(function()
		local mesh = WeaponMeshes.create(id)
		if not mesh then
			return
		end
		if viewMeshes[id] ~= false then -- switched away while it was building
			mesh:Destroy()
			return
		end
		mesh.Size *= HOLD[id].scale or 1
		mesh.Transparency = 1
		mesh.Parent = camera
		viewMeshes[id] = mesh
	end)
end

-- Where our own shots leave from (Fx draws the tracer from here): the front end of the weapon mesh
-- we are holding, first-person viewmodel or the one in the body's hand, wherever it is this frame.
Fx.muzzle = function(id: string): Vector3?
	local mesh = if isFirstPerson() then viewMeshes[id] else bodyWeapon.id == id and bodyWeapon.part
	local lo, hi = WeaponMeshes.bounds(id)
	if not mesh or not lo or not hi then
		return nil
	end
	return mesh.CFrame * Vector3.new((lo.X + hi.X) / 2, lo.Y + (hi.Y - lo.Y) * 0.7, lo.Z) -- barrel height, front end
end

-- Thrown grenades / molotovs are plain server parts; dress them in the same meshes locally.
workspace.ChildAdded:Connect(function(child)
	if not child:GetAttribute("Projectile") then
		return
	end
	local mesh = WeaponMeshes.create(child.Name)
	if not mesh then
		return
	end
	if not child.Parent then
		mesh:Destroy()
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

-- Throw arc (right mouse held with a grenade / molotov / tomato): the server's throw (throw() in
-- init.server: from the head + 2.5 studs along the aim, dir * speed + 12 up, workspace gravity)
-- stepped forward until it hits something, drawn as dots with a ring where it lands.
local ARC_DOTS, ARC_STEP = 48, 0.012 -- a dot every 2 steps: ~1.7 studs apart at grenade speed
local arcDots = {}
for i = 1, ARC_DOTS do
	local dot = Instance.new("Part")
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.one * 0.18
	dot.Material = Enum.Material.Neon
	dot.Color = Color3.fromRGB(255, 255, 255)
	dot.Anchored, dot.CanCollide, dot.CanQuery, dot.CanTouch, dot.CastShadow = true, false, false, false, false
	dot.Transparency = 1
	dot.Parent = camera
	arcDots[i] = dot
end
local arcRing = Instance.new("Part")
arcRing.Shape = Enum.PartType.Cylinder
arcRing.Size = Vector3.new(0.08, 2.4, 2.4)
arcRing.Material = Enum.Material.Neon
arcRing.Color = Color3.fromRGB(255, 90, 60)
arcRing.Anchored, arcRing.CanCollide, arcRing.CanQuery, arcRing.CanTouch, arcRing.CastShadow = true, false, false, false, false
arcRing.Transparency = 1
arcRing.Parent = camera

local function drawArc(weapon)
	local head = weapon and player.Character and player.Character:FindFirstChild("Head")
	local shown = 0
	if head then
		local result, ray = aim(300)
		local target = result and result.Position or ray.Origin + ray.Direction * 300
		local dir = (target - head.Position).Unit
		local pos = head.Position + dir * 2.5
		local vel = dir * weapon.speed + Vector3.yAxis * 12
		local g = Vector3.new(0, -workspace.Gravity, 0)
		local hit
		for i = 1, ARC_DOTS * 2 do
			local nextVel = vel + g * ARC_STEP
			local step = (vel + nextVel) / 2 * ARC_STEP
			hit = workspace:Raycast(pos, step, rayParams) -- aim() left the filter on the character + camera
			if hit then
				break
			end
			pos += step
			vel = nextVel
			if i % 2 == 0 and i >= 6 and shown < ARC_DOTS then -- none right in front of the eye
				shown += 1
				arcDots[shown].Position = pos
				arcDots[shown].Transparency = 0.15 + 0.6 * shown / ARC_DOTS
			end
		end
		arcRing.Transparency = hit and 0.25 or 1
		if hit then
			arcRing.CFrame = CFrame.lookAlong(hit.Position + hit.Normal * 0.05, hit.Normal) * CFrame.Angles(0, math.rad(90), 0)
		end
	else
		arcRing.Transparency = 1
	end
	for i = shown + 1, ARC_DOTS do
		arcDots[i].Transparency = 1
	end
end

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
	local dir = (target - head.Position).Unit
	if dir:Dot(ray.Direction) < 0.5 then -- something right beside the head: aim past it, straight down the crosshair
		dir = (ray.Origin + ray.Direction * 300 - head.Position).Unit
	end
	-- hip fire: the shot leaves somewhere in a wide cone round the crosshair; aiming (first or third
	-- person) closes it, and once fully up the shot goes exactly to the crosshair
	local aimed = math.max(ads, thirdAim)
	local spread = aimed > 0.95 and 0 or (weapon.hip or 0) * (1 - aimed)
	if spread > 0 then
		dir = (CFrame.lookAlong(Vector3.zero, dir)
			* CFrame.Angles(0, 0, math.random() * math.pi * 2)
			* CFrame.Angles(spread * math.sqrt(math.random()), 0, 0)).LookVector -- sqrt: even over the cone, not bunched in the middle
	end
	-- where the head is now (not where the server last saw it), and whether we are aimed (tight pellets)
	weaponRemote:FireServer(weapon.id, dir, head.Position, aimed > 0.95)
	if weapon.kind == "gun" or weapon.kind == "rocket" then
		recoil = 1
	else
		hands.right.t = 0 -- the punch motion doubles as the swing / throw
	end
end

-- Hotbar (bottom centre) + weapon wheel (hold Q); Q tap / F / L1 R1 / the mouse wheel step through.
require(script:WaitForChild("WeaponBar")).start(gui, Weapons, VIEWMODELS, {
	{ BALL, Vector3.one * 0.9, CFrame.identity, SKIN },
	{ BLOCK, Vector3.new(0.5, 0.5, 1.4), CFrame.new(0, 0, 0.9), SKIN },
}, {
	get = function()
		return weaponIndex
	end,
	set = function(i: number)
		weaponIndex = i
		lastWeaponUse = 0
	end,
	cooldown = function(): number
		local cd = Weapons[weaponIndex].cd
		if not cd then
			return 0
		end
		return math.clamp(1 - (os.clock() - lastWeaponUse) / cd, 0, 1)
	end,
	blocked = function(): boolean
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return Menu.active or not hum or hum.Health <= 0
	end,
	scrollable = function(): boolean
		return holding == nil
	end,
	freeze = function(on: boolean)
		camera.CameraType = on and Enum.CameraType.Scriptable or Enum.CameraType.Custom
	end,
})

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
	if result and (dummyOf(result.Instance) or (result.Instance.Parent and result.Instance.Parent.Name == "Grave")) then
		punchRemote:FireServer(result.Instance)
		Fx.hit(result.Position)
	end
end

-- Third-person attack: the foot lands in front of the body, wherever the camera points.
local function kick()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if os.clock() - lastKick < KICK_INTERVAL or not root or not kickTrack then
		return
	end
	lastKick = os.clock()
	kickTrack:Play(0.05)
	if sounds.Kick then
		sounds.Kick:Play()
	end
	moveRemote:FireServer("shot", "kick")
	local running = sprint > 0.5 or mv.sliding -- a kick out of a slide hits like the running one
	task.delay(0.18, function() -- leg fully out
		if running then -- running kick: hits like a ground slam, server does crater, damage and fx
			actionRemote:FireServer("kick")
			return
		end
		local foot = root.Position + root.CFrame.LookVector * 3.5 + Vector3.yAxis
		local best, bestDist = nil, math.huge
		for _, part in workspace:GetPartBoundsInRadius(foot, 3.5, kickParams) do
			local dist = (part.Position - foot).Magnitude
			if dist < bestDist then
				best, bestDist = part, dist
			end
		end
		if best then
			punchRemote:FireServer(best)
			Fx.hit(best.Position)
		end
	end)
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

-- Ground slam: R in the air arms it; the landing hits the ground with both hands, harder the
-- faster you were falling (see updateLanding).
local slamming = false
-- the wall being run along or clung to (see Wall running); nil when not on a wall
-- key: the stick direction that keeps you on it ("A", "D" or "W", see pressed)
local wall: { normal: Vector3, key: string, velocity: Vector3, along: Vector3, speed: number, clinging: boolean?, lookedAlong: boolean? }? = nil
local fallSpeed = 0
-- Horizontal speed carried over from a boost (wall jump, double jump, dash, slide, roll); see
-- the momentum block in updateWallRun, which holds it against Humanoid control and bleeds it off.
local carry = Vector3.zero
local rollUntil = 0 -- a roll is going until then (see Landing roll)

-- Movement input by direction ("W", "A", "S", "D") rather than by key: read off the Humanoid's
-- MoveDirection against the camera's heading, so the gamepad and touch sticks count as well.
local function pressed(humanoid: Humanoid, dir: string): boolean
	local right = camera.CFrame.RightVector
	local move = humanoid.MoveDirection
	local x, z = move:Dot(right), move:Dot(Vector3.yAxis:Cross(right))
	if dir == "D" then
		return x > 0.5
	elseif dir == "A" then
		return x < -0.5
	elseif dir == "W" then
		return z > 0.5
	end
	return z < -0.5
end

-- R (or the gamepad / touch button) in the air: slam mode, lasting until you hit the ground. You
-- dive: a shove downward now and extra gravity on the way (see updateWallRun), so the landing,
-- which scales with fall speed, comes sooner and harder. True when in the air (armed or already was).
function mv.armSlam(): boolean
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if wall or not (humanoid and root) or humanoid.FloorMaterial ~= Enum.Material.Air
		or humanoid.Health <= 0 or char:GetAttribute("Ragdolled") then
		return false
	end
	if not slamming then
		slamming = true
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X * 0.4, math.min(v.Y, -MOVE.SLAM_KICK), v.Z * 0.4)
		carry *= 0.4
		mv.diveUntil = 0
		if diveTrack then
			diveTrack:Play(0.2)
		end
	end
	return true
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or Menu.active then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		if holding then
			drop(camera.CFrame.LookVector * THROW_SPEED)
			return
		end
		punching = true
		local weapon = Weapons[weaponIndex]
		while punching and not holding and Weapons[weaponIndex] == weapon do
			if not weapon.kind then
				if mv.diveKick() then
					-- in the air, on a wall or sliding: the fists give way to a kick out of the move
				elseif isFirstPerson() then
					punch()
				else
					kick()
				end
			else
				useWeapon(weapon)
			end
			task.wait(weapon.cd or PUNCH_INTERVAL)
			if weapon.kind and not weapon.auto then
				break -- one use per click
			end
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		aiming = true
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
		if wall or mv.armSlam() then
			return -- no slam (or revive) while running along or hanging on a wall
		end
		local result = aim(60)
		actionRemote:FireServer("revive", result and dummyOf(result.Instance) and result.Instance)
	elseif input.KeyCode == Enum.KeyCode.B then -- scan: X-ray the whole dummy you are looking at
		local result = aim(60)
		local dummy = result and dummyOf(result.Instance)
		if dummy then
			Fx.scan(dummy, 4)
		end
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
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		punching = false
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		aiming = false
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
	local root = char:WaitForChild("HumanoidRootPart")
	for name, id in SFX do
		local sound = Instance.new("Sound")
		sound.Name = name .. "Sfx"
		sound.SoundId = id ~= "" and "rbxassetid://" .. id or ""
		sound.Looped = name == "Run"
		sound.Volume = name == "Run" and 0.4 or 0.7
		sound.Parent = root
		sounds[name] = sound
	end
	sprintTrack = humanoid:WaitForChild("Animator"):LoadAnimation(sprintAnim)
	sprintTrack.Priority = Enum.AnimationPriority.Movement -- over the default run (Core)
	sprintTrack.Looped = true
	rollTrack = humanoid.Animator:LoadAnimation(rollAnim)
	rollTrack.Priority = Enum.AnimationPriority.Action4
	diveTrack = humanoid.Animator:LoadAnimation(diveAnim)
	diveTrack.Priority = Enum.AnimationPriority.Action4
	diveTrack.Looped = true
	for side, anim in wallRunAnims do
		local track = humanoid.Animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action -- over the sprint cycle (Movement)
		track.Looped = true
		wallRunTracks[side] = track
	end
	clingTrack = humanoid.Animator:LoadAnimation(clingAnim)
	clingTrack.Priority = Enum.AnimationPriority.Action
	clingTrack.Looped = true
	for kind, anim in aimAnims do
		local track = humanoid.Animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action2 -- over the walk, run and wall cycles
		track.Looped = true
		aimTracks[kind] = track
	end
	flipTrack = humanoid.Animator:LoadAnimation(flipAnim)
	flipTrack.Priority = Enum.AnimationPriority.Action4
	kickTrack = humanoid.Animator:LoadAnimation(kickAnim)
	kickTrack.Priority = Enum.AnimationPriority.Action4
	dashTrack = humanoid.Animator:LoadAnimation(dashAnim)
	dashTrack.Priority = Enum.AnimationPriority.Action4
	for kind, anim in lowAnims do
		local track = humanoid.Animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		lowTracks[kind] = track
	end
	slamming = false
	carry = Vector3.zero
	mv.low, mv.sliding, mv.dashing, mv.diveUntil = false, false, false, 0
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

-- Wall running ------------------------------------------------------------------
-- Jump at a wall (in front or beside you) and hold A or D to run along it left or right;
-- look up to run up it. Letting go of the key drops you; WALL_TIME seconds per jump,
-- refilled on landing. Client-side: we own our character's physics.
-- a wall run is at least this fast (the wall's friction takes a couple off: measured about 2 over
-- the sprint); coming in faster, it keeps that speed for a while
local WALL_SPEED = 32
local WALL_TIME = 3.5
local WALL_REACH = 3.2
local WALL_FADE = 0.7
local AIR_STEER = 25 -- how fast WASD turns a boost in the air (per second); high = near-free air control
local FALL_GRAVITY = 0.5 -- gravity multiplier while falling (going down, not on a wall)
local nextScrape = 0
local SPARK = Color3.fromRGB(255, 205, 90)
local regrabAt = 0 -- no grabbing a wall before this (set by the wall jump)
local steerLockUntil = 0 -- no air steering before this: W held at a wall would turn a push-off back into it
local CLING_JUMP_LOCK = 0.4
local doubleJumpFrom, doubleJumpUntil = 0, 0 -- double jump window, opened by the wall jump
local groundedAt, groundedY, ledgeUsed = 0, 0, false -- last time/height on the ground; ledge boost spent this airtime
local WALL_KEYS = { D = 1, A = -1 }
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
-- `wall` (the current wall run / cling) is declared up by the input handler, which needs it too

-- Mantle: grabbing a wall close under its top edge pulls you up and over onto it. The same pull
-- is the vault: running (or jumping) forward into something low enough takes you onto it,
-- keeping your speed.
local MANTLE_REACH = 5 -- the top may be up to this far above the root
local MANTLE_TIME = 0.4
local mantle: { from: Vector3, over: Vector3, to: Vector3, face: Vector3, t: number, time: number, speed: number }? = nil

-- The standing spot on top of the wall in front (normal points out of the wall), or nil when the
-- wall goes on up past reach, the top isn't flat, or there's no headroom to stand there.
local function findLedge(root: BasePart, humanoid: Humanoid, normal: Vector3, wallPoint: Vector3): Vector3?
	local above = root.Position + Vector3.yAxis * (MANTLE_REACH + 1)
	if workspace:Raycast(above, -normal * (WALL_REACH + 1), wallParams) then
		return nil -- still wall up there: not near the edge
	end
	-- probe the top a bit past the wall face (measured from where the wall was hit), so you
	-- land with your feet on it rather than teetering on the edge
	local probe = Vector3.new(wallPoint.X, above.Y, wallPoint.Z) - normal * 1.2
	local top = workspace:Raycast(probe, -Vector3.yAxis * (MANTLE_REACH + 4), wallParams)
	if not (top and top.Normal.Y > 0.7 and top.Position.Y > root.Position.Y - 2) then
		return nil
	end
	local stand = humanoid.HipHeight + root.Size.Y / 2
	if workspace:Raycast(top.Position + Vector3.yAxis * 0.1, Vector3.yAxis * (stand * 2), wallParams) then
		return nil -- no room to stand up there
	end
	return top.Position + Vector3.yAxis * stand
end

-- Starts the pull up onto `stand` (from findLedge) over `time` seconds; `speed` is how fast you
-- run on, away from the edge, once you are up.
local function startMantle(root: BasePart, stand: Vector3, normal: Vector3, time: number, speed: number)
	local face = (-normal * XZ).Unit
	mantle = {
		from = root.Position,
		over = Vector3.new(root.Position.X, stand.Y + 0.5, root.Position.Z),
		to = stand + face * 0.8,
		face = face,
		t = 0,
		time = time,
		speed = speed,
	}
	flipUntil = os.clock() + time -- keep facing the wall while climbing
	wall = nil
	carry = Vector3.zero
end
-- Turning the camera into the wall mid-run grabs on: you hang there (the run timer pauses)
-- until you look back along the wall, which runs on that way, or jump off it.
local CLING_IN, CLING_OUT = 0.75, 0.55 -- camera-into-wall dot to grab on / let go (gap stops flicker)
local wallLeft = WALL_TIME

-- Whether a wall with this normal can be grabbed. A different wall from the last one refills the
-- run timer, so going wall to wall keeps you up; coming back to the same wall does not.
function mv.wallOk(normal: Vector3): boolean
	if not mv.lastWallNormal or mv.lastWallNormal:Dot(normal) < 0.5 then
		wallLeft = WALL_TIME
	end
	mv.lastWallNormal = normal
	return wallLeft > 0
end

-- Holds a horizontal velocity against Humanoid air/ground control (which wins over a plain
-- AssemblyLinearVelocity write within a physics step); Y stays free so gravity still works.
-- nil releases it.
local function hold(root: BasePart, velocity: Vector3?)
	local mover = root:FindFirstChild("HoldVelocity") :: LinearVelocity?
	if not mover then
		mover = Instance.new("LinearVelocity")
		mover.Name = "HoldVelocity"
		mover.Attachment0 = root:FindFirstChild("RootAttachment") :: Attachment
		mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		mover.MaxAxesForce = Vector3.new(1e5, 0, 1e5)
		mover.RelativeTo = Enum.ActuatorRelativeTo.World
		mover.Enabled = false
		mover.Parent = root
	end
	mover.Enabled = velocity ~= nil
	mover.VectorVelocity = velocity or Vector3.zero
end

local function findWall(root: BasePart): RaycastResult?
	local look, right = root.CFrame.LookVector, root.CFrame.RightVector
	for _, dir in { look, right, -right, (look + right).Unit, (look - right).Unit } do
		local hit = workspace:Raycast(root.Position, dir * WALL_REACH, wallParams)
		if hit and math.abs(hit.Normal.Y) < 0.3 then -- walls only, not floors or ramps
			return hit
		end
	end
	return nil
end

local function updateWallRun(dt: number, char: Model, humanoid: Humanoid, root: BasePart)
	wallParams.FilterDescendantsInstances = { char, workspace:FindFirstChild("Dummies") }
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local able = humanoid.Health > 0 and not char:GetAttribute("Ragdolled")
	if grounded then
		wallLeft = WALL_TIME
		doubleJumpUntil = 0
		groundedAt, groundedY, ledgeUsed = os.clock(), root.Position.Y, false
		mv.lastWallNormal, mv.airDashUsed, mv.airJumpUsed = nil, false, false
	end
	if mantle then
		-- up along the wall first, then forward onto the top; physics is held still meanwhile
		hold(root, nil)
		mantle.t += dt / mantle.time
		local t = math.min(mantle.t, 1)
		local p = t < 0.6 and mantle.from:Lerp(mantle.over, t / 0.6) or mantle.over:Lerp(mantle.to, (t - 0.6) / 0.4)
		root.CFrame = CFrame.lookAt(p, p + mantle.face)
		root.AssemblyLinearVelocity = Vector3.zero
		if t >= 1 or not able then
			if able then
				carry = mantle.face * mantle.speed -- a vault runs on at the speed it came in with
			end
			mantle = nil
		end
		return
	end
	if wall then
		hold(root, nil) -- the run sets velocity itself
		local flat = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
		flat = flat.Magnitude > 0.01 and flat.Unit or root.CFrame.LookVector
		local into = flat:Dot(-wall.normal)
		-- runs often start looking straight at the wall: only grab on once you've looked along it
		wall.lookedAlong = wall.lookedAlong or into < CLING_OUT
		-- W while looking at the wall grabs on too (and holds you there without A/D)
		local forward = pressed(humanoid, "W")
		local clinging = (wall.lookedAlong or forward) and into > (wall.clinging and CLING_OUT or CLING_IN)
		if wall.clinging and not clinging then
			-- let go of the cling: run on whichever way along the wall you now look
			wall.along = wall.along:Dot(flat) >= 0 and wall.along or -wall.along
		end
		wall.clinging = clinging
		if not clinging then
			wallLeft -= dt
		end
		local hit = workspace:Raycast(root.Position, -wall.normal * (WALL_REACH + 1), wallParams)
		local held = pressed(humanoid, wall.key) or (clinging and forward)
		if not (held and wallLeft > 0 and not grounded and hit and able) then
			-- keep the run's momentum and peel off gently, so the fall carries on from the run
			-- from the run's own last velocity: the root's can already be bent by contacts
			local v = wall.velocity + wall.normal * 8
			root.AssemblyLinearVelocity = v
			carry = v * XZ
			wall = nil
			return
		end
		local normal = hit.Normal
		wall.normal = normal
		-- keep the direction picked on grab: re-deciding from the camera every frame flips it
		-- (you run backwards) as soon as you turn to look along the wall
		local along = normal:Cross(Vector3.yAxis).Unit
		if along:Dot(wall.along) < 0 then
			along = -along
		end
		wall.along = along
		if clinging then
			local stand = findLedge(root, humanoid, normal, hit.Position)
			if stand then
				-- grabbed near the top edge: pull up onto it instead of hanging
				startMantle(root, stand, normal, MANTLE_TIME, 0)
				return
			end
			-- hang still: cancel this frame's gravity, press lightly into the wall, face it
			wall.velocity = Vector3.zero
			wall.speed = WALL_SPEED
			root.AssemblyLinearVelocity = Vector3.yAxis * workspace.Gravity * dt - normal * 2
			root.CFrame = CFrame.lookAt(root.Position, root.Position - normal)
			return
		end
		-- looking up bends the run up the wall
		local dir = (along + Vector3.yAxis * math.max(camera.CFrame.LookVector.Y, 0) * 2.5).Unit
		-- grip fades over the last WALL_FADE seconds: the run slows and you start sliding down
		-- instead of dropping off all at once
		local grip = math.clamp(wallLeft / WALL_FADE, 0, 1)
		local slide = Vector3.yAxis * (workspace.Gravity * dt - 20 * (1 - grip)) -- gravity term cancels this frame's fall
		-- speed brought onto the wall settles back to the plain run's
		wall.speed = WALL_SPEED + (wall.speed - WALL_SPEED) * math.exp(-MOVE.WALL_KEEP * dt)
		wall.velocity = dir * wall.speed * (0.3 + 0.7 * grip)
		root.AssemblyLinearVelocity = wall.velocity - normal * 1.5 + slide -- pressed in lightly: harder and the wall's friction eats the run's speed
		-- face the run direction, side to the wall (AutoRotate is off while running, see below)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + along)
		if os.clock() > nextScrape then -- sparks scraping off where the feet hit the wall
			nextScrape = os.clock() + 0.07
			Fx.sparks(root.Position - normal * 1.2 - Vector3.yAxis * 2.5, 2, 2.5, SPARK, -dir)
		end
		return
	end
	-- Momentum. Humanoid control would kill a boost's speed in a frame or two, so `carry` is held
	-- against it and bleeds off with drag instead: slowly in the air and in a slide or roll, faster
	-- running on the ground (jump again in time and you keep it), at once with the stick let go.
	local now = os.clock()
	local input = humanoid.MoveDirection
	local steering = input.Magnitude > 0.1 and now > steerLockUntil
	local speed = carry.Magnitude
	if mv.dashing and now >= mv.dashUntil then
		mv.dashing = false
		speed = math.min(speed, MOVE.DASH_EXIT) -- a dash is a burst: most of it is gone when it ends
	end
	if speed > 0.01 and able then
		local gliding = mv.sliding or now < rollUntil or now < mv.dashUntil
		local dir = carry.Unit
		-- Run into something solid and the carry is over: left on, it would keep shoving you into
		-- it, hard enough to pin you to a wall in mid-air. (A moment's grace: a fresh carry takes
		-- a frame or two to show up as real speed.)
		if (root.AssemblyLinearVelocity * XZ):Dot(dir) < speed * 0.4 then
			mv.blocked += dt
			if mv.blocked > 0.15 then
				speed = 0
			end
		else
			mv.blocked = 0
		end
		if gliding then
			speed *= math.exp(-MOVE.GLIDE_DRAG * dt)
		else
			local drag = not grounded and MOVE.AIR_DRAG or steering and MOVE.GROUND_DRAG or MOVE.STOP_DRAG
			speed *= math.exp(-drag * dt)
			if steering then
				-- the stick turns the carried speed toward itself (near-free in the air)
				local turned = dir:Lerp(input.Unit, math.min(dt * (grounded and MOVE.GROUND_STEER or AIR_STEER), 1))
				dir = turned.Magnitude > 0.01 and turned.Unit or input.Unit
			end
		end
		-- from here down Humanoid control is at least as fast: hand back to it. In the air with the
		-- stick held the carry stays (no slower than that), so a boost's direction is never dropped.
		local floor = steering and humanoid.WalkSpeed or 4
		if not grounded and steering and speed > 0 then
			speed = math.max(speed, floor)
		end
		local keep = speed > 0 and (gliding or speed > floor or (not grounded and steering))
		carry = keep and dir * speed or Vector3.zero
	else
		carry = Vector3.zero
	end
	hold(root, carry.Magnitude > 0 and carry or nil)
	if not grounded and able then
		local v = root.AssemblyLinearVelocity
		if slamming then
			-- slam dive: extra gravity, so it comes down faster (and so hits harder)
			root.AssemblyLinearVelocity = v - Vector3.yAxis * workspace.Gravity * MOVE.SLAM_GRAVITY * dt
		elseif mv.dashing then
			root.AssemblyLinearVelocity = v * XZ -- an air dash goes straight
		elseif v.Y < 0 and now > mv.diveUntil then
			-- scaled gravity on the way down only, so jumps keep their height but float down slower
			root.AssemblyLinearVelocity = v - Vector3.yAxis * workspace.Gravity * (FALL_GRAVITY - 1) * dt
		end
	end
	if not able or mv.low or now < regrabAt then
		return
	end
	local forward = pressed(humanoid, "W")
	-- Vault: sprinting on the ground, or moving forward in the air, into something whose top is in
	-- reach (a crate, a low wall, a ledge at foot level) takes you up onto it.
	if forward and (not grounded or sprint > 0.5) then
		local dir = input.Unit
		local hit = workspace:Raycast(root.Position - Vector3.yAxis * 1.5, dir * 2.8, wallParams)
		-- anchored only: loose rubble is not something to climb
		if hit and math.abs(hit.Normal.Y) < 0.3 and dir:Dot(-hit.Normal) > 0.5 and hit.Instance.Anchored then
			local stand = findLedge(root, humanoid, hit.Normal, hit.Position)
			local rise = stand and stand.Y - root.Position.Y
			if stand and rise > (grounded and MOVE.VAULT_MIN or -0.5) then
				local speedIn = (root.AssemblyLinearVelocity * XZ).Magnitude
				startMantle(root, stand, hit.Normal, grounded and MOVE.VAULT_TIME or MANTLE_TIME, speedIn)
				return
			end
		end
	end
	if grounded then
		return
	end
	for key, side in WALL_KEYS do
		local hit = pressed(humanoid, key) and findWall(root)
		if hit and mv.wallOk(hit.Normal) then
			-- facing the wall, D runs right and A left; with the wall beside you (the key's
			-- side tells nothing about along-wall direction) you run the way you are looking
			local along = hit.Normal:Cross(Vector3.yAxis).Unit
			local flat = camera.CFrame.LookVector * XZ
			local sideways = along:Dot(camera.CFrame.RightVector) * side
			local pick = math.abs(sideways) > 0.5 and sideways or along:Dot(flat)
			-- the run starts at the speed you came in with, when that is faster
			local speedIn = (root.AssemblyLinearVelocity * XZ).Magnitude
			wall = {
				normal = hit.Normal, key = key, velocity = Vector3.zero, along = pick < 0 and -along or along,
				speed = math.clamp(speedIn, WALL_SPEED, MOVE.WALL_MAX),
			}
			carry = Vector3.zero
			return
		end
	end
	-- W in the air while looking at a big wall grabs straight on (no run first). "Big": the
	-- wall is there both at the hips and a body height above, so crates and low ledges don't count.
	if forward then
		local flat = camera.CFrame.LookVector * XZ
		if flat.Magnitude < 0.01 then
			return
		end
		flat = flat.Unit
		local hit = workspace:Raycast(root.Position, flat * WALL_REACH, wallParams)
		local high = hit and workspace:Raycast(root.Position + Vector3.yAxis * 5, flat * (WALL_REACH + 1), wallParams)
		if hit and high and math.abs(hit.Normal.Y) < 0.3 and mv.wallOk(hit.Normal) then
			wall = {
				normal = hit.Normal, key = "W", velocity = Vector3.zero, speed = WALL_SPEED,
				along = hit.Normal:Cross(Vector3.yAxis).Unit, clinging = true, lookedAlong = true,
			}
			carry = Vector3.zero
		end
	end
end

-- Landing roll -------------------------------------------------------------------
-- Falling more than ROLL_HEIGHT (from the highest point of the jump or wall run) ends in a
-- forward roll that carries you on instead of a dead stop.
local ROLL_HEIGHT = 16
local ROLL_TIME = 0.65 -- the body animation's own length
local FP_ROLL_TIME = 0.42 -- first person: only the camera rolls, so it can be quicker
local ROLL_SPEED = 22
local airPeak: number? = nil
local rollTime = ROLL_TIME
local rollFirstPerson = false

-- A roll along `dir`: off a big fall, or the dash on the ground. It keeps whatever speed you
-- already carry when that is more than the roll's own.
local function startRoll(dir: Vector3, speed: number)
	if not rollTrack then
		return
	end
	rollFirstPerson = isFirstPerson()
	rollTime = rollFirstPerson and FP_ROLL_TIME or ROLL_TIME
	rollTrack:Play(0.05, 1, ROLL_TIME / rollTime) -- body keeps pace with the camera
	rollUntil = os.clock() + rollTime
	carry = dir * math.max(carry.Magnitude, speed)
	moveRemote:FireServer("shot", "roll")
end

local function updateLanding(humanoid: Humanoid, root: BasePart, able: boolean)
	local y = root.Position.Y
	if humanoid.FloorMaterial == Enum.Material.Air then
		airPeak = math.max(airPeak or y, y)
		fallSpeed = math.max(-root.AssemblyLinearVelocity.Y, 0) -- last airborne frame = impact speed
		if slamming and math.random() < 0.5 then -- red trail streaming off the dive
			Fx.sparks(root.Position - Vector3.yAxis * 2, 2, 1.5, Color3.fromRGB(255, 40, 40), Vector3.yAxis, 0.3)
		end
		return
	end
	if slamming then
		slamming = false
		if diveTrack then
			diveTrack:Stop(0.1)
		end
		airPeak = nil -- the slam replaces the landing roll
		if able then
			hands.left.t, hands.right.t = 0, 0 -- both fists into the ground
			actionRemote:FireServer("slam", fallSpeed * MOVE.SLAM_POWER)
			sounds.Slam:Play()
			moveRemote:FireServer("shot", "slam")
		end
		return
	end
	if airPeak and airPeak - y > ROLL_HEIGHT and able and not mv.crouchHeld then -- Ctrl held: slide out of it instead
		local flat = root.CFrame.LookVector * XZ
		startRoll(flat.Magnitude > 0.01 and flat.Unit or Vector3.zAxis, ROLL_SPEED)
	end
	airPeak = nil
end

-- Movement screen effects ------------------------------------------------------------
-- White streaks on the screen edges (strongest on the wall's side) while wall running, and a
-- flash of them plus an FOV kick on the jumps. UI gradients, no textures, like the rest of Fx.
local AIR = Color3.fromRGB(120, 220, 255)
local WHITE_FLASH = Color3.new(1, 1, 1)
local edgeGui = Instance.new("ScreenGui")
edgeGui.Name = "MoveFx"
edgeGui.IgnoreGuiInset = true
edgeGui.ResetOnSpawn = false
local edges = {}
for _, side in { -1, 1 } do
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(0.3, 1)
	frame.Position = UDim2.fromScale(side < 0 and 0 or 0.7, 0)
	local gradient = Instance.new("UIGradient") -- solid at the screen edge, clear toward the middle
	gradient.Transparency = NumberSequence.new(side < 0 and 0.2 or 1, side < 0 and 1 or 0.2)
	gradient.Parent = frame
	frame.Parent = edgeGui
	edges[side] = frame
end
edgeGui.Parent = player:WaitForChild("PlayerGui")
local fovKick, flash, wallGlow, moveFov = 0, 0, 0, 0

local function jolt(fov: number, flashAmount: number)
	fovKick = math.max(fovKick, fov)
	flash = math.max(flash, flashAmount)
end

-- Wall jump and double jump --------------------------------------------------------
-- Space on a wall kicks off it with a boost forward (the run direction) and up, then gives
-- DOUBLE_JUMP_WINDOW seconds for one more jump in the air: a strong boost toward where you
-- look and up. Landing closes the window.
-- Any airtime has one double jump in it: after a plain jump (or walking off an edge) it is the
-- weaker one (MOVE.AIR_JUMP), inside the wall jump's window the strong one.
local WALL_JUMP_ALONG = 30
local WALL_JUMP_AWAY = 18
local WALL_JUMP_UP = 55
local DOUBLE_JUMP_FORWARD = 48
local DOUBLE_JUMP_UP = 65
local DOUBLE_JUMP_WINDOW = 3
local LEDGE_DROP = 10 -- a jump off an edge over a drop deeper than this gets the same launch
local LEDGE_COOLDOWN = 1.5 -- seconds between ledge launches
local ledgeReadyAt = 0
local LEDGE_GRACE = 2 -- seconds after leaving the ground (walking or jumping off) the ledge launch can still be triggered

local function zap() -- the special jumps' sound, not the plain jump
	if sounds.Jump then
		sounds.Jump:Play()
	end
	moveRemote:FireServer("shot", "jump")
end

-- The double jump's launch: a boost toward where you look, and up. `power` scales it (1 = the
-- strong one); speed you already have beyond the boost's own is kept.
local function launch(root: BasePart, power: number)
	local flat = camera.CFrame.LookVector * XZ
	flat = flat.Magnitude > 0.01 and flat.Unit or root.CFrame.LookVector
	local forward = math.max(DOUBLE_JUMP_FORWARD * power, (root.AssemblyLinearVelocity * XZ).Magnitude)
	carry = flat * forward
	root.AssemblyLinearVelocity = carry + Vector3.yAxis * DOUBLE_JUMP_UP * power
	local feet = root.Position - Vector3.yAxis * 3
	Fx.ring(CFrame.new(feet), 1, 10 * power, 0.4, AIR, { thick = 0.7, sides = 8, spin = 1 })
	Fx.sparks(feet, math.round(12 * power), 8 * power, AIR, -flat)
	for _ = 1, math.round(10 * power) do
		Fx.speedLine()
	end
	Fx.dust(feet, 5, 3, 0.8)
	Fx.shake(root.Position, 0.5 * power, 0.25)
	jolt(30 * power, 0.8 * power)
	zap()
end

-- Standing at an edge with a deep drop just ahead (where you look): no wall in the way, and
-- nothing within LEDGE_DROP studs below your feet a couple of steps out.
local function ledgeAhead(root: BasePart, humanoid: Humanoid): boolean
	-- where you're running, else where you look
	local flat = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.MoveDirection or camera.CFrame.LookVector
	flat *= Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.01 then
		return false
	end
	flat = flat.Unit
	if workspace:Raycast(root.Position, flat * 3, wallParams) then
		return false
	end
	-- measured from the height you left the ground at, so a plain jump over flat ground doesn't count
	local toFeet = humanoid.HipHeight + root.Size.Y / 2 + math.max(root.Position.Y - groundedY, 0)
	for _, dist in { 0, 1.5, 3, 5, 7 } do -- 0: already out over the drop (pressed mid-air)
		if not workspace:Raycast(root.Position + flat * dist, -Vector3.yAxis * (toFeet + LEDGE_DROP), wallParams) then
			return true
		end
	end
	return false
end

-- A fresh press of jump (Space, gamepad A, the touch jump button), on top of the Humanoid's own jump.
local function jumpPressed()
	if Menu.active or UserInputService:GetFocusedTextBox() then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 or char:GetAttribute("Ragdolled") or mantle or slamming then
		return
	end
	local now = os.clock()
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	if wall then
		-- off a cling there's no run to carry on: push back off the wall instead, and keep W (still
		-- held, still facing the wall) from steering you straight back into it for a moment
		-- off a run: along it, at least as fast as the run was going
		local v = wall.clinging and wall.normal * WALL_JUMP_AWAY * 1.6 + Vector3.yAxis * WALL_JUMP_UP
			or wall.along * math.max(WALL_JUMP_ALONG, wall.speed) + wall.normal * WALL_JUMP_AWAY + Vector3.yAxis * WALL_JUMP_UP
		-- off a run a shorter lock: the stick is held along the wall, and steering to it at once
		-- would drop the push away and leave you scraping down the wall
		steerLockUntil = now + (wall.clinging and CLING_JUMP_LOCK or 0.2)
		root.AssemblyLinearVelocity = v
		carry = v * XZ -- keep the kick against air control
		mv.airJumpUsed = false
		local push = root.Position - wall.normal * 1.2 -- the spot on the wall you kick from
		Fx.ring(CFrame.fromMatrix(push, wall.along, wall.normal), 1, 8, 0.35, AIR, { thick = 0.5 })
		Fx.sparks(push, 10, 7, AIR, wall.normal)
		wall = nil
		regrabAt = now + 0.4 -- A/D is probably still held: don't snap straight back on
		doubleJumpFrom, doubleJumpUntil = now + 0.15, now + DOUBLE_JUMP_WINDOW
		Fx.dust(root.Position - Vector3.new(0, 3, 0), 4, 2, 0.6)
		Fx.shake(root.Position, 0.35, 0.2)
		jolt(20, 0.55)
		zap()
	elseif not ledgeUsed and now > ledgeReadyAt and now - groundedAt < LEDGE_GRACE
		and (not airborne or not mv.airJumpUsed) and ledgeAhead(root, humanoid) then
		-- leaping off an edge over a drop: from the ground, or a press shortly after jumping off it
		-- (which is then this airtime's double jump)
		ledgeUsed = airborne
		mv.airJumpUsed = airborne
		ledgeReadyAt = now + LEDGE_COOLDOWN
		launch(root, 1)
	elseif airborne and not mv.airJumpUsed and now > doubleJumpFrom then
		mv.airJumpUsed = true
		launch(root, now < doubleJumpUntil and 1 or MOVE.AIR_JUMP)
		doubleJumpUntil = 0
	end
end

-- InputBegan rather than JumpRequest: JumpRequest repeats while Space is held, and the
-- double jump should need a fresh press. Not gated on `processed`: the default jump binding
-- may claim Space.
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
		jumpPressed()
	end
end)
-- The touch jump button raises no key, only JumpRequest, which repeats while it is held: take
-- the first of each burst as the press.
local lastJumpRequest = 0
UserInputService.JumpRequest:Connect(function()
	local now = os.clock()
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch and now - lastJumpRequest > 0.2 then
		jumpPressed()
	end
	lastJumpRequest = now
end)

-- Wall backflip: hanging on a wall with W held, S kicks off it with one foot and backflips
-- hard away from it (WallFlip animation), then the double jump window opens like a wall jump.
-- The dash button does the same while hanging, which is how a gamepad or touch screen does it.
local WALL_FLIP_BACK = 55
local WALL_FLIP_UP = 60
local WALL_FLIP_TIME = 0.7 -- the animation's length
function mv.wallFlip()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (root and wall and wall.clinging) then
		return
	end
	local now = os.clock()
	local normal = wall.normal
	wall = nil
	root.CFrame = CFrame.lookAt(root.Position, root.Position - normal) -- facing the wall it kicks off
	local v = normal * WALL_FLIP_BACK + Vector3.yAxis * WALL_FLIP_UP
	root.AssemblyLinearVelocity = v
	carry = v * XZ
	mv.airJumpUsed = false
	steerLockUntil = now + 0.5 -- W is still held toward the wall
	regrabAt = now + 0.6
	doubleJumpFrom, doubleJumpUntil = now + 0.3, now + DOUBLE_JUMP_WINDOW
	flipUntil = now + WALL_FLIP_TIME
	if flipTrack then
		flipTrack:Play(0.05)
	end
	local foot = root.Position - normal * 1.2 - Vector3.yAxis * 1.5 -- where the foot hits the wall
	Fx.ring(CFrame.fromMatrix(foot, normal:Cross(Vector3.yAxis), normal), 1, 9, 0.35, AIR, { thick = 0.6 }) -- flat on the wall, like the wall jump's
	Fx.sparks(foot, 12, 7, AIR, normal)
	Fx.dust(foot, 4, 2, 0.7)
	Fx.shake(root.Position, 0.4, 0.2)
	jolt(24, 0.6)
	zap()
	moveRemote:FireServer("shot", "flip")
end
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.S and not Menu.active and UserInputService:IsKeyDown(Enum.KeyCode.W) then
		mv.wallFlip()
	end
end)

-- Dash ---------------------------------------------------------------------------
-- X: a burst the way you are moving (or looking, standing still). On the ground it is a dodge
-- roll; in the air a short straight dash, once per airtime; out of a slide or crouch a shove
-- along the ground. Off a wall run it leaves the wall.
function mv.dash()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 or char:GetAttribute("Ragdolled") or mantle then
		return
	end
	if wall and wall.clinging then
		mv.wallFlip()
		return
	end
	local now = os.clock()
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local dir = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.MoveDirection or camera.CFrame.LookVector * XZ
	if now < mv.dashReadyAt or (not grounded and mv.airDashUsed) or dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	mv.dashReadyAt = now + MOVE.DASH_COOLDOWN
	if wall then
		wall = nil
		regrabAt = now + 0.4
	end
	if slamming then -- dashing out of a slam dive calls it off
		slamming = false
		if diveTrack then
			diveTrack:Stop(0.1)
		end
	end
	-- one burst for the ground and the air alike: the body throws itself forward flat (DashBurst)
	-- and the speed is held, undragged and unsteered, for the burst, then mostly let go
	mv.airDashUsed = not grounded
	mv.dashing = true
	mv.dashUntil = now + (grounded and MOVE.GROUND_DASH_TIME or MOVE.DASH_TIME)
	carry = dir * math.max(grounded and MOVE.GROUND_DASH_SPEED or MOVE.DASH_SPEED, carry.Magnitude)
	root.AssemblyLinearVelocity = carry
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir) -- face the way it goes, at once
	flipUntil = math.max(flipUntil, now + 0.25) -- AutoRotate stays off for the burst
	if dashTrack then
		dashTrack:Play(0.03)
	end
	moveRemote:FireServer("shot", "dash")

	local feet = root.Position - Vector3.yAxis * (humanoid.HipHeight + root.Size.Y / 2 - 0.2)
	-- a white flash ring torn open where it left, a wind ring behind, sparks and dust thrown back
	Fx.ring(CFrame.lookAt(root.Position, root.Position + dir) * CFrame.Angles(math.pi / 2, 0, 0), 1.5, 9, 0.25, WHITE_FLASH, { thick = 0.35 })
	Fx.ring(CFrame.lookAt(root.Position - dir * 2, root.Position + dir) * CFrame.Angles(math.pi / 2, 0, 0), 1, 6, 0.35, AIR, { thick = 0.5 })
	Fx.sparks(root.Position, 12, 7, AIR, -dir)
	if grounded then
		Fx.dust(feet, 6, 3, 1.2)
	end
	if not isFirstPerson() and player.Character then
		Fx.ghosts(player.Character, AIR, 5, 0.035, 0.32)
	end
	for _ = 1, 12 do
		Fx.speedLine()
	end
	Fx.shake(root.Position, 0.25, 0.12)
	jolt(22, 0.55)
	zap()
end

-- Slide and crouch -----------------------------------------------------------------
-- Ctrl lowers you (the Humanoid's HipHeight comes down, so you fit under things). Going fast
-- enough when it does, it is a slide: your speed, plus a boost, carried along the ground with
-- little drag until it runs out; jumping out of it keeps the speed. Otherwise it is a crouch.
-- Holding Ctrl through a landing slides out of the fall. You stay down under a low ceiling.
function mv.updateLow(humanoid: Humanoid, root: BasePart, grounded: boolean, able: boolean)
	local now = os.clock()
	local want = mv.crouchHeld and able and not wall and not mantle and not slamming
	local v = root.AssemblyLinearVelocity * XZ
	if want and grounded and not mv.low and v.Magnitude > MOVE.SLIDE_FROM then
		mv.sliding = true
		local boost = now > mv.slideBoostAt
		carry = v.Unit * (boost and math.max(v.Magnitude * MOVE.SLIDE_BOOST, MOVE.SLIDE_MIN) or v.Magnitude)
		if boost then
			mv.slideBoostAt = now + MOVE.SLIDE_COOLDOWN
			Fx.dust(root.Position - Vector3.yAxis * 2.5, 5, 3, 0.8)
			jolt(10, 0.3)
		end
	end
	-- Lowering the hips drops the body, which reads as "in the air" for a moment (so does a bump
	-- in the floor): only a real stretch of airtime, like a jump, stands you up.
	if grounded then
		mv.groundedAt = now
	end
	local onGround = grounded or (mv.low and now - mv.groundedAt < 0.3)
	if mv.sliding and (not want or not onGround or carry.Magnitude < MOVE.SLIDE_END) then
		mv.sliding = false
	end
	local low = want and onGround
	if mv.low and not low and grounded and workspace:Raycast(root.Position, Vector3.yAxis * (MOVE.LOW_DROP + 3), wallParams) then
		low = true -- no room to stand up
	end
	if low ~= mv.low then
		if low then
			mv.baseHip = humanoid.HipHeight
		end
		mv.low = low
		humanoid.HipHeight = mv.baseHip - (low and MOVE.LOW_DROP or 0)
	end
end

-- Dive kick ------------------------------------------------------------------------
-- Clicking with the fists in the air or on a wall throws you foot first the way you look; the
-- first dummy in the way takes a hit like the running kick's, and you bounce back off it with your
-- double jump returned. Out of a slide the click is the running kick. True when it took the click.
function mv.diveKick(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and kickTrack) or humanoid.Health <= 0 or char:GetAttribute("Ragdolled") or mantle or slamming then
		return false
	end
	if mv.sliding then
		kick()
		return true
	end
	local now = os.clock()
	if not (wall or humanoid.FloorMaterial == Enum.Material.Air) or now < mv.diveReadyAt then
		return false
	end
	mv.diveReadyAt = now + MOVE.DIVE_COOLDOWN
	if wall then
		wall = nil
		regrabAt = now + 0.5
	end
	local dir = camera.CFrame.LookVector
	local flat = dir * XZ
	root.AssemblyLinearVelocity = dir * MOVE.DIVE_SPEED
	carry = flat * MOVE.DIVE_SPEED
	mv.dashUntil = now + 0.3 -- nothing slows or turns it on the way in
	mv.diveUntil = now + MOVE.DIVE_TIME
	mv.diveDir = dir
	if flat.Magnitude > 0.01 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		flipUntil = now + MOVE.DIVE_TIME -- keep facing the kick
	end
	kickTrack:Play(0.05)
	if sounds.Kick then
		sounds.Kick:Play()
	end
	moveRemote:FireServer("shot", "kick")
	for _ = 1, 8 do
		Fx.speedLine()
	end
	jolt(16, 0.4)
	return true
end

-- The flying part of the dive kick: ends on the first dummy within reach of the foot, or on landing.
function mv.updateDive(humanoid: Humanoid, root: BasePart)
	if os.clock() > mv.diveUntil then
		return
	end
	local foot = root.Position + mv.diveDir * 3
	if #workspace:GetPartBoundsInRadius(foot, 4, kickParams) > 0 then
		mv.diveUntil, mv.dashUntil = 0, 0
		actionRemote:FireServer("dive")
		Fx.hit(foot)
		local back = -(mv.diveDir * XZ) * 18
		root.AssemblyLinearVelocity = back + Vector3.yAxis * 40
		carry = back
		mv.airJumpUsed = false
	elseif humanoid.FloorMaterial ~= Enum.Material.Air then
		mv.diveUntil = 0
	end
end

-- Bound through ContextActionService rather than read as keys, so each move gets a gamepad
-- button and, on a touch screen, an on-screen button as well.
local function bind(name: string, title: string, fn: (began: boolean, input: InputObject) -> (), ...: Enum.KeyCode)
	ContextActionService:BindAction(name, function(_, state, input)
		local began = state == Enum.UserInputState.Begin
		if state ~= Enum.UserInputState.Change and not (began and Menu.active) then
			fn(began, input)
		end
		return Enum.ContextActionResult.Pass
	end, true, ...)
	ContextActionService:SetTitle(name, title)
end
-- the keyboard holds these two; a gamepad or touch button toggles them
bind("Sprint", "Run", function(began, input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		mv.sprintHeld = began
	elseif began then
		mv.sprintToggle = not mv.sprintToggle
	end
end, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
bind("Crouch", "Slide", function(began, input)
	if input.KeyCode == Enum.KeyCode.LeftControl then
		mv.crouchHeld = began
	elseif began then
		mv.crouchHeld = not mv.crouchHeld
	end
end, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
bind("Dash", "Dash", function(began)
	if began then
		mv.dash()
	end
end, Enum.KeyCode.X, Enum.KeyCode.ButtonX)
bind("Slam", "Slam", function(began) -- the keyboard's R is in the main input handler (it is also Revive)
	if began then
		mv.armSlam()
	end
end, Enum.KeyCode.ButtonY)

-- Camera: leans away from the wall while wall running, and somersaults with the roll in first
-- person (you can't see your own body there). Both ease in and out.
local ROLL_PIVOT = 1.6 -- studs from the eyes down to the hips the view turns around
local ROLL_SINK = 0.6 -- how far the view drops at the middle of the roll
local ROLL_PITCH = math.rad(30) -- how far the view nods forward mid-roll (was a full 360 flip)
local wallTilt = 0
-- The default camera builds each frame from the current camera.CFrame, so an offset left in
-- place would be fed back into it (the view stays turned after the roll). Put the camera's own
-- frame back before it runs; the offset is re-applied after it.
local cleanCamera: CFrame? = nil
RunService:BindToRenderStep("MoveCameraRestore", Enum.RenderPriority.Camera.Value - 1, function()
	if cleanCamera and camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CFrame = cleanCamera
	end
	cleanCamera = nil
end)
RunService:BindToRenderStep("MoveCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if thirdWeapon then -- after the camera scripts, which would set their own mouse behaviour
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	elseif mouseLocked and not isFirstPerson() then -- weapon put away: free the mouse again
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	mouseLocked = thirdWeapon
	local target = 0
	if wall then
		target = math.rad(10) * (wall.normal:Dot(camera.CFrame.RightVector) > 0 and 1 or -1)
	end
	wallTilt += (target - wallTilt) * math.min(dt * 6, 1)
	local cf = camera.CFrame
	local left = rollUntil - os.clock()
	if left > 0 and rollFirstPerson then
		-- first-person roll: a gentle forward nod around the hips (ROLL_PIVOT below the eyes)
		-- and a small sink, in and back out, instead of a full somersault
		local t = 1 - left / rollTime
		local s = math.sin(t * math.pi)
		cf = (cf - Vector3.yAxis * s * ROLL_SINK) * CFrame.new(0, -ROLL_PIVOT, 0) * CFrame.Angles(-ROLL_PITCH * s, 0, 0) * CFrame.new(0, ROLL_PIVOT, 0)
	end
	if wallTilt ~= 0 then
		cf *= CFrame.Angles(0, 0, wallTilt)
	end
	if cf ~= camera.CFrame then
		cleanCamera = camera.CFrame
		camera.CFrame = cf
	end

	-- screen edges and FOV (applied by Fx through fovBoost in the sprint block)
	wallGlow += ((wall and 1 or 0) - wallGlow) * math.min(dt * 8, 1)
	flash *= math.exp(-dt * 6)
	fovKick *= math.exp(-dt * 4)
	moveFov = wallGlow * 12 + fovKick
	-- the wall's side of the screen: its normal points away from it
	local wallSide = wall and (wall.normal:Dot(camera.CFrame.RightVector) > 0 and -1 or 1) or 0
	for side, frame in edges do
		local level = flash * 0.6 + wallGlow * (side == wallSide and 0.5 or 0.18)
		frame.BackgroundTransparency = 1 - math.clamp(level, 0, 0.7)
	end
end)

-- Per frame -------------------------------------------------------------------
local bounceParams = RaycastParams.new()
bounceParams.FilterType = Enum.RaycastFilterType.Exclude
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
	UserInputService.MouseIconEnabled = not isFirstPerson() and not thirdWeapon
	crosshair.Visible = isFirstPerson() or thirdWeapon

	-- sprint
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if moving == 0 then
		mv.sprintToggle = false
	end
	local sprinting = (mv.sprintHeld or mv.sprintToggle) and moving == 1 and not holding and root and not mv.low
		and humanoid.Health > 0 and not char:GetAttribute("Ragdolled")
	if humanoid then
		humanoid.WalkSpeed = mv.low and MOVE.CROUCH_SPEED or sprinting and SPRINT_SPEED or WALK_SPEED
	end
	if humanoid and root and not Menu.active then
		local able = humanoid.Health > 0 and not char:GetAttribute("Ragdolled")
		updateWallRun(dt, char, humanoid, root)
		updateLanding(humanoid, root, able)
		mv.updateLow(humanoid, root, humanoid.FloorMaterial ~= Enum.Material.Air, able)
		mv.updateDive(humanoid, root)
		-- trampolines (server/Map.luau): the pad names how hard it throws; we own our body, so we
		-- do the bounce ourselves
		if able then
			bounceParams.FilterDescendantsInstances = { char }
			local under = workspace:Raycast(root.Position, Vector3.new(0, -(humanoid.HipHeight + root.Size.Y / 2 + 1.5), 0), bounceParams)
			local bounce = under and under.Instance:GetAttribute("Bounce")
			local v = root.AssemblyLinearVelocity
			if typeof(bounce) == "number" and v.Y < 10 then
				root.AssemblyLinearVelocity = Vector3.new(v.X, bounce, v.Z)
				mv.airJumpUsed = false -- a fresh double jump up there
				if sounds.Jump then
					sounds.Jump:Play()
				end
			end
		end
	end
	for kind, track in lowTracks do
		local on = mv.low and (kind == "slide") == mv.sliding
		if on ~= track.IsPlaying then
			if on then
				track:Play(0.12)
			else
				track:Stop(0.15)
			end
		end
	end
	if lowTracks.crouch then
		lowTracks.crouch:AdjustSpeed(moving) -- the shuffle freezes when you stand still
	end
	-- wall run: its own mirrored cycle for the wall's side, and no turning toward the camera
	if wall and slamming then -- getting onto a wall calls off an armed ground slam
		slamming = false
		if diveTrack then
			diveTrack:Stop(0.15)
		end
	end
	local clingNow = (wall ~= nil and wall.clinging == true) or mantle ~= nil -- hands-up pose for the climb too
	if clingTrack and clingNow ~= clingTrack.IsPlaying then
		if clingNow then
			clingTrack:Play(0.15)
		else
			clingTrack:Stop(0.15)
		end
	end
	local wallSide = wall and not clingNow and ((-wall.normal):Dot(wall.along:Cross(Vector3.yAxis)) > 0 and 1 or -1) or nil
	for side, track in wallRunTracks do
		if side == wallSide and not track.IsPlaying then
			track:Play(0.12)
		elseif side ~= wallSide and track.IsPlaying then
			track:Stop(0.25)
		end
	end
	local turnFree = wall == nil and os.clock() > flipUntil
	local out = Weapons[weaponIndex]
	thirdWeapon = out.kind ~= nil and not isFirstPerson() and not holding and not Menu.active
		and humanoid ~= nil and humanoid.Health > 0 and not (char and char:GetAttribute("Ragdolled"))
	if thirdWeapon and turnFree and root then -- face where the camera looks (shift-lock style)
		local look = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAlong(root.Position, look)
		end
		turnFree = false
	end
	if humanoid and humanoid.AutoRotate ~= turnFree then
		humanoid.AutoRotate = turnFree
	end
	thirdAim += (((thirdWeapon and aiming) and 1 or 0) - thirdAim) * math.min(dt * 12, 1)
	Fx.cameraOffset = SHOULDER * (thirdWeapon and 0.5 + 0.5 * thirdAim or 0)
	local pose = thirdWeapon and aiming and (out.kind == "gun" and "gun" or out.kind == "rocket" and "rocket"
		or (out.kind == "knife" or out.kind == "thrown") and "throw") or nil
	for kind, track in aimTracks do
		if (kind == pose) ~= track.IsPlaying then
			if kind == pose then
				track:Play(0.15)
			else
				track:Stop(0.2)
			end
		end
	end
	local running = sprinting and humanoid.FloorMaterial ~= Enum.Material.Air
	local footsteps = running or (wall ~= nil and not clingNow)
	if sounds.Run and footsteps ~= sounds.Run.IsPlaying then
		if footsteps then
			sounds.Run:Play()
		else
			sounds.Run:Stop()
		end
	end
	if sprintTrack and running and not sprintTrack.IsPlaying then
		sprintTrack:Play(0.15)
	elseif sprintTrack and not running and sprintTrack.IsPlaying then
		sprintTrack:Stop(0.35) -- a slower fade reads as easing into the fall, not a snap
	end
	sprint += ((sprinting and 1 or 0) - sprint) * math.min(dt * 8, 1)
	-- aiming down the sights: zoom in, slow the mouse; the sniper looks through its scope instead
	local held = Weapons[weaponIndex]
	local sniper = held.id == "Sniper"
	local wantAds = aiming and show and (held.kind == "gun" or held.kind == "rocket")
	ads += ((wantAds and 1 or 0) - ads) * math.min(dt * 14, 1)
	Fx.fovBoost = (14 * sprint + moveFov) * (1 - ads) - ads * (sniper and 52 or 22)
	UserInputService.MouseDeltaSensitivity = 1 - ads * (sniper and 0.7 or 0.35)
	crosshair.TextSize = 22 + math.min((held.hip or 0) * (1 - math.max(ads, thirdAim)) * 300, 50) -- a wide cross for a wide spread
	local scoped = sniper and ads > 0.85
	scope.Visible = scoped
	if scoped then
		show = false
		crosshair.Visible = false
	end
	drawArc(aiming and (show or thirdWeapon) and held.kind == "thrown" and held)
	Fx.fovBoost -= 10 * thirdAim
	-- knife aim: 0 -> 1 plays the toss and catch by the blade, 1 -> 0 (letting go) plays it back
	local wantKnife = aiming and show and held.kind == "knife"
	knifeT = math.clamp(knifeT + (wantKnife and dt or -dt) / KNIFE_FLIP, 0, 1)
	Fx.fovBoost -= 8 * knifeT
	local now = os.clock()
	-- tell the other clients what this body is doing, so they can show it too (see Others)
	local loop = clingNow and "cling" or wallSide and "wall" .. wallSide or slamming and "dive"
		or mv.sliding and "slide" or mv.low and "crouch" or running and "sprint" or ""
	if loop ~= mv.loop then
		mv.loop = loop
		moveRemote:FireServer("loop", loop)
	end
	-- movement HUD
	local airborne = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
	mv.hud.wallBack.Visible = wallLeft < WALL_TIME - 0.05
	mv.hud.wall.Size = UDim2.fromScale(math.clamp(wallLeft / WALL_TIME, 0, 1), 1)
	mv.hud.jump.TextTransparency = (mv.airJumpUsed or slamming) and 0.8 or 0
	mv.hud.dash.TextTransparency = (now < mv.dashReadyAt or (airborne and mv.airDashUsed)) and 0.8 or 0
	if (sprinting or wall or mv.sliding) and now > nextLine then
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
		if side == "right" and hold and ads > 0 then -- aiming: the gun comes up to the crosshair (adsFix, below)
			move = move:Lerp(hold.hand + (adsFix[weapon.id] or Vector3.zero) + Vector3.new(0, 0, -0.35 + 0.15 * recoil), ads) -- held out, so both hands show
		elseif side == "right" and hold and weapon.kind == "knife" and knifeT > 0 then -- the arm bends back once it's caught
			move = move:Lerp(KNIFE_COCK, smooth(math.clamp((knifeT - 0.35) / 0.65, 0, 1)))
		elseif side == "left" and ads > 0 and leftGrip[weapon.id] then -- and the left hand takes hold of it
			local rest = Vector3.new(h.x * (0.85 - 0.5 * ext), -0.85 + 0.35 * ext + bob * h.x, -2.35 - 1.2 * ext)
			move = move:Lerp(leftGrip[weapon.id] - rest, ads)
		end
		local fist = camera.CFrame
			* CFrame.new(h.x * (0.85 - 0.5 * ext) + move.X, -0.85 + 0.35 * ext + bob * h.x + move.Y, -2.35 - 1.2 * ext + move.Z)
		h.fist.CFrame = fist
		h.arm.CFrame = fist * CFrame.Angles(math.rad(ARM_PITCH), math.rad(ARM_YAW * h.x), 0) * CFrame.new(0, 0, 1.3)
		local real = arms[side]
		h.fist.Transparency = (show and not real) and 0 or 1
		h.arm.Transparency = (show and not real) and 0 or 1
		-- fingers forward, forearm running back, down and outward past the camera
		local arm = fist * CFrame.Angles(math.rad(ARM_PITCH), math.rad(ARM_YAW * h.x), 0) * CFrame.Angles(math.rad(90), 0, 0)
		local hand = arm
		if side == "right" and hold then
			-- The wrist bends so the hand is square to the view whatever the forearm is doing:
			-- guns point at the crosshair, melee and throwables stand upright and tip forward to swing.
			local tilt = (weapon.kind == "gun" or weapon.kind == "rocket") and 14 * recoil or -25 - 75 * ext
			if weapon.kind == "knife" and knifeT > 0 then -- cocked: the wrist tips the upturned knife's handle at the crosshair
				tilt += (KNIFE_TILT - tilt) * smooth(math.clamp((knifeT - 0.35) / 0.65, 0, 1))
			end
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
	if viewMeshes[weapon.id] == nil then
		equipMesh(weapon.id)
	end
	for id, mesh in viewMeshes do
		local active = id == weapon.id and inHand
		if mesh then
			mesh.Transparency = active and 0 or 1
			if active then
				mesh:PivotTo(weaponCF * (id == "Knife" and knifeT > 0 and knifeFlip(knifeT) or CFrame.identity) * HOLD[id].grip)
				if HOLD[id].support then -- the fist's centre sits a little under the point the palm grips
					leftGrip[id] = camera.CFrame:PointToObjectSpace(mesh.CFrame * HOLD[id].support) + Vector3.new(0, -0.2, 0)
				end
				if ads > 0.9 and recoil < 0.05 then -- learn only once settled, or the easing / kick skews it
					local lo, hi = WeaponMeshes.bounds(id)
					local topCentre = Vector3.new((lo.X + hi.X) / 2, hi.Y, (lo.Z + hi.Z) / 2)
					local top = camera.CFrame:PointToObjectSpace(mesh.CFrame * topCentre)
					-- the top of the mesh is the sight: the launcher's flip-up sight sits a little higher
					local want = Vector3.new(0, weapon.kind == "rocket" and -0.04 or -0.12, top.Z)
					adsFix[id] = (adsFix[id] or Vector3.zero) + (want - top) * math.min(dt * 12, 1)
				end
			end
		end
	end
	-- the same weapon in the body's own right hand, for the pulled-back camera
	local bodyId = not isFirstPerson() and humanoid and humanoid.Health > 0 and HOLD[weapon.id]
		and not (thrown and os.clock() - lastWeaponUse < weapon.cd) and weapon.id or nil
	if bodyWeapon.id ~= bodyId then
		if bodyWeapon.part then
			bodyWeapon.part:Destroy()
		end
		bodyWeapon.id, bodyWeapon.part = bodyId, nil
		if bodyId then
			task.spawn(function()
				local mesh = WeaponMeshes.create(bodyId)
				if not mesh then
					return
				end
				if bodyWeapon.id ~= bodyId or bodyWeapon.part then -- switched again while it was building
					mesh:Destroy()
					return
				end
				mesh.Size *= HOLD[bodyId].scale or 1
				mesh.Parent = camera
				bodyWeapon.part = mesh
			end)
		end
	end
	local rightHand = char and char:FindFirstChild("RightHand") :: BasePart?
	if bodyWeapon.part and rightHand then
		local grip = rightHand:FindFirstChild("RightGripAttachment") :: Attachment?
		local meshCF = rightHand.CFrame * (grip and grip.CFrame or DEFAULT_GRIP) * BODY_GRIP * HOLD[bodyWeapon.id].grip
		local leftHand = char:FindFirstChild("LeftHand") :: BasePart?
		if thirdAim > 0.5 and leftHand and (weapon.kind == "gun" or weapon.kind == "rocket") then
			-- aimed, both hands on it: the gun sits halfway between the hands (the middle of its
			-- grip-to-support span there) and points straight at the crosshair
			local leftGrip = leftHand:FindFirstChild("LeftGripAttachment") :: Attachment?
			local mid = ((grip and grip.WorldPosition or rightHand.Position) + (leftGrip and leftGrip.WorldPosition or leftHand.Position)) / 2
			local rot = CFrame.lookAlong(Vector3.zero, camera.CFrame.LookVector) * HOLD[bodyWeapon.id].grip.Rotation
			meshCF = rot + mid - rot:VectorToWorldSpace((HOLD[bodyWeapon.id].support or Vector3.zero) / 2)
		end
		bodyWeapon.part:PivotTo(meshCF)
	end
	weaponLabel.Text = weapon.name

	for _, attack in Attacks do
		attack.label.TextTransparency = os.clock() < attack.readyAt and 0.65 or 0
	end

	-- hints + target info
	local result = aim(60)
	local dummy = result and dummyOf(result.Instance)
	if dummy then
		local injuries = dummy:GetAttribute("Injuries")
		local blood = dummy:GetAttribute("Blood") or 100
		targetTitle.Text = injuries ~= "" and injuries or "No injuries"
		targetInfo.Text = `{dummy.Name} · {dummy:GetAttribute("Trait") or "?"} · {dummy:GetAttribute("Status")} · {blood >= 100 and "full blood" or blood .. "% blood"}`
		mv.seen, mv.seenAt = dummy, os.clock()
		-- pointing a gun at it: tell the server now and then, so it puts its hands up
		local aimRemote = remotes:FindFirstChild("Aim")
		if (weapon.kind == "gun" or weapon.kind == "rocket") and aimRemote and not holding and os.clock() - (mv.aimedAt or 0) > 0.4 then
			mv.aimedAt = os.clock()
			aimRemote:FireServer(result.Instance)
		end
	else
		targetTitle.Text = ""
		targetInfo.Text = ""
	end

	-- vitals of the dummy last looked at; the panel lingers a while after you look away
	local seen = mv.seen
	if seen and (not seen.Parent or os.clock() - mv.seenAt > 8) then
		seen, mv.seen = nil, nil
	end
	local vitals = mv.vitals
	vitals.panel.Visible = seen ~= nil
	if seen then
		local blood = seen:GetAttribute("Blood") or 100
		local pain = seen:GetAttribute("Pain") or 0
		local status = seen:GetAttribute("Status") or ""
		local levels = {}
		for name, level in (seen:GetAttribute("Body") or ""):gmatch("(%w+):(%d)") do
			levels[name] = tonumber(level)
		end
		for name, cell in vitals.cells do
			cell.BackgroundColor3 = vitals.colors[levels[name] or 0]
		end
		local dead = status:sub(1, 4) == "Dead"
		-- the heart races with pain and with blood loss
		local bpm = dead and 0 or math.floor(72 + pain * 0.7 + (100 - blood) * 1.6 + math.sin(os.clock() * 3) * 2)
		vitals.status.Text = status
		vitals.pulse.Text = bpm .. " bpm"
		vitals.pulse.TextColor3 = (dead or bpm > 140) and Color3.fromRGB(255, 120, 60) or Color3.fromRGB(120, 230, 150)
		vitals.blood.Size = UDim2.fromScale(blood / 100, 1)
		local awake = (dead or status == "Out cold") and 0 or status == "Drowsy" and 0.35 or 1 - pain / 250
		vitals.awake.Size = UDim2.fromScale(awake, 1)
	end
end)
