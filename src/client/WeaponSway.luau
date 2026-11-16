-- Camera rotation only: presentation must never move the crosshair or the shot ray.
-- A critically damped spring has an exact solution, so it settles the same at 30/60/144 FPS.
local WeaponSway = {}
WeaponSway.__index = WeaponSway

function WeaponSway.new()
	return setmetatable({ previous = nil, position = Vector3.zero, velocity = Vector3.zero }, WeaponSway)
end

function WeaponSway:reset()
	self.previous = nil
	self.position = Vector3.zero
	self.velocity = Vector3.zero
end

function WeaponSway:update(cf: CFrame, dt: number, active: boolean, ads: number): CFrame
	local rotation = cf.Rotation
	local previous = self.previous
	self.previous = rotation
	if not active or not previous or dt <= 0 or dt > 0.15 then
		self.position, self.velocity = Vector3.zero, Vector3.zero
		return CFrame.identity
	end
	local pitch, yaw, roll = rotation:ToObjectSpace(previous):ToOrientation()
	-- Camera cuts, respawns and switching views should not fling the hands across the screen.
	if math.max(math.abs(pitch), math.abs(yaw), math.abs(roll)) > math.rad(35) then
		self.position, self.velocity = Vector3.zero, Vector3.zero
		return CFrame.identity
	end
	local strength = 1 - 0.85 * math.clamp(ads, 0, 1)
	local target = Vector3.new(
		math.clamp(pitch / dt * 0.018, -0.045, 0.045),
		math.clamp(yaw / dt * 0.022, -0.055, 0.055),
		math.clamp(-yaw / dt * 0.012, -0.035, 0.035)
	) * strength
	local speed = 18
	local displacement = self.position - target
	local impulse = self.velocity + displacement * speed
	local decay = math.exp(-speed * dt)
	self.position = target + (displacement + impulse * dt) * decay
	self.velocity = (self.velocity - impulse * (speed * dt)) * decay
	local p = self.position
	return CFrame.new(p.Y * 1.2, -p.X * 0.9, math.abs(p.Y) * 0.15)
		* CFrame.Angles(p.X, p.Y, p.Z)
end

return WeaponSway
