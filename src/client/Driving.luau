--!strict
-- Driving the cars (server/PoliceCar). While the local player sits in a DriveSeat: W/S (or the stick,
-- or touch) drive the rear wheels, A/D turn the front ones, the camera sits behind the car, Space gets
-- out. Every car with a siren and a driver flashes its light bar. Runs itself when required.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Sfx"))

local player = Players.LocalPlayer

local STEER_ANGLE = math.rad(32) -- full lock
local STEER_TIME = 0.35 -- seconds from centre to full lock
local CENTRE_TIME = 0.2 -- seconds back to straight when let go
local FAST_LOCK = 0.35 -- share of full lock left at top speed: no twitchy swerves on the straight
local THROTTLE_TIME = 0.45 -- seconds the pedal takes from 0 to full: no wheelspin, no lurch
-- Grip (on the ground only): how fast the sideways slide is taken out (per second), the push down
-- per stud/s of speed, and how fast the body's roll is damped. Calibration knobs: try them in play.
local GRIP = 6
local DOWNFORCE = 0.6
local ROLL_DAMP = 4
local GROUND_RAY = 5 -- studs under the chassis centre that still count as on the ground
local IDLE_TORQUE = 2500 -- engine brake with no throttle
local DRIVE_SIGN = -1 -- motor direction that moves the car along its LookVector (checked in play)
local CAMERA_DIST = 24
local FLASH = 0.22 -- seconds per light bar phase
local RIGHT_AFTER = 1.5 -- seconds tipped over before the car is put back on its wheels

local Driving = {}

-- the car's wheel joints, found once (a broken car has hundreds of cubes to look through)
local function joints(car: Model): { CylindricalConstraint }
	local list = {}
	for _, d in car:GetDescendants() do
		if d:IsA("CylindricalConstraint") then
			table.insert(list, d)
		end
	end
	return list
end

-- One drive step on the machine that owns the car. Throttle and steer are -1..1 (the seat's floats).
local steerNow, throttleNow = 0, 0
local function apply(car: Model, seat: VehicleSeat, throttle: number, steer: number, dt: number, list: { CylindricalConstraint }?)
	local maxW = seat.MaxSpeed / ((car:GetAttribute("WheelRadius") :: number?) or 1.4)
	-- the pedal eases in; let go (or the other way) and it comes off at once
	if throttle == 0 or math.sign(throttle) ~= math.sign(throttleNow) then
		throttleNow = 0
	end
	throttleNow += math.clamp(throttle - throttleNow, -dt / THROTTLE_TIME, dt / THROTTLE_TIME)
	-- less lock the faster it goes
	local chassis = car:FindFirstChild("Chassis") :: BasePart?
	local speed = if chassis then chassis.AssemblyLinearVelocity.Magnitude else 0
	local lock = STEER_ANGLE * (1 - (1 - FAST_LOCK) * math.clamp(speed / seat.MaxSpeed, 0, 1))
	local target = -steer * lock -- minus: a positive turn of the hub steers left (checked in play)
	local rate = (if math.abs(target) < math.abs(steerNow) then STEER_ANGLE / CENTRE_TIME else STEER_ANGLE / STEER_TIME) * dt
	steerNow += math.clamp(target - steerNow, -rate, rate)
	for _, d in list or joints(car) do
		if d.Parent then
			if d:GetAttribute("Drive") then
				-- a target speed that rises with the pedal: the wheels pull up to it instead of spinning
				d.AngularVelocity = DRIVE_SIGN * throttleNow * maxW
				d.MotorMaxTorque = if throttle == 0 then IDLE_TORQUE else seat.Torque
			elseif d:GetAttribute("Steer") then
				local hub = d.Attachment0 :: Attachment
				hub.CFrame = (hub:GetAttribute("BaseCFrame") :: CFrame) * CFrame.Angles(steerNow, 0, 0)
			end
		end
	end
end

local driving: RBXScriptConnection? = nil
local saved: { any }? = nil

local function stop()
	if driving then
		driving:Disconnect()
		driving = nil
	end
	if saved then
		player.CameraMode, player.CameraMinZoomDistance, player.CameraMaxZoomDistance = table.unpack(saved)
		saved = nil
	end
end

local function onSeat(part: BasePart?)
	stop()
	local car = part and part:IsA("VehicleSeat") and part.Parent
	if not (car and car:IsA("Model") and CollectionService:HasTag(car, "Car")) or car:GetAttribute("Tank") or car:GetAttribute("Bike") then -- the tank: client/TankClient; the bike: client/BikeClient
		return
	end
	local seat = part :: VehicleSeat
	saved = { player.CameraMode, player.CameraMinZoomDistance, player.CameraMaxZoomDistance }
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance, player.CameraMinZoomDistance = CAMERA_DIST, CAMERA_DIST
	steerNow, throttleNow = 0, 0
	local chassis = car:FindFirstChild("Chassis") :: BasePart
	local ray = RaycastParams.new()
	ray.FilterDescendantsInstances = { car, player.Character :: Model }
	local tipped = 0
	local list = joints(car)
	driving = RunService.Heartbeat:Connect(function(dt)
		if seat.Parent then
			apply(car, seat, seat.ThrottleFloat, seat.SteerFloat, dt, list)
		end
		-- grip: on its wheels on the ground, the slide sideways dies out, speed presses it down and
		-- the body stops rocking side to side (we own its physics, so we may push it)
		local cf = chassis.CFrame
		if cf.UpVector.Y > 0.7 and workspace:Raycast(chassis.Position, -cf.UpVector * GROUND_RAY, ray) then
			local v = chassis.AssemblyLinearVelocity
			local side = cf.RightVector:Dot(v)
			v -= cf.RightVector * side * math.min(1, GRIP * dt)
			v -= cf.UpVector * DOWNFORCE * v.Magnitude * dt
			chassis.AssemblyLinearVelocity = v
			local w = chassis.AssemblyAngularVelocity
			chassis.AssemblyAngularVelocity = w - cf.LookVector * cf.LookVector:Dot(w) * math.min(1, ROLL_DAMP * dt)
		end
		-- on its side or roof and nearly still for a moment: back on its wheels (we own its physics)
		local still = chassis.AssemblyLinearVelocity.Magnitude < 4
		tipped = if chassis.CFrame.UpVector.Y < 0.4 and still then tipped + dt else 0
		if tipped > RIGHT_AFTER then
			tipped = 0
			local look = chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
			local at = chassis.Position + Vector3.new(0, 4, 0)
			car:PivotTo(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look else Vector3.zAxis)))
			chassis.AssemblyLinearVelocity, chassis.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end)
end

local function onCharacter(char: Model)
	stop()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	-- getting out leaves the motors to the server's copy, which never changed: idle brake, wheels straight
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeat(hum.SeatPart)
	end)
	onSeat(hum.SeatPart)
end

-- the light bar: blue and red take turns while someone drives
local bars: { [Model]: { blue: { BasePart }, red: { BasePart } } } = {}
local function track(car: Instance)
	if car:IsA("Model") and car:GetAttribute("Siren") then
		local entry = { blue = {}, red = {} }
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") and (p.Name == "3060FF" or p.Name == "FF3030") then
				table.insert(if p.Name == "3060FF" then entry.blue else entry.red, p)
			end
		end
		bars[car] = entry
	end
end
CollectionService:GetInstanceAddedSignal("Car"):Connect(track)
CollectionService:GetInstanceRemovedSignal("Car"):Connect(function(car)
	bars[car :: Model] = nil
end)
for _, car in CollectionService:GetTagged("Car") do
	track(car)
end
local function light(parts: { BasePart }, on: boolean)
	for _, p in parts do
		p.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Transparency = if on then 0 else 0.35
	end
end
task.spawn(function()
	local phase = false
	while true do
		task.wait(FLASH)
		phase = not phase
		for car, entry in bars do
			local on = car:GetAttribute("Driver") ~= ""
			light(entry.blue, not on or phase)
			light(entry.red, not on or not phase)
		end
	end
end)

-- Every car's sounds, on every client from what replicates (the Driver attribute, the chassis
-- speed): the engine while someone drives (idle fading into the drive hum as it speeds up, the hum
-- rising in pitch), the siren on a police car, the door as a driver gets in or out, the tyres when
-- it slides sideways, a crunch when it stops dead at speed.
-- Calibration knobs: try them in play.
local SCREECH_SLIDE = 14 -- studs/s sideways that squeal
local CRASH_DROP = 30 -- studs/s of speed lost in one frame that count as a crash
type Noise = { driven: boolean, speed: number, screechAt: number, crashAt: number, loops: { Sound }? }
local noises: { [Model]: Noise } = {}
local function silence(n: Noise)
	for _, s in n.loops or {} do
		s:Destroy()
	end
	n.loops = nil
end
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, car in CollectionService:GetTagged("Car") do
		if not car:IsA("Model") or car:GetAttribute("Tank") or car:GetAttribute("Bike") then -- the tank sounds itself (client/TankClient); a bike has no engine
			continue
		end
		local chassis = (car:FindFirstChild("Chassis") or car.PrimaryPart) :: BasePart?
		local n = noises[car]
		if not n then
			n = { driven = false, speed = 0, screechAt = 0, crashAt = 0 }
			noises[car] = n
		end
		if not chassis or car:GetAttribute("Wrecked") then
			silence(n)
			continue
		end
		local driven = (car:GetAttribute("Driver") or "") ~= ""
		if driven ~= n.driven then
			n.driven = driven
			Sfx.playLocal({ Sfx.CAR_DOOR, 1, 0.7 }, chassis.Position)
			if driven then
				n.loops = { Sfx.loop(chassis, Sfx.CAR_ENGINE_IDLE_LOOP, 0, 150), Sfx.loop(chassis, Sfx.CAR_ENGINE_DRIVE_LOOP, 0, 150) }
				if car:GetAttribute("Siren") then
					table.insert(n.loops, Sfx.loop(chassis, Sfx.POLICE_SIREN_LOOP, 0.5, 300))
				end
			else
				silence(n)
			end
		end
		local v = chassis.AssemblyLinearVelocity
		local speed = v.Magnitude
		local loops = n.loops
		if loops then
			local seat = car:FindFirstChildWhichIsA("VehicleSeat", true)
			local t = math.clamp(speed / (if seat then seat.MaxSpeed else 60), 0, 1)
			loops[1].Volume = 0.5 * (1 - t)
			loops[2].Volume = 0.15 + 0.55 * t
			loops[2].PlaybackSpeed = 0.8 + 0.7 * t
			if math.abs(chassis.CFrame.RightVector:Dot(v)) > SCREECH_SLIDE and now > n.screechAt then
				n.screechAt = now + 1.4
				Sfx.playLocal({ Sfx.TIRE_SCREECH, 1, 0.6 }, chassis.Position)
			end
		end
		if n.speed - speed > CRASH_DROP and now > n.crashAt then
			n.crashAt = now + 1
			Sfx.playLocal({ Sfx.CAR_CRASH, 1, math.clamp((n.speed - speed) / 60, 0.4, 1) }, chassis.Position)
		end
		n.speed = speed
	end
end)
CollectionService:GetInstanceRemovedSignal("Car"):Connect(function(car)
	local n = noises[car :: Model]
	if n then
		silence(n)
		noises[car :: Model] = nil
	end
end)

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

Driving.apply = apply
return Driving
