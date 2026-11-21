--!strict
-- The tank (docs/czolg-brief.md): Blender meshes (assets/army/build.py tank -> ReplicatedStorage.ArmyKit)
-- on a heavy sprung chassis, driven like the cars (server/PoliceCar: spawn, seat, network ownership,
-- blasts that break its pieces into cubes). The driver's client steers it tank style and aims the
-- turret (client/TankClient.luau); here the server keeps the turret honest (turn rate, elevation
-- limits), fires the gun, runs over dummies and makes the wreck fall apart comically: the turret pops
-- up spinning, the driver flies out of the hatch, the tracks slide off, the rest goes to cubes.
--
-- Tank space (like the cars'): ground under the middle at y 0, front -Z. The turret turns on a joint
-- "Yaw" round TURRET (in the hull roof), the gun on "Pitch" round GUN (the trunnions); the barrel hangs
-- on a joint "Mount" so clients can kick it back when it fires. The joints are plain Welds moved by
-- their C0: a VehicleSeat drives every Motor (and Motor6D) in its assembly when steering, and that
-- tore the tank apart (NaN) on the first A/D.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PoliceCar = require(script.Parent.PoliceCar)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local Tank = {}

local parts = PoliceCar.parts
local box, weld, dress = parts.box, parts.weld, parts.dress

local TURRET = Vector3.new(0, 4.9, -0.4) -- turret ring (yaw pivot), as build.py TANK_TURRET
local GUN = Vector3.new(0, 6.3, -4.1) -- trunnions (pitch pivot), as build.py TANK_GUN
local MUZZLE = 13.7 -- studs from the trunnions to the muzzle along the gun
local HULL = { "Tank_Hull", "Tank_FenderL", "Tank_FenderR", "Tank_TrackL", "Tank_TrackR", "Tank_Exhaust" }
-- road wheels as build.py TANK_WHEELS (right side; the left mirror x): outer row of 4, inner row of 3
local WHEELS = { 4.4, -5.4, 4.4, -1.8, 4.4, 1.8, 4.4, 5.4, 3.55, -3.6, 3.55, 0, 3.55, 3.6 }
local WHEEL_Y = 1.4
-- the physics under it: 4 invisible rollers a side on springs (radius, x, z list), the hull box
local ROLLER_R, ROLLER_X, ROLLERS = 1.5, 3.9, { -6.3, -2.1, 2.1, 6.3 }
local UPPER, LOWER, REST, FREE_LENGTH, STIFFNESS, DAMPING = -0.8, -1.6, 1.2, 2.0, 37000, 2500
local CHASSIS = { size = Vector3.new(9.0, 3.2, 15.2), y = 3.3, density = 2.5 }

-- Gameplay numbers (the client reads them off the model's attributes). Calibration knobs.
local STATS = {
	MaxSpeed = 22, -- studs/s
	YawRate = 60, -- turret, degrees/s
	PitchRate = 30,
	PitchMin = -8, -- gun elevation, degrees
	PitchMax = 20,
	Reload = 2.5, -- seconds
	ShellSpeed = 240, -- studs/s
	ShellDrop = 40, -- studs/s² pulling the shell down: a short arc
	Muzzle = MUZZLE,
}
local SHELL_LIFE = 3 -- seconds a shell flies before it bursts in the air
local BLAST_SCALE = 1.5 -- of a grenade's (explode)
local ARMOR = 0.32 -- blasts reach this share as deep into it as into a car (one TNT: a chunk, about 2-3 wreck it)
local WRECK_AT = 0.3 -- share of its cubes it can lose before it falls apart
local RAM_SPEED = 6 -- studs/s from which it bowls dummies over

local tanks: { [Model]: any } = {}
local remote = Instance.new("RemoteEvent")
remote.Name = "TankControl"
remote.Parent = ReplicatedStorage

-- set by init.server: explode(position, sound, scale), ram(player, position, direction, speed)
Tank.explode = nil :: ((Vector3, string, number?) -> ())?
Tank.ram = nil :: ((Player?, Vector3, Vector3, number) -> ())?
Tank.act = nil :: ((Player?) -> ())? -- Wanted.act(player, "Tank") for this thread

local function motor(name: string, a: BasePart, b: BasePart, pivot: CFrame): Weld
	local m = Instance.new("Weld")
	m.Name = name
	m.Part0, m.Part1 = a, b
	m.C0, m.C1 = a.CFrame:ToObjectSpace(pivot), b.CFrame:ToObjectSpace(pivot)
	m:SetAttribute("Base", m.C0)
	m.Parent = b
	return m
end

local function wheelAt(i: number, side: number): CFrame -- a road wheel's hub; the left ones turn half round
	return CFrame.new(side * WHEELS[i], WHEEL_Y, WHEELS[i + 1]) * (if side < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
end

local function build(model: Model, _spec, origin: CFrame): (BasePart, VehicleSeat, Vector3, CFrame)
	local chassis = box("Chassis", CHASSIS.size, origin * CFrame.new(0, CHASSIS.y, 0), model)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(CHASSIS.density, 0.3, 0.1)
	chassis.CollisionGroup = "CarBody"
	model.PrimaryPart = chassis
	-- the upper hull: as long as the tank, above kerb height (the chassis is shorter, so the front
	-- rollers meet a kerb before it does)
	local upper = box("Upper", Vector3.new(8.4, 1.5, 17.4), origin * CFrame.new(0, 4.15, 0), model)
	upper.Massless, upper.CollisionGroup = true, "CarBody"
	weld(chassis, upper)

	-- the turret: its own box (it collides and, in a wreck, flies), on the yaw joint; the gun on pitch
	local ring = box("Turret", Vector3.new(7, 2.8, 7.6), origin * CFrame.new(0, 6.3, 0), model)
	ring.Massless, ring.CollisionGroup = true, "CarBody"
	motor("Yaw", chassis, ring, origin * CFrame.new(TURRET))
	local gun = box("Gun", Vector3.one, origin * CFrame.new(GUN), model)
	gun.Massless, gun.CanCollide, gun.CanQuery, gun.CanTouch = true, false, false, false
	motor("Pitch", ring, gun, origin * CFrame.new(GUN))

	local mounts = { Tank_Turret = ring, Tank_Mantlet = gun, Tank_Barrel = gun }
	local total = parts.addPanels(model, HULL, origin, function()
		return chassis
	end)
	total += parts.addPanels(model, { "Tank_Turret", "Tank_Mantlet", "Tank_Barrel" }, origin, function(piece)
		return mounts[piece]
	end)
	local barrel = (model:FindFirstChild("Panels") :: Folder):FindFirstChild("Tank_Barrel") :: Model
	local collider = barrel.PrimaryPart :: BasePart
	(collider:FindFirstChild("Mount") :: Instance):Destroy()
	motor("Mount", gun, collider, collider.CFrame)

	-- road wheels: looks only, each spun by its own joint on every client
	for side = -1, 1, 2 do
		for i = 1, #WHEELS, 2 do
			local hub = box("WheelVis", Vector3.one * 0.2, origin * wheelAt(i, side), model)
			hub.Massless, hub.CanCollide, hub.CanQuery, hub.CanTouch = true, false, false, false
			dress("Tank_Wheel", hub.CFrame, hub, hub)
			motor("Spin", chassis, hub, hub.CFrame):SetAttribute("Side", side)
		end
	end

	-- the rollers it rides on (invisible; the server's copy brakes them, the driver's client frees them)
	local slide = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	for side = -1, 1, 2 do
		for _, z in ROLLERS do
			local at = Vector3.new(side * ROLLER_X, ROLLER_R, z)
			local hub = Instance.new("Attachment")
			hub.Name = "Hub"
			hub.CFrame = chassis.CFrame:ToObjectSpace(origin * CFrame.new(at + Vector3.new(0, REST, 0))) * slide
			hub.Parent = chassis
			local roller = box("Roller", Vector3.new(2, ROLLER_R * 2, ROLLER_R * 2), origin * CFrame.new(at), model)
			roller.Shape = Enum.PartType.Cylinder
			roller.CustomPhysicalProperties = PhysicalProperties.new(1, 0.25, 0, 100, 1)
			roller.CollisionGroup = "CarWheel"
			local axle = Instance.new("Attachment")
			axle.Name = "Axle"
			axle.Parent = roller
			local cyl = Instance.new("CylindricalConstraint")
			cyl.Name = "Suspension"
			cyl.Attachment0, cyl.Attachment1 = hub, axle
			cyl.InclinationAngle = 90
			cyl.LimitsEnabled, cyl.UpperLimit, cyl.LowerLimit = true, UPPER, LOWER
			cyl.AngularActuatorType = Enum.ActuatorType.Motor
			cyl.MotorMaxTorque, cyl.AngularVelocity = 1e6, 0 -- parked: brakes on
			cyl.Parent = roller
			local spring = Instance.new("SpringConstraint")
			spring.Attachment0, spring.Attachment1 = hub, axle
			spring.Stiffness, spring.Damping, spring.FreeLength = STIFFNESS, DAMPING, FREE_LENGTH
			spring.Parent = roller
		end
	end

	-- the driver sits low in the hull, out of sight
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(1.6, 0.4, 1.6)
	seat.CFrame = origin * CFrame.new(0, 1.8, -2)
	seat.Transparency, seat.Massless, seat.CanCollide, seat.CollisionGroup = 1, true, false, "CarBody"
	seat.MaxSpeed, seat.HeadsUpDisplay = STATS.MaxSpeed, false
	seat.Parent = model
	weld(chassis, seat)

	model:SetAttribute("Tank", true)
	model:SetAttribute("Cubes", total)
	model:SetAttribute("Armor", ARMOR)
	model:SetAttribute("WreckAt", WRECK_AT)
	model:SetAttribute("CrashAt", 10)
	for k, v in STATS do
		model:SetAttribute(k, v)
	end
	tanks[model] = { yaw = 0, pitch = 0, wantYaw = 0, wantPitch = 0, fired = 0, rammed = 0, seat = seat, gun = gun,
		yawM = ring:FindFirstChild("Yaw"), pitchM = gun:FindFirstChild("Pitch") }
	model.Destroying:Connect(function()
		tanks[model] = nil
	end)
	-- the prompt by the left fender, out on the ground beside it; a wreck throws the driver out the hatch
	return chassis, seat, Vector3.new(-5.4, 3.6, -4), CFrame.new(-7.5, -1.5, -3)
end

local function preview(): Model
	local m = Instance.new("Model")
	m.Name = "Tank"
	for _, piece in { "Tank_Hull", "Tank_FenderL", "Tank_FenderR", "Tank_TrackL", "Tank_TrackR", "Tank_Exhaust", "Tank_Turret", "Tank_Mantlet", "Tank_Barrel" } do
		dress(piece, CFrame.identity, m)
	end
	for side = -1, 1, 2 do
		for i = 1, #WHEELS, 2 do
			dress("Tank_Wheel", wheelAt(i, side), m)
		end
	end
	return m
end

-- What comes off whole when it falls apart (PoliceCar's wreck shatters the rest): the turret, with
-- the gun, shoots up tumbling; the tracks slide off sideways. Into their own model, gone soon.
local function wreck(car: Model, from: Vector3, _power: number)
	local ring = car:FindFirstChild("Turret") :: BasePart?
	local panels = car:FindFirstChild("Panels")
	if not (ring and panels) then
		return
	end
	local loose = Instance.new("Model")
	loose.Name = "TankWreck"
	local yaw = ring:FindFirstChild("Yaw")
	if yaw then
		yaw:Destroy()
	end
	ring.Parent = loose;
	(car:FindFirstChild("Gun") :: Instance).Parent = loose
	for _, name in { "Tank_Turret", "Tank_Mantlet", "Tank_Barrel" } do
		local p = panels:FindFirstChild(name)
		if p then
			p.Parent = loose
		end
	end
	ring.Massless, ring.CanCollide = false, true
	local away = (ring.Position - from) * Vector3.new(1, 0, 1)
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.zero
	ring.AssemblyLinearVelocity = Vector3.new(0, 85, 0) + away * 12
	ring.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-8, 8), math.random(-6, 6))
	local chassis = car.PrimaryPart :: BasePart
	for _, name in { "Tank_TrackL", "Tank_TrackR" } do
		local p = panels:FindFirstChild(name) :: Model?
		local c = p and p.PrimaryPart
		if p and c then
			(c:FindFirstChild("Mount") :: Instance):Destroy()
			c.CanCollide, c.Massless = true, false
			p.Parent = loose
			local out = chassis.CFrame.RightVector * (if name == "Tank_TrackL" then -1 else 1)
			c.AssemblyLinearVelocity = out * 18 + Vector3.new(0, 12, 0)
			c.AssemblyAngularVelocity = chassis.CFrame.LookVector * (if name == "Tank_TrackL" then 2 else -2)
		end
	end
	loose.Parent = workspace
	for _, p in loose:GetDescendants() do
		if p:IsA("BasePart") and p:CanSetNetworkOwnership() then
			p:SetNetworkOwner(nil)
		end
	end
	Debris:AddItem(loose, parts.LOOSE_LIFE + 2)
end

PoliceCar.KINDS.Tank.build = build
PoliceCar.KINDS.Tank.preview = preview
PoliceCar.KINDS.Tank.wreck = wreck
PoliceCar.KINDS.Tank.eject = 90

-- The driver's tank (seated in it, alive, not wrecked), or nil.
local function tankOf(player: Player): (Model?, any)
	local char = player.Character
	for model, t in tanks do
		local hum = t.seat.Occupant
		if hum and hum.Parent == char and not model:GetAttribute("Wrecked") then
			return model, t
		end
	end
	return nil, nil
end

-- A shell from the muzzle along the gun: flown by hand with a little drop, raycast every step so it
-- never tunnels, a big blast where it lands (explode: Map.blast + smash, as a rocket's).
local function fire(model: Model, t, player: Player)
	t.fired = os.clock()
	local muzzle = t.gun.CFrame * CFrame.new(0, 0, -MUZZLE)
	remote:FireAllClients("fired", model)
	Sfx.play({ Sfx.RPG_BOOM, 0.55, 1 }, muzzle.Position)
	Sfx.play({ Sfx.SNIPER_SHOT, 0.5, 1 }, muzzle.Position)
	task.spawn(function()
		if Tank.act then
			Tank.act(player) -- whatever the blast does is on the gunner (Wanted)
		end
		local shell = Instance.new("Part")
		shell.Name = "Shell"
		shell.Size = Vector3.new(0.6, 0.6, 1.6)
		shell.Color = Color3.fromHex("2E2E30")
		shell.Material = Enum.Material.Metal
		shell.Anchored, shell.CanCollide, shell.CanQuery, shell.CanTouch, shell.CastShadow = true, false, false, false, false
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0.25, 0, 0.6), Vector3.new(-0.25, 0, 0.6)
		a0.Parent, a1.Parent = shell, shell
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime, trail.LightEmission, trail.FaceCamera = 0.25, 0.8, true
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 40))
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0.3)
		trail.Parent = shell
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { model, player.Character :: Instance }
		local position, velocity = muzzle.Position, muzzle.LookVector * STATS.ShellSpeed
		shell.CFrame = CFrame.lookAt(position, position + velocity)
		shell.Parent = workspace
		local age = 0
		while age < SHELL_LIFE do
			local dt = RunService.Heartbeat:Wait()
			age += dt
			local step = velocity * dt
			local hit = workspace:Raycast(position, step, params)
			if hit then
				position = hit.Position - step.Unit * 0.3
				break
			end
			position += step
			velocity -= Vector3.new(0, STATS.ShellDrop * dt, 0)
			shell.CFrame = CFrame.lookAt(position, position + velocity)
		end
		shell:Destroy()
		if Tank.explode then
			Tank.explode(position, Sfx.RPG_BOOM, BLAST_SCALE)
		end
	end)
end

remote.OnServerEvent:Connect(function(player, action, a, b)
	local model, t = tankOf(player)
	if not model then
		return
	end
	if action == "aim" and typeof(a) == "number" and typeof(b) == "number" and a == a and b == b and math.abs(a) < 1e4 then
		t.wantYaw = a
		t.wantPitch = math.clamp(b, math.rad(STATS.PitchMin), math.rad(STATS.PitchMax))
	elseif action == "fire" and os.clock() - t.fired >= STATS.Reload - 0.15 then
		local barrel = (model:FindFirstChild("Panels") :: Folder):FindFirstChild("Tank_Barrel")
		if barrel and not barrel:GetAttribute("Broken") then -- a broken gun (PoliceCar: BROKEN_AT of it gone) does not fire
			fire(model, t, player)
		end
	end
end)

-- Every frame: the turret and gun turn toward what the driver asked at their rates (so a cheat can
-- neither snap them round nor point the gun out of its range; the joints replicate), and a tank going
-- along bowls over the dummies in front of it.
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for model, t in tanks do
		if model:GetAttribute("Wrecked") or not t.yawM.Parent then
			continue
		end
		local turn = (t.wantYaw - t.yaw + math.pi) % (2 * math.pi) - math.pi
		local yr, pr = math.rad(STATS.YawRate) * dt, math.rad(STATS.PitchRate) * dt
		t.yaw = (t.yaw + math.clamp(turn, -yr, yr)) % (2 * math.pi)
		t.pitch += math.clamp(t.wantPitch - t.pitch, -pr, pr)
		t.yawM.C0 = (t.yawM:GetAttribute("Base") :: CFrame) * CFrame.Angles(0, t.yaw, 0)
		t.pitchM.C0 = (t.pitchM:GetAttribute("Base") :: CFrame) * CFrame.Angles(t.pitch, 0, 0)
		local chassis = model.PrimaryPart
		local hum = t.seat.Occupant
		if chassis and hum and now > t.rammed then
			local v = chassis.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
			local look = chassis.CFrame.LookVector
			local speed = v:Dot(look)
			if math.abs(speed) > RAM_SPEED and Tank.ram then
				t.rammed = now + 0.35
				local dir = look * math.sign(speed)
				Tank.ram(game:GetService("Players"):GetPlayerFromCharacter(hum.Parent), chassis.Position + dir * 9.5 - chassis.CFrame.UpVector, dir, math.abs(speed))
			end
		end
	end
end)

-- a wrecked tank's turret joint is gone; a tank leaving takes its state
CollectionService:GetInstanceRemovedSignal("Car"):Connect(function(car)
	tanks[car :: Model] = nil
end)

return Tank
