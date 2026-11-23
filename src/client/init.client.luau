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
local equipRemote = remotes:WaitForChild("EquipWeapon")
local fxRemote = remotes:WaitForChild("Fx")
local moveRemote = remotes:WaitForChild("Move")
local dummyFolder = workspace:WaitForChild("Dummies")

local Attacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attacks"))
local Weapons = require(ReplicatedStorage.Shared:WaitForChild("Weapons"))
local Sfx = require(ReplicatedStorage.Shared:WaitForChild("Sfx"))
local SwingArc = require(ReplicatedStorage.Shared:WaitForChild("SwingArc"))
local Impact = require(ReplicatedStorage.Shared:WaitForChild("Impact"))
local Fx = require(script:WaitForChild("Fx"))
local WeaponMeshes = require(script:WaitForChild("WeaponMeshes"))
local GloveMeshes = require(script:WaitForChild("GloveMeshes"))
local Inspect = require(script:WaitForChild("Inspect"))
local WeaponSway = require(script:WaitForChild("WeaponSway"))
require(script:WaitForChild("Driving")) -- the police car: runs itself (no local: this script is at the 200-local limit)
require(script:WaitForChild("TankClient")) -- the tank: driving, the turret, the gun; runs itself
local WeaponBob = require(script:WaitForChild("WeaponBob"))
local WeaponRecoil = require(script:WaitForChild("WeaponRecoil"))
local BoxingGloves = require(ReplicatedStorage.Shared:WaitForChild("BoxingGloves"))
local Menu = require(script:WaitForChild("Menu"))
require(script:WaitForChild("Music")) -- starts the background playlist
require(script:WaitForChild("PerfMode")) -- fewer shadows, lights and particles on phones (runs itself)
task.spawn(require, script:WaitForChild("KoStars")) -- stars over dummies out cold
task.spawn(require, script:WaitForChild("AdminPanel")) -- owner and Studio only (server/Admin)
require(script:WaitForChild("DummyGear")) -- the cops' guns and the hooligans' bats
require(script:WaitForChild("WantedHud")) -- the wanted stars
task.spawn(require, script:WaitForChild("LikePrompt")) -- the optional "like the game?" card (waits for progress)
require(script:WaitForChild("HeliRotors")) -- the army helicopters' rotors
require(script:WaitForChild("Speech")).start(dummyFolder) -- comic speech bubbles over dummies

-- Sprint run cycle (assets/anims/SprintFlail.json), built in memory, no upload.
-- ponytail: a registered id is session-local, so other players see the default run; upload
-- assets/anims/SprintFlail.rbxmx from the Animation Editor and use that id if they should see it.
local keyframeId = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("KeyframeId"))
local polished = {
	clips = require(ReplicatedStorage.Shared:WaitForChild("AnimationClips")),
	anims = {}, tracks = {}, kickToken = 0, diveToken = 0, sliding = false,
}
for key, name in { slideEnter = "SlideEnter", slideExit = "SlideExit",
	mantle = "Mantle", diveEnter = "DiveEnter", slam = "SlamLand" } do
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = keyframeId(polished.clips.build(name))
	if animation.AnimationId ~= "" then
		polished.anims[key] = animation
	else
		animation:Destroy() -- an optional clip awaiting upload must not break startup
	end
end
function polished.play(name: string, fade: number?, speed: number?)
	local track = polished.tracks[name]
	if track then
		track:Play(fade or 0.08, 1, speed or 1)
	end
end
local sprintAnim = Instance.new("Animation")
sprintAnim.AnimationId = keyframeId(require(script:WaitForChild("SprintFlail")))
local sprintTrack: AnimationTrack? = nil
local rollAnim = Instance.new("Animation") -- same deal, see RollForward
rollAnim.AnimationId = keyframeId(require(script:WaitForChild("RollForward")))
local rollTrack: AnimationTrack? = nil
local diveAnim = Instance.new("Animation") -- slam mode pose, see SupermanDive
diveAnim.AnimationId = keyframeId(require(script:WaitForChild("SupermanDive")))
local diveTrack: AnimationTrack? = nil
-- wall run cycle, one mirror per wall side (1 = wall on the right, -1 = left), see WallRun
local wallRunAnims = {}
for _, side in { 1, -1 } do
	local anim = Instance.new("Animation")
	anim.AnimationId = keyframeId(require(script:WaitForChild("WallRun"))(side))
	wallRunAnims[side] = anim
end
local wallRunTracks: { [number]: AnimationTrack } = {}
local clingAnim = Instance.new("Animation") -- holding on to the wall, see WallCling
clingAnim.AnimationId = keyframeId(require(script:WaitForChild("WallCling")))
local clingTrack: AnimationTrack? = nil
local flipAnim = Instance.new("Animation") -- backflip off the wall, see WallFlip
flipAnim.AnimationId = keyframeId(require(script:WaitForChild("WallFlip")))
local flipTrack: AnimationTrack? = nil
local kickAnim = Instance.new("Animation") -- left click in third person, see HighKick
kickAnim.AnimationId = keyframeId(require(script:WaitForChild("HighKick")))
local kickTrack: AnimationTrack? = nil
-- slide pose and crouch shuffle, see SlideCrouch
local lowAnims, lowTracks = {}, {} :: { [string]: AnimationTrack }
for _, kind in { "slide", "crouch", "crouchIdle" } do
	local anim = Instance.new("Animation")
	anim.AnimationId = keyframeId(require(script:WaitForChild("SlideCrouch"))(kind))
	anim.Name = kind
	if anim.AnimationId ~= "" then lowAnims[kind] = anim else anim:Destroy() end
end
local dashAnim = Instance.new("Animation") -- the dash burst, see DashBurst
dashAnim.AnimationId = keyframeId(require(script:WaitForChild("DashBurst")))
local dashTrack: AnimationTrack? = nil
local flipUntil = 0
local aimAnims = {} -- third-person aiming poses, see AimPose
for _, kind in { "gun", "rocket", "throw" } do
	local anim = Instance.new("Animation")
	anim.AnimationId = keyframeId(require(script:WaitForChild("AimPose"))(kind))
	aimAnims[kind] = anim
end
local aimTracks: { [string]: AnimationTrack } = {}
local dragAnims = {} -- holding a dummy in one hand (F): at your side / pressing it down / raking it / the punt, see DragPose
for _, kind in { "hold", "scrape", "punt" } do
	local anim = Instance.new("Animation")
	anim.AnimationId = keyframeId(require(script:WaitForChild("DragPose"))(kind))
	dragAnims[kind] = anim
end
local dragTracks: { [string]: AnimationTrack } = {}

-- Sounds (assets/sfx/*.wav, uploaded as Audio). An empty id stays silent.
-- ponytail: played locally, so only you hear your own; add a remote if others should.
local SFX = {
	Jump = "122753128464765", -- assets/sfx/Jump.wav, wall jump / double jump / ledge launch / wall flip
	Kick = "111158906695255", -- assets/sfx/Kick.wav
	Slam = "99067212893039", -- ground slam (R in the air) hitting the ground
	Run = "112506453896973", -- assets/sfx/Run.wav, looped while sprinting on the ground or wall running
	Walk = Sfx.WALK_LOOP, -- looped while walking (not sprinting) on the ground
	Land = Sfx.LAND_SOFT, -- feet back on the ground after a fall
	LandHard = Sfx.LAND_HARD, -- ... after a long one
	Dash = Sfx.DASH_WHOOSH,
	BowDraw = Sfx.BOW_DRAW, -- the string pulled back (cut when it is let go)
}
local sounds: { [string]: Sound } = {} -- the body keeps facing the wall it flipped off until the flip is done
-- the same animations and sounds, played here on the other players' characters as they report them
require(script:WaitForChild("Others")).start(moveRemote, {
	sprint = sprintAnim, roll = rollAnim, dive = diveAnim, wall1 = wallRunAnims[1], ["wall-1"] = wallRunAnims[-1],
	cling = clingAnim, flip = flipAnim, kick = kickAnim, slide = lowAnims.slide, crouch = lowAnims.crouch,
	dash = dashAnim,
	crouchIdle = lowAnims.crouchIdle, slideEnter = polished.anims.slideEnter,
	slideExit = polished.anims.slideExit, mantle = polished.anims.mantle,
	vault = polished.anims.mantle, diveEnter = polished.anims.diveEnter, slam = polished.anims.slam,
}, SFX)

local PUNCH_RANGE = 9
local PUNCH_INTERVAL = 0.28
local KICK_INTERVAL = 0.7
local GRAB_RANGE = 13
-- F: a dummy gripped by the clothes at its collar in your right fist, held rigid (the hand's anim:
-- DragPose "hold"); DRAG_HOLD (root space: right, up, forward) only when the rig has no right hand
local DRAG_HOLD = Vector3.new(2.4, 0.3, -0.8)
local DRAG_FIST = CFrame.new(0, -0.25, 0) -- the collar in the fist, from the hand's centre
local DRAG_TILT = 25 -- degrees it leans back off the fist, heels dragging
local DRAG_COLLAR_MIN = 1.2 -- the collar never comes lower than this above the ground under it
local DRAG_CHEST_REACH = 4 -- F takes the chest even this much past GRAB_RANGE (server: the same)
local DRAG_VIEW_REACH = 2.3 -- first person: how far out toward the collar the right fist is drawn
-- held with F, looking a little down (camera look below RAKE_LOOK) with the left button held: you
-- lean into it and drive it down and back into the ground beside you as you run (DragPose "scrape"),
-- laid back RAKE_TILT so it ploughs on its back, one unbroken furrow behind it (the server lays
-- it, Fx "Furrow"). Full speed: the faster you go the more it throws up. RAKE_SPEED only paces the
-- scrape animation's judder.
local RAKE_LOOK = -0.2
local RAKE_TILT = 62
local RAKE_SPEED = 20
-- looking ahead, one click: the punt (DragPose "punt"). Swung back and heaved up over your head, it
-- leaves the hand at PUNT_RELEASE, falls into a front kick that meets it at PUNT_KICK and flies off
-- at PUNT_SPEED: a launch the server marks, so what it hits takes a far harder blow than a throw.
local PUNT_RELEASE = 0.3
local PUNT_KICK = 0.52
local PUNT_LENGTH = 0.95
local PUNT_SPEED = 150
local PUNT_LIFT = 50 -- launched ~18 degrees up: it leaves from the foot, low, so less noses into the ground
local PUNT_APEX = Vector3.new(0.7, 2.6, -2.3) -- root space (right, up, back): over your head, just in front
local PUNT_FOOT = Vector3.new(0.5, 0.35, -2.9) -- where the foot meets it
-- first person, the view follows it: up as it is heaved overhead, down to the kick, then back
-- (degrees, + looks up). The legs show for the whole punt, and no weapon is out until it ends.
local PUNT_LOOK_UP, PUNT_LOOK_DOWN = 12, -40
-- the kicked body ploughing into things (see the loose body below): from PUNT_ARM s after the kick
-- (just let go, the limbs still settle), PUNT_HITS hits at most, PUNT_GAP s apart (not under the
-- server's 0.3 s per landing), for PUNT_TIME (the server's PUNT_HITS / PUNT_TIME)
local PUNT_ARM, PUNT_HITS, PUNT_GAP, PUNT_TIME = 0.25, 3, 0.3, 3
local PUNT_NEAR, PUNT_LOOKAHEAD = 2, 0.05 -- studs past the chest and s of travel looked ahead for a wall
local PUNT_WALL = 0.6 -- |normal.Y| below this is something standing (a wall); above, floor or a ledge top
local PUNT_MIN_SPEED = 30 -- studs/s it still needs to break anything
local PUNT_KEEP = 0.5 -- of its speed it keeps after smashing through
local PUNT_EYE =Vector3.new(0, 0.35, 1) -- first person: the eye draws back (Z) and up (Y) for the kick
local puntUntil = 0 -- os.clock() the punt animation ends (it plays on after the body has gone)
local PUNT_SHOWN = { "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
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
	simple = function(): boolean return false end, -- the easy touch controls are on (TouchControls replaces it)
	sprintHeld = false, -- Shift
	freeCursor = false, -- O: a free cursor in third person
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
	-- moves cut for now, to keep the controls short (true = gone): the slam dive (R / Y in the air, and
	-- its ground slam), the wall flip off a cling (S, or dash while hanging) and the sprint vault onto
	-- low cover (an airborne ledge grab still climbs). Flip one back to false to bring it back.
	cut = { slam = true, flip = true, vault = true },
	lastWallNormal = nil :: Vector3?, -- the wall last run on this airtime
	loop = "", -- the looping movement look last reported to the server (see Others)
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local holding = nil -- { part, dist, since, impact }: impact tracks hits we swing it into (shared/Impact)
local punching = false
local lastPunch = 0
local lastKick = 0
local kickParams = OverlapParams.new()
kickParams.FilterType = Enum.RaycastFilterType.Include
kickParams.FilterDescendantsInstances = { dummyFolder }
local nextHand = "right"
local weaponIndex = 1 -- Weapons[1] is fists
local heldAbility = nil -- an Attacks entry taken from the hotbar: the hands glow its colour, a click casts it
local lastWeaponUse = 0
local weaponVisual = { sway = WeaponSway.new(), bob = WeaponBob.new(), recoil = WeaponRecoil.new(), equipToken = 0, lastAction = "", slashSide = 1 }
do -- the comic set's own moves (WeaponAnims): clips for the body, loaded onto each character below
	weaponVisual.lib = require(script:WaitForChild("WeaponAnims"))
	weaponVisual.detonator = require(script:WaitForChild("Detonator"))
	weaponVisual.anims, weaponVisual.animTracks = {}, {}
	for name in weaponVisual.lib.CLIPS do
		local anim = Instance.new("Animation")
		anim.Name = name
		anim.AnimationId = keyframeId(weaponVisual.lib.sequence(name))
		if anim.AnimationId ~= "" then
			weaponVisual.anims[name] = anim
		end
	end
end
-- A first-person hand pressed flat on a wall (normal n) at `at`, fingers along `fingers`, the
-- forearm bent back from the wrist toward the shoulder; blended in over hand / arm by w.
-- x: 1 right hand, -1 left; wrist: the wrist point in hand space.
function weaponVisual.palm(hand: CFrame, arm: CFrame, at: Vector3, n: Vector3, fingers: Vector3, x: number,
	wrist: Vector3, view: CFrame, w: number): (CFrame, CFrame)
	local palmOut = n * x -- an R15 hand's palm faces -X on the right hand, +X on the left
	local flat = CFrame.fromMatrix(at + n * 0.12, palmOut, -fingers) -- fingers at the hand's -Y
	local wristAt = flat * wrist
	local toShoulder = (view * Vector3.new(x, -1.5, 0.8) - wristAt).Unit
	local armX = (palmOut - toShoulder * palmOut:Dot(toShoulder)).Unit
	local bent = CFrame.fromMatrix(wristAt, armX, toShoulder) * CFrame.new(-wrist)
	return hand:Lerp(flat, w), arm:Lerp(bent, w)
end
local recoil = 0
local aiming = false -- right mouse / L2 held: aim down the sights (guns) or show the throw arc (thrown)
local ads = 0 -- eased 0..1
-- boxing block (right mouse / L2 with the gloves): sent to the server, which then blocks every
-- attack (knockPlayer); guardT eases the first-person gloves up to the face
local guarding, guardT = false, 0
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
-- Y: look the held weapon over (first person, timelines in Inspect); any action cancels it.
local inspect = nil :: { id: string, at: number }?
local inspectLeft = nil :: Vector3? -- camera-space point the left fist reaches for (pose.leftAt), last frame's
-- Puts the held weapon's moving pieces where the inspect pose wants them (pose nil: back in place).
-- meshCF: the mesh's CFrame this frame; fists: this frame's fist CFrames, for a piece handed over.
local function posePieces(id: string, pose, viewCF: CFrame, fists, meshCF: CFrame?)
	local names = Inspect.pieces[id]
	if not names then
		return
	end
	for _, name in names do
		local off = pose and pose.pieces and pose.pieces[name] or CFrame.identity
		local attach = pose and pose.attach
		if meshCF and attach and attach.piece == name and attach.w > 0 and fists.left then
			local c = WeaponMeshes.pieceCentre(id, name)
			if c then -- the piece in the left fist, expressed in the mesh's own space
				off = off:Lerp(meshCF:Inverse() * fists.left * attach.at * CFrame.new(-c), attach.w)
			end
		end
		WeaponMeshes.pose(id, name, off)
	end
	local reach = pose and pose.leftAt
	if meshCF and reach then -- the fist's centre sits a little under the point the palm grips
		local off = reach.piece and pose.pieces and pose.pieces[reach.piece] or CFrame.identity
		inspectLeft = viewCF:PointToObjectSpace(meshCF * (off * reach.point)) + Vector3.new(0, -0.2, 0)
	end
end
-- The knife relative to its normal place in the hand at toss progress t: lifted on an arc, spun
-- one and a half turns (ends upside down), sliding down so the blade ends up in the palm.
local function knifeFlip(t: number): CFrame
	local e = smooth(t)
	return CFrame.new(0, math.sin(math.pi * t) * 0.9 + KNIFE_BLADE * e, 0) * CFrame.Angles(math.pi * 3 * e, 0, 0)
end
local sprint = 0 -- eased 0..1
local nextLine = 0

player.CameraMode = Enum.CameraMode.LockFirstPerson
local THIRD_PERSON_DIST = 10 -- studs behind the body in the V view (fixed: the wheel does not zoom)

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
-- Aimed swing (weapons with aimSwing): hold the attack button, a circle comes up round the crosshair
-- and the mouse or right stick (the camera turns at 15% meanwhile) draws a line from its centre. Direction = where
-- the blow goes, length = power. Released, it swings.
-- (one table: the script is at Luau's 200-local limit)
local swingUi = { R = 70, HOLD = 0.1, aim = nil :: { weapon: any, x: number, y: number, shown: boolean }? } -- aim: x right, y up, pixels (0..R); HOLD: seconds held before the circle shows
do
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(swingUi.R * 2, swingUi.R * 2)
	ring.BackgroundTransparency = 0.85
	ring.BackgroundColor3 = Color3.new(0, 0, 0)
	ring.Visible = false
	ring.Parent = gui
	Instance.new("UICorner", ring).CornerRadius = UDim.new(0.5, 0)
	local stroke = Instance.new("UIStroke", ring)
	stroke.Color, stroke.Thickness, stroke.Transparency = Color3.new(1, 1, 1), 2, 0.3
	-- centred halfway to the dot: Rotation turns a frame about its own centre whatever its AnchorPoint
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BorderSizePixel = 0
	line.Parent = ring
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Size = UDim2.fromOffset(10, 10)
	tip.BorderSizePixel = 0
	tip.Parent = ring
	Instance.new("UICorner", tip).CornerRadius = UDim.new(0.5, 0)
	function swingUi.draw()
		local a = swingUi.aim
		ring.Visible = a ~= nil and a.shown
		if not a or not a.shown then return end
		local len = math.sqrt(a.x * a.x + a.y * a.y)
		local colour = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 70, 40), len / swingUi.R) -- white weak, red full
		line.Size = UDim2.fromOffset(len, 4)
		line.Position = UDim2.new(0.5, a.x / 2, 0.5, -a.y / 2)
		line.Rotation = math.deg(math.atan2(-a.y, a.x))
		line.BackgroundColor3, tip.BackgroundColor3, stroke.Color = colour, colour, colour
		tip.Position = UDim2.new(0.5, a.x, 0.5, -a.y)
	end
	-- The camera turns at CAMERA_SLOW of the player's sensitivity while the line is drawn: the
	-- PlayerModule turns it through the bindings of its CameraRotationAction (InputActions, which a
	-- CAS sink does not reach), so their Scale is cut and put back on release.
	-- The same goes for aiming (the sniper's scope above all): UserInputService.MouseDeltaSensitivity
	-- never reaches those bindings either. cameraScale(f) sets every binding to f times its own Scale
	-- (read once); false while the PlayerModule has no such action (then the caller falls back).
	swingUi.CAMERA_SLOW, swingUi.slow = 0.15, false
	local cameraBindings: { InputBinding }?, cameraBase, cameraLast = nil, {} :: { [Instance]: number }, 1
	function swingUi.cameraScale(f: number): boolean
		if not cameraBindings then
			local module = player.PlayerScripts:FindFirstChild("PlayerModule") or game:GetService("StarterPlayer"):FindFirstChild("PlayerModule")
			local action = module and module:FindFirstChild("CameraRotationAction", true)
			if not action then return false end
			cameraBindings = {}
			for _, binding in action:GetChildren() do
				if binding:IsA("InputBinding") then
					table.insert(cameraBindings :: any, binding)
					cameraBase[binding] = binding.Scale
				end
			end
		end
		local list = cameraBindings :: { InputBinding }
		if f ~= cameraLast then
			cameraLast = f
			for _, binding in list do binding.Scale = cameraBase[binding] * f end
		end
		return #list > 0
	end
	function swingUi.holdCamera(hold: boolean) -- applied with the aim's own slow-down every frame (below)
		swingUi.slow = hold
	end
	-- The line drawn on by (dx, dy) screen pixels (y down), kept inside the circle: the mouse, and on a
	-- phone the finger holding ATTACK (TouchControls calls mv.swingDrag), so a touch can aim the swing too
	function swingUi.move(dx: number, dy: number)
		local a = swingUi.aim
		if not a then return end
		a.x += dx
		a.y -= dy
		local len = math.sqrt(a.x * a.x + a.y * a.y)
		if len > swingUi.R then a.x, a.y = a.x / len * swingUi.R, a.y / len * swingUi.R end
		swingUi.draw()
	end
	mv.swingDrag = function(delta: Vector3) swingUi.move(delta.X, delta.Y) end
	-- The line as (side, up, power): side/up the unit direction (0, 0 if barely moved), power 0..1;
	-- an unmoved line is a plain swing (0.5).
	function swingUi.value(): Vector3
		local a = swingUi.aim :: any
		local len = math.sqrt(a.x * a.x + a.y * a.y)
		if len < 4 then return Vector3.new(0, 0, 0.5) end
		return Vector3.new(a.x / len, a.y / len, len / swingUi.R)
	end
end
-- How each aimed-swing weapon moves in first person along the drawn line:
-- time: seconds per swing; split: share of it spent sweeping through (the rest recovers);
-- cock: how far it is drawn back; reach: studs swept across the view; push: lunge ahead;
-- tilt: degrees the head turns round per unit of sweep (the edge always leads: see the wrist below);
-- sink: drops through the target at the end (heavy heads); spin: a twirl round the handle on the
-- recovery (degrees).
local SWING_STYLE = {
	Bat = { time = 0.2, split = 0.55, cock = 1, reach = 0.8, push = 0.35, tilt = 85 },
	Pan = { time = 0.17, split = 0.42, cock = 0.6, reach = 0.6, push = 0.5, tilt = 60 },
	Katana = { time = 0.16, split = 0.38, cock = 1.2, reach = 1.15, push = 0.2, tilt = 95 },
	Axe = { time = 0.3, split = 0.62, cock = 1.4, reach = 0.85, push = 0.45, tilt = 100, sink = 0.3 },
	Crowbar = { time = 0.22, split = 0.48, cock = 0.7, reach = 0.55, push = 0.5, tilt = 70 },
	Sledgehammer = { time = 0.45, split = 0.68, cock = 1.6, reach = 1, push = 0.3, tilt = 100, sink = 0.45 },
	Lightsaber = { time = 0.18, split = 0.36, cock = 1, reach = 1.2, push = 0.25, tilt = 90, spin = 360 },
}
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
	Text = "1-5  Weapons, Q or J  Arsenal\nX  Dash\nClick with an ability in hand  Use it\nF on a dummy  Hold it (sprint: grind it into the ground)\nHolding it, look down + hold click  Pound it into the ground\nE  Grab / drop\nC  Fall\nTab  Toolbox (characters, teams, build)\nG  Spawn the picked character\nBuilding: hold Q  Blocks, 1 / 2  Block / trash, click  Build / delete\nR  Revive\nB  Scan (X-ray a dummy)\nV  Camera\nM  Back to the menu",
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(320, 320),
})
local controlsHint = label({
	Text = "H  Controls    M  Menu",
	TextSize = 13,
	TextTransparency = 0.25,
	TextXAlignment = Enum.TextXAlignment.Left,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(240, 16),
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
for _, attack in Attacks do -- cast from the weapon wheel (WeaponBar), which shows their cooldowns
	attack.readyAt = 0
end
-- Movement HUD, bottom centre (clear of the body in third person): the wall run time left (shown
-- only once some is used).
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
	mv.hud = { wallBack = back, wall = fill }
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
	-- The chart note beside it: what was done to the dummy (its newest injuries, server "Injuries"),
	-- then "Name · Status · 87% blood". It flashes white when the note changes.
	local note = Instance.new("Frame")
	note.AnchorPoint = Vector2.new(1, 1)
	note.Position = UDim2.new(1, -174, 1, -160) -- left of the panel, bottoms level
	note.Size = UDim2.fromOffset(280, 52)
	note.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	note.BackgroundTransparency = 0.25
	note.BorderSizePixel = 0
	note.Visible = false
	note.Parent = gui
	local noteBar = Instance.new("Frame") -- the yellow edge, as on a chart
	noteBar.Size = UDim2.new(0, 3, 1, 0)
	noteBar.BackgroundColor3 = Color3.fromRGB(252, 200, 50)
	noteBar.BorderSizePixel = 0
	noteBar.Parent = note
	local headline = label({ TextSize = 13, TextColor3 = Color3.fromRGB(252, 200, 50), TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -16, 0, 30) }) -- two lines at most
	headline.Parent = note
	local detail = label({ TextSize = 11, TextColor3 = Color3.fromRGB(220, 220, 220), TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Font = Enum.Font.Gotham, Position = UDim2.new(0, 10, 1, -18), Size = UDim2.new(1, -16, 0, 13) })
	detail.Parent = note
	mv.vitals = {
		note = note,
		headline = headline,
		detail = detail,
		panel = panel,
		cells = cells,
		status = line(156, 13, Color3.fromRGB(255, 160, 60)),
		pulse = line(172, 12, Color3.fromRGB(120, 230, 150)),
		blood = bar(194, "Blood", Color3.fromRGB(198, 30, 40)),
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
	-- on a touch screen the last touch is a button, never the target: the crosshair in the middle
	local mouse = if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	if mv.assist then -- easy touch controls: bend to a dummy just off the crosshair (TouchControls)
		ray = Ray.new(ray.Origin, mv.assist(ray.Origin, ray.Direction, range) or ray.Direction)
	end
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

-- A hand glowing the colour of the ability in hand: tinted (Highlight), a light and sparks on the
-- part, built once, then switched. `color` nil or `on` false puts it out.
local glows = setmetatable({}, { __mode = "k" }) -- [part] = { tint, light, sparks }
local function handGlow(p: BasePart?, color: Color3?, on: boolean)
	local g = p and glows[p]
	if not p or (not g and not (color and on)) then
		return
	end
	if not g then
		local light = Instance.new("PointLight")
		light.Range, light.Brightness, light.Shadows = 6, 3, false
		light.Parent = p
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.LightEmission = 1
		sparks.Rate = 30
		sparks.Lifetime = NumberRange.new(0.2, 0.4)
		sparks.Speed = NumberRange.new(0.3, 1.2)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Size = NumberSequence.new(0.18, 0)
		sparks.Transparency = NumberSequence.new(0.1, 1)
		sparks.Parent = p
		local tint = Instance.new("Highlight")
		tint.DepthMode = Enum.HighlightDepthMode.Occluded
		tint.FillTransparency = 0.35
		tint.OutlineTransparency = 0.2
		tint.Parent = p
		g = { tint = tint, light = light, sparks = sparks }
		glows[p] = g
	end
	local lit = color ~= nil and on
	g.tint.Enabled, g.light.Enabled, g.sparks.Enabled = lit, lit, lit
	if lit then
		g.tint.FillColor, g.tint.OutlineColor = color, color
		g.light.Color = color
		g.sparks.Color = ColorSequence.new(color)
	end
end

-- First-person arms are clones of the character's own hand / lower arm / upper arm, so they carry
-- the avatar's skin, shape and sleeves. The ball-and-block fists above stay as the anchor the
-- weapons hang off, and as the fallback for a rig without R15 arms.
-- Where a tool sits in an R15 hand: in the palm, turned so the tool's -Z runs out along the fingers.
local DEFAULT_GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
-- Forearm angle off the view direction and how much the cloned lower / upper arm is stretched along
-- its length. Pitch tips the fingers up: a little reads as a natural guard; much more (12) and the
-- arms look raised, below zero they reach out like a zombie. Yaw splays the forearms outward.
local ARM_PITCH, ARM_YAW = 0, 30
local GLOVE_REST = Vector3.new(0.35, 0.25, -0.3) -- boxing: arm offset (x outward) so gloves sit at the fists
-- boxing: the glove's front tipped up GLOVE_TIP degrees about the wrist, GLOVE_WRIST studs back from
-- the fist, so the cuff and forearm stay where they are
local GLOVE_TIP, GLOVE_WRIST = 25, 0.6
-- bare fists sit this much further apart and nearer the camera (a weapon's hand keeps its tuned spot)
local FIST_SPREAD, FIST_PULL = 0.3, 0.3
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
	Bow = {
		{ BLOCK, Vector3.new(0.18, 0.9, 0.18), CFrame.new(0, 0, 0), WOOD },
		{ BLOCK, Vector3.new(0.14, 1.4, 0.16), CFrame.new(0, 0.95, -0.22) * CFrame.Angles(-0.32, 0, 0), WOOD },
		{ BLOCK, Vector3.new(0.14, 1.4, 0.16), CFrame.new(0, -0.95, -0.22) * CFrame.Angles(0.32, 0, 0), WOOD },
		{ BLOCK, Vector3.new(0.04, 3.1, 0.04), CFrame.new(0, 0, 0.18), Color3.fromRGB(218, 212, 190) },
		{ BLOCK, Vector3.new(0.07, 0.07, 2), CFrame.new(0, 0, -0.65), WOOD },
	},
	BoxingGloves = BoxingGloves.icon(),
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
weaponVisual.gloves = {
	left = BoxingGloves.create(camera, "ViewGlove_Left", -1),
	right = BoxingGloves.create(camera, "ViewGlove_Right", 1),
}
local VIEW_GLOVE_SCALE = 0.8 -- the first-person pair, down to about the size of the bare fists
for side, x in { left = -1, right = 1 } do
	task.spawn(function()
		local glove = weaponVisual.gloves[side]
		GloveMeshes.dress(glove, x, camera)
		if glove.mesh then
			glove.mesh.Size *= VIEW_GLOVE_SCALE
		end
	end)
end
GloveMeshes.watch(camera, function(character)
	-- our own: the viewmodel pair draws instead in first person, and holding one with F (or kicking it)
	-- the hands are bare
	return character == player.Character
		and (isFirstPerson() or (holding ~= nil and holding.drag == true) or os.clock() < puntUntil)
end)
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
	Bow = { grip = CFrame.new(0, 0, -0.05), hand = Vector3.new(-0.35, 0.2, 0.15) },
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
	Crowbar = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Sledgehammer = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0) },
	Spear = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0), scale = 0.9 },
	Lightsaber = { grip = CFrame.new(0, 0.05, 0), hand = Vector3.new(0.1, 0.05, 0) },
	-- the comic set's guns (assets/weapons/comic_weapons.py): support = their front grip / under the barrel
	Chainsaw = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.6, -0.62) },
	Taser = { grip = CFrame.new(0, -0.08, 0.08), hand = Vector3.new(-0.25, 0.2, 0.1), support = Vector3.new(-0.12, 0, 0.1) },
	Frostgun = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.2, -0.95) },
	Boilgun = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.25, -0.9) },
	Flamethrower = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.05, -1.18) },
	Minigun = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0, -0.88), scale = 0.85 },
	Harpoon = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.18, -1.2) },
	-- held in the fist (thrown / placed)
	Lasso = { grip = CFrame.new(0, 0, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.9 },
	TNT = { grip = CFrame.new(0, 0.1, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.8 },
	C4 = { grip = CFrame.new(0, 0.38, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.8 }, -- on the palm, not in the fist
	Landmine = { grip = CFrame.new(0, 0.1, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.7 },
	Shotgun = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.45), support = Vector3.new(0, 0.2, -1.3) },
	Sniper = { grip = CFrame.new(0, 0.12, -0.04), hand = Vector3.new(-0.2, 0.05, 0.5), support = Vector3.new(0, 0.15, -1.3) },
	Rocket = { grip = CFrame.new(0, -0.2, 0), hand = Vector3.new(-0.1, 0.35, 0.4), support = Vector3.new(0, 0, -0.85) },
	Tomato = { grip = CFrame.new(0, 0.2, 0), hand = Vector3.new(0, 0.1, 0), scale = 0.85 },
}
do -- the minigun's barrels spin while the trigger is held, run up and wind down (WeaponMeshes.pose)
	local speed, angle = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		local firing = punching and Weapons[weaponIndex].id == "Minigun"
		speed += ((firing and 30 or 0) - speed) * math.min(1, dt * (firing and 2.5 or 1.5))
		if speed < 0.05 then
			return
		end
		angle = (angle + speed * dt) % (math.pi * 2)
		local c = WeaponMeshes.pieceCentre("Minigun", "Barrels")
		if c then -- round the barrels' own axis (mesh Z, through their centre)
			WeaponMeshes.pose("Minigun", "Barrels", CFrame.new(c) * CFrame.Angles(0, 0, angle) * CFrame.new(-c))
		end
	end)
end

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

-- A point of the weapon we hold (its mesh space, scaled as held) in the world this frame, first-person
-- viewmodel or the body's: the crowbar's claw carries a torn-off arm there (Fx "Hang").
Fx.weaponPoint = function(id: string, point: Vector3): CFrame?
	local mesh = if isFirstPerson() then viewMeshes[id] else bodyWeapon.id == id and bodyWeapon.part
	if not mesh then
		return nil
	end
	return mesh.CFrame * CFrame.new(point * (HOLD[id] and HOLD[id].scale or 1))
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

local function useWeapon(weapon, swing: Vector3?, detonate: boolean?) -- detonate: C4's remote (right mouse)
	if gui:GetAttribute("WeaponPickerOpen") then return end
	weapon = weapon.slash and not aiming and weapon.slash or weapon.heavy and aiming and weapon.heavy or weapon
	local now = os.clock()
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if now - lastWeaponUse < (weaponVisual.lastCooldown or weapon.cd) or not head or char:GetAttribute("Ragdolled") then
		return
	end
	lastWeaponUse = now
	weaponVisual.lastAction, weaponVisual.lastCooldown = weapon.id, weapon.cd
	local result, ray = aim(300)
	local target = result and result.Position or ray.Origin + ray.Direction * 300
	local dir = (target - head.Position).Unit
	if dir:Dot(ray.Direction) < 0.5 then -- something right beside the head: aim past it, straight down the crosshair
		dir = (ray.Origin + ray.Direction * 300 - head.Position).Unit
	end
	-- an aimed swing that would miss bends to the dummy nearest the crosshair within reach (25° cone)
	if weapon.aimSwing and not (result and dummyOf(result.Instance) and (result.Position - head.Position).Magnitude <= weapon.range) then
		local best, crosshairDir = math.cos(math.rad(25)), dir
		for _, m in dummyFolder:GetChildren() do
			local torso = m:FindFirstChild("UpperTorso") :: BasePart?
			local to = torso and torso.Position - head.Position
			if to and to.Magnitude <= weapon.range + 1 and to.Unit:Dot(crosshairDir) > best then
				best, dir = to.Unit:Dot(crosshairDir), to.Unit
			end
		end
	end
	-- hip fire: the shot leaves somewhere in a wide cone round the crosshair; aiming (first or third
	-- person) closes it, and once fully up the shot goes exactly to the crosshair
	local aimed = if detonate then 1 else math.max(ads, thirdAim)
	local spread = aimed > 0.95 and 0 or (weapon.hip or 0) * (1 - aimed)
	if spread > 0 then
		dir = (CFrame.lookAlong(Vector3.zero, dir)
			* CFrame.Angles(0, 0, math.random() * math.pi * 2)
			* CFrame.Angles(spread * math.sqrt(math.random()), 0, 0)).LookVector -- sqrt: even over the cone, not bunched in the middle
	end
	-- where the head is now (not where the server last saw it), and whether we are aimed (tight pellets)
	weaponRemote:FireServer(weapon.id, dir, head.Position, aimed > 0.95, swing)
	if weapon.id == "Sniper" and aimed > 0.95 then
		Fx.scopedShotAt = now -- through the scope: its hit gets the impact frames (Fx)
	end
	if weapon.spinUp then -- the minigun: the server fires only once the barrels have spun up; no bang before
		if now - (weaponVisual.spinLast or 0) > 0.3 then
			weaponVisual.spinSince = now
		end
		weaponVisual.spinLast = now
		if now - weaponVisual.spinSince < weapon.spinUp then
			return
		end
	end
	-- the comic set's own moves (WeaponAnims): the body's clip, the viewmodel's timer; a gun fired from
	-- the hip in third person comes up into the aim pose for a moment
	local lib = weaponVisual.lib
	local clipName = aimed > 0.95 and lib.USE_AIMED[weapon.id] or lib.USE[weapon.id]
	local clip = clipName and weaponVisual.animTracks[clipName]
	if clip then
		clip:Play(0.05)
	end
	weaponVisual.useAt, weaponVisual.useId, weaponVisual.useAimed = now, weapon.id, aimed > 0.95
	if weapon.kind == "gun" and not aiming then
		weaponVisual.hipAimUntil = now + (weapon.auto and 0.4 or 0.8)
	end
	weaponVisual.swing = swing
	-- our own sounds now, not a round trip later (the server leaves us out of these)
	local sounds = if detonate then {} else Sfx.WEAPON[weapon.id] or {} -- the server beeps the remote
	-- the fast auto weapons (flamethrower, chainsaw) play their clip once every Sfx.HUSH s, as the server does
	local hush = Sfx.HUSH[weapon.id]
	if sounds.fire and (not hush or now - (weaponVisual.fireSoundAt or 0) >= hush) then
		weaponVisual.fireSoundAt = now
		Sfx.playLocal(sounds.fire, head.Position)
	end
	if weapon.hurt == "bullet" and not detonate then -- where the round lands, guessed here too: no round trip for our own hits
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		local shot = workspace:Raycast(head.Position, dir * (weapon.range or 300), params)
		if shot then
			local monsters = workspace:FindFirstChild("Monsters")
			local onBody = shot.Instance:IsDescendantOf(dummyFolder) or (monsters ~= nil and shot.Instance:IsDescendantOf(monsters))
			local sound = if onBody then sounds.hit else Sfx.surface(shot.Instance)
			if sound then
				Sfx.playLocal(sound, shot.Position)
			end
		end
	end
	if weapon.kind == "melee" then -- the server's swing ray, guessed here; ponytail: a dodged swing still rings as a hit for us
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		local swing = if weapon.aimSwing
			then SwingArc.cast(head.Position, dir, swing, weapon.range, params, function(inst) return inst:IsDescendantOf(dummyFolder) end)
			else workspace:Raycast(head.Position, dir * weapon.range, params)
		local onBody = swing and swing.Instance:IsDescendantOf(dummyFolder)
		local sound = if not swing then sounds.swing elseif onBody then sounds.hit else nil
		if sound then
			Sfx.playLocal(sound, swing and swing.Position or head.Position)
		end
	end
	if weapon.kind == "gun" or weapon.kind == "rocket" then
		recoil = 1
		weaponVisual.recoil:fire(weapon.id)
	elseif weapon.id == "BoxingGloves" then
		hands[nextHand].t, hands[nextHand].heavy = 0, false
		nextHand = nextHand == "right" and "left" or "right"
	elseif weapon.id == "BoxingHeavy" then -- the lead hand straight out of the block
		hands.left.t, hands.left.heavy = 0, true
		nextHand = "right"
	else
		hands.right.t = 0 -- the punch motion doubles as the swing / throw
		if weapon.id == "KnifeSlash" then
			knifeT = 0
			weaponVisual.slashSide = -weaponVisual.slashSide
		end
	end
end

local toggleDrag: () -> boolean -- F on a dummy (Grabbing, below); the weapon bar asks it first

local function castAbility(attack)
	if os.clock() >= attack.readyAt and not holding then
		attack.readyAt = os.clock() + attack.cd
		attackRemote:FireServer(attack.id, camera.CFrame.LookVector) -- cast where the player looks
	end
end

-- Tab: G spawns the picked character, a picked block puts a click on building (Toolbox.luau);
-- assigned below, the hotbar puts the build tool away
local toolbox

-- Hotbar (bottom centre) + weapon wheel (hold Q); 1-5 / Q tap / F / L1 R1 / the mouse wheel step through.
-- Studio only: a BindableFunction "WeaponTest" on the player for MCP playtests (another VM can call it):
-- ("select", id) takes a weapon in hand as the bar does, ("use", swing?) uses it as a click would,
-- ("view", "first" | "third") switches the camera, ("aim", on) holds / lets go of right mouse.
local barApi
if RunService:IsStudio() then
	local test = Instance.new("BindableFunction")
	test.Name = "WeaponTest"
	test.OnInvoke = function(cmd: string, arg: any): any
		if cmd == "select" then
			for i, w in Weapons do
				if w.id == arg then
					barApi.set(i)
					return true
				end
			end
			return false
		elseif cmd == "use" then
			useWeapon(Weapons[weaponIndex], arg)
			return Weapons[weaponIndex].id
		elseif cmd == "view" then
			player.CameraMode = if arg == "first" then Enum.CameraMode.LockFirstPerson else Enum.CameraMode.Classic
			if arg ~= "first" then
				player.CameraMaxZoomDistance, player.CameraMinZoomDistance = THIRD_PERSON_DIST, THIRD_PERSON_DIST
			else
				player.CameraMinZoomDistance = 0.5
			end
			return arg
		elseif cmd == "aim" then
			aiming = arg == true
			return aiming
		elseif cmd == "hold" then -- the trigger held (auto weapons, the minigun's spin, the chainsaw)
			punching = arg == true
			return punching
		elseif cmd == "hangTest" then -- (seconds): a dummy's arm copied onto our crowbar's claw, as after a rip
			local src -- a dummy streamed in whole (a far one may have no arms here yet)
			for _, m in dummyFolder:GetChildren() do
				if m:FindFirstChild("LeftUpperArm") and m:FindFirstChild("LeftLowerArm") and m:FindFirstChild("LeftHand") then
					src = m
					break
				end
			end
			local gib = Instance.new("Model")
			for _, name in { "LeftUpperArm", "LeftLowerArm", "LeftHand" } do
				local p = src and src:FindFirstChild(name)
				if p then
					local c = p:Clone()
					c.Anchored, c.CanCollide = true, false
					c.Parent = gib
				end
			end
			local arm = gib:FindFirstChild("LeftUpperArm") :: BasePart?
			if not arm then
				return false
			end
			gib.Parent = workspace
			local dur = arg or 6
			Fx.hookAt = os.clock() - 3.05 -- the claw just tore it free: held up (both views)
			weaponVisual.hookSeen = Fx.hookAt
			local rip = weaponVisual.animTracks.Rip_Crowbar
			if rip then
				rip:Play(0)
				rip.TimePosition = 3.4
				rip:AdjustSpeed(0)
				task.delay(dur, rip.Stop, rip, 0.2)
			end
			Fx.play("Hang", player.Character, gib, arm, dur)
			task.delay(dur + 0.2, gib.Destroy, gib)
			return true
		elseif cmd == "face" then -- (Vector3 | nil): the third-person body faces this way, not the camera's
			weaponVisual.testFace = arg
			return arg
		elseif cmd == "freeze" then -- (u 0..1 | nil): the last use held still at that point, both views
			weaponVisual.freezeU = arg
			local lib, id = weaponVisual.lib, Weapons[weaponIndex].id
			local name = weaponVisual.useAimed and lib.USE_AIMED[id] or lib.USE[id]
			local track = name and weaponVisual.animTracks[name]
			if track then
				if arg then
					if not track.IsPlaying then
						track:Play(0)
					end
					track.TimePosition = arg * track.Length
					track:AdjustSpeed(0)
				else
					track:AdjustSpeed(1)
				end
			end
			weaponVisual.hipAimUntil = if arg and Weapons[weaponIndex].kind == "gun" then math.huge else 0
			return name
		end
		return nil
	end
	test.Parent = player
end
barApi = {
	get = function()
		return weaponIndex
	end,
	set = function(i: number)
		if toolbox then
			toolbox.stop()
		end
		heldAbility = nil
		weaponVisual.bowDrawAt = nil
		if player.Character then player.Character:SetAttribute("LocalBowDrawAt", nil) end
		weaponIndex = i
		lastWeaponUse = 0
		recoil, ads, knifeT = 0, 0, 0
		hands.left.t, hands.right.t = 1, 1
		nextHand = "right"
		weaponVisual.sway:reset()
		weaponVisual.recoil:reset()
		weaponVisual.lastAction, weaponVisual.lastCooldown = "", nil
		equipRemote:FireServer(Weapons[weaponIndex].id)
		-- Coalesce quick wheel scrolling; the final selected weapon always reaches the server.
		weaponVisual.equipToken += 1
		local token = weaponVisual.equipToken
		task.delay(0.1, function()
			if token == weaponVisual.equipToken then equipRemote:FireServer(Weapons[weaponIndex].id) end
		end)
	end,
	cooldown = function(): number
		if heldAbility then
			return math.clamp((heldAbility.readyAt - os.clock()) / heldAbility.cd, 0, 1)
		end
		local cd = weaponVisual.lastCooldown or Weapons[weaponIndex].cd
		if not cd then
			return 0
		end
		return math.clamp(1 - (os.clock() - lastWeaponUse) / cd, 0, 1)
	end,
	blocked = function(): boolean
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return Menu.active or not hum or hum.Health <= 0
	end,
	building = function(): boolean -- BUILD on (Toolbox): the weapon keys are the build bar's
		return toolbox ~= nil and toolbox.building()
	end,
	scrollable = function(): boolean
		return holding == nil
	end,
	-- the special attacks: their own page of the wheel, and onto the hotbar like a weapon; taking
	-- one puts the fists in hand with the hands glowing its colour, and a click casts it
	attacks = Attacks,
	held = function()
		return heldAbility
	end,
	ability = function(attack) -- WeaponBar puts the fists (Weapons[1]) in hand first
		if toolbox then
			toolbox.stop()
		end
		heldAbility = attack
	end,
	-- F: true when it grabbed a dummy to drag (or let go of one), so F does not also change weapon
	drag = function(): boolean
		return toggleDrag()
	end,
	-- While the wheel is open the mouse picks a weapon, so the view must not turn; it still rides
	-- along with the body (the camera keeps its offset from the root and its direction).
	freeze = function(on: boolean)
		RunService:UnbindFromRenderStep("WheelCamera")
		if not on then
			camera.CameraType = Enum.CameraType.Custom
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local held = camera.CFrame
		local from = root.Position
		RunService:BindToRenderStep("WheelCamera", Enum.RenderPriority.Camera.Value + 2, function()
			if root.Parent then
				camera.CFrame = held + (root.Position - from)
			end
		end)
	end,
}
require(script:WaitForChild("WeaponBar")).start(gui, Weapons, VIEWMODELS, {
	{ BALL, Vector3.one * 0.9, CFrame.identity, SKIN },
	{ BLOCK, Vector3.new(0.5, 0.5, 1.4), CFrame.new(0, 0, 0.9), SKIN },
}, barApi)
toolbox = require(script:WaitForChild("Toolbox")).start(gui, actionRemote, barApi, aim)
require(script:WaitForChild("TouchControls")).start(mv, dummyFolder, function(): boolean
	return aiming
end)

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
		if dummyOf(result.Instance) then
			Sfx.playLocal(Sfx.PUNCH, result.Position) -- ponytail: a dodged punch still smacks for us
		end
	end
end

-- Third-person attack: the foot lands in front of the body, wherever the camera points.
local function kick()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if os.clock() - lastKick < KICK_INTERVAL or not root or not kickTrack then
		return
	end
	lastKick = os.clock()
	polished.kickToken += 1
	local token = polished.kickToken
	local running = sprint > 0.5 or mv.sliding -- a kick out of a slide hits like the running one
	local fired = false
	local markerConnection, stoppedConnection
	local function disconnect()
		if markerConnection then markerConnection:Disconnect() end
		if stoppedConnection then stoppedConnection:Disconnect() end
	end
	local function impact()
		if fired then return end
		fired = true
		disconnect()
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if token ~= polished.kickToken or player.Character ~= character or not root.Parent
			or not humanoid or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") then
			return
		end
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
			if dummyOf(best) then
				Sfx.playLocal(Sfx.PUNCH, best.Position)
			end
		end
	end
	markerConnection = kickTrack:GetMarkerReachedSignal("Hit"):Connect(impact)
	stoppedConnection = kickTrack.Stopped:Connect(function()
		fired = true
		disconnect()
	end)
	kickTrack:Play(0.05)
	if sounds.Kick then sounds.Kick:Play() end
	moveRemote:FireServer("shot", "kick")
	-- Old uploaded clips do not have a Hit marker; the same authored impact
	-- timestamp is their fallback. The fired flag prevents double damage.
	task.delay(polished.clips.impactTime("HighKick") + 1 / 30, impact)
	task.delay(KICK_INTERVAL + 0.1, disconnect)
end

-- Let go. The body stays ours to simulate until it lies still (server: release), so the throw and
-- the grab's end happen here at once, with no wait for the server and no snap back to its copy.
local loose = nil -- { body, impact, untilTime }: a body we let go of and still simulate
local function drop(velocity: Vector3)
	grabRemote:FireServer("release", velocity)
	local body = holding and dummyOf(holding.part)
	if holding and holding.raking then
		grabRemote:FireServer("rake", false)
	end
	if body then
		local grab = holding.part:FindFirstChild("GrabAttachment")
		if grab then
			grab:Destroy() -- the server removes it too; until that arrives it would hold the body back
		end
		if velocity.Magnitude > 0 then
			for _, part in body:GetDescendants() do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = velocity
				end
			end
		end
		loose = { body = body, impact = holding.impact, untilTime = os.clock() + 4 } -- server LOOSE_MAX
	end
	holding = nil
end

-- M: back to the menu. The server takes the character off the map ("menu") and Menu.reopen builds the
-- menu again; PLAY from there goes back in like the first time.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.M or Menu.active or gui:GetAttribute("WeaponPickerOpen")
		or UserInputService:GetFocusedTextBox() then
		return
	end
	if holding then
		drop(Vector3.zero)
	end
	actionRemote:FireServer("menu")
	Menu.reopen()
end)

local function toggleGrab()
	if holding then
		drop(Vector3.zero)
		return
	end
	local result = aim(GRAB_RANGE)
	if result and dummyOf(result.Instance) then
		grabRemote:FireServer("grab", result.Instance)
		loose = nil -- caught: whatever we were still simulating, the hold reports from here on
		local head = player.Character and player.Character:FindFirstChild("Head")
		local dist = head and (result.Position - head.Position).Magnitude or 5
		holding = { part = result.Instance, dist = math.clamp(dist, 3, 8), since = os.clock(), impact = Impact.new() }
	end
end

-- F on a dummy you are looking at: take it by the chest in one hand and hold it at your side;
-- sprint and you bend over and grind it into the ground (the per-frame block). F again lets go.
-- False when F was not for this (no dummy in reach), so it changes weapon as usual.
function toggleDrag(): boolean
	if holding then
		if not holding.drag then
			return false
		end
		drop(Vector3.zero)
		return true
	end
	local result = aim(GRAB_RANGE)
	local body = result and dummyOf(result.Instance)
	local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
	if not body or not head then
		return false
	end
	-- by the chest, like grabbing the collar (the legs trail behind); the part looked at if the
	-- chest is out of reach
	local chest = body:FindFirstChild("UpperTorso") :: BasePart?
	local part = if chest and (chest.Position - head.Position).Magnitude < GRAB_RANGE + DRAG_CHEST_REACH then chest else result.Instance
	grabRemote:FireServer("grab", part, "drag")
	loose = nil
	holding = { part = part, dist = 0, since = os.clock(), impact = Impact.new(), drag = true, rake = 0 }
	return true
end

-- Held with F, looking ahead, one click: the punt. You turn to where you look, swing it back, heave it
-- up over your head and front-kick it away as it drops (the body's path: the per-frame block). At
-- the kick the server hears "punt" first (the blow, and the mark that makes its landing hit harder),
-- then the usual release with the kick's speed.
-- Raking: the furrow is laid here, where the body is this frame (we simulate it), so it opens right
-- under it; waiting for the server's copy left it trailing. The server lays it for everyone else.
-- Same stretches as the server's (Fx "Furrow"): from the last point, joined, a new start after a gap.
local FURROW_EVERY, FURROW_MIN_SPEED = 0.05, 2
local furrowParams = RaycastParams.new()
furrowParams.FilterType = Enum.RaycastFilterType.Exclude
local function furrowStep(held, char: Model)
	local now = os.clock()
	if now < (held.nextFurrow or 0) then
		return
	end
	local body = dummyOf(held.part)
	local torso = body and body:FindFirstChild("UpperTorso") :: BasePart?
	if not torso then
		return
	end
	held.nextFurrow = now + FURROW_EVERY
	local last, lastAt = held.furrowFrom, held.furrowFromAt
	held.furrowFrom, held.furrowFromAt = torso.Position, now
	if not last or now - lastAt > 0.3 then
		return
	end
	local velocity = (torso.Position - last) * XZ / (now - lastAt)
	if velocity.Magnitude < FURROW_MIN_SPEED then
		return
	end
	furrowParams.FilterDescendantsInstances = { body, char }
	local floor = workspace:Raycast(torso.Position, Vector3.yAxis * -3.5, furrowParams)
	if not floor or dummyOf(floor.Instance) then
		held.furrowAt = nil
		return
	end
	local from = held.furrowAt
	if not from or (from - floor.Position).Magnitude > 5 then
		from = floor.Position - velocity.Unit * 0.6
	end
	held.furrowAt = floor.Position
	Fx.play("Furrow", nil, from, floor.Position, floor.Normal, velocity.Magnitude)
end

local function startPunt()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not holding or not root then
		return
	end
	local start = os.clock()
	holding.punt, holding.digHeld = start, false
	puntUntil = start + PUNT_LENGTH
	local look = camera.CFrame.LookVector * XZ
	look = look.Magnitude > 0.1 and look.Unit or root.CFrame.LookVector
	root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	if dragTracks.punt then
		dragTracks.punt:Play(0.08)
	end
	task.delay(PUNT_KICK, function()
		if not holding or holding.punt ~= start then
			return -- let go or lost it on the way
		end
		local aimed = camera.CFrame.LookVector
		local dir = ((aimed * XZ).Magnitude > 0.1 and (aimed * XZ).Unit or look) * PUNT_SPEED + Vector3.yAxis * (PUNT_LIFT + math.max(aimed.Y, 0) * PUNT_SPEED)
		grabRemote:FireServer("punt", dir)
		if sounds.Kick then
			sounds.Kick:Play()
		end
		drop(dir)
		if loose then
			loose.punt = os.clock() -- its first hit is the punt's landing (see below)
		end
	end)
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
	if mv.cut.slam then
		return false
	end
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
			polished.diveToken += 1
			local token = polished.diveToken
			polished.play("diveEnter", 0.035)
			moveRemote:FireServer("shot", "diveEnter")
			task.delay(0.18, function()
				if slamming and player.Character == char and token == polished.diveToken then
					diveTrack:Play(0.08)
				end
			end)
		end
	end
	return true
end

-- mv.began / mv.ended: also pressed by the touch buttons (TouchControls) with a stand-in input
mv.began = function(input, processed)
	if processed or Menu.active or gui:GetAttribute("WeaponPickerOpen") then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		local seated = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if seated and seated.SeatPart then
			return -- in a vehicle: no swing (its lunge shoved the welded vehicle); the tank's gun is client/TankClient
		end
		if os.clock() < puntUntil then
			return -- mid-punt: no swing, shot or throw until the kick is done
		end
		if holding and holding.drag then
			if holding.punt then
				return -- already on its way
			elseif camera.CFrame.LookVector.Y < RAKE_LOOK then
				holding.digHeld = true -- held in one hand, looking down: rake it through the ground while held
			else
				startPunt()
			end
			return
		end
		if holding then
			drop(camera.CFrame.LookVector * THROW_SPEED)
			return
		end
		if toolbox.click() then
			return -- a block picked in the toolbox: the click builds (or deletes)
		end
		if heldAbility then
			castAbility(heldAbility)
			return
		end
		punching = true
		local weapon = Weapons[weaponIndex]
		if weapon.kind == "bow" then
			weaponVisual.bowDrawAt = os.clock()
			if player.Character then player.Character:SetAttribute("LocalBowDrawAt", workspace:GetServerTimeNow()) end
			if sounds.BowDraw then sounds.BowDraw:Play() end
			actionRemote:FireServer("bowDraw")
			return
		end
		if weapon.aimSwing then -- the swing comes on release (InputEnded); meanwhile the mouse draws it
			-- a quick click is a plain swing: the circle (and the slowed camera) only come up once the
			-- button has been held for swingUi.HOLD; until then the mouse turns the camera as usual
			local aim = { weapon = weapon, x = 0, y = 0, shown = false }
			swingUi.aim = aim
			task.delay(swingUi.HOLD, function()
				if swingUi.aim ~= aim then return end -- let go already
				aim.shown = true
				swingUi.draw()
				swingUi.holdCamera(true)
			end)
			-- reads the mouse/stick for the line; the camera barely turns meanwhile (holdCamera), so the
			-- crosshair stays on what you aimed at
			ContextActionService:BindActionAtPriority("SwingAim", function(_, _, inp)
				local a = swingUi.aim
				if not a then return Enum.ContextActionResult.Pass end
				-- counted from the press, not from when the circle shows: a line drawn straight away is
				-- already there when it comes up (a release before that is still a plain swing, mv.ended)
				if inp.UserInputType == Enum.UserInputType.MouseMovement then
					swingUi.move(inp.Delta.X, inp.Delta.Y)
				else -- right stick: where it points is the line
					a.x, a.y = 0, 0
					swingUi.move(inp.Position.X * swingUi.R, -inp.Position.Y * swingUi.R)
				end
				return Enum.ContextActionResult.Pass -- on to the camera, slowed by holdCamera
			end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseMovement, Enum.KeyCode.Thumbstick2)
			return
		end
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
				useWeapon(weapon) -- with the block up the gloves throw the heavy left instead (useWeapon)
			end
			task.wait((weapon.slash and not aiming and weapon.slash.cd) or weapon.cd or PUNCH_INTERVAL)
			if weapon.kind and (not weapon.auto or (weapon.heavy and aiming)) then
				break -- one use per click (and one heavy left per click out of the block)
			end
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		aiming = true
		if Weapons[weaponIndex].id == "C4" and (player:GetAttribute("C4Out") or 0) > 0 and not Menu.active then
			useWeapon(Weapons[weaponIndex], nil, true) -- the remote in the left hand: every charge goes off
		end
		if Weapons[weaponIndex].id == "Lasso" and not Menu.active then
			actionRemote:FireServer("lassoCut") -- lets go of the dummy caught last
		end
	elseif input.KeyCode == Enum.KeyCode.Y or input.KeyCode == Enum.KeyCode.DPadUp then
		local weapon = Weapons[weaponIndex]
		if (HOLD[weapon.id] or weapon.id == "BoxingGloves") and isFirstPerson() and not holding then
			inspect = { id = weapon.id, at = os.clock() }
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		toggleGrab()
	elseif input.KeyCode == Enum.KeyCode.C then
		actionRemote:FireServer("fall")
	elseif input.KeyCode == Enum.KeyCode.G then
		toolbox.use()
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
	elseif input.KeyCode == Enum.KeyCode.O then
		mv.freeCursor = not mv.freeCursor -- third person: a free cursor (MoveCamera, the mouse icon below)
	elseif input.KeyCode == Enum.KeyCode.V then
		-- only V changes the view: third person is held at one distance, so the mouse wheel
		-- (weapon bar, held body) never zooms the camera
		if player.CameraMode == Enum.CameraMode.LockFirstPerson then
			player.CameraMaxZoomDistance = THIRD_PERSON_DIST
			player.CameraMinZoomDistance = THIRD_PERSON_DIST
			player.CameraMode = Enum.CameraMode.Classic
		else
			player.CameraMode = Enum.CameraMode.LockFirstPerson
			player.CameraMinZoomDistance = 0.5
		end
	end
end
UserInputService.InputBegan:Connect(mv.began)

mv.ended = function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		punching = false
		if swingUi.aim then
			-- let go before the circle came up: a plain click, whatever the mouse did meanwhile
			local weapon = swingUi.aim.weapon
			local swing = if swingUi.aim.shown then swingUi.value() else Vector3.new(0, 0, 0.5)
			swingUi.aim = nil
			swingUi.draw()
			ContextActionService:UnbindAction("SwingAim")
			swingUi.holdCamera(false)
			if Weapons[weaponIndex] == weapon and not Menu.active and not holding then useWeapon(weapon, swing) end
		end
		if weaponVisual.bowDrawAt then
			local elapsed = os.clock() - weaponVisual.bowDrawAt
			weaponVisual.bowDrawAt = nil
			if sounds.BowDraw then sounds.BowDraw:Stop() end
			if player.Character then player.Character:SetAttribute("LocalBowDrawAt", nil) end
			if Weapons[weaponIndex].kind == "bow" and not Menu.active and elapsed >= 0.1 then useWeapon(Weapons[weaponIndex])
			else actionRemote:FireServer("bowCancel") end
		end
		if holding then
			holding.digHeld = false
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		aiming = false
	end
end
UserInputService.InputEnded:Connect(mv.ended)

UserInputService.InputChanged:Connect(function(input)
	if holding and input.UserInputType == Enum.UserInputType.MouseWheel then
		holding.dist = math.clamp(holding.dist + input.Position.Z, 3, 16)
	end
end)

fxRemote.OnClientEvent:Connect(Fx.play)
require(script:WaitForChild("MythPresentation")).start(gui, remotes, {
	weapon = function() return Weapons[weaponIndex] end,
})
-- Sky light (environment diffuse/specular) is not blocked by the factory roof and floods the
-- inside, so switch it off in there and let the lamps plus a little ambient do the work.
local Lighting = game:GetService("Lighting")
local OUTSIDE = { Ambient = Lighting.Ambient, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale, EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale }
local INSIDE = { Ambient = Color3.fromRGB(20, 20, 20), EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0 }
player:GetAttributeChangedSignal("Map"):Connect(function()
	local inside = player:GetAttribute("Map") == "FACTORY"
	for prop, value in inside and INSIDE or OUTSIDE do
		Lighting[prop] = value
	end
	-- the lamps light the hall's yellow (deck edges, rails, the crane) past the bloom threshold and
	-- it glowed like neon: inside, only what is really bright (lava, fire, lamps' cores) blooms
	for _, bloom in Lighting:GetChildren() do
		if bloom:IsA("BloomEffect") then
			if bloom:GetAttribute("OutsideThreshold") == nil then
				bloom:SetAttribute("OutsideThreshold", bloom.Threshold)
			end
			bloom.Threshold = if inside then 4 else bloom:GetAttribute("OutsideThreshold")
		end
	end
end)
remotes:WaitForChild("Hazard").OnClientEvent:Connect(function(velocity: Vector3, boost: boolean?)
	-- a factory machine hit us; we own our physics, so the server cannot fling us itself.
	-- `boost` (a rocket jump): kept like a double jump's speed, against air control (carry)
	local char = player.Character
	if boost then
		local horizontal = velocity * XZ -- the speed you already had along it is kept if it is more
		carry = if horizontal.Magnitude > 0.01 then horizontal.Unit * math.max(horizontal.Magnitude, carry.Magnitude) else Vector3.zero
		velocity = carry + Vector3.yAxis * velocity.Y
		mv.airJumpUsed = false -- one more jump in the air after it
	end
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
	weaponVisual.sway:reset()
	weaponVisual.recoil:reset()
	weaponVisual.lastAction, weaponVisual.lastCooldown = "", nil
	hands.left.t, hands.right.t = 1, 1
	recoil, ads, knifeT = 0, 0, 0
	nextHand = "right"
	polished.diveToken += 1
	polished.kickToken += 1
	polished.sliding = false
	polished.tracks = {}
	mv.baseHip = humanoid.HipHeight
	for name, animation in polished.anims do
		local track = humanoid:WaitForChild("Animator"):LoadAnimation(animation)
		track.Priority = (name == "slideEnter" or name == "slideExit")
			and Enum.AnimationPriority.Action2 or Enum.AnimationPriority.Action4
		track.Looped = false
		polished.tracks[name] = track
	end
	for name, id in SFX do
		local sound = Instance.new("Sound")
		sound.Name = name .. "Sfx"
		sound.SoundId = if id and id ~= "" then "rbxassetid://" .. id else ""
		sound.Looped = name == "Run" or name == "Walk"
		sound.Volume = if name == "Walk" then 0.3 elseif name == "Run" then 0.4 else 0.7
		Sfx.prepare(sound)
		sound.Parent = root
		sounds[name] = sound
	end
	-- Roblox's own footsteps and landing would double ours (Walk, Land): muted on this character
	local function muteDefault(s: Instance)
		if s:IsA("Sound") and (s.Name == "Running" or s.Name == "Landing") then
			s.Volume = 0
		end
	end
	for _, s in root:GetChildren() do
		muteDefault(s)
	end
	root.ChildAdded:Connect(muteDefault)
	sprintTrack = humanoid:WaitForChild("Animator"):LoadAnimation(sprintAnim)
	sprintTrack.Priority = Enum.AnimationPriority.Movement -- over the default run (Core)
	sprintTrack.Looped = true
	for _, marker in { "StepLeft", "StepRight" } do
		sprintTrack:GetMarkerReachedSignal(marker):Connect(function()
			if player.Character ~= char or humanoid.FloorMaterial == Enum.Material.Air
				or mv.low or char:GetAttribute("Ragdolled") then return end
			local foot = char:FindFirstChild(marker == "StepLeft" and "LeftFoot" or "RightFoot")
			if foot then Fx.dust(foot.Position - Vector3.yAxis * foot.Size.Y / 2, 3, 2, 0.6) end
		end)
	end
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
	for kind, anim in dragAnims do
		local track = humanoid.Animator:LoadAnimation(anim)
		track.Priority = Enum.AnimationPriority.Action2 -- over the walk and the sprint cycle
		track.Looped = kind ~= "punt"
		if kind == "punt" then
			track.Priority = Enum.AnimationPriority.Action4 -- the whole body, over everything
		end
		dragTracks[kind] = track
	end
	for name, anim in weaponVisual.anims do -- WeaponAnims: a use plays once, a hold loops
		weaponVisual.animTracks[name] = humanoid.Animator:LoadAnimation(anim)
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
			equipRemote:FireServer(Weapons[weaponIndex].id)
		end
	end)
	char:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if char:GetAttribute("Ragdolled") then
			polished.kickToken += 1
			polished.diveToken += 1
			slamming = false
			for _, track in polished.tracks do track:Stop(0.05) end
			for _, track in lowTracks do track:Stop(0.05) end
			if kickTrack then kickTrack:Stop(0.05) end
			if diveTrack then diveTrack:Stop(0.05) end
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
	polished.play("mantle", 0.045, polished.clips.length("Mantle") / time)
	moveRemote:FireServer("shot", speed > 0 and "vault" or "mantle")
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
	if humanoid.SeatPart then -- in a vehicle the root is welded to it: none of this may push it (the tank flew off)
		hold(root, nil)
		wall, mantle, carry = nil, nil, Vector3.zero
		return
	end
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
		local phase = t < 0.6 and t / 0.6 or (t - 0.6) / 0.4
		local eased = phase * phase * (3 - 2 * phase)
		local p = t < 0.6 and mantle.from:Lerp(mantle.over, eased) or mantle.over:Lerp(mantle.to, eased)
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
	if mv.simple() then -- easy touch controls: no wall runs, clings or vaults
		wall = nil
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
	if forward and (not grounded or (sprint > 0.5 and not mv.cut.vault)) then
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
		polished.diveToken += 1
		if polished.tracks.diveEnter then polished.tracks.diveEnter:Stop(0.04) end
		airPeak = nil -- the slam replaces the landing roll
		if able then
			hands.left.t, hands.right.t = 0, 0 -- both fists into the ground
			actionRemote:FireServer("slam", fallSpeed * MOVE.SLAM_POWER)
			sounds.Slam:Play()
			moveRemote:FireServer("shot", "slam")
			polished.play("slam", 0.025)
		end
		return
	end
	if airPeak and fallSpeed > 18 then -- feet down: a soft step, or a heavy one after a long drop
		local s = if fallSpeed > 55 then sounds.LandHard else sounds.Land
		if s then
			s:Play()
		end
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

-- Strength of the movement juice (FOV kick, flash, shake, speed lines); calibration knob, 1 = old full strength
local MOVE_FX = 0.5

local function jolt(fov: number, flashAmount: number)
	fov, flashAmount = fov * MOVE_FX, flashAmount * MOVE_FX
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
	for _ = 1, math.round(10 * power * MOVE_FX) do
		Fx.speedLine()
	end
	Fx.dust(feet, 5, 3, 0.8)
	Fx.shake(root.Position, 0.5 * power * MOVE_FX, 0.25)
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
	if not (root and humanoid) or humanoid.Health <= 0 or char:GetAttribute("Ragdolled") or mantle or slamming
		or mv.simple() then -- easy touch controls: the plain jump only (no double jump, no ledge leap)
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
		Fx.shake(root.Position, 0.35 * MOVE_FX, 0.2)
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
	if mv.cut.flip then
		return
	end
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
	weaponVisual.flipAt = now
	if flipTrack then
		flipTrack:Play(0.05)
	end
	local foot = root.Position - normal * 1.2 - Vector3.yAxis * 1.5 -- where the foot hits the wall
	Fx.ring(CFrame.fromMatrix(foot, normal:Cross(Vector3.yAxis), normal), 1, 9, 0.35, AIR, { thick = 0.6 }) -- flat on the wall, like the wall jump's
	Fx.sparks(foot, 12, 7, AIR, normal)
	Fx.dust(foot, 4, 2, 0.7)
	Fx.shake(root.Position, 0.4 * MOVE_FX, 0.2)
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
	if wall and wall.clinging and not mv.cut.flip then
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
	if sounds.Dash then
		sounds.Dash:Play()
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
	for _ = 1, math.round(12 * MOVE_FX) do
		Fx.speedLine()
	end
	Fx.shake(root.Position, 0.25 * MOVE_FX, 0.12)
	jolt(22, 0.55)
	zap()
end

-- Slide and crouch -----------------------------------------------------------------
-- Ctrl lowers you (the Humanoid's HipHeight comes down, so you fit under things). Going fast
-- enough when it does, it is a slide: your speed, plus a boost, carried along the ground with
-- little drag until it runs out; jumping out of it keeps the speed. Otherwise it is a crouch.
-- Holding Ctrl through a landing slides out of the fall. You stay down under a low ceiling.
function mv.updateLow(humanoid: Humanoid, root: BasePart, grounded: boolean, able: boolean, dt: number)
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
	mv.low = low
	local targetHeight = mv.baseHip - (low and MOVE.LOW_DROP or 0)
	humanoid.HipHeight += (targetHeight - humanoid.HipHeight) * (1 - math.exp(-22 * dt))
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
	for _ = 1, math.round(8 * MOVE_FX) do
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
RunService:BindToRenderStep("MoveCameraRestore", Enum.RenderPriority.Camera.Value - 1, function(dt)
	if cleanCamera and camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CFrame = cleanCamera
	end
	cleanCamera = nil
	if mv.magnet and camera.CameraType ~= Enum.CameraType.Scriptable then
		mv.magnet(dt) -- easy touch controls: the view drifts onto a target near the crosshair (TouchControls)
	end
end)
RunService:BindToRenderStep("MoveCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local free = mv.freeCursor and not isFirstPerson() -- O in third person
	if gui:GetAttribute("WeaponPickerOpen") or free then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	elseif thirdWeapon then -- after the camera scripts, which would set their own mouse behaviour
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	elseif mouseLocked and not isFirstPerson() then -- weapon put away: free the mouse again
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	mouseLocked = thirdWeapon and not free
	local target = 0
	if wall then
		-- head away from the wall, as the third-person body leans (WallRun); +Z tips it left
		target = math.rad(14) * (wall.normal:Dot(camera.CFrame.RightVector) > 0 and -1 or 1)
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
	local punting = PUNT_LENGTH - (puntUntil - os.clock())
	if punting < PUNT_LENGTH and isFirstPerson() then
		-- the punt from your own eyes: follow it up overhead, down into the kick, back level...
		local function ease(a: number): number
			a = math.clamp(a, 0, 1)
			return a * a * (3 - 2 * a)
		end
		local look = if punting < PUNT_RELEASE then PUNT_LOOK_UP * ease(punting / PUNT_RELEASE)
			elseif punting < PUNT_KICK then PUNT_LOOK_UP + (PUNT_LOOK_DOWN - PUNT_LOOK_UP) * ease((punting - PUNT_RELEASE) / (PUNT_KICK - PUNT_RELEASE))
			else PUNT_LOOK_DOWN * (1 - ease((punting - PUNT_KICK) / (PUNT_LENGTH - PUNT_KICK)))
		-- ...the eye drawn back and up out of your own body for it, so the whole kicking leg and the dummy
		-- are in view rather than the inside of your hip...
		local back = if punting < PUNT_RELEASE then ease(punting / PUNT_RELEASE)
			elseif punting < PUNT_KICK + 0.12 then 1
			else 1 - ease((punting - PUNT_KICK - 0.12) / (PUNT_LENGTH - PUNT_KICK - 0.12))
		cf *= CFrame.new(0, PUNT_EYE.Y * back, PUNT_EYE.Z * back) * CFrame.Angles(math.rad(look), 0, 0)
		-- ...with your legs drawn (the camera hides the whole body in first person), so you see the kick
		local char = player.Character
		for _, name in PUNT_SHOWN do
			local part = char and char:FindFirstChild(name) :: BasePart?
			if part then
				part.LocalTransparencyModifier = 0
			end
		end
	end
	if cf ~= camera.CFrame then
		cleanCamera = camera.CFrame
		camera.CFrame = cf
	end

	-- screen edges and FOV (applied by Fx through fovBoost in the sprint block)
	wallGlow += ((wall and 1 or 0) - wallGlow) * math.min(dt * 8, 1)
	flash *= math.exp(-dt * 6)
	fovKick *= math.exp(-dt * 4)
	moveFov = wallGlow * 12 * MOVE_FX + fovKick
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

-- `to`, or as far toward it from `from` as a ball of `radius` gets before it touches something
-- (bodies and loose debris aside): where a held body can be pulled without going into the wall.
local clearParams = RaycastParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Exclude
clearParams.RespectCanCollide = true
local function clearOf(from: Vector3, to: Vector3, radius: number, char: Model): Vector3
	local way = to - from
	if way.Magnitude < 0.05 then
		return to
	end
	clearParams.FilterDescendantsInstances = { char, dummyFolder }
	clearParams.CollisionGroup = "Debris" -- passes through loose cubes (Debris does not hit Debris), stops on the rest
	local hit = workspace:Spherecast(from, radius, way, clearParams)
	return hit and from + way.Unit * hit.Distance or to
end
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head") :: BasePart?

	-- drive the held body part (we own its physics while holding)
	if holding then
		local align = holding.part:FindFirstChild("GrabAlign", true) :: AlignPosition?
		local dragRoot = holding.drag and char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if align and dragRoot and humanoid then
			-- gripped by the clothes at the collar (the server put the grab attachment there) and held
			-- rigid in the fist: the collar goes where the fist is this frame, the chest is turned the way
			-- you hold it, and only the limbs flop. Leaning back off the fist with the heels dragging
			-- (DRAG_TILT); raking, laid back further so it ploughs on its back (RAKE_TILT).
			-- looking a little down with the mouse held: raking it through the ground (a furrow, server)
			local raking = holding.digHeld == true and not holding.punt and camera.CFrame.LookVector.Y < RAKE_LOOK
			if raking ~= (holding.raking or false) then
				holding.raking = raking
				grabRemote:FireServer("rake", raking)
			end
			if raking then
				furrowStep(holding, char)
			else
				holding.furrowAt, holding.furrowFrom = nil, nil
			end
			holding.rake = (holding.rake or 0) + ((raking and 1 or 0) - (holding.rake or 0)) * math.min(dt * 7, 1)
			local look = dragRoot.CFrame.LookVector * XZ
			look = look.Magnitude > 0.1 and look.Unit or Vector3.zAxis
			local right = look:Cross(Vector3.yAxis)
			local hand = char:FindFirstChild("RightHand") :: BasePart?
			local target = hand and (hand.CFrame * DRAG_FIST).Position
				or Vector3.new(dragRoot.Position.X, dragRoot.Position.Y + DRAG_HOLD.Y, dragRoot.Position.Z) + right * DRAG_HOLD.X - look * DRAG_HOLD.Z
			local tilt = math.rad(DRAG_TILT + (RAKE_TILT - DRAG_TILT) * holding.rake)
			local up = Vector3.yAxis * math.cos(tilt) + look * math.sin(tilt) -- head leaning forward, toward the fist
			local front = Vector3.yAxis * math.sin(tilt) - look * math.cos(tilt) -- face up and back
			local turn = holding.part:FindFirstChild("GrabTurn", true) :: AlignOrientation?
			if turn then
				turn.CFrame = CFrame.fromMatrix(Vector3.zero, up:Cross(-front), up, -front)
			end
			local punting = holding.punt and os.clock() - holding.punt
			if punting and hand then
				local flat = CFrame.lookAt(dragRoot.Position, dragRoot.Position + look)
				if punting < PUNT_RELEASE then
					holding.puntFrom = target -- swung back and up in the fist
				else
					-- thrown up over your head, dropping into the kick: a curve from where it left the hand
					-- through over your head to the foot, turning over freely
					if turn then
						turn.Enabled = false
					end
					local s = math.clamp((punting - PUNT_RELEASE) / (PUNT_KICK - PUNT_RELEASE), 0, 1)
					local from = holding.puntFrom or target
					local over = flat:PointToWorldSpace(PUNT_APEX + Vector3.yAxis * 1.5)
					local foot = flat:PointToWorldSpace(PUNT_FOOT)
					target = from * (1 - s) ^ 2 + over * (2 * s * (1 - s)) + foot * s ^ 2
				end
			end
			-- never below the ground actually under it: the grip is strong enough to push a body
			-- through a thin floor (or the edge of a wall) and lose it under the map
			bounceParams.FilterDescendantsInstances = { char, dummyFolder }
			local ground = workspace:Raycast(target + Vector3.yAxis * 3, Vector3.yAxis * -8, bounceParams)
			if ground and not punting then
				target = Vector3.new(target.X, math.max(target.Y, ground.Position.Y + DRAG_COLLAR_MIN), target.Z)
			end
			-- and not into a wall: it stops against it and slides along, instead of being forced in
			if not punting then
				target = clearOf(dragRoot.Position + Vector3.yAxis, target, 0.9, char)
			end
			align.Position = target
			local body = dummyOf(holding.part)
			local landed = body and Impact.step(holding.impact, body, dt)
			if landed and not punting and not raking then -- raking: one long scrape, not a thud a frame
				Sfx.playLocal(Sfx.THUD, landed.part.Position)
				grabRemote:FireServer("slam", landed.part, landed.lost, landed.dir)
			end
		elseif align and head then
			local _, ray = aim(0)
			-- held out in front: up against a wall or the floor it stops there and slides, instead of
			-- being shoved into it (and jammed, or out the other side)
			align.Position = clearOf(head.Position, head.Position + ray.Direction.Unit * holding.dist, 1, char)
			-- swung into the ground or a wall: we own this body, so we see the hit and report it
			local body = dummyOf(holding.part)
			local landed = body and Impact.step(holding.impact, body, dt)
			if landed then
				Sfx.playLocal(Sfx.THUD, landed.part.Position)
				grabRemote:FireServer("slam", landed.part, landed.lost, landed.dir)
			end
		elseif not holding.part.Parent or os.clock() - holding.since > 1 then
			holding = nil -- server let go (revive, despawn, rejected grab)
		end
	end
	-- a body we let go of: still ours until it rests, so its landings are ours to report
	if loose then
		-- just kicked: the launch itself (every limb's speed jumping) is no landing, or the punt's one
		-- hard hit would go off at your feet; it starts counting afresh once PUNT_ARM has passed
		local arming = loose.punt and os.clock() < loose.punt + PUNT_ARM
		if arming then
			loose.impact = Impact.new()
		end
		local landed = not arming and loose.body.Parent and os.clock() < loose.untilTime and Impact.step(loose.impact, loose.body, dt)
		-- kicked: what it flies into - a pillar, a wall, anything standing in its way, never the floor
		-- it skids along - is a hit. Looked for just ahead of the chest each frame, so it is caught
		-- going in: that spot breaks (server, at the point we saw: its copy of the body lags) and the
		-- body loses PUNT_KEEP of its speed as it ploughs through. PUNT_HITS such hits, PUNT_GAP apart.
		local now = os.clock()
		local punting = loose.punt and now < loose.punt + PUNT_TIME and (loose.puntHits or 0) < PUNT_HITS
		-- (from the kick on: at its speed it covers a wall's distance before any settling is over)
		local torso = punting and now > (loose.puntNext or 0)
			and loose.body:FindFirstChild("UpperTorso") :: BasePart?
		local v = torso and torso.AssemblyLinearVelocity
		if v and v.Magnitude > PUNT_MIN_SPEED then
			furrowParams.FilterDescendantsInstances = { loose.body, player.Character }
			local ahead = workspace:Raycast(torso.Position, v * (dt + PUNT_LOOKAHEAD) + v.Unit * PUNT_NEAR, furrowParams)			if ahead and math.abs(ahead.Normal.Y) < PUNT_WALL and not dummyOf(ahead.Instance) then
				landed = { part = torso, lost = Impact.SPEED + Impact.PER_POWER, dir = v.Unit, at = ahead.Position }
				loose.puntHits, loose.puntNext = (loose.puntHits or 0) + 1, now + PUNT_GAP
				for _, part in loose.body:GetDescendants() do
					if part:IsA("BasePart") then
						part.AssemblyLinearVelocity *= PUNT_KEEP
					end
				end
			end
		end
		if landed then
			Sfx.playLocal(Sfx.THUD, landed.part.Position)
			grabRemote:FireServer("slam", landed.part, landed.lost, landed.dir, landed.at)
		elseif not loose.body.Parent or os.clock() >= loose.untilTime then
			loose = nil
		end
	end

	gui.Enabled = not Menu.active

	-- fists
	-- holding one with F the arms still show: the left pumping as you run, the right reaching for
	-- the dummy's collar (see the fists loop)
	local dragView = (holding ~= nil and holding.drag == true) or os.clock() < puntUntil
	local show = isFirstPerson() and not Menu.active and (not holding or dragView) and humanoid and humanoid.Health > 0 and not (char and char:GetAttribute("Ragdolled"))
	local moving = humanoid and humanoid.MoveDirection.Magnitude > 0 and 1 or 0
	UserInputService.MouseIconEnabled = gui:GetAttribute("WeaponPickerOpen") == true or (not isFirstPerson() and (not thirdWeapon or mv.freeCursor == true))
	crosshair.Visible = isFirstPerson() or thirdWeapon

	-- sprint
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if moving == 0 then
		mv.sprintToggle = false
	end
	-- easy touch controls (mv.simple) always run; you can run dragging one
	local sprinting = (mv.sprintHeld or mv.sprintToggle or mv.simple()) and moving == 1 and (not holding or holding.drag) and root and not mv.low
		and humanoid.Health > 0 and not char:GetAttribute("Ragdolled")
	if humanoid then
		humanoid.WalkSpeed = ((holding and holding.punt and 4)
			or mv.low and MOVE.CROUCH_SPEED or sprinting and SPRINT_SPEED or WALK_SPEED)
			* (if player:GetAttribute("AdminFast") then 2 else 1) -- the admin panel's super speed
	end
	if humanoid and root and not Menu.active then
		local able = humanoid.Health > 0 and not char:GetAttribute("Ragdolled")
		updateWallRun(dt, char, humanoid, root)
		updateLanding(humanoid, root, able)
		mv.updateLow(humanoid, root, humanoid.FloorMaterial ~= Enum.Material.Air, able, dt)
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
	if polished.sliding ~= mv.sliding then
		polished.sliding = mv.sliding
		if humanoid and humanoid.Health > 0 and not char:GetAttribute("Ragdolled") then
			local transition = mv.sliding and "slideEnter" or "slideExit"
			if polished.tracks.slideEnter then polished.tracks.slideEnter:Stop(0.04) end
			if polished.tracks.slideExit then polished.tracks.slideExit:Stop(0.04) end
			polished.play(transition, 0.045)
			moveRemote:FireServer("shot", transition)
		end
	end
	for kind, track in lowTracks do
		local speed = root and (root.AssemblyLinearVelocity * XZ).Magnitude or 0
		local on = mv.low and (mv.sliding and kind == "slide"
			or not mv.sliding and kind == (speed > 0.5 and moving == 1 and "crouch"
				or lowTracks.crouchIdle and "crouchIdle" or "crouch"))
		if on ~= track.IsPlaying then
			if on then
				track:Play(0.12)
			else
				track:Stop(0.15)
			end
		end
	end
	if lowTracks.crouch then
		local speed = root and (root.AssemblyLinearVelocity * XZ).Magnitude or 0
		lowTracks.crouch:AdjustSpeed(moving == 0 and not lowTracks.crouchIdle and 0
			or math.clamp(speed / polished.clips.referenceSpeed("crouch"), 0.2, 2.4))
	end
	-- wall run: its own mirrored cycle for the wall's side, and no turning toward the camera
	if wall and slamming then -- getting onto a wall calls off an armed ground slam
		slamming = false
		polished.diveToken += 1
		if polished.tracks.diveEnter then polished.tracks.diveEnter:Stop(0.08) end
		if diveTrack then
			diveTrack:Stop(0.15)
		end
	end
	local clingNow = (wall ~= nil and wall.clinging == true) or (mantle ~= nil and not polished.tracks.mantle)
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
	thirdWeapon = (out.kind ~= nil or heldAbility ~= nil) and not isFirstPerson() and not holding and not Menu.active
		and humanoid ~= nil and humanoid.Health > 0 and not (char and char:GetAttribute("Ragdolled"))
		and humanoid.SeatPart == nil -- seated, the root is welded to the vehicle: turning it would turn (and tear) the vehicle
	if thirdWeapon and turnFree and root then -- face where the camera looks (shift-lock style)
		local look = (weaponVisual.testFace or camera.CFrame.LookVector) * Vector3.new(1, 0, 1) -- testFace: WeaponTest "face"
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
	-- a gun fired from the hip comes up into the aim pose for a moment (weaponVisual.hipAimUntil, useWeapon)
	weaponVisual.hipAim = thirdWeapon and out.kind == "gun" and os.clock() < (weaponVisual.hipAimUntil or 0)
	local pose = thirdWeapon and (aiming or weaponVisual.hipAim) and (out.kind == "gun" and "gun" or out.kind == "rocket" and "rocket"
		or (out.kind == "knife" or out.kind == "thrown") and "throw") or nil
	-- our crowbar's claw went into a shoulder (Fx.hookAt): the body heaves on it, then yanks the arm off
	if Fx.hookAt and Fx.hookAt ~= weaponVisual.hookSeen then
		weaponVisual.hookSeen = Fx.hookAt
		local rip = weaponVisual.animTracks.Rip_Crowbar
		if rip then
			rip:Play(0.05)
		end
	end
	-- the comic set's two-handed weapons are carried at the hip in both hands (WeaponAnims.HOLD)
	local holdClip = thirdWeapon and out.id and weaponVisual.lib.HOLD[out.id] or nil
	for name, track in weaponVisual.animTracks do
		if weaponVisual.lib.CLIPS[name][1] and (name == holdClip) ~= track.IsPlaying then
			if name == holdClip then
				track:Play(0.2)
			else
				track:Stop(0.2)
			end
		end
	end
	for kind, track in aimTracks do
		if (kind == pose) ~= track.IsPlaying then
			if kind == pose then
				track:Play(0.15)
			else
				track:Stop(0.2)
			end
		end
	end
	-- holding one with F: the "hold" pose, blended into "scrape" as you rake it; the punt plays on
	-- its own (to its end, after the body is gone)
	local gripping = holding and holding.drag and not holding.punt
	local rake = gripping and holding.rake or 0
	local weights = { hold = gripping and 1 - rake or 0, scrape = rake }
	if dragTracks.scrape and dragTracks.scrape.IsPlaying and root then
		-- the arm judders with the drag: faster the faster you run
		dragTracks.scrape:AdjustSpeed(math.clamp((root.AssemblyLinearVelocity * XZ).Magnitude / RAKE_SPEED, 0.3, 1.6))
	end
	for kind, track in dragTracks do
		if kind == "punt" then
			continue
		end
		local weight = weights[kind] or 0
		if weight > 0.02 then
			if not track.IsPlaying then
				track:Play(0.15, weight)
			end
			track:AdjustWeight(weight, 0.05)
		elseif track.IsPlaying then
			track:Stop(0.2)
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
	local walking = humanoid ~= nil and root ~= nil and not footsteps and humanoid.FloorMaterial ~= Enum.Material.Air
		and humanoid.MoveDirection.Magnitude > 0.1 and (root.AssemblyLinearVelocity * XZ).Magnitude > 3
	if sounds.Walk and walking ~= sounds.Walk.IsPlaying then
		if walking then
			sounds.Walk:Play()
		else
			sounds.Walk:Stop()
		end
	end
	if sprintTrack and running and not sprintTrack.IsPlaying then
		sprintTrack:Play(0.15)
	elseif sprintTrack and not running and sprintTrack.IsPlaying then
		sprintTrack:Stop(0.35) -- a slower fade reads as easing into the fall, not a snap
	end
	if sprintTrack and running and root then
		local speed = (root.AssemblyLinearVelocity * XZ).Magnitude
		sprintTrack:AdjustSpeed(math.clamp(speed / polished.clips.referenceSpeed("SprintFlail"), 0.5, 2.4))
	end
	sprint += ((sprinting and 1 or 0) - sprint) * math.min(dt * 8, 1)
	-- aiming down the sights: zoom in, slow the mouse; the sniper looks through its scope instead
	local held = Weapons[weaponIndex]
	local sniper = held.id == "Sniper"
	local wantAds = aiming and show and (held.kind == "gun" or held.kind == "rocket")
	ads += ((wantAds and 1 or 0) - ads) * math.min(dt * 14, 1)
	Fx.fovBoost = (14 * MOVE_FX * sprint + moveFov) * (1 - ads) - ads * (sniper and 52 or 22)
	-- the scope zooms ~4x, so it turns at a fifth; other sights a little slower; a drawn swing line slower still
	local adsSlow = 1 - ads * (sniper and 0.8 or 0.35)
	if swingUi.cameraScale(adsSlow * (swingUi.slow and swingUi.CAMERA_SLOW or 1)) then
		UserInputService.MouseDeltaSensitivity = 1
	else
		UserInputService.MouseDeltaSensitivity = adsSlow
	end
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
	local wantGuard = aiming and held.id == "BoxingGloves" and humanoid ~= nil and humanoid.Health > 0 and not holding
	if wantGuard ~= guarding then
		guarding = wantGuard
		actionRemote:FireServer("guard", wantGuard)
	end
	guardT += ((wantGuard and 1 or 0) - guardT) * math.min(dt * 14, 1)
	Fx.fovBoost -= 8 * knifeT
	local now = os.clock()
	-- tell the other clients what this body is doing, so they can show it too (see Others)
	local lowMoving = root and moving == 1 and (root.AssemblyLinearVelocity * XZ).Magnitude > 0.5
	local loop = mantle and "" or clingNow and "cling" or wallSide and "wall" .. wallSide or slamming and "dive"
		or mv.sliding and "slide" or mv.low and (lowMoving and "crouch"
			or lowTracks.crouchIdle and "crouchIdle" or "crouch") or running and "sprint" or ""
	if loop ~= mv.loop then
		mv.loop = loop
		moveRemote:FireServer("loop", loop)
	end
	-- movement HUD
	local airborne = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
	mv.hud.wallBack.Visible = wallLeft < WALL_TIME - 0.05
	mv.hud.wall.Size = UDim2.fromScale(math.clamp(wallLeft / WALL_TIME, 0, 1), 1)
	if (sprinting or wall or mv.sliding) and now > nextLine then
		nextLine = now + 0.03 / MOVE_FX
		Fx.speedLine()
	end

	local weapon = Weapons[weaponIndex]
	local hold = not dragView and HOLD[weapon.id] or nil -- holding one with F: no weapon in hand
	local viewCF = camera.CFrame * weaponVisual.sway:update(camera.CFrame, dt,
		show == true and camera.CameraType ~= Enum.CameraType.Scriptable, ads)
		* weaponVisual.bob:update(dt, show == true and root ~= nil, root and root.AssemblyLinearVelocity or Vector3.zero,
			not airborne, sprint, ads)
		* weaponVisual.recoil:update(dt, show == true)
	recoil = math.max(recoil - dt / 0.15, 0)
	local pose = inspect and Inspect.pose(inspect.id, now - inspect.at)
	if inspect and (not pose or inspect.id ~= weapon.id or punching or aiming or not show or knifeT > 0) then
		inspect, pose = nil, nil
	end
	if not (pose and pose.leftAt) then
		inspectLeft = nil
	end
	local inspectRot = pose and pose.rightRot or CFrame.identity
	local weaponCF = nil
	local fists = {} -- this frame's fist CFrames, for a piece handed to the left fist
	local gloveCFs = {} -- this frame's glove grip CFrames, placed after both are known
	-- wall run: the hand on the wall's side is planted flat on it (the near arm in WallRun).
	-- The last contact is kept in view space, so a hand easing off a wall you jump away from stays
	-- with you instead of stretching after it.
	local function contact(hit: RaycastResult)
		return { point = viewCF:PointToObjectSpace(hit.Position), normal = viewCF:VectorToObjectSpace(hit.Normal) }
	end
	local function world(c)
		return c and { side = c.side, point = viewCF * c.point, normal = viewCF:VectorToWorldSpace(c.normal) }
	end
	local touching = false
	if wall and not wall.clinging and show and not dragView then
		local hit = workspace:Raycast(viewCF.Position, -wall.normal * 4, wallParams)
		if hit then
			touching = true
			weaponVisual.wallHand = contact(hit)
			weaponVisual.wallHand.side = hit.Normal:Dot(viewCF.RightVector) > 0 and "left" or "right"
		end
	end
	local wallHand = world(weaponVisual.wallHand)
	weaponVisual.wallT = (weaponVisual.wallT or 0) + ((touching and 1 or 0) - (weaponVisual.wallT or 0)) * math.min(dt * 10, 1)
	-- hanging on a wall: both palms on it either side of the view (kept, like wallHand, to ease off)
	local holdingOn = false
	if wall and wall.clinging and show and not dragView then
		local hit = workspace:Raycast(viewCF.Position, -wall.normal * 4, wallParams)
		if hit then
			holdingOn = true
			weaponVisual.cling = contact(hit)
		end
	end
	local cling = world(weaponVisual.cling)
	weaponVisual.clingT = (weaponVisual.clingT or 0) + ((holdingOn and 1 or 0) - (weaponVisual.clingT or 0)) * math.min(dt * 10, 1)
	-- the kick off the wall (mv.wallFlip): 0 -> 1 over the flip, nil when not flipping
	local flipT = weaponVisual.flipAt and (now - weaponVisual.flipAt) / WALL_FLIP_TIME
	flipT = flipT and flipT < 1 and flipT or nil
	-- a jump: the hands swing up while you rise and come back down as it tops out (not on a wall,
	-- where the hands have their own poses, nor in the flip)
	local rise = root and airborne and not wall and not flipT and math.clamp(root.AssemblyLinearVelocity.Y / 12, 0, 1) or 0
	local jumpT = weaponVisual.jumpT or 0
	weaponVisual.jumpT = jumpT + (rise - jumpT) * math.min(dt * (rise > jumpT and 25 or 5), 1) -- snap up, settle slowly
	for side, h in hands do
		local viewTime = side == "right" and (SWING_STYLE[weapon.id] and SWING_STYLE[weapon.id].time
			or weaponVisual.lib.VIEW_TIME[weapon.id]) or nil -- its own pace (an aimed swing's style, else WeaponAnims)
		h.t = math.min(h.t + dt / (h.heavy and 0.34 or viewTime or 0.2), 1)
		if side == "right" and weaponVisual.freezeU then -- WeaponTest "freeze" (Studio): held at that point
			h.t = weaponVisual.freezeU
		end
		local ext = math.sin(h.t * math.pi)
		-- WeaponAnims.view: the comic set's own first-person moves; with a wrist angle it replaces the
		-- generic punch-swing for this hand (the hand goes where it says, not out with the punch)
		local special = side == "right" and hold and not dragView and weaponVisual.lib.view(weapon.id,
			weaponVisual.freezeU or weaponVisual.useId == weapon.id and (now - weaponVisual.useAt) / (viewTime or 0.2) or 1,
			punching, now, Fx.hookAt and now - Fx.hookAt or nil) or nil
		if special and special.tilt then
			ext = 0
		end
		local boxing = weapon.id == "BoxingGloves" and not dragView
		-- the block holds the gloves up, except the hand throwing the heavy left out of it
		local guard = guardT * (h.heavy and 1 - ext or 1)
		-- the right hand moves to where this weapon is held, and kicks back with recoil
		local move = (side == "right" and hold) and hold.hand or Vector3.zero
		if special and special.move then
			move += special.move
		end
		if dragView and side == "left" then
			-- the free arm pumps with your stride, as in any run
			local pump = math.sin(os.clock() * (8 + 6 * sprint)) * moving
			move += Vector3.new(0.05 * pump, 0.12 * pump, -0.55 * pump) * (0.4 + 0.6 * sprint)
		end
		if weapon.kind == "bow" and not dragView then
			local draw = weaponVisual.bowDrawAt and math.clamp((os.clock() - weaponVisual.bowDrawAt) / 1.1, 0, 1) or 0
			if side == "left" then move += Vector3.new(0.75, 0.25, draw * 0.65)
			else move += Vector3.new(-0.15, 0.12, 0) end
		end
		local cutting = weapon.id == "Knife" and weaponVisual.lastAction == "KnifeSlash"
			and now - lastWeaponUse < 0.28
		if cutting and side == "right" then
			ext = math.sin(math.clamp((now - lastWeaponUse) / 0.28, 0, 1) * math.pi)
			move += Vector3.new(weaponVisual.slashSide * 0.75 * ext, -0.10 * ext, -0.30 * ext)
		end
		-- aimed swing: drawn back against the line while it is drawn, then swept through along it.
		-- sweep: -power while drawing (cocked back), -> +1 (follow-through) -> 0 (rest) over the swing,
		-- so the release picks up exactly where the draw left it. An unmoved line is the plain chop.
		local drawing = side == "right" and swingUi.aim ~= nil and swingUi.aim.weapon == weapon
		local aimed = drawing and swingUi.value() or side == "right" and weapon.aimSwing
			and weaponVisual.lastAction == weapon.id and h.t < 1 and weaponVisual.swing or nil
		if aimed and aimed.X == 0 and aimed.Y == 0 then aimed = nil end
		local sweep, style, recover = 0, nil, 0
		if aimed then
			style = SWING_STYLE[weapon.id] or SWING_STYLE.Bat
			local cocked, split = aimed.Z * style.cock, style.split
			if drawing then
				sweep = -cocked
			elseif h.t < split then
				sweep = -cocked + (1 + cocked) * smooth(h.t / split)
			else
				recover = smooth((h.t - split) / (1 - split))
				sweep = 1 - recover
			end
			local through = math.max(sweep, 0) -- past the middle, on the follow-through
			move += Vector3.new(aimed.X, aimed.Y, 0) * style.reach * sweep
				+ Vector3.new(0, -(style.sink or 0) * through * through,
					drawing and 0.15 * aimed.Z or 0.15 * aimed.Z * (1 - smooth(h.t)) - style.push * ext)
		end
		if boxing then
			-- At rest the gloves land where the bare fists are (a glove sits back on the forearm, so the
			-- arm goes up, out and away to put it there); the striking fist travels inward and turns over.
			move += GLOVE_REST * Vector3.new(h.x, 1, 1) + Vector3.new(-h.x * 0.32 * ext, 0.08 * ext, 0)
			-- the block: both gloves up in front of the face, pressed together (kept apart below)
			move = move:Lerp(Vector3.new(-h.x * 0.6, 0.8, 0.5), guard)
			if h.heavy then
				move += Vector3.new(0, 0.1, -0.5) * ext -- reaches further than a jab
			end
		end
		if side == "right" and hold and ads > 0 then -- aiming: the gun comes up to the crosshair (adsFix, below)
			move = move:Lerp(hold.hand + (adsFix[weapon.id] or Vector3.zero) + Vector3.new(0, 0, -0.35), ads) -- held out, so both hands show
		elseif side == "right" and hold and weapon.kind == "knife" and knifeT > 0 then -- the arm bends back once it's caught
			move = move:Lerp(KNIFE_COCK, smooth(math.clamp((knifeT - 0.35) / 0.65, 0, 1)))
		elseif side == "left" and ads > 0 and leftGrip[weapon.id] then -- and the left hand takes hold of it
			local rest = Vector3.new(h.x * (0.85 - 0.5 * ext), -0.85 + 0.35 * ext, -2.35 - 1.2 * ext)
			move = move:Lerp(leftGrip[weapon.id] - rest, ads)
		end
		if pose then
			move += (side == "right" and pose.right or pose.left) or Vector3.zero
			if side == "left" and pose.leftAt and inspectLeft then -- reaching for a point on the weapon
				local rest = Vector3.new(h.x * (0.85 - 0.5 * ext), -0.85 + 0.35 * ext, -2.35 - 1.2 * ext)
				move = move:Lerp(inspectLeft - rest, pose.leftAt.w)
			end
		end
		move += weaponVisual.bob:hand(h.x) * (1 - ads) -- arms swing in opposition while walking; aiming steadies them
		-- wall run: the free hand (away from the wall) flails out for balance with the stride, as the
		-- far arm in WallRun does; one swing each way per 0.5 s cycle
		if flipT and not (side == "right" and hold) then
			-- the kick: both hands shove off the wall, then are thrown up and out overhead (mostly off
			-- the top of the screen) and come back down for the landing, as in WallFlip
			local shove = math.sin(math.clamp(flipT / 0.2, 0, 1) * math.pi)
			local throw = math.sin(math.clamp((flipT - 0.08) / 0.8, 0, 1) * math.pi)
			move += Vector3.new(h.x * 0.5 * throw, 1.6 * throw, -0.6 * shove + 0.3 * throw)
		end
		if weaponVisual.jumpT > 0.01 and not (side == "right" and hold) then
			move += Vector3.new(h.x * 0.3, 1.0, -0.25) * weaponVisual.jumpT * (1 - ext) -- up and a little out
		end
		local flail = wallHand and wallHand.side ~= side and weaponVisual.wallT * (1 - ext) or 0
		if flail > 0.01 and not (side == "right" and hold) then
			local s = math.sin(now * math.pi * 4)
			move += Vector3.new(h.x * (0.5 + 0.2 * s), -0.1 + 0.25 * s, 0.3 - 0.6 * s) * flail
		end
		-- the same wide, near rest for bare fists and anything held; a punch still reaches all the way
		-- out, and aiming, the drawn bow and a hand reaching for the weapon go exactly where they're put
		local bare = (1 - ext) * (1 - ads) * (weapon.kind == "bow" and 0 or 1)
			* (1 - (side == "left" and pose and pose.leftAt and inspectLeft and pose.leftAt.w or 0))
		local fist = viewCF
			* CFrame.new(h.x * (0.85 - 0.5 * ext + FIST_SPREAD * bare) + move.X, -0.85 + 0.35 * ext + move.Y,
				-2.35 - 1.2 * ext + FIST_PULL * bare + move.Z)
		local grab = dragView and side == "right" and holding and holding.part:FindFirstChild("GrabAttachment") :: Attachment?
		if grab then
			-- the fist reaches out toward the dummy's collar, the forearm coming up from the bottom
			-- right of the screen: on screen it is the hand that holds it, not a shoulder in your face
			-- on the plane DRAG_VIEW_REACH ahead, where the collar is seen through it, kept inside the
			-- bottom right of the screen (the collar is often beside or behind you: then the corner)
			local at = viewCF:PointToObjectSpace(grab.WorldPosition)
			local z = -DRAG_VIEW_REACH
			local x, y = 0.95, -0.8
			if at.Z < -0.2 then
				x, y = at.X * z / at.Z, at.Y * z / at.Z
			end
			x, y = math.clamp(x, 0.45, 1.25), math.clamp(y, -1.0, -0.4)
			local spot = viewCF * Vector3.new(x, y, z)
			-- knuckles along the line from your eye through the fist (the collar itself may be off
			-- screen): the forearm then runs back out of the bottom right corner, never across the view
			fist = CFrame.lookAt(spot, viewCF * (Vector3.new(x, y, z) * 2), viewCF.UpVector)
		end
		h.fist.CFrame = fist
		fists[side] = fist
		h.arm.CFrame = fist * CFrame.Angles(math.rad(ARM_PITCH), math.rad(ARM_YAW * h.x), 0) * CFrame.new(0, 0, 1.3)
		local real = arms[side]
		h.fist.Transparency = (show and not real) and 0 or 1
		h.arm.Transparency = (show and not real) and 0 or 1
		-- fingers forward, forearm running back, down and outward past the camera
		local pitch = ARM_PITCH + (boxing and 30 * guard or 0) -- blocking: forearms up, gloves upright
		local yawed = fist * CFrame.Angles(math.rad(pitch), math.rad(ARM_YAW * h.x), 0)
		local arm = yawed * CFrame.Angles(math.rad(90), 0, 0)
		local hand = arm
		if boxing then
			-- The glove tips its front up at the wrist (the cuff and forearm stay put) and turns over
			-- along the forearm's axis as it punches.
			hand = yawed * CFrame.new(0, 0, GLOVE_WRIST) * CFrame.Angles(math.rad(GLOVE_TIP), 0, 0)
				* CFrame.new(0, 0, -GLOVE_WRIST) * CFrame.Angles(math.rad(90), 0, 0)
				* CFrame.Angles(0, math.rad(-h.x * 45 * ext), 0)
		end
		if side == "right" and hold then
			-- The wrist bends so the hand is square to the view whatever the forearm is doing:
			-- guns point at the crosshair, melee and throwables stand upright and tip forward to swing.
			local tilt = (weapon.kind == "gun" or weapon.kind == "rocket" or weapon.kind == "bow") and 0 or -25 - 75 * ext
			local yaw, roll = 0, 0
			local swingRot = nil
			if aimed then
				-- The edge leads, whichever way the line goes. The mesh's handle is +Y and its edge (the axe's
				-- blade, the katana's cutting side, the crowbar's claw, the pan's face, the hammer's face) is
				-- -Z. The handle turns through the plane of the swing (the view's forward and the line):
				-- pointing back against the line when cocked, at the crosshair at the hit, along the line on
				-- the follow-through; the edge faces where the head is moving, square to the handle.
				local st = style :: any
				local m = Vector3.new(aimed.X, aimed.Y, 0).Unit
				local th = math.rad(math.clamp(sweep * st.tilt, -115, 115))
				local fwd = Vector3.new(0, 0, -1)
				local handle = (fwd * math.cos(th) + m * math.sin(th) + Vector3.new(0, 0.35, 0)).Unit -- a little up: the head stays over the hand
				local edge = m * math.cos(th) - fwd * math.sin(th)
				edge = (edge - handle * edge:Dot(handle)).Unit
				swingRot = CFrame.fromMatrix(Vector3.zero, handle:Cross(-edge), handle, -edge)
				if st.spin then -- a twirl round the handle on the recovery
					swingRot *= CFrame.Angles(0, math.rad(st.spin * recover), 0)
				end
				-- in from the rest pose as the line is drawn, back to it over the recovery
				local w = if drawing then math.clamp(aimed.Z * 3, 0, 1) else 1 - recover
				swingRot = CFrame.Angles(math.rad(-25), 0, 0):Lerp(swingRot, w)
			elseif cutting then
				yaw, roll = math.rad(-weaponVisual.slashSide * 65 * ext), math.rad(weaponVisual.slashSide * 45 * ext)
			end
			if special and special.tilt then
				tilt, yaw, roll = special.tilt, math.rad(special.yaw or 0), math.rad(special.roll or 0)
				swingRot = nil
			end
			if weapon.kind == "knife" and knifeT > 0 then -- cocked: the wrist tips the upturned knife's handle at the crosshair
				tilt += (KNIFE_TILT - tilt) * smooth(math.clamp((knifeT - 0.35) / 0.65, 0, 1))
			end
			local pivot = real and real.wrist or Vector3.zero
			hand = CFrame.new(arm * pivot)
				* viewCF.Rotation
				* inspectRot
				* (swingRot or CFrame.Angles(math.rad(tilt), yaw, roll))
				* CFrame.Angles(math.rad(90), 0, 0)
				* CFrame.new(-pivot)
			weaponCF = hand * (real and real.grip or DEFAULT_GRIP)
		end
		local free = not (side == "right" and hold)
		local wrist = real and real.wrist or Vector3.zero
		local planted = wallHand and wallHand.side == side and weaponVisual.wallT * (1 - ext) or 0
		if planted > 0.01 and free then
			-- wall run: a little ahead of and below the eye, fingers up and forward along the wall
			local n = wallHand.normal
			local up = (Vector3.yAxis - n * n.Y).Unit
			local along = viewCF.LookVector - n * viewCF.LookVector:Dot(n)
			along = along.Magnitude > 0.01 and along.Unit or up:Cross(n)
			local at = viewCF.Position + along * 1.6 - up * 0.3
			at += n * (wallHand.point - at):Dot(n)
			hand, arm = weaponVisual.palm(hand, arm, at, n, (up + along * 0.6).Unit, h.x, wrist, viewCF, planted)
		end
		local clung = cling and weaponVisual.clingT * (1 - ext) or 0
		if clung > 0.01 and free then
			-- hanging: shoulder width apart just below the eye, fingers up and a little outward
			local n = cling.normal
			local up = (Vector3.yAxis - n * n.Y).Unit
			local across = n:Cross(up).Unit
			if across:Dot(viewCF.RightVector) < 0 then
				across = -across
			end
			local at = cling.point + across * (h.x * 0.6) - up * 0.15
			hand, arm = weaponVisual.palm(hand, arm, at, n, (up + across * h.x * 0.3).Unit, h.x, wrist, viewCF, clung)
		end
		if real then
			for i, piece in real.pieces do
				piece.part.CFrame = (i == 1 and hand or arm) * piece.offset
				piece.part.LocalTransparencyModifier = (show and not (boxing and i == 1)) and 0 or 1
			end
		end
		local glove = weaponVisual.gloves[side]
		local gloveCF = hand * (real and real.grip or DEFAULT_GRIP)
		if boxing then -- blocking: thumbs up, backs of the gloves turned out, rolled about the forearm
			gloveCF *= glove.origin * CFrame.Angles(0, 0, math.rad(-90 * h.x * guard)) * glove.origin:Inverse()
		end
		gloveCFs[side] = gloveCF
	end
	-- The gloves never pass through each other: each one stays on its own side of the middle of the
	-- view (they are mirror images), measured on the glove's own vertices; one that reaches over is
	-- slid back out with its forearm.
	local boxingNow = weapon.id == "BoxingGloves" and not dragView -- holding one with F: bare hands
	for side, h in hands do
		local glove = weaponVisual.gloves[side]
		local gloveCF = gloveCFs[side]
		if boxingNow and show then
			local inward = viewCF.RightVector * -h.x
			local over = GloveMeshes.reach(h.x, gloveCF * glove.origin, inward) - inward:Dot(viewCF.Position) + 0.02
			if over > 0 then
				local shift = -inward * over
				gloveCF += shift
				h.fist.CFrame += shift
				h.arm.CFrame += shift
				for _, piece in (arms[side] or { pieces = {} }).pieces do
					piece.part.CFrame += shift
				end
			end
		end
		BoxingGloves.update(glove, gloveCF, show == true and boxingNow)
	end
	weaponVisual.detonator.update(isFirstPerson(), show and weapon.id == "C4" and gloveCFs.left or nil)
	-- Hide replicated body gloves locally in first person (the anchored pair above draws instead) and
	-- while holding one with F or kicking it, when the hands are bare
	local bodyGloves = char and char:FindFirstChild("BoxingGloves")
	if bodyGloves then
		local hidden = isFirstPerson() or dragView
		for _, padding in bodyGloves:GetDescendants() do
			if padding:IsA("BasePart") then padding.LocalTransparencyModifier = hidden and 1 or 0 end
		end
	end

	-- weapon in the right hand
	-- a thrown one has left the hand until its cooldown is over; the lasso keeps its coil, C4's detonator
	-- (right click) throws nothing, the landmine is in the hand until it has been put down
	local thrown = (weapon.kind == "thrown" and not weaponVisual.lib.KEEP[weapon.id]
		and not (weapon.id == "C4" and weaponVisual.useAimed and weaponVisual.useId == "C4"))
		or (weapon.kind == "knife" and weaponVisual.lastAction ~= "KnifeSlash")
	local since = os.clock() - lastWeaponUse
	weaponVisual.gone = thrown and since < weapon.cd and since >= (weapon.id == "Landmine" and 0.3 or 0)
	local inHand = show and weaponCF and not weaponVisual.gone -- it left the hand
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
			if not active then
				posePieces(id, nil, viewCF, fists)
			else
				local meshCF = weaponCF * (id == "Knife" and knifeT > 0 and knifeFlip(knifeT) or CFrame.identity) * HOLD[id].grip
				if pose and pose.weapon then -- tossed or spun about its own centre, camera space
					local lo, hi = WeaponMeshes.bounds(id)
					local c = meshCF * ((lo + hi) / 2)
					meshCF = CFrame.new(c + viewCF:VectorToWorldSpace(pose.weapon.Position))
						* (viewCF.Rotation * pose.weapon.Rotation * viewCF.Rotation:Inverse())
						* CFrame.new(-c) * meshCF
				end
				mesh:PivotTo(meshCF)
				posePieces(id, pose, viewCF, fists, mesh.CFrame)
				if HOLD[id].support then -- the fist's centre sits a little under the point the palm grips
					leftGrip[id] = viewCF:PointToObjectSpace(mesh.CFrame * HOLD[id].support) + Vector3.new(0, -0.2, 0)
				end
				if ads > 0.9 and recoil < 0.05 then -- learn only once settled, or the easing / kick skews it
					local lo, hi = WeaponMeshes.bounds(id)
					local topCentre = Vector3.new((lo.X + hi.X) / 2, hi.Y, (lo.Z + hi.Z) / 2)
					local top = viewCF:PointToObjectSpace(mesh.CFrame * topCentre)
					-- the top of the mesh is the sight: the launcher's flip-up sight sits a little higher
					local want = Vector3.new(0, weapon.kind == "rocket" and -0.04 or -0.12, top.Z)
					adsFix[id] = (adsFix[id] or Vector3.zero) + (want - top) * math.min(dt * 12, 1)
				end
			end
		end
	end
	-- the same weapon in the body's own right hand, for the pulled-back camera
	-- (none while a dummy is held with F or being punted: the right hand is busy with it)
	local bodyId = not isFirstPerson() and humanoid and humanoid.Health > 0 and HOLD[weapon.id]
		and not (holding and holding.drag) and os.clock() >= puntUntil
		and not weaponVisual.gone and weapon.id or nil
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
		-- aimed (or just fired from the hip), or one of the two-handed ones carried at the hip
		-- (WeaponAnims.HOLD): held between the hands, pointing where the camera looks
		local twoHands = weaponVisual.hipAim or weaponVisual.lib.HOLD[weapon.id] ~= nil
		if (thirdAim > 0.5 or twoHands) and leftHand and (weapon.kind == "gun" or weapon.kind == "rocket" or twoHands) then
			-- aimed, both hands on it: the gun sits halfway between the hands (the middle of its
			-- grip-to-support span there) and points straight at the crosshair
			local leftGrip = leftHand:FindFirstChild("LeftGripAttachment") :: Attachment?
			local mid = ((grip and grip.WorldPosition or rightHand.Position) + (leftGrip and leftGrip.WorldPosition or leftHand.Position)) / 2
			-- aimed: at the crosshair; carried at the hip: level, the way the body faces
			local hipCarry = thirdAim <= 0.5 and not weaponVisual.hipAim and root ~= nil
			local ahead = if hipCarry then root.CFrame.LookVector * Vector3.new(1, 0, 1) else camera.CFrame.LookVector
			local rot = CFrame.lookAlong(Vector3.zero, ahead.Magnitude > 0.01 and ahead or camera.CFrame.LookVector) * HOLD[bodyWeapon.id].grip.Rotation
			meshCF = rot + mid - rot:VectorToWorldSpace((HOLD[bodyWeapon.id].support or Vector3.zero) / 2)
		end
		bodyWeapon.part:PivotTo(meshCF)
	end
	weaponLabel.Text = weapon.name

	-- an ability in hand: the viewmodel hands glow in first person, the body's own in third
	local glowColor = heldAbility and heldAbility.color
	local firstPerson = isFirstPerson()
	for side, h in hands do
		local real = arms[side] -- the cloned avatar hand when there is one, else the ball fist
		handGlow(real and real.pieces[1].part or h.fist, glowColor, firstPerson)
	end
	handGlow(char and char:FindFirstChild("LeftHand") :: BasePart?, glowColor, not firstPerson)
	handGlow(char and char:FindFirstChild("RightHand") :: BasePart?, glowColor, not firstPerson)

	-- the dummy in the crosshair: its vitals panel (below)
	local result = aim(60)
	local dummy = result and dummyOf(result.Instance)
	if dummy then
		mv.seen, mv.seenAt = dummy, os.clock()
		-- pointing a gun at it: tell the server now and then, so it puts its hands up
		local aimRemote = remotes:FindFirstChild("Aim")
		if (weapon.kind == "gun" or weapon.kind == "rocket") and aimRemote and not holding and os.clock() - (mv.aimedAt or 0) > 0.4 then
			mv.aimedAt = os.clock()
			aimRemote:FireServer(result.Instance)
		end
	end

	-- vitals of the dummy last looked at; the panel lingers a while after you look away
	local seen = mv.seen
	if seen and (not seen.Parent or os.clock() - mv.seenAt > 8) then
		seen, mv.seen = nil, nil
	end
	local vitals = mv.vitals
	vitals.panel.Visible = seen ~= nil
	vitals.note.Visible = seen ~= nil
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
		-- the server lists them oldest first; newest first here, so a cut-off note loses the old ones
		local injuries = (seen:GetAttribute("Injuries") or ""):lower():split(", ")
		for i = 1, #injuries // 2 do
			injuries[i], injuries[#injuries + 1 - i] = injuries[#injuries + 1 - i], injuries[i]
		end
		local list = table.concat(injuries, ", ")
		local headline = if list ~= "" then list:sub(1, 1):upper() .. list:sub(2) else "No injuries yet"
		if vitals.headline.Text ~= headline then
			if vitals.noteOf == seen then -- a new injury on the same dummy, not a new dummy looked at
				vitals.headline.TextColor3 = Color3.new(1, 1, 1)
				game:GetService("TweenService"):Create(vitals.headline, TweenInfo.new(0.5), { TextColor3 = Color3.fromRGB(252, 200, 50) }):Play()
			end
			vitals.headline.Text = headline
			-- the box fits the note: one line or two (the headline's own box holds two)
			vitals.note.Size = UDim2.fromOffset(280, 5 + math.min(vitals.headline.TextBounds.Y, 30) + 24)
		end
		vitals.noteOf = seen
		vitals.detail.Text = `{seen.Name} · {status} · {math.floor(blood)}% blood`
		vitals.pulse.Text = bpm .. " bpm"
		vitals.pulse.TextColor3 = (dead or bpm > 140) and Color3.fromRGB(255, 120, 60) or Color3.fromRGB(120, 230, 150)
		vitals.blood.Size = UDim2.fromScale(blood / 100, 1)
		local awake = (dead or status == "Out cold") and 0 or status == "Drowsy" and 0.35 or 1 - pain / 250
		vitals.awake.Size = UDim2.fromScale(awake, 1)
	end
end)

-- the first-time tutorial: outlines on its dummies, what to do next (server/Tutorial)
require(script:WaitForChild("TutorialHud")).start()
require(script:WaitForChild("Disasters")).start() -- tornado, tsunami, meteors, nuke (server/Disasters)
require(script:WaitForChild("CashHud")).start() -- the cash counter, top right
