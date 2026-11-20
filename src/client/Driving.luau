--!strict
-- Driving the police car (server/PoliceCar). While the local player sits in its DriveSeat: W/S (or
-- the stick, or touch) drive the rear wheels, A/D turn the front ones, the camera sits behind the car,
-- Space gets out. Every car with a driver flashes its light bar. Runs itself when required.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local STEER_ANGLE = math.rad(32) -- full lock
local STEER_TIME = 0.35 -- seconds from centre to full lock
local IDLE_TORQUE = 2500 -- engine brake with no throttle
local DRIVE_SIGN = -1 -- motor direction that moves the car along its LookVector (checked in play)
local CAMERA_DIST = 24
local FLASH = 0.22 -- seconds per light bar phase
local RIGHT_AFTER = 1.5 -- seconds tipped over before the car is put back on its wheels

local Driving = {}

-- One drive step on the machine that owns the car. Throttle and steer are -1..1 (the seat's floats).
local steerNow = 0
local function apply(car: Model, seat: VehicleSeat, throttle: number, steer: number, dt: number)
	local maxW = seat.MaxSpeed / ((car:GetAttribute("WheelRadius") :: number?) or 1.4)
	local step = STEER_ANGLE / STEER_TIME * dt
	steerNow += math.clamp(-steer * STEER_ANGLE - steerNow, -step, step) -- minus: a positive turn of the hub steers left (checked in play)
	for _, d in car:GetDescendants() do
		if d:IsA("CylindricalConstraint") then
			if d:GetAttribute("Drive") then
				d.AngularVelocity = DRIVE_SIGN * math.sign(throttle) * maxW
				d.MotorMaxTorque = if throttle == 0 then IDLE_TORQUE else math.abs(throttle) * seat.Torque
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
	if not (car and car:IsA("Model") and CollectionService:HasTag(car, "PoliceCar")) then
		return
	end
	local seat = part :: VehicleSeat
	saved = { player.CameraMode, player.CameraMinZoomDistance, player.CameraMaxZoomDistance }
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance, player.CameraMinZoomDistance = CAMERA_DIST, CAMERA_DIST
	steerNow = 0
	local chassis = car:FindFirstChild("Chassis") :: BasePart
	local tipped = 0
	driving = RunService.Heartbeat:Connect(function(dt)
		if seat.Parent then
			apply(car, seat, seat.ThrottleFloat, seat.SteerFloat, dt)
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
	if car:IsA("Model") then
		local entry = { blue = {}, red = {} }
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") and (p.Name == "3060FF" or p.Name == "FF3030") then
				table.insert(if p.Name == "3060FF" then entry.blue else entry.red, p)
			end
		end
		bars[car] = entry
	end
end
CollectionService:GetInstanceAddedSignal("PoliceCar"):Connect(track)
CollectionService:GetInstanceRemovedSignal("PoliceCar"):Connect(function(car)
	bars[car :: Model] = nil
end)
for _, car in CollectionService:GetTagged("PoliceCar") do
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

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

Driving.apply = apply
return Driving
