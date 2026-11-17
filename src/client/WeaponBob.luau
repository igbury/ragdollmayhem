-- Walk / run motion of the first-person hands and weapon. Cosmetic only: the shot ray comes from the camera.
-- The step phase advances with ground distance, so the swing stays in time with the feet at any speed.
local WeaponBob = {}
WeaponBob.__index = WeaponBob

local STRIDE = 5 -- one swing of each arm per two steps
local WALK_AMP = 1
local SPRINT_AMP = 1.8
local SWING = 0.1 -- studs each hand travels forward / back at walk; calibration knob

function WeaponBob.new()
	return setmetatable({ phase = 0, amp = 0, run = 0, lift = 0, liftVel = 0, swing = 0 }, WeaponBob)
end

function WeaponBob:reset()
	self.amp, self.run, self.lift, self.liftVel, self.swing = 0, 0, 0, 0, 0
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

-- velocity: the root's, grounded: feet on the floor, sprint: eased 0..1, ads: eased 0..1
function WeaponBob:update(dt: number, active: boolean, velocity: Vector3, grounded: boolean, sprint: number, ads: number): CFrame
	if not active or dt <= 0 or dt > 0.15 then self:reset(); return CFrame.identity end
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walking = grounded and speed > 0.5
	self.phase = (self.phase + (walking and speed * dt / STRIDE * math.pi * 2 or 0)) % (math.pi * 2)
	self.amp = approach(self.amp, walking and math.min(speed / 16, 1) * (WALK_AMP + (SPRINT_AMP - WALK_AMP) * sprint) or 0, 8, dt)
	self.run = approach(self.run, walking and sprint or 0, 7, dt)
	-- the hands lag behind jumps and landings on a soft spring
	local target = math.clamp(-velocity.Y * 0.004, -0.12, 0.12)
	self.liftVel += ((target - self.lift) * 120 - self.liftVel * 16) * dt
	self.lift += self.liftVel * dt

	local a = self.amp * (1 - 0.8 * math.clamp(ads, 0, 1))
	-- arm swing, contralateral like a walking person: +1 = right hand forward, left back
	self.swing = math.sin(self.phase) * a
	local run = self.run * (1 - math.clamp(ads, 0, 1))
	-- running carries it lower; no yaw or roll: turning the whole view slid both hands off to the left
	return CFrame.new(0, self.lift - 0.1 * run, 0.05 * run) * CFrame.Angles(-0.18 * run + self.lift * 0.6, 0, 0)
end

-- this hand's pendulum offset (side: +1 right, -1 left); forward hands ride a little higher on the arc
function WeaponBob:hand(side: number): Vector3
	local w = self.swing * side
	return Vector3.new(0, 0.03 * w * w, -SWING * w)
end

return WeaponBob
