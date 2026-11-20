--!strict
-- The drivable police car: the Blender meshes (assets/army/build.py police_car -> ReplicatedStorage.ArmyKit
-- Cop_Body / Cop_Wheel) on a constraint chassis. Per wheel one CylindricalConstraint (slide, spin,
-- motor) plus one SpringConstraint on the same attachments (scenario-roblox-gameplay Car).
-- The driver's client turns the seat's throttle and steer into motor speeds (client/Driving.luau);
-- the server hands the driver network ownership and gets them out beside the door.
--
-- Car space: ground under the middle of the car at y 0, front toward -Z (the model's LookVector).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PoliceCar = {}

local RADIUS = 1.4 -- wheel radius (build.py: tyre 2.8 across)
local WHEELS = { -- hub in car space; front ones steer, rear ones drive
	{ name = "FL", at = Vector3.new(-3.25, RADIUS, -5.2), front = true },
	{ name = "FR", at = Vector3.new(3.25, RADIUS, -5.2), front = true },
	{ name = "RL", at = Vector3.new(-3.25, RADIUS, 5.3), front = false },
	{ name = "RR", at = Vector3.new(3.25, RADIUS, 5.3), front = false },
}
local CHASSIS = { size = Vector3.new(6.6, 1.6, 16.8), y = 2.6 } -- the low heavy floor, car space
local CABIN = { size = Vector3.new(6.2, 2.0, 7.6), at = Vector3.new(0, 4.35, 0.6) }
-- suspension: the wheel hangs 1..2 studs under its hub, resting at 1.5; the spring carries the car
-- there (chassis ~106 + driver ~10 mass: 4 x 4400 x 1.3 compression ~ its weight)
local UPPER, LOWER, FREE_LENGTH, STIFFNESS, DAMPING = -1, -2, 2.8, 4400, 260
local REST_DROP = -(UPPER + LOWER) / 2
local MAX_SPEED, TORQUE = 60, 5000 -- studs/s, MotorMaxTorque at full throttle (0 to 60 in about 2 s)
local PER_PLAYER = 2 -- cars one player can have out; the oldest goes

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

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
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

local function wheelTurn(w): CFrame -- the kit wheel faces +X; the left ones turn half round
	return CFrame.new(w.at) * (if w.at.X < 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
end

-- A still, anchored copy for the Toolbox's stage (ToolboxPreviews), origin on the ground.
function PoliceCar.preview(): Model
	local m = Instance.new("Model")
	m.Name = "PoliceCar"
	dress("Cop_Body", CFrame.identity, m)
	for _, w in WHEELS do
		dress("Cop_Wheel", wheelTurn(w), m)
	end
	return m
end

-- A drivable car with its ground point at `cf` (facing cf.LookVector), for `owner`.
function PoliceCar.spawn(cf: CFrame, owner: Player?): Model
	groups()
	local model = Instance.new("Model")
	model.Name = "PoliceCar"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the driver's client needs every constraint
	local origin = cf

	local chassis = box("Chassis", CHASSIS.size, origin * CFrame.new(0, CHASSIS.y, 0), model)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.3, 0.3)
	chassis.CollisionGroup = "CarBody"
	model.PrimaryPart = chassis
	local cabin = box("Cabin", CABIN.size, origin * CFrame.new(CABIN.at), model)
	cabin.Massless, cabin.CollisionGroup = true, "CarBody"
	weld(chassis, cabin)
	dress("Cop_Body", origin, model, chassis)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(1.6, 0.4, 1.6)
	seat.CFrame = origin * CFrame.new(-1.4, 1.5, -0.3) -- low: a seated R15 head stays under the roof
	seat.Transparency, seat.Massless, seat.CollisionGroup = 1, true, "CarBody"
	seat.MaxSpeed, seat.Torque, seat.HeadsUpDisplay = MAX_SPEED, TORQUE, false
	seat.Parent = model
	weld(chassis, seat)

	-- Attachment0 on the chassis: X up (the slide axis), Y to the right (the axle once InclinationAngle
	-- is 90). Attachment1 on the wheel: X along the cylinder, its axle.
	local slide = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	for _, w in WHEELS do
		local hub = Instance.new("Attachment")
		hub.Name = "Hub" .. w.name
		hub.CFrame = chassis.CFrame:ToObjectSpace(origin * CFrame.new(w.at + Vector3.new(0, REST_DROP, 0))) * slide
		hub:SetAttribute("BaseCFrame", hub.CFrame)
		hub.Parent = chassis

		local wheel = box("Wheel" .. w.name, Vector3.new(1.1, RADIUS * 2, RADIUS * 2), origin * CFrame.new(w.at), model)
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CustomPhysicalProperties = PhysicalProperties.new(1, 1.5, 0.2, 100, 1)
		wheel.CollisionGroup = "CarWheel"
		dress("Cop_Wheel", origin * wheelTurn(w), model, wheel)
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
	model:SetAttribute("WheelRadius", RADIUS)
	model:SetAttribute("Driver", "")

	-- getting in: a prompt by the driver's door (T; E is grab), the seat itself sits deep in the body
	local door = Instance.new("Attachment")
	door.Name = "Door"
	door.Position = chassis.CFrame:PointToObjectSpace(origin * Vector3.new(-CHASSIS.size.X / 2, 3.2, -0.3))
	door.Parent = chassis
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Drive", "Police car"
	prompt.KeyboardKeyCode, prompt.GamepadKeyCode = Enum.KeyCode.T, Enum.KeyCode.ButtonL3
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 10, false
	prompt.Parent = door
	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not seat.Occupant and not char:GetAttribute("Ragdolled") then
			seat:Sit(hum)
		end
	end)

	-- the driver owns the whole mechanism while seated (a passenger who sat first would otherwise);
	-- getting out puts them beside the driver's door, never inside the roof
	local inside: Humanoid? = nil
	local groupsWere: { [BasePart]: string } = {}
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local hum = seat.Occupant
		local player = hum and Players:GetPlayerFromCharacter(hum.Parent)
		model:SetAttribute("Driver", if player then player.Name else "")
		prompt.Enabled = hum == nil
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
			task.defer(function() -- after the seat weld is gone
				local at = chassis.CFrame * CFrame.new(-CHASSIS.size.X / 2 - 2.5, 1.5, -0.3)
				char:PivotTo(CFrame.new(at.Position) * chassis.CFrame.Rotation)
			end)
		end
	end)

	CollectionService:AddTag(model, "PoliceCar")
	model.Parent = workspace
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

-- Where a car with its ground point at `at` fits, facing `look` or the nearest free quarter turn of it:
-- nothing solid (walls, players, dummies) in its box above the ground. nil when no heading fits.
function PoliceCar.fit(at: Vector3, look: Vector3): CFrame?
	local params = OverlapParams.new()
	params.RespectCanCollide = true
	for _, turn in { 0, 90, -90, 180 } do
		local cf = CFrame.lookAt(at, at + look) * CFrame.Angles(0, math.rad(turn), 0)
		if #workspace:GetPartBoundsInBox(cf * CFrame.new(0, 2.7, 0), Vector3.new(7.8, 4.6, 19), params) == 0 then
			return cf
		end
	end
	return nil
end

-- Toolbox WORLD's clear: every car goes.
function PoliceCar.clear()
	for _, car in CollectionService:GetTagged("PoliceCar") do
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
