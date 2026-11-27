--!strict
-- The drivable cars: Blender meshes (assets/army/build.py police_car / sport_car -> ReplicatedStorage.ArmyKit)
-- on a constraint chassis. Per wheel one CylindricalConstraint (slide, spin, motor) plus one
-- SpringConstraint on the same attachments (scenario-roblox-gameplay Car). The driver's client turns
-- the seat's throttle and steer into motor speeds (client/Driving.luau); the server hands the driver
-- network ownership and gets them out beside the door.
--
-- The cars break into cubes like the map: a piece (the police car's body; the sport car's core, hood,
-- bumpers, doors, cabin, wing) stays one set of meshes until a Map.blast (explosions, weapon chips, a
-- punt) reaches it, then splits in place into the 1-stud cubes of its surface (CarVoxels, made by
-- assets/army/voxels.py), and the cubes in reach fly off as Map.knock throws bricks. A crash at speed
-- blasts where the car hit, which breaks the wall and the car's own end alike. Once WRECK_AT of its
-- cubes are gone the car falls apart: driver thrown out, every cube and the wheels off, then it goes.
--
-- Car space: ground under the middle of the car at y 0, front toward -Z (the model's LookVector).
--
-- The tank (server/Tank.luau) is a kind here too: it fills in KINDS.Tank's build / preview / wreck
-- and uses the shared pieces below (PoliceCar.parts). A tank's pieces turn with its turret, so every
-- piece keeps its own origin ("Origin": the piece's ground point seen from its collider) and the part
-- it is mounted on (its "Mount" joint's Part0); car attributes Armor (blast reach factor), WreckAt and
-- CrashAt override the car defaults.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarVoxels = require(script.Parent.CarVoxels)
local Map = require(script.Parent.Map)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local PoliceCar = {}

-- per kind: the kit pieces it is built of (each breaks into its cubes on its own), the wheel, where the
-- hubs sit (track: x, front/rear: z), the invisible cabin collider and the seat height (a seated R15
-- head stays under the roof)
local SPECS = {
	PoliceCar = {
		label = "Police car", panels = { "Cop_Body" }, wheel = "Cop_Wheel", radius = 1.4,
		track = 3.25, front = -5.2, rear = 5.3, siren = true, seatY = 1.5,
		cabin = { size = Vector3.new(6.2, 2.0, 7.6), at = Vector3.new(0, 4.35, 0.6) },
	},
	SportCar = {
		label = "Sport car", wheel = "Sport_Wheel", radius = 1.35,
		panels = { "Sport_Body", "Sport_Hood", "Sport_BumperF", "Sport_BumperR", "Sport_DoorL", "Sport_DoorR", "Sport_Cabin", "Sport_Wing" },
		track = 3.2, front = -5.0, rear = 5.2, siren = false, seatY = 0.8,
		cabin = { size = Vector3.new(6.0, 1.4, 8.0), at = Vector3.new(0, 3.95, 1.0) },
	},
	Tank = { label = "Tank", wheel = "Tank_Wheel", fit = Vector3.new(11.5, 8, 21) }, -- built by server/Tank.luau
	Bike = { label = "Bike", fit = Vector3.new(2.6, 4, 7.2) }, -- built by server/Bike.luau
}
PoliceCar.KINDS = SPECS

local CHASSIS = { size = Vector3.new(6.6, 1.6, 16.8), y = 2.6 } -- the low heavy floor, car space
-- suspension: the wheel hangs 1..2 studs under its hub, resting at 1.5; the spring carries the car
-- there (chassis ~106 + driver ~10 mass: 4 x 4400 x 1.3 compression ~ its weight)
local UPPER, LOWER, FREE_LENGTH, STIFFNESS, DAMPING = -1, -2, 2.8, 4400, 260
local REST_DROP = -(UPPER + LOWER) / 2
local MAX_SPEED, TORQUE = 60, 5000 -- studs/s, MotorMaxTorque at full throttle (0 to 60 in about 2 s)
local PER_PLAYER = 2 -- cars one player can have out; the oldest goes
local LOOSE_LIFE = 6 -- seconds the wreck's frame lies about, like the map's loose bricks
local CRASH = 30 -- studs/s lost within CRASH_WINDOW that count as a crash
local CRASH_WINDOW = 0.12
local WRECK_AT = 0.45 -- share of its cubes a car can lose before it falls apart (a structure: 0.9)
local BROKEN_AT = 0.4 -- share of a piece's own cubes gone that marks it "Broken" (a tank's track stops pulling, its gun firing)

local owned: { [Player]: { Model } } = {}

local function groups()
	for _, g in { "CarBody", "CarWheel" } do
		if not workspace:IsCollisionGroupRegistered(g) then
			workspace:RegisterCollisionGroup(g)
		end
	end
	workspace:CollisionGroupSetCollidable("CarBody", "CarWheel", false)
	workspace:CollisionGroupSetCollidable("CarWheel", "CarWheel", false)
	-- the driver: the rig's limbs hang on AnimationConstraints (ragdoll ready), so they are not welded
	-- into the car's assembly and their torsos would lift and wedge the car from inside it
	if not workspace:IsCollisionGroupRegistered("CarDriver") then
		workspace:RegisterCollisionGroup("CarDriver")
	end
	for _, g in { "CarBody", "CarWheel", "Default" } do
		workspace:CollisionGroupSetCollidable("CarDriver", g, false)
	end
end

-- puts every part of `char` in "CarDriver", or (restore) back in the groups it had
local function driverGroup(char: Model, restore: { [BasePart]: string }?): { [BasePart]: string }
	local was = {}
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			if restore then
				part.CollisionGroup = restore[part] or part.CollisionGroup
			else
				was[part] = part.CollisionGroup
				part.CollisionGroup = "CarDriver"
			end
		end
	end
	return was
end

local function box(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame = name, size, cf
	p.Transparency, p.CastShadow = 1, false
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, name: string?): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Name = name or "WeldConstraint"
	w.Part0, w.Part1 = a, b
	w.Parent = b
	return w
end

-- the kit's meshes for `piece`, placed at `cf` (its origin) and welded to `to` (nil: anchored)
local function dress(piece: string, cf: CFrame, parent: Instance, to: BasePart?)
	local kit = ReplicatedStorage:FindFirstChild("ArmyKit")
	local folder = kit and kit:FindFirstChild(piece)
	for _, mesh in if folder then folder:GetChildren() else {} do
		local p = mesh:Clone() :: BasePart
		p.CFrame = cf * (p:GetAttribute("Place") or CFrame.identity)
		p.Anchored = to == nil
		p.Parent = parent
		if to then
			weld(to, p)
		end
	end
end

local function wheels(spec)
	local r = spec.radius
	return {
		{ name = "FL", at = Vector3.new(-spec.track, r, spec.front), front = true },
		{ name = "FR", at = Vector3.new(spec.track, r, spec.front), front = true },
		{ name = "RL", at = Vector3.new(-spec.track, r, spec.rear), front = false },
		{ name = "RR", at = Vector3.new(spec.track, r, spec.rear), front = false },
	}
end

local function wheelTurn(w): CFrame -- the kit wheel faces +X; the left ones turn half round
	return CFrame.new(w.at) * (if w.at.X < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
end

-- nearest point of a box to `p` within `radius` (the map's own reach test)
local function reaches(cf: CFrame, size: Vector3, p: Vector3, radius: number): boolean
	local at = cf:PointToObjectSpace(p)
	local h = size / 2
	local near = Vector3.new(math.clamp(at.X, -h.X, h.X), math.clamp(at.Y, -h.Y, h.Y), math.clamp(at.Z, -h.Z, h.Z))
	return (at - near).Magnitude <= radius
end

local cubeParams = OverlapParams.new()
cubeParams.FilterType = Enum.RaycastFilterType.Include

-- A piece's origin right now and the part it is mounted on (the chassis, or a tank's turret / gun).
local function frameOf(panel: Model): (CFrame, BasePart)
	local c = panel.PrimaryPart :: BasePart
	local mount = c:FindFirstChild("Mount") :: any
	return c.CFrame * ((panel:GetAttribute("Origin") :: CFrame?) or CFrame.identity), mount.Part0
end

-- Builds `piece`'s cubes at `base` (its origin) into a new folder, each welded to `to` by a "Mount".
local function cubes(piece: string, base: CFrame, to: BasePart): Folder
	local data = CarVoxels[piece]
	local kit = ReplicatedStorage:FindFirstChild("ArmyKit")
	local look = kit and kit:FindFirstChild(piece)
	local size = CarVoxels.size
	local folder = Instance.new("Folder")
	folder.Name = "Cubes"
	local cells = data.cells
	for i = 1, #cells, 4 do
		local hex = data.colours[cells[i + 3]]
		local mesh = look and look:FindFirstChild(hex) :: BasePart?
		local cube = Instance.new("Part")
		cube.Name = "Cube"
		cube.Size = Vector3.one * size
		cube.CFrame = base * CFrame.new(cells[i] * size, cells[i + 1] * size, cells[i + 2] * size)
		cube.Color = Color3.fromHex(hex)
		cube.Material = if mesh then mesh.Material else Enum.Material.SmoothPlastic
		cube.Transparency = if mesh then mesh.Transparency else 0
		cube.CanCollide, cube.CanTouch, cube.Massless, cube.CastShadow = false, false, true, false
		cube.CollisionGroup = "CarBody"
		cube.Parent = folder
		weld(to, cube, "Mount")
	end
	return folder
end

-- Whether any cube of `piece` (its own space) lies within `radius` of `p` (the same space): only then
-- does a blast split the piece; its box alone reaches much further than its surface.
local function near(piece: string, p: Vector3, radius: number): boolean
	local data = CarVoxels[piece]
	local cells, size, r2 = data.cells, CarVoxels.size, (radius + 0.75) ^ 2
	for i = 1, #cells, 4 do
		local d = Vector3.new(cells[i] * size, cells[i + 1] * size, cells[i + 2] * size) - p
		if d:Dot(d) <= r2 then
			return true
		end
	end
	return false
end

-- A whole piece splits in place into its cubes (the map's big blocks do the same when first hit).
local function shatter(panel: Model)
	if panel:GetAttribute("Shattered") or not panel.PrimaryPart then
		return
	end
	panel:SetAttribute("Shattered", true)
	local base, mount = frameOf(panel)
	cubes(panel.Name, base, mount).Parent = panel
	for _, p in panel:GetChildren() do
		if p:IsA("BasePart") then
			p:Destroy() -- the meshes and the collider, in the same frame the cubes appear
		end
	end
end

-- One cube off the car, thrown like a brick out of a wall.
local function knockCube(cube: BasePart, from: Vector3, power: number)
	local mount = cube:FindFirstChild("Mount")
	if mount then
		mount:Destroy()
	end
	cube.CanCollide, cube.Massless = true, false
	Map.knock(cube, from, power)
end

-- Falls apart: driver thrown out, every piece to cubes and off, the wheels too, the frame goes.
local function wreck(car: Model, from: Vector3, power: number)
	car:SetAttribute("Wrecked", true)
	local seat = car:FindFirstChild("DriveSeat")
	local seatWeld = seat and seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy() -- the Occupant handler puts them out beside the door
	end
	local prompt = car:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		prompt.Enabled = false
	end
	local spec = SPECS[car.Name] or SPECS.PoliceCar
	task.defer(function() -- once the driver is clear of it
		if spec.wreck then
			spec.wreck(car, from, power) -- the tank: what flies off whole leaves car.Panels first
		end
		local panels = car:FindFirstChild("Panels")
		for _, panel in if panels then panels:GetChildren() else {} do
			shatter(panel :: Model)
		end
		local chassis = car.PrimaryPart :: BasePart
		for _, w in car:GetChildren() do
			if w:IsA("BasePart") and w.Name:match("^Wheel") then
				-- a car's wheel is a plain cylinder with its meshes turned on it; a tank's road wheel ("WheelVis") is turned itself
				local turn = if w.Name ~= "WheelVis" and chassis.CFrame:PointToObjectSpace(w.Position).X < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
				cubes(spec.wheel, w.CFrame * turn, chassis).Parent = car
				w:Destroy()
			end
		end
		local all = {}
		for _, d in car:GetDescendants() do
			if d.Name == "Cube" and d:IsA("BasePart") then
				table.insert(all, d)
			end
		end
		for i = #all, 2, -1 do -- shuffled: past the map's debris cap the oldest vanish, so spread them
			local j = math.random(i)
			all[i], all[j] = all[j], all[i]
		end
		for _, cube in all do
			knockCube(cube, from, power * 0.6)
		end
		for _, d in car:GetDescendants() do
			if d:IsA("BasePart") then -- the empty frame: out of sight, out of the way
				d.Transparency, d.CanCollide, d.Anchored = 1, false, true
			end
		end
		Debris:AddItem(car, LOOSE_LIFE)
	end)
	Sfx.play(Sfx.CAR_CRASH, from)
end

-- Map.blast reached here: pieces in reach split into cubes, the cubes in reach fly off, and a car
-- that has lost WRECK_AT of its cubes falls apart.
local function blasted(position: Vector3, radius: number, power: number)
	for _, car in CollectionService:GetTagged("Car") do
		local panels = car:FindFirstChild("Panels")
		if not (panels and car.Parent == workspace and car:IsA("Model")) or car:GetAttribute("Wrecked") then
			continue
		end
		local r = radius * ((car:GetAttribute("Armor") :: number?) or 1) -- armour: the blast bites less deep
		for _, panel in panels:GetChildren() do
			local c = (panel :: Model).PrimaryPart
			if c and not panel:GetAttribute("Shattered") and reaches(c.CFrame, c.Size, position, r + 0.5) then
				local here = frameOf(panel :: Model):PointToObjectSpace(position) -- the blast in the piece's own space
				if near(panel.Name, here, r) then
					shatter(panel :: Model)
				end
			end
		end
		cubeParams.FilterDescendantsInstances = { panels }
		local knocked = 0
		for _, cube in workspace:GetPartBoundsInRadius(position, r + 1, cubeParams) do
			if cube.Name == "Cube" and cube:FindFirstChild("Mount") and (cube.Position - position).Magnitude <= r + 0.25 then
				local panel = cube.Parent and cube.Parent.Parent :: Instance
				knockCube(cube, position, power)
				knocked += 1
				if panel then
					local gone = ((panel:GetAttribute("Lost") :: number?) or 0) + 1
					panel:SetAttribute("Lost", gone)
					if gone >= ((panel:GetAttribute("Cells") :: number?) or math.huge) * BROKEN_AT then
						panel:SetAttribute("Broken", true)
					end
				end
			end
		end
		if knocked > 0 then
			Sfx.play(Sfx.METAL, position)
			local lost = ((car:GetAttribute("Lost") :: number?) or 0) + knocked
			car:SetAttribute("Lost", lost)
			if lost >= ((car:GetAttribute("Cubes") :: number?) or math.huge) * ((car:GetAttribute("WreckAt") :: number?) or WRECK_AT) then
				wreck(car, position, power)
			end
		end
	end
end
table.insert(Map.blasted, blasted)

-- A crash: the car lost CRASH studs/s in a moment. Blast where its leading end hit, as
-- hard as it hit: the wall and the car's own panels there break alike.
local samples: { [Model]: { t: number, v: Vector3, cool: number } } = {}
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for car, s in samples do
		local chassis = car.PrimaryPart
		if not chassis or not car.Parent or car:GetAttribute("Wrecked") then
			samples[car] = nil
			continue
		end
		if now - s.t < CRASH_WINDOW then
			continue
		end
		local v = chassis.AssemblyLinearVelocity
		local lost = s.v.Magnitude - v.Magnitude
		if lost > ((car:GetAttribute("CrashAt") :: number?) or CRASH) and now > s.cool and s.v.Magnitude > 1 then
			s.cool = now + 0.6
			local dir = s.v.Unit
			local reach = math.max(math.abs(dir:Dot(chassis.CFrame.LookVector)) * 9, math.abs(dir:Dot(chassis.CFrame.RightVector)) * 4)
			Map.blast(chassis.Position + dir * reach, 3.5, lost, nil, true) -- structures only: no crater under the car
		end
		s.t, s.v = now, v
	end
end)

-- A still, anchored copy for the Toolbox's stage (ToolboxPreviews), origin on the ground.
function PoliceCar.preview(kind: string): Model
	local spec = SPECS[kind]
	if spec.preview then
		return spec.preview()
	end
	local m = Instance.new("Model")
	m.Name = kind
	for _, piece in spec.panels do
		dress(piece, CFrame.identity, m)
	end
	for _, w in wheels(spec) do
		dress(spec.wheel, wheelTurn(w), m)
	end
	return m
end

-- The pieces: each its own model in car.Panels, its meshes welded to an invisible collider (its box,
-- which weapons hit; the chassis and cabin boxes do the colliding) that a "Mount" weld holds on.
-- Counts the car's cubes for WRECK_AT.
local function addPanels(model: Model, pieces: { string }, origin: CFrame, mountOf: (string) -> BasePart): number
	local total = 0
	local folder = model:FindFirstChild("Panels") or Instance.new("Folder")
	folder.Name = "Panels"
	folder.Parent = model
	for _, piece in pieces do
		local panel = Instance.new("Model")
		panel.Name = piece
		dress(piece, origin, panel)
		panel.WorldPivot = origin
		local cf, size = panel:GetBoundingBox()
		local collider = box("Collider", size, cf, panel)
		collider.CanCollide, collider.CanTouch, collider.Massless = false, false, true
		collider.CollisionGroup = "CarBody"
		collider.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.4, 0.2)
		for _, mesh in panel:GetChildren() do
			if mesh ~= collider and mesh:IsA("BasePart") then
				mesh.Anchored = false
				weld(collider, mesh)
			end
		end
		panel.PrimaryPart = collider
		panel:SetAttribute("Origin", collider.CFrame:ToObjectSpace(origin))
		panel.Parent = folder
		weld(mountOf(piece), collider, "Mount")
		panel:SetAttribute("Cells", #CarVoxels[piece].cells // 4)
		total += #CarVoxels[piece].cells // 4
	end
	return total
end

-- A car's own frame: chassis, cabin, pieces, seat and the four sprung wheels at `origin`, into `model`.
-- Returns the chassis, the seat, the prompt's spot (car space) and where the driver gets out (chassis space).
local function carBody(model: Model, spec, origin: CFrame): (BasePart, VehicleSeat, Vector3, CFrame)
	local chassis = box("Chassis", CHASSIS.size, origin * CFrame.new(0, CHASSIS.y, 0), model)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.3, 0.3)
	chassis.CollisionGroup = "CarBody"
	model.PrimaryPart = chassis
	local cabin = box("Cabin", spec.cabin.size, origin * CFrame.new(spec.cabin.at), model)
	cabin.Massless, cabin.CollisionGroup = true, "CarBody"
	weld(chassis, cabin)
	model:SetAttribute("Cubes", addPanels(model, spec.panels, origin, function()
		return chassis
	end))

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(1.6, 0.4, 1.6)
	seat.CFrame = origin * CFrame.new(-1.4, spec.seatY, -0.3)
	seat.Transparency, seat.Massless, seat.CanCollide, seat.CollisionGroup = 1, true, false, "CarBody"
	seat.MaxSpeed, seat.Torque, seat.HeadsUpDisplay = MAX_SPEED, TORQUE, false
	seat.Parent = model
	weld(chassis, seat)

	-- Attachment0 on the chassis: X up (the slide axis), Y to the right (the axle once InclinationAngle
	-- is 90). Attachment1 on the wheel: X along the cylinder, its axle.
	local slide = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	for _, w in wheels(spec) do
		local hub = Instance.new("Attachment")
		hub.Name = "Hub" .. w.name
		hub.CFrame = chassis.CFrame:ToObjectSpace(origin * CFrame.new(w.at + Vector3.new(0, REST_DROP, 0))) * slide
		hub:SetAttribute("BaseCFrame", hub.CFrame)
		hub.Parent = chassis

		local wheel = box("Wheel" .. w.name, Vector3.new(1.1, spec.radius * 2, spec.radius * 2), origin * CFrame.new(w.at), model)
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CustomPhysicalProperties = PhysicalProperties.new(1, 1.5, 0.2, 100, 1)
		wheel.CollisionGroup = "CarWheel"
		dress(spec.wheel, origin * wheelTurn(w), model, wheel)
		local axle = Instance.new("Attachment")
		axle.Name = "Axle"
		axle.Parent = wheel

		local cyl = Instance.new("CylindricalConstraint")
		cyl.Name = "Suspension"
		cyl.Attachment0, cyl.Attachment1 = hub, axle
		cyl.InclinationAngle = 90
		cyl.LimitsEnabled, cyl.UpperLimit, cyl.LowerLimit = true, UPPER, LOWER
		cyl.AngularActuatorType = if w.front then Enum.ActuatorType.None else Enum.ActuatorType.Motor
		cyl.MotorMaxTorque, cyl.AngularVelocity = 2500, 0
		cyl:SetAttribute("Drive", not w.front)
		cyl:SetAttribute("Steer", w.front)
		cyl.Parent = wheel

		local spring = Instance.new("SpringConstraint")
		spring.Attachment0, spring.Attachment1 = hub, axle
		spring.Stiffness, spring.Damping, spring.FreeLength = STIFFNESS, DAMPING, FREE_LENGTH
		spring.Parent = wheel
	end
	model:SetAttribute("WheelRadius", spec.radius)
	model:SetAttribute("Siren", spec.siren)
	return chassis, seat, Vector3.new(-CHASSIS.size.X / 2, 3.2, -0.3), CFrame.new(-CHASSIS.size.X / 2 - 2.5, 1.5, -0.3)
end

-- Getting in: a prompt at `door` (car space; T, E is grab), the seat itself sits deep in the body. The
-- driver owns the whole mechanism while seated (a passenger who sat first would otherwise); getting out
-- puts them at `exit` (chassis space), never inside the roof. `eject` (the tank): a wreck throws the
-- driver up at this speed (PoliceCar.fling: they own their physics).
local function seatUp(model: Model, chassis: BasePart, seat: VehicleSeat, origin: CFrame, label: string, door: Vector3, exit: CFrame, eject: number?)
	local spot = Instance.new("Attachment")
	spot.Name = "Door"
	spot.Position = chassis.CFrame:PointToObjectSpace(origin * door)
	spot.Parent = chassis
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Drive", label
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.T, Enum.KeyCode.ButtonL3
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 10, false
	prompt.Parent = spot
	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not seat.Occupant and not char:GetAttribute("Ragdolled") and not model:GetAttribute("Wrecked") then
			seat:Sit(hum)
		end
	end)

	local inside: Humanoid? = nil
	local groupsWere: { [BasePart]: string } = {}
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
		model:SetAttribute("Driver", if player then player.Name else "")
		prompt.Enabled = hum == nil and not model:GetAttribute("Wrecked")
		if player then
			chassis:SetNetworkOwner(player)
		elseif chassis:CanSetNetworkOwnership() then
			chassis:SetNetworkOwnershipAuto()
		end
		local left = inside
		inside = hum
		if hum and hum.Parent then
			groupsWere = driverGroup(hum.Parent :: Model)
		end
		if not hum and left and left.Parent then
			local char = left.Parent :: Model
			driverGroup(char, groupsWere)
			local at = chassis.CFrame * exit
			local thrown = eject and model:GetAttribute("Wrecked") and Players:GetPlayerFromCharacter(char)
			task.defer(function() -- after the seat weld is gone
				char:PivotTo(CFrame.new(at.Position) * chassis.CFrame.Rotation)
				if thrown and PoliceCar.fling then
					PoliceCar.fling(thrown, Vector3.new(math.random(-12, 12), eject :: number, math.random(-12, 12)))
				end
			end)
		end
	end)
end

-- A drivable car of `kind` (SPECS) with its ground point at `cf` (facing cf.LookVector), for `owner`.
function PoliceCar.spawn(cf: CFrame, owner: Player?, kind: string?): Model
	groups()
	local spec = SPECS[kind or "PoliceCar"] or SPECS.PoliceCar
	local model = Instance.new("Model")
	model.Name = kind or "PoliceCar"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the driver's client needs every constraint
	model:SetAttribute("Driver", "")
	local chassis, seat, door, exit = (spec.build or carBody)(model, spec, cf)
	seatUp(model, chassis, seat, cf, spec.label, door, exit, spec.eject)

	CollectionService:AddTag(model, "Car")
	model.Parent = workspace
	samples[model] = { t = os.clock(), v = Vector3.zero, cool = 0 }
	if owner then
		local list = owned[owner] or {}
		owned[owner] = list
		table.insert(list, model)
		while #list > PER_PLAYER do
			table.remove(list, 1):Destroy()
		end
		model.Destroying:Connect(function()
			local i = table.find(list, model)
			if i then
				table.remove(list, i)
			end
		end)
	end
	return model
end

-- Where a car of `kind` with its ground point at `at` fits, facing `look` or the nearest free quarter
-- turn of it: nothing solid (walls, players, dummies) in its box above the ground. nil when no heading fits.
function PoliceCar.fit(at: Vector3, look: Vector3, kind: string?): CFrame?
	local size = (kind and SPECS[kind] and SPECS[kind].fit) or Vector3.new(7.8, 4.6, 19)
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	for _, turn in { 0, 90, -90, 180 } do
		local cf = CFrame.lookAt(at, at + look) * CFrame.Angles(0, math.rad(turn), 0)
		if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 0.4 + size.Y / 2, 0), size, params) == 0 then
			return cf
		end
	end
	return nil
end

-- the shared pieces server/Tank.luau builds with
PoliceCar.parts = { box = box, weld = weld, dress = dress, addPanels = addPanels, groups = groups, LOOSE_LIFE = LOOSE_LIFE }
PoliceCar.fling = nil :: ((Player, Vector3) -> ())? -- set by init.server: throws a player (they own their physics)

-- Toolbox WORLD's clear: every car goes.
function PoliceCar.clear()
	for _, car in CollectionService:GetTagged("Car") do
		if car:IsDescendantOf(workspace) then
			car:Destroy()
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	for _, car in table.clone(owned[player] or {}) do
		car:Destroy()
	end
	owned[player] = nil
end)

return PoliceCar
