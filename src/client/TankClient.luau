--!strict
-- The tank (server/Tank) on the client. While the local player sits in one: W/S drive, A/D turn (in
-- place when there is no throttle: the tracks pull against each other), the stick and touch work
-- through the seat as in the cars (client/Driving), the turret and gun follow the camera at their own
-- rates, LMB / R2 / FIRE shoots, Space gets out. The camera sits behind and above the turret; the
-- reticle shows where a shell would land now (arc included) and fills up while it reloads. For every
-- tank on every client: road wheels spin with their track's speed, the gun kicks back and flashes
-- when it fires, the engine, tracks and turret are heard. Runs itself when required.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))
local remote = ReplicatedStorage:WaitForChild("TankControl") :: RemoteEvent

local player = Players.LocalPlayer

-- Driving feel. Calibration knobs: try them in play.
local ACCEL = 9 -- studs/s² speeding up (0 to 22 in about 2.5 s: heavy)
local BRAKE = 18 -- studs/s² slowing down
local TURN_RATE = math.rad(45) -- turning in place
local TURN_ACCEL = math.rad(150)
local TRACK_HALF = 3.9 -- studs from the middle to each track
local PUSH = 90 -- studs/s² at most the drive pulls the hull toward its wanted speed
local TWIST = 12 -- rad/s² at most it pulls the turn rate
local SLIP = 6 -- studs/s the wanted speed may run ahead of the real one (blocked: no wind-up)
local GRIP = 8 -- per second: how fast a sideways slide dies out
local STEADY = 5 -- per second: how fast rocking and rolling die out (it does not tip in turns)
local GROUND_RAY = 6
local RIGHT_AFTER = 1.5 -- seconds on its side before it is put back on its tracks
local CAMERA_DIST = 26
local CAMERA_UP = 6 -- the camera looks over the turret at a point this far above it
local AIM_RANGE = 600
local SEND_EVERY = 0.08 -- seconds between aim updates to the server
local WHEEL_R = 1.4

local Tank = {}

-- every tank: its joints, found once
type Rig = { chassis: BasePart, yawM: Weld?, pitchM: Weld?, mount: Weld?, gun: BasePart?, spins: { Weld },
	angle: { [number]: number }, kick: number, lastYaw: CFrame?, loops: { Sound }?, speed: number, crashAt: number }
local rigs: { [Model]: Rig } = {}

local function rigOf(model: Model): Rig?
	local rig = rigs[model]
	if rig and rig.chassis.Parent then
		return rig
	end
	local chassis = model:FindFirstChild("Chassis") :: BasePart?
	if not (chassis and model:GetAttribute("Tank")) then
		return nil
	end
	local spins = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Spin" then
			table.insert(spins, d)
		end
	end
	local ring = model:FindFirstChild("Turret")
	local gun = model:FindFirstChild("Gun") :: BasePart?
	local panels = model:FindFirstChild("Panels")
	local barrel = panels and panels:FindFirstChild("Tank_Barrel")
	local collider = barrel and (barrel :: Model).PrimaryPart
	rig = {
		chassis = chassis, spins = spins, angle = { [-1] = 0, [1] = 0 }, kick = 0, speed = 0, crashAt = 0,
		yawM = ring and ring:FindFirstChild("Yaw") :: Weld?, pitchM = gun and gun:FindFirstChild("Pitch") :: Weld?,
		mount = collider and collider:FindFirstChild("Mount") :: Weld?, gun = gun,
	}
	rigs[model] = rig
	return rig
end

local function stat(model: Model, name: string): number
	return (model:GetAttribute(name) :: number?) or 0
end

local function trackUp(model: Model, name: string): boolean -- a broken track (server/PoliceCar BROKEN_AT) pulls no more
	local panels = model:FindFirstChild("Panels")
	local p = panels and panels:FindFirstChild(name)
	return p ~= nil and not p:GetAttribute("Broken")
end

-- Where a shell fired now would come down: flown in steps like the server's, raycast.
local function impact(model: Model, gun: BasePart, ignore: { Instance }): Vector3
	local muzzle = gun.CFrame * CFrame.new(0, 0, -stat(model, "Muzzle"))
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = ignore
	local position, velocity = muzzle.Position, muzzle.LookVector * stat(model, "ShellSpeed")
	local drop, dt = stat(model, "ShellDrop"), 1 / 30
	for _ = 1, 90 do
		local step = velocity * dt
		local hit = workspace:Raycast(position, step, params)
		if hit then
			return hit.Position
		end
		position += step
		velocity -= Vector3.new(0, drop * dt, 0)
	end
	return position
end

-- The gun elevation (world, radians) that lands a shell at `target` from `from`: the low arc.
local function elevation(from: Vector3, target: Vector3, speed: number, drop: number): number
	local d = target - from
	local x = (d * Vector3.new(1, 0, 1)).Magnitude
	if x < 1 or drop <= 0 then
		return math.atan2(d.Y, math.max(x, 0.01))
	end
	local v2 = speed * speed
	local disc = v2 * v2 - drop * (drop * x * x + 2 * d.Y * v2)
	if disc < 0 then
		return math.rad(45) -- out of reach: as far as it goes
	end
	return math.atan((v2 - math.sqrt(disc)) / (drop * x))
end

---------------------------------------------------------------------------------- the HUD
local function hud(): (ScreenGui, Frame, Frame, TextButton?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "TankHud"
	gui.IgnoreGuiInset, gui.ResetOnSpawn = true, false
	local dot = Instance.new("Frame")
	dot.AnchorPoint, dot.Position, dot.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", dot)
	stroke.Thickness = 1.5
	dot.Parent = gui
	local reticle = Instance.new("Frame")
	reticle.Name = "Reticle"
	reticle.AnchorPoint, reticle.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(46, 46)
	reticle.BackgroundTransparency = 1
	Instance.new("UICorner", reticle).CornerRadius = UDim.new(1, 0)
	local ring = Instance.new("UIStroke", reticle)
	ring.Color, ring.Thickness = Color3.fromRGB(255, 225, 120), 3
	local outline = Instance.new("Frame") -- the comic black edge round it
	outline.AnchorPoint, outline.Position, outline.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.new(1, 8, 1, 8)
	outline.BackgroundTransparency = 1
	Instance.new("UICorner", outline).CornerRadius = UDim.new(1, 0)
	Instance.new("UIStroke", outline).Thickness = 2
	outline.Parent = reticle
	local bar = Instance.new("Frame") -- reloading: the bar under the reticle fills
	bar.Name = "Reload"
	bar.AnchorPoint, bar.Position, bar.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 1, 10), UDim2.fromOffset(70, 9)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 32)
	Instance.new("UIStroke", bar).Thickness = 2
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	bar.Parent = reticle
	reticle.Parent = gui
	local fire: TextButton? = nil
	if UserInputService.TouchEnabled then
		local b = Instance.new("TextButton")
		b.Name = "Fire"
		b.AnchorPoint, b.Position, b.Size = Vector2.new(1, 1), UDim2.new(1, -110, 1, -150), UDim2.fromOffset(96, 96)
		b.BackgroundColor3 = Color3.fromRGB(220, 60, 40)
		b.Text, b.Font, b.TextSize, b.TextColor3 = "FIRE", Enum.Font.FredokaOne, 28, Color3.new(1, 1, 1)
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		Instance.new("UIStroke", b).Thickness = 3
		b.Parent = gui
		fire = b
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, reticle, fill, fire
end

---------------------------------------------------------------------------------- driving it
local session: { stop: () -> () }? = nil
local shake = 0 -- camera shake left (seconds), set by our own shot

local function drive(model: Model, seat: VehicleSeat)
	local rig = rigOf(model)
	if not rig then
		return
	end
	local chassis = rig.chassis
	local char = player.Character :: Model
	local ignore = { model, char }
	local conns: { RBXScriptConnection } = {}
	local camera = workspace.CurrentCamera
	local saved = { player.CameraMode, player.CameraMinZoomDistance, player.CameraMaxZoomDistance, camera.CameraSubject }
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance, player.CameraMinZoomDistance = CAMERA_DIST, CAMERA_DIST
	local focus = Instance.new("Part") -- what the camera orbits: a point over the turret
	focus.Name = "TankCameraFocus"
	focus.Anchored, focus.CanCollide, focus.CanQuery, focus.CanTouch, focus.Transparency = true, false, false, false, 1
	focus.Size = Vector3.one * 0.2
	focus.Parent = workspace
	camera.CameraSubject = focus
	-- the rollers roll free while we drive (the server's copy keeps them braked for when we leave)
	for _, d in model:GetDescendants() do
		if d:IsA("CylindricalConstraint") then
			d.MotorMaxTorque = 0
		end
	end
	local gui, reticle, fill, fireButton = hud()
	local yaw, pitch, wantYaw, wantPitch, sentAt = 0, 0, 0, 0, 0
	local speedNow, spinNow = 0, 0 -- the drive's wanted forward speed and turn rate, ramped
	local tipped = 0

	local function shoot()
		local reload = stat(model, "Reload")
		if os.clock() - (model:GetAttribute("ClientFiredAt") :: number? or -99) >= reload then
			remote:FireServer("fire")
		end
	end
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			shoot()
		end
	end))
	if fireButton then
		table.insert(conns, fireButton.Activated:Connect(shoot))
	end

	-- before the camera: the focus point, the mouse held in the middle (moving it turns the camera)
	RunService:BindToRenderStep("TankCamera", Enum.RenderPriority.Camera.Value - 1, function()
		local ring = model:FindFirstChild("Turret") :: BasePart?
		focus.CFrame = CFrame.new((if ring then ring.Position else chassis.Position) + Vector3.new(0, CAMERA_UP, 0))
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end)
	-- after the camera: turret and gun toward where it looks, the reticle, our shot's shake
	RunService:BindToRenderStep("TankAim", Enum.RenderPriority.Camera.Value + 1, function(dt)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local gun = rig.gun
		if rig.yawM and rig.yawM.Parent == model:FindFirstChild("Turret") and rig.pitchM and gun then
			local cam = camera.CFrame
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = ignore
			local hit = workspace:Raycast(cam.Position, cam.LookVector * AIM_RANGE, params)
			local target = if hit then hit.Position else cam.Position + cam.LookVector * AIM_RANGE
			local from = gun.Position
			local up = elevation(from, target, stat(model, "ShellSpeed"), stat(model, "ShellDrop"))
			local flat = (target - from) * Vector3.new(1, 0, 1)
			flat = if flat.Magnitude > 0.01 then flat.Unit else chassis.CFrame.LookVector
			local l = chassis.CFrame:VectorToObjectSpace(flat * math.cos(up) + Vector3.yAxis * math.sin(up))
			wantYaw = math.atan2(-l.X, -l.Z)
			wantPitch = math.clamp(math.atan2(l.Y, math.sqrt(l.X * l.X + l.Z * l.Z)), math.rad(stat(model, "PitchMin")), math.rad(stat(model, "PitchMax")))
			local turn = (wantYaw - yaw + math.pi) % (2 * math.pi) - math.pi
			local yr, pr = math.rad(stat(model, "YawRate")) * dt, math.rad(stat(model, "PitchRate")) * dt
			yaw = (yaw + math.clamp(turn, -yr, yr)) % (2 * math.pi)
			pitch += math.clamp(wantPitch - pitch, -pr, pr)
			rig.yawM.C0 = (rig.yawM:GetAttribute("Base") :: CFrame) * CFrame.Angles(0, yaw, 0)
			rig.pitchM.C0 = (rig.pitchM:GetAttribute("Base") :: CFrame) * CFrame.Angles(pitch, 0, 0)
			if os.clock() - sentAt > SEND_EVERY then
				sentAt = os.clock()
				remote:FireServer("aim", wantYaw, wantPitch)
			end
			local screen, onScreen = camera:WorldToViewportPoint(impact(model, gun, ignore))
			reticle.Visible = onScreen
			reticle.Position = UDim2.fromOffset(screen.X, screen.Y)
		end
		local reload = stat(model, "Reload")
		local t = math.clamp((os.clock() - (model:GetAttribute("ClientFiredAt") :: number? or -99)) / reload, 0, 1)
		fill.Size = UDim2.fromScale(t, 1)
		fill.Parent.Visible = t < 1
		if shake > 0 then
			shake -= dt
			local k = shake * 0.06
			camera.CFrame *= CFrame.Angles((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
		end
	end)

	-- the drive itself, on the machine that owns its physics (us)
	table.insert(conns, RunService.Heartbeat:Connect(function(dt)
		if not seat.Parent or model:GetAttribute("Wrecked") then
			return
		end
		local maxS = stat(model, "MaxSpeed")
		local throttle, steer = seat.ThrottleFloat, seat.SteerFloat
		local turnS = TURN_RATE * TRACK_HALF
		local left = math.clamp(throttle * maxS + steer * turnS, -maxS, maxS) * (if trackUp(model, "Tank_TrackL") then 1 else 0)
		local right = math.clamp(throttle * maxS - steer * turnS, -maxS, maxS) * (if trackUp(model, "Tank_TrackR") then 1 else 0)
		local forward = (left + right) / 2
		local spin = math.clamp(-(left - right) / (2 * TRACK_HALF), -TURN_RATE * 2, TURN_RATE * 2) -- + is a left turn
		local cf = chassis.CFrame
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = ignore
		if cf.UpVector.Y > 0.6 and workspace:Raycast(chassis.Position, -cf.UpVector * GROUND_RAY, params) then
			-- the wanted speed and turn ramp in (heavy), then the hull is pulled toward them with a
			-- bounded push each frame: enough to beat the rollers scrubbing sideways, never a shove
			-- through a wall (blocked, the wanted speed stays near the real one)
			local v = chassis.AssemblyLinearVelocity
			local now = cf.LookVector:Dot(v)
			local rate = if math.abs(forward) > math.abs(speedNow) and forward * speedNow >= 0 then ACCEL else BRAKE
			speedNow += math.clamp(forward - speedNow, -rate * dt, rate * dt)
			speedNow = math.clamp(speedNow, now - SLIP, now + SLIP)
			v += cf.LookVector * math.clamp(speedNow - now, -PUSH * dt, PUSH * dt) - cf.RightVector * cf.RightVector:Dot(v) * math.min(1, GRIP * dt)
			chassis.AssemblyLinearVelocity = v
			local w = chassis.AssemblyAngularVelocity
			local wy = cf.UpVector:Dot(w)
			spinNow += math.clamp(spin - spinNow, -TURN_ACCEL * dt, TURN_ACCEL * dt)
			spinNow = math.clamp(spinNow, wy - 0.6, wy + 0.6)
			w += cf.UpVector * math.clamp(spinNow - wy, -TWIST * dt, TWIST * dt)
			w -= cf.LookVector * cf.LookVector:Dot(w) * math.min(1, STEADY * dt)
			w -= cf.RightVector * cf.RightVector:Dot(w) * math.min(1, STEADY * 0.5 * dt)
			chassis.AssemblyAngularVelocity = w
		end
		local still = chassis.AssemblyLinearVelocity.Magnitude < 4
		tipped = if chassis.CFrame.UpVector.Y < 0.4 and still then tipped + dt else 0
		if tipped > RIGHT_AFTER then
			tipped = 0
			local look = chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
			local at = chassis.Position + Vector3.new(0, 5, 0)
			model:PivotTo(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look else Vector3.zAxis)))
			chassis.AssemblyLinearVelocity, chassis.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		end
	end))

	session = {
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			RunService:UnbindFromRenderStep("TankCamera")
			RunService:UnbindFromRenderStep("TankAim")
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			gui:Destroy()
			focus:Destroy()
			player.CameraMode, player.CameraMinZoomDistance, player.CameraMaxZoomDistance = saved[1], saved[2], saved[3]
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			camera.CameraSubject = hum or saved[4]
		end,
	}
end

local function onSeat(part: BasePart?)
	if session then
		session.stop()
		session = nil
	end
	local model = part and part:IsA("VehicleSeat") and part.Parent
	if model and model:IsA("Model") and model:GetAttribute("Tank") then
		drive(model, part :: VehicleSeat)
	end
end

local function onCharacter(char: Model)
	onSeat(nil)
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

---------------------------------------------------------------------------------- every tank
-- A shot (any tank): flash and smoke at the muzzle, the barrel kicks back, the clank of the reload.
-- Our own: the camera shakes and the hull rocks back on its tracks.
remote.OnClientEvent:Connect(function(what, model: Model)
	if what ~= "fired" or typeof(model) ~= "Instance" then
		return
	end
	local rig = rigOf(model)
	if not (rig and rig.gun) then
		return
	end
	model:SetAttribute("ClientFiredAt", os.clock())
	rig.kick = 1
	local muzzle = rig.gun.CFrame * CFrame.new(0, 0, -stat(model, "Muzzle"))
	local puff = Instance.new("Part")
	puff.Anchored, puff.CanCollide, puff.CanQuery, puff.CanTouch, puff.Transparency = true, false, false, false, 1
	puff.Size, puff.CFrame = Vector3.one, muzzle
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 190, 90), 24, 6
	light.Parent = puff
	local flash = Instance.new("ParticleEmitter")
	flash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	flash.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 120, 30))
	flash.LightEmission, flash.Lifetime, flash.Speed = 1, NumberRange.new(0.08, 0.15), NumberRange.new(30, 60)
	flash.Size = NumberSequence.new(4, 1)
	flash.SpreadAngle, flash.EmissionDirection, flash.Enabled = Vector2.new(25, 25), Enum.NormalId.Front, false
	flash.Parent = puff
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(205, 200, 190))
	smoke.Lifetime, smoke.Speed, smoke.Drag = NumberRange.new(1, 1.8), NumberRange.new(6, 18), 3
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.SpreadAngle, smoke.EmissionDirection, smoke.Enabled = Vector2.new(70, 70), Enum.NormalId.Front, false
	smoke.Parent = puff
	puff.Parent = workspace
	flash:Emit(14)
	smoke:Emit(22)
	task.delay(0.12, function()
		light.Enabled = false
	end)
	game:GetService("Debris"):AddItem(puff, 2.5)
	task.delay(1.4, function()
		if rig.chassis.Parent then
			Sfx.playLocal({ Sfx.RELOAD_RIFLE, 0.6, 0.9 }, rig.chassis.Position)
		end
	end)
	if session and model:GetAttribute("Driver") == player.Name then
		shake = 0.45
		local chassis = rig.chassis
		chassis.AssemblyAngularVelocity += chassis.CFrame.RightVector * 1.6 -- nose up: rocks back
		chassis.AssemblyLinearVelocity -= rig.gun.CFrame.LookVector * Vector3.new(4, 0, 4)
	end
end)

-- Per frame for every tank: the road wheels turn with their track, the barrel comes back from its
-- kick, and the sounds: diesel idling into a drive roar, the track clatter by speed, the turret's
-- whine while it turns, a crunch when it stops dead.
local function silence(rig: Rig)
	for _, s in rig.loops or {} do
		s:Destroy()
	end
	rig.loops = nil
end
RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, car in CollectionService:GetTagged("Car") do
		if not (car:IsA("Model") and car:GetAttribute("Tank")) then
			continue
		end
		local rig = rigOf(car)
		if not rig then
			continue
		end
		if car:GetAttribute("Wrecked") then
			silence(rig)
			continue
		end
		local chassis = rig.chassis
		local cf = chassis.CFrame
		local v = chassis.AssemblyLinearVelocity
		local forward = cf.LookVector:Dot(v)
		local wy = cf.UpVector:Dot(chassis.AssemblyAngularVelocity)
		for side = -1, 1, 2 do
			local speed = forward + side * wy * TRACK_HALF -- turning left, the left track is slower
			rig.angle[side] = (rig.angle[side] + speed / WHEEL_R * dt) % (2 * math.pi)
		end
		for _, m in rig.spins do
			if m.Parent then
				local side = (m:GetAttribute("Side") :: number?) or 1
				m.C0 = (m:GetAttribute("Base") :: CFrame) * CFrame.Angles(-side * rig.angle[side], 0, 0)
			end
		end
		if rig.kick > 0 and rig.mount and rig.mount.Parent then
			rig.kick = math.max(0, rig.kick - dt * 2.2)
			local k = rig.kick ^ 2 * 1.6 -- snaps back fast, eases home
			rig.mount.C0 = (rig.mount:GetAttribute("Base") :: CFrame) * CFrame.new(0, 0, k)
		end
		local driven = (car:GetAttribute("Driver") or "") ~= ""
		if driven and not rig.loops then
			Sfx.playLocal({ Sfx.CAR_DOOR, 0.7, 0.8 }, chassis.Position)
			rig.loops = {
				Sfx.loop(chassis, Sfx.CAR_ENGINE_IDLE_LOOP, 0, 180),
				Sfx.loop(chassis, Sfx.CAR_ENGINE_DRIVE_LOOP, 0, 180),
				Sfx.loop(chassis, Sfx.HEAVY_GATE_SLIDE, 0, 160),
				Sfx.loop(chassis, Sfx.HEAVY_GATE_SLIDE, 0, 80),
			}
		elseif not driven and rig.loops then
			silence(rig)
			Sfx.playLocal({ Sfx.CAR_DOOR, 0.7, 0.8 }, chassis.Position)
		end
		local loops = rig.loops
		if loops then
			local t = math.clamp(math.max(math.abs(forward), math.abs(wy) * TRACK_HALF) / stat(car, "MaxSpeed"), 0, 1)
			loops[1].Volume, loops[1].PlaybackSpeed = 0.7 * (1 - t) + 0.2, 0.55
			loops[2].Volume, loops[2].PlaybackSpeed = 0.1 + 0.6 * t, 0.5 + 0.35 * t
			loops[3].Volume, loops[3].PlaybackSpeed = 0.7 * t, 0.9 + 0.5 * t
			local yawC0 = rig.yawM and rig.yawM.C0
			local turning = yawC0 and rig.lastYaw and yawC0.LookVector:Dot(rig.lastYaw.LookVector) < 0.99999
			rig.lastYaw = yawC0
			loops[4].Volume = if turning then 0.35 else math.max(0, loops[4].Volume - dt * 2)
			loops[4].PlaybackSpeed = 2.2
		end
		if rig.speed - v.Magnitude > 9 and now > rig.crashAt then -- rammed into something
			rig.crashAt = now + 0.8
			Sfx.playLocal({ Sfx.CAR_CRASH, 0.6, 1 }, chassis.Position)
		end
		rig.speed = v.Magnitude
	end
end)
CollectionService:GetInstanceRemovedSignal("Car"):Connect(function(car)
	local rig = rigs[car :: Model]
	if rig then
		silence(rig)
		rigs[car :: Model] = nil
	end
end)

return Tank
