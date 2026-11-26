-- A short impulse followed by a damped recovery, shared by both viewmodel arms.
-- Values describe cosmetic motion only; aim and server hit directions stay unchanged.
local Recoil = {}
Recoil.__index = Recoil
local PROFILES = {
	Handgun = { back = 4.2, pitch = 5.8, speed = 28 },
	Revolver = { back = 6.0, pitch = 8.0, speed = 26 },
	Shotgun = { back = 7.8, pitch = 9.5, speed = 24 },
	Rifle = { back = 2.3, pitch = 3.2, speed = 34 },
	Sniper = { back = 7.0, pitch = 8.5, speed = 23 },
	Rocket = { back = 6.0, pitch = 5.0, speed = 22 },
	-- the comic set
	Taser = { back = 3.0, pitch = 4.2, speed = 30 },
	Frostgun = { back = 4.0, pitch = 5.0, speed = 26 },
	Boilgun = { back = 6.5, pitch = 7.5, speed = 24 },
	Flamethrower = { back = 0.6, pitch = 0.8, speed = 40 },
	Minigun = { back = 1.2, pitch = 1.6, speed = 40 },
	Harpoon = { back = 7.0, pitch = 6.0, speed = 22 },
	Grapple = { back = 5.5, pitch = 5.0, speed = 24 },
	Gravgun = { back = 6.0, pitch = 4.0, speed = 22 },
	BalloonGun = { back = 3.5, pitch = 5.0, speed = 26 },
	LeafBlower = { back = 0.5, pitch = 0.4, speed = 40 },
}

local function step(position: Vector3, velocity: Vector3, speed: number, dt: number): (Vector3, Vector3)
	local damping = 0.76
	local decay = math.exp(-damping * speed * dt)
	local frequency = speed * math.sqrt(1 - damping * damping)
	local c, s = math.cos(frequency * dt), math.sin(frequency * dt) / frequency
	return (position * c + (velocity + position * (damping * speed)) * s) * decay,
		(velocity * c - (velocity * (damping * speed) + position * (speed * speed)) * s) * decay
end

function Recoil.new()
	local self = setmetatable({}, Recoil)
	self:reset()
	return self
end

function Recoil:reset()
	self.position, self.velocity = Vector3.zero, Vector3.zero
	self.angles, self.angularVelocity = Vector3.zero, Vector3.zero
	self.speed, self.shots = 28, 0
end

function Recoil:fire(id: string)
	local profile = PROFILES[id]
	if not profile then return end
	self.speed = profile.speed
	self.shots += 1
	local side = self.shots % 2 == 0 and -1 or 1
	self.velocity += Vector3.new(side * 0.12, 0, profile.back)
	self.angularVelocity += Vector3.new(profile.pitch, side * 0.25, side * 0.50)
end

function Recoil:update(dt: number, visible: boolean): CFrame
	if not visible or dt <= 0 or dt > 0.15 then self:reset(); return CFrame.identity end
	self.position, self.velocity = step(self.position, self.velocity, self.speed, dt)
	self.angles, self.angularVelocity = step(self.angles, self.angularVelocity, self.speed, dt)
	local p, a = self.position, self.angles
	return CFrame.new(math.clamp(p.X, -0.04, 0.04), p.Y, math.clamp(p.Z, -0.04, 0.35))
		* CFrame.Angles(math.clamp(a.X, -0.03, 0.28), math.clamp(a.Y, -0.06, 0.06), math.clamp(a.Z, -0.08, 0.08))
end

return Recoil
