--!strict
-- Riding the bike (server/Bike.luau). While the local player sits on one: W pedals (the rear wheel's
-- motor), S brakes and then backs up slowly, A/D turn the fork (a servo round the head tube) and lean
-- the bike round and into the turn (its Upright AlignOrientation), the cranks turn with the back wheel while
-- pedalling, the camera sits behind, Space gets off. The rider owns its physics while seated
-- (server/PoliceCar hands it over), so the constraint targets set here are the ones that count.
-- Runs itself when required.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Calibration knobs: try them in play.
local STEER = 32 -- degrees of fork at a standstill
local FAST_STEER = 0.35 -- share of it left at top speed
local STEER_RATE = 140 -- degrees/s the bars turn
local LEAN = math.rad(24) -- into a full turn at LEAN_SPEED and over
local LEAN_SPEED = 24 -- studs/s
local PUSH_TIME = 0.7 -- seconds the pedalling takes from 0 to full
local COAST_TORQUE = 60 -- rolling drag with no pedal
local BRAKE_TORQUE = 2500
local BACK_SPEED = 6 -- studs/s backing up on S
local GRIP = 5 -- per second: how fast a sideways slide is taken out (on the ground)
local TURN_TORQUE = 1e6 -- the Upright's pull while riding: it sets the heading, the wheels only roll
local AHEAD = 0.3 -- radians the steered heading may run ahead of the bike (against a wall: no wind-up)
local WHEELBASE = 3.68 -- studs between the hubs
local GROUND_RAY = 3.5 -- studs under the frame box that still count as on the ground
local CRANK_RATIO = 0.45 -- crank turns per wheel turn
local DRIVE_SIGN = -1 -- hinge direction that rolls it along its LookVector (checked in play)
local STEER_SIGN = 1 -- fork direction that turns it right on D (checked in play)
local CAMERA_DIST = 14
local RIGHT_AFTER = 1.2 -- seconds on its side and still before it is stood back up

local riding: RBXScriptConnection? = nil
local saved: { any }? = nil

local function stop()
	if riding then
		riding:Disconnect()
		riding = nil
	end
	if saved then
		player.CameraMode, player.CameraMinZoomDistance, player.CameraMaxZoomDistance = table.unpack(saved)
		saved = nil
	end
end

local function ride(bike: Model, seat: VehicleSeat)
	local chassis = bike:FindFirstChild("Chassis") :: BasePart
	local drive = bike:FindFirstChild("Drive", true) :: HingeConstraint
	local steer = bike:FindFirstChild("Steer", true) :: HingeConstraint
	local cranks = bike:FindFirstChild("Cranks", true) :: HingeConstraint
	local upright = chassis:FindFirstChild("Upright") :: AlignOrientation
	local rear = drive.Parent :: BasePart
	local maxW = seat.MaxSpeed / ((bike:GetAttribute("WheelRadius") :: number?) or 1.33)
	local ray = RaycastParams.new()
	ray.FilterDescendantsInstances = { bike, player.Character :: Model }
	local push, fork, tipped = 0, 0, 0
	local heading = math.atan2(-chassis.CFrame.LookVector.X, -chassis.CFrame.LookVector.Z)
	upright.MaxTorque = TURN_TORQUE
	saved = { player.CameraMode, player.CameraMinZoomDistance, player.CameraMaxZoomDistance }
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance, player.CameraMinZoomDistance = CAMERA_DIST, CAMERA_DIST
	riding = RunService.Heartbeat:Connect(function(dt)
		if not (seat.Parent and chassis.Parent) then
			return
		end
		local cf = chassis.CFrame
		local v = chassis.AssemblyLinearVelocity
		local speed = v:Dot(cf.LookVector)
		local throttle, turn = seat.ThrottleFloat, seat.SteerFloat
		-- pedals: ease in; S brakes while rolling forward, then backs up
		push = if throttle > 0 then math.min(1, push + dt / PUSH_TIME) else 0
		if throttle > 0 then
			drive.AngularVelocity, drive.MotorMaxTorque = DRIVE_SIGN * push * maxW, seat.Torque
		elseif throttle < 0 and speed > 2 then
			drive.AngularVelocity, drive.MotorMaxTorque = 0, BRAKE_TORQUE
		elseif throttle < 0 then
			drive.AngularVelocity, drive.MotorMaxTorque = -DRIVE_SIGN * BACK_SPEED * maxW / seat.MaxSpeed, seat.Torque * 0.5
		else
			drive.AngularVelocity, drive.MotorMaxTorque = 0, COAST_TORQUE
		end
		-- bars: less lock the faster it goes
		local fast = math.clamp(math.abs(speed) / seat.MaxSpeed, 0, 1)
		local lock = STEER * (1 - (1 - FAST_STEER) * fast)
		local want = turn * lock
		fork += math.clamp(want - fork, -STEER_RATE * dt, STEER_RATE * dt)
		steer.TargetAngle = STEER_SIGN * fork
		-- arcade steering: the heading turns as the fork points (yaw rate = speed * tan(fork) / wheelbase,
		-- fork + turns right), the Upright holds it there leaned into the turn; pitch follows the ground
		-- under it (in the air: wherever it is), never its own last pitch, which would freeze it
		local look = cf.LookVector
		local ground = if cf.UpVector.Y > 0.6 then workspace:Raycast(chassis.Position, -cf.UpVector * GROUND_RAY, ray) else nil
		local now = math.atan2(-look.X, -look.Z)
		heading -= speed * math.tan(math.rad(fork)) / WHEELBASE * dt
		heading = now + math.clamp((heading - now + math.pi) % (2 * math.pi) - math.pi, -AHEAD, AHEAD)
		local lean = math.clamp(fork / lock, -1, 1) * LEAN * math.clamp(math.abs(speed) / LEAN_SPEED, 0, 1)
		local along = if ground then look - ground.Normal * look:Dot(ground.Normal) else look
		local pitch = math.asin(math.clamp(along.Unit.Y, -1, 1))
		upright.CFrame = CFrame.Angles(0, heading, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, -lean)
		-- cranks: turn with the back wheel while pedalling, freewheel otherwise
		local spin = (rear.AssemblyAngularVelocity - chassis.AssemblyAngularVelocity):Dot(drive.Attachment0.WorldAxis)
		cranks.AngularVelocity = if push > 0 then spin * CRANK_RATIO else 0
		-- grip: on the ground a bike rolls, it does not slide sideways
		if ground then
			local side = cf.RightVector:Dot(v)
			chassis.AssemblyLinearVelocity = v - cf.RightVector * side * math.min(1, GRIP * dt)
		end
		-- down and nearly still for a moment: stood back up
		tipped = if cf.UpVector.Y < 0.5 and v.Magnitude < 4 then tipped + dt else 0
		if tipped > RIGHT_AFTER then
			tipped = 0
			local flat = look * Vector3.new(1, 0, 1)
			local at = chassis.Position + Vector3.new(0, 2, 0)
			bike:PivotTo(CFrame.lookAt(at, at + (if flat.Magnitude > 0.1 then flat else Vector3.zAxis)))
			chassis.AssemblyLinearVelocity, chassis.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			heading = math.atan2(-chassis.CFrame.LookVector.X, -chassis.CFrame.LookVector.Z)
		end
	end)
end

local function onSeat(part: BasePart?)
	stop()
	local bike = part and part:IsA("VehicleSeat") and part.Parent
	if bike and bike:IsA("Model") and bike:GetAttribute("Bike") and CollectionService:HasTag(bike, "Car") then
		ride(bike, part :: VehicleSeat)
	end
end

local function onCharacter(char: Model)
	stop()
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeat(hum.SeatPart)
	end)
	onSeat(hum.SeatPart)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

return {}
