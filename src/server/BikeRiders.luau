--!strict
-- Downtown's cyclists: a few dummies ride COSMIC bikes (server/Bike) round the skyscraper block,
-- server-driven. Any hit (init.server hit(): a riding dummy always goes down) or anything else that
-- ragdolls the rider throws it off: the seat weld goes, the bike's Upright lets go and the bike
-- topples with whatever speed it had. A while later the bike is stood up again and the rider (or a
-- fresh dummy, if it died or left) gets back on. A fallen bike is a free bike: a player can take it.
-- init.server starts it with its dummies table; the dummy Heartbeat skips its walking brain while
-- `d.riding` is set.

local PoliceCar = require(script.Parent.PoliceCar)

local BikeRiders = {}

-- Calibration knobs: try them in play.
local RIDERS = 3
-- clockwise round the skyscraper block on the outer edge of its four streets (Map: street bands
-- [144,160] and [208,224]), clear of the cars parked on the centre lines
local ROUTE = { Vector3.new(146, 0, 146), Vector3.new(222, 0, 146), Vector3.new(222, 0, 222), Vector3.new(146, 0, 222) }
local SPEED = 16 -- studs/s
local CORNER_SPEED = 9 -- studs/s into a corner
local SLOW_AT = 14 -- studs before the corner it starts slowing
local NEXT_AT = 5 -- studs from a corner it aims for the next one
local MAX_FORK = math.rad(30)
local LEAN = math.rad(20) -- into a full-lock turn at speed
local WHEELBASE = 3.68 -- studs between the hubs (client/BikeClient)
local GRIP = 5 -- per second: sideways slide taken out
local DRIVE_SIGN = -1 -- the rear hinge direction that rolls it forward (client/BikeClient)
local TOPPLE = 14 -- angular push that starts the fall, per unit of bike mass
local REMOUNT = 12 -- seconds down before it gets back on
local SIT_ANIM = "rbxassetid://2506281703" -- Roblox's own R15 sit

type Rider = { bike: Model?, d: any?, wp: number, heading: number, track: AnimationTrack?, downAt: number?, since: number? }

local function flat(v: Vector3): Vector3
	return v * Vector3.new(1, 0, 1)
end

-- the bike's spare parts by name
local function parts(bike: Model)
	local chassis = bike:FindFirstChild("Chassis") :: BasePart
	return chassis, bike:FindFirstChild("DriveSeat") :: VehicleSeat, chassis:FindFirstChild("Upright") :: AlignOrientation,
		bike:FindFirstChild("Drive", true) :: HingeConstraint, bike:FindFirstChild("Steer", true) :: HingeConstraint
end

local function headingOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

function BikeRiders.start(spawnDummy: (CFrame) -> any, dummies: { [Model]: any })
	local riders: { Rider } = {}

	-- the stretch of route nearest `at`: its end corner
	local function nearestLeg(at: Vector3): number
		local best, bestI = math.huge, 1
		for i, a in ROUTE do
			local b = ROUTE[i % #ROUTE + 1]
			local ab = b - a
			local t = math.clamp((at - a):Dot(ab) / ab:Dot(ab), 0, 1)
			local dist = (flat(at) - (a + ab * t)).Magnitude
			if dist < best then
				best, bestI = dist, i % #ROUTE + 1
			end
		end
		return bestI
	end

	local function newBike(r: Rider, at: Vector3)
		r.wp = nearestLeg(at)
		local look = flat(ROUTE[r.wp] - at)
		r.bike = PoliceCar.spawn(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look else Vector3.xAxis)), nil, "Bike")
	end

	-- stood up where it lies, facing on along the route
	local function standUp(r: Rider)
		local bike = r.bike :: Model
		local chassis, _, upright = parts(bike)
		local at = flat(chassis.Position) + Vector3.new(0, 0.5, 0)
		r.wp = nearestLeg(at)
		local look = flat(ROUTE[r.wp] - at)
		bike:PivotTo(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look else Vector3.xAxis)) * CFrame.new(0, 1.7, 0))
		chassis.AssemblyLinearVelocity, chassis.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		upright.Enabled = true
	end

	local function mount(r: Rider)
		local bike, d = r.bike :: Model, r.d
		local chassis, seat, upright = parts(bike)
		r.heading = headingOf(chassis.CFrame.LookVector)
		upright.CFrame, upright.MaxTorque = CFrame.Angles(0, r.heading, 0), 1e6
		d.riding = true
		d.humanoid.WalkSpeed = 0
		d.model:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
		seat:Sit(d.humanoid)
		local animator = d.humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", d.humanoid)
		local anim = Instance.new("Animation")
		anim.AnimationId = SIT_ANIM
		r.track = (animator :: Animator):LoadAnimation(anim)
		;(r.track :: AnimationTrack):Play(0.1)
		task.defer(function() -- after the seat's own Occupant handler handed it to Auto
			if chassis:CanSetNetworkOwnership() then
				chassis:SetNetworkOwner(nil)
			end
		end)
		r.downAt, r.since = nil, os.clock()
	end

	-- off it goes: the rider limp (the hit did that), the bike falls the way it was leaning
	local function fall(r: Rider)
		local d = r.d
		if d then
			d.riding = false
		end
		if r.track then
			r.track:Stop(0)
			r.track = nil
		end
		r.downAt = os.clock()
		local bike = r.bike
		if not (bike and bike.Parent) then
			return
		end
		local chassis, seat, upright, drive, steer = parts(bike)
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		upright.Enabled = false
		drive.AngularVelocity, drive.MotorMaxTorque = 0, 60
		steer.TargetAngle = 0
		local roll = chassis.CFrame.RightVector:Dot(Vector3.yAxis) -- already leaning: further that way
		local side = if math.abs(roll) > 0.02 then -math.sign(roll) else (if math.random() < 0.5 then 1 else -1)
		chassis:ApplyAngularImpulse(chassis.CFrame.LookVector * side * chassis.AssemblyMass * TOPPLE)
	end

	local function watch(r: Rider, d)
		r.d = d
		d.model:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			if r.d == d and d.riding and d.model:GetAttribute("Ragdolled") then
				fall(r)
			end
		end)
		d.model.Destroying:Connect(function()
			if r.d == d then
				if d.riding then
					fall(r)
				end
				r.d = nil
			end
		end)
	end

	local function ride(r: Rider, dt: number)
		local chassis, seat, upright, drive, steer = parts(r.bike :: Model)
		if seat.Occupant ~= r.d.humanoid and os.clock() - (r.since or 0) > 1 then -- thrown off some other way (Sit lost): treat as a fall
			fall(r)
			return
		end
		local cf = chassis.CFrame
		local pos, v = flat(chassis.Position), chassis.AssemblyLinearVelocity
		local speed = v:Dot(cf.LookVector)
		local target = ROUTE[r.wp]
		local toGo = (target - pos).Magnitude
		if toGo < NEXT_AT then
			r.wp = r.wp % #ROUTE + 1
			target = ROUTE[r.wp]
		end
		-- the heading turns toward the corner no faster than full lock allows at this speed
		local want = headingOf(target - pos)
		local diff = (want - r.heading + math.pi) % (2 * math.pi) - math.pi
		local rate = math.max(math.abs(speed), 2) * math.tan(MAX_FORK) / WHEELBASE
		local turn = math.clamp(diff, -rate * dt, rate * dt)
		r.heading += turn
		local share = turn / math.max(rate * dt, 1e-6) -- -1..1 of full lock, + = left
		steer.TargetAngle = -share * math.deg(MAX_FORK) -- + fork turns right (client/BikeClient)
		local lean = share * LEAN * math.clamp(math.abs(speed) / SPEED, 0, 1)
		upright.CFrame = CFrame.Angles(0, r.heading, 0) * CFrame.Angles(0, 0, lean)
		-- pedal: slower into the corner
		local goal = if toGo < SLOW_AT then CORNER_SPEED else SPEED
		local radius = ((r.bike :: Model):GetAttribute("WheelRadius") :: number?) or 1.33
		drive.AngularVelocity, drive.MotorMaxTorque = DRIVE_SIGN * goal / radius, if speed > goal + 2 then 2500 else 1800
		chassis.AssemblyLinearVelocity = v - cf.RightVector * cf.RightVector:Dot(v) * math.min(1, GRIP * dt)
	end

	-- down a while: stand the bike up (or a new one if a player has it or it is gone) and get back on
	local function remount(r: Rider)
		local d = r.d
		local up = d and d.model.Parent and d.state == "Awake" and not d.model:GetAttribute("Ragdolled") and not d.heldBy
		if d and not up and d.state ~= "Dead" and d.model.Parent then
			return -- still down or carried off: wait for it
		end
		local bike = r.bike
		local _, seat = if bike and bike.Parent then parts(bike) else nil, nil
		if not bike or not bike.Parent or (seat and seat.Occupant) then
			newBike(r, ROUTE[math.random(#ROUTE)])
		else
			standUp(r)
		end
		if not up then
			local _, s = parts(r.bike :: Model)
			watch(r, spawnDummy(s.CFrame * CFrame.new(3, 2, 0)))
		end
		mount(r)
	end

	task.spawn(function()
		task.wait(3) -- the bike asset loads (server/Bike) and the map is built
		for i = 1, RIDERS do
			local r: Rider = { wp = 1, heading = 0 }
			local a, b = ROUTE[i], ROUTE[i % #ROUTE + 1]
			newBike(r, a:Lerp(b, 0.5))
			local _, seat = parts(r.bike :: Model)
			watch(r, spawnDummy(seat.CFrame * CFrame.new(3, 2, 0)))
			mount(r)
			table.insert(riders, r)
		end
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			for _, r in riders do
				local d = r.d
				if d and d.riding and r.bike and r.bike.Parent and dummies[d.model] then
					ride(r, dt)
				elseif d and d.riding then
					fall(r) -- the bike went (Toolbox clear) or the dummy did
				elseif os.clock() - (r.downAt or 0) > REMOUNT then
					r.downAt = os.clock() - REMOUNT + 2 -- try again in 2 s if it cannot yet
					remount(r)
				end
			end
		end)
	end)
end

return BikeRiders
