--!strict
-- The COSMIC bike (assets/bike/cosmic_bike.py, uploaded as the group's model BIKE_ASSET): a kind of
-- server/PoliceCar, so spawning (Toolbox SPAWN), the T prompt, the seat, network ownership and Space
-- to get off all come from there. Its physics: an invisible frame box carrying the frame mesh and the
-- saddle, the rear wheel on a motor hinge, the fork (Bike_Steering) on a servo hinge round the head
-- tube carrying the front wheel, the cranks on their own motor hinge, and an AlignOrientation
-- ("Upright") that holds it up. The rider's client pedals, steers and leans it (client/BikeClient).
--
-- Bike space: the asset's own, ground at y 0, front toward -Z, 1 stud = 0.28 m (the asset is pre-scaled).

local InsertService = game:GetService("InsertService")

local PoliceCar = require(script.Parent.PoliceCar)

local Bike = {}

local parts = PoliceCar.parts
local box, weld = parts.box, parts.weld

local BIKE_ASSET = 75923488065842
local AXIS = Vector3.new(0, 0.921, 0.391).Unit -- the head tube, up and back (cosmic_bike.py AXIS)
local SEAT = CFrame.new(0, 3.2, 1.0) -- the VehicleSeat on the saddle
local CHASSIS = { size = Vector3.new(0.7, 1.0, 3.4), y = 1.7 }
local WHEEL = Vector3.new(0.5, 2.66, 2.66) -- cylinder along X, the tyre's outer size
-- Gameplay numbers (the client reads them off the model's attributes). Calibration knobs.
local STATS = { MaxSpeed = 40, Torque = 1800 }

local template: Model? = nil
local function kit(): Model?
	if not template then
		local ok, res = pcall(InsertService.LoadAsset, InsertService, BIKE_ASSET)
		local frame = ok and (res :: Model):FindFirstChild("Bike_Frame", true)
		if frame then
			template = frame.Parent :: Model
		else
			warn("bike asset", BIKE_ASSET, res)
		end
	end
	return template
end
task.spawn(kit)

-- a hinge between a and b round `at`'s X axis (world)
local function hinge(name: string, a: BasePart, b: BasePart, at: CFrame, kind: Enum.ActuatorType): HingeConstraint
	local a0 = Instance.new("Attachment")
	a0.Name, a0.CFrame = name .. "0", a.CFrame:ToObjectSpace(at)
	a0.Parent = a
	local a1 = Instance.new("Attachment")
	a1.Name, a1.CFrame = name .. "1", b.CFrame:ToObjectSpace(at)
	a1.Parent = b
	local h = Instance.new("HingeConstraint")
	h.Name, h.Attachment0, h.Attachment1, h.ActuatorType = name, a0, a1, kind
	h.Parent = b
	return h
end

local function build(model: Model, _spec, origin: CFrame): (BasePart, VehicleSeat, Vector3, CFrame)
	local source = kit()
	assert(source, "bike asset not loaded")
	local function piece(name: string): MeshPart
		local p = (source:FindFirstChild(name) :: MeshPart):Clone()
		p.CFrame = origin * p.CFrame
		p.Anchored, p.CanCollide, p.CanTouch, p.CollisionGroup = false, false, false, "CarBody"
		p.Parent = model
		return p
	end

	local chassis = box("Chassis", CHASSIS.size, origin * CFrame.new(0, CHASSIS.y, 0), model)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(3, 0.3, 0.3)
	chassis.CollisionGroup = "CarBody"
	chassis.RootPriority = 10 -- the root even with a rider on: sitting must not swing the bike round to the rider
	model.PrimaryPart = chassis
	local frame = piece("Bike_Frame")
	frame.Massless = true
	weld(chassis, frame)

	local function wheel(name: string, mesh: MeshPart): BasePart
		local w = box(name, WHEEL, mesh:GetPivot(), model)
		w.Shape = Enum.PartType.Cylinder
		w.CustomPhysicalProperties = PhysicalProperties.new(1, 1.5, 0.2, 100, 1)
		w.CollisionGroup = "CarWheel"
		mesh.Massless = true
		weld(w, mesh)
		return w
	end
	local rear = wheel("WheelRear", piece("Bike_Wheel_Rear"))
	local drive = hinge("Drive", chassis, rear, rear.CFrame, Enum.ActuatorType.Motor)
	drive.MotorMaxTorque, drive.AngularVelocity = 60, 0

	-- the fork turns round the head tube: X of the hinge frame along AXIS
	local fork = piece("Bike_Steering")
	local axis = origin:VectorToWorldSpace(AXIS)
	local steer = hinge("Steer", chassis, fork, CFrame.fromMatrix(fork:GetPivot().Position, axis, origin.RightVector), Enum.ActuatorType.Servo)
	steer.ServoMaxTorque, steer.AngularSpeed = 4e4, 8
	steer.LimitsEnabled, steer.LowerAngle, steer.UpperAngle = true, -45, 45
	local front = wheel("WheelFront", piece("Bike_Wheel_Front"))
	hinge("Axle", fork, front, front.CFrame, Enum.ActuatorType.None)

	local cranks = piece("Bike_Crankset")
	local turn = hinge("Cranks", chassis, cranks, CFrame.new(cranks:GetPivot().Position) * origin.Rotation, Enum.ActuatorType.Motor)
	turn.MotorMaxTorque, turn.AngularVelocity = 1e4, 0

	-- held up, facing its heading; the rider's client steers and leans the target (client/BikeClient)
	local up = Instance.new("Attachment")
	up.Name = "UprightAxis"
	up.Parent = chassis
	local align = Instance.new("AlignOrientation")
	align.Name, align.Mode = "Upright", Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0, align.CFrame = up, origin.Rotation
	align.MaxTorque, align.Responsiveness = 4e4, 25
	align.Parent = chassis

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = Vector3.new(1, 0.2, 1.2)
	seat.CFrame = origin * SEAT
	seat.Transparency, seat.Massless, seat.CanCollide, seat.CollisionGroup = 1, true, false, "CarBody"
	seat.MaxSpeed, seat.Torque, seat.HeadsUpDisplay = STATS.MaxSpeed, STATS.Torque, false
	seat.Parent = model
	weld(chassis, seat)
	-- parked: stand facing wherever the rider left it (their client's target never reached here)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local look = chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
		if not seat.Occupant and look.Magnitude > 0.1 then
			align.CFrame = CFrame.lookAt(Vector3.zero, look)
		end
	end)

	model:SetAttribute("Bike", true)
	model:SetAttribute("CrashAt", 1e9) -- no car crash blasts: a bike just stops
	model:SetAttribute("WheelRadius", WHEEL.Y / 2)
	-- the prompt by the left pedal; off to the left, on the ground
	return chassis, seat, Vector3.new(-1.6, 2.4, 0.6), CFrame.new(-2.8, 1.3, 0.6)
end

-- a still copy for the Toolbox's stage, origin on the ground (empty if the asset did not load)
local function preview(): Model
	local source = kit()
	local m = if source then source:Clone() else Instance.new("Model")
	m.Name = "Bike"
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	return m
end

PoliceCar.KINDS.Bike.build = build
PoliceCar.KINDS.Bike.preview = preview

return Bike
