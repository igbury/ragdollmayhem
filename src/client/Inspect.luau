-- Weapon inspect (Y): keyframed first-person timelines, one per weapon, generic for the rest.
-- Inspect.pose(id, t) gives what the view model does at t seconds in, or nil once it is over:
--   right / left: camera-space offset of that fist from where it rests (studs)
--   rightRot:     wrist turn of the right hand, camera space (the weapon turns with it)
--   weapon:       extra move of the weapon about its own centre, camera space (tosses, spins)
--   pieces:       [name] = mesh-space CFrame for a moving piece (WeaponMeshes.pose)
--   attach:       { piece, w, at }: the piece leaves the weapon for the left fist (w 0..1),
--                 held at `at` relative to that fist
--   leftAt:       { point, piece?, w }: the left fist goes to this mesh-space point (on the piece, if
--                 given) with weight w
-- Camera space: +X right, +Y up, +Z toward the viewer. Angles are degrees (pitch, yaw, roll):
-- pitch + tips the muzzle up, yaw + turns it left, roll + tips the top to the left.
local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))

local V = Vector3.new
local Z = Vector3.zero

-- keys = { {time, value, lin?}, ... } (value: number or Vector3); smooth between keys unless the
-- later key says lin (constant speed: spins)
local function track(keys, t)
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local s = (t - a[1]) / (b[1] - a[1])
			if not b[3] then
				s = s * s * (3 - 2 * s)
			end
			return a[2] + (b[2] - a[2]) * s
		end
	end
	return keys[#keys][2]
end

local function angles(deg: Vector3): CFrame
	return CFrame.Angles(math.rad(deg.X), math.rad(deg.Y), math.rad(deg.Z))
end

-- Everything else: bring it in, show one side, flip to the other, put it back.
local GENERIC_TIME = 3.2
local GENERIC_ROT = { -- fractions of GENERIC_TIME
	{ 0, Z }, { 0.18, V(10, 55, 30) }, { 0.45, V(4, 62, 38) }, { 0.6, V(-8, -35, -70) }, { 0.84, V(-4, -42, -78) }, { 1, Z },
}
local function generic(id: string, t: number)
	local lo, hi = WeaponMeshes.bounds(id)
	local long = lo and hi and (hi - lo).Magnitude > 3 -- long guns and blades turn less and go out, not in
	local u = t / GENERIC_TIME
	local into = math.clamp(math.min(u, 1 - u) / 0.15, 0, 1)
	into = into * into * (3 - 2 * into)
	return {
		right = (long and V(-0.3, 0.1, -0.6) or V(-0.4, 0.22, 0.35)) * into,
		rightRot = angles(track(GENERIC_ROT, u) * (long and 0.45 or 1)),
	}
end

local SPECS = {}

SPECS.Handgun = {
	time = 3.8,
	right = { { 0, Z }, { 0.25, V(-0.3, 0.2, 0.35) }, { 0.42, V(-0.25, 0.08, 0.35) }, { 1.7, V(-0.2, 0.05, 0.3) },
		{ 2.2, V(-0.25, 0.15, 0.35) }, { 2.4, V(-0.25, 0.22, 0.35) }, { 3.3, V(-0.25, 0.15, 0.35) }, { 3.8, Z } },
	rightRot = { { 0, Z }, { 0.25, V(10, 25, -40) }, { 0.4, V(22, 25, -60) }, { 0.6, V(5, 20, -25) }, { 1.7, V(5, 20, -25) },
		{ 2.2, V(0, 30, -50) }, { 2.42, V(10, 30, -45) }, { 2.6, V(0, 35, -15) }, { 2.78, V(6, 35, -15) },
		{ 3.0, V(0, 35, -15) }, { 3.8, Z } },
	left = { { 0, Z }, { 0.4, V(0.3, 0.35, 0.35) }, { 0.65, V(0.35, 0.45, 0.45) }, { 1.75, V(0.35, 0.45, 0.45) },
		{ 2.2, V(0.75, 0.15, 0.4) }, { 2.45, V(0.75, 0.12, 0.4) }, { 3.15, V(0.3, 0.1, 0.2) }, { 3.8, Z } },
	magDrop = { { 0.35, Z }, { 0.45, V(0, -0.45, 0.08) }, { 1.8, V(0, -0.3, 0.05) }, { 2.25, V(0, -0.3, 0.05) }, { 2.4, Z } },
	magHand = { { 0.45, 0 }, { 0.65, 1 }, { 1.8, 1 }, { 2.25, 0 } },
	magLook = { { 0.65, V(0, 0, 10) }, { 1.0, V(55, 0, -15) }, { 1.3, V(60, 15, -5) }, { 1.6, V(50, -10, 5) }, { 1.8, Z } },
	slide = { { 2.62, 0 }, { 2.76, 0.3, true }, { 2.86, 0, true } },
	rack = { { 2.45, 0 }, { 2.6, 1 }, { 2.95, 1 }, { 3.1, 0 } },
}
function SPECS.Handgun.extra(p, t, spec)
	p.pieces = {
		Mag = CFrame.new(track(spec.magDrop, t)),
		Slide = CFrame.new(0, 0, track(spec.slide, t)),
	}
	p.attach = { piece = "Mag", w = track(spec.magHand, t), at = CFrame.new(0, 0.35, -0.05) * angles(track(spec.magLook, t)) }
	local slide = WeaponMeshes.pieceCentre("Handgun", "Slide")
	if slide then
		p.leftAt = { point = slide + V(0, 0.08, 0.3), piece = "Slide", w = track(spec.rack, t) }
	end
end

SPECS.Shotgun = { -- the generic turn, then a pump: the left hand goes to the pump and racks it
	time = GENERIC_TIME + 1.2,
	pump = { { GENERIC_TIME + 0.3, 0 }, { GENERIC_TIME + 0.5, 0.32 }, { GENERIC_TIME + 0.72, 0 } },
	reach = { { GENERIC_TIME, 0 }, { GENERIC_TIME + 0.22, 1 }, { GENERIC_TIME + 0.9, 1 }, { GENERIC_TIME + 1.2, 0 } },
	kick = { { GENERIC_TIME + 0.4, Z }, { GENERIC_TIME + 0.5, V(6, 0, 0) }, { GENERIC_TIME + 0.8, Z } },
	out = { { GENERIC_TIME, Z }, { GENERIC_TIME + 0.25, V(-0.25, 0.12, -0.45) }, { GENERIC_TIME + 0.95, V(-0.25, 0.12, -0.45) },
		{ GENERIC_TIME + 1.2, Z } }, -- held out and in, so the pump shows
}
function SPECS.Shotgun.extra(p, t, spec)
	if t < GENERIC_TIME then
		local g = generic("Shotgun", t)
		p.right, p.rightRot = g.right, g.rightRot
	else
		p.right, p.rightRot = track(spec.out, t), angles(track(spec.kick, t))
	end
	p.pieces = { Pump = CFrame.new(0, 0, track(spec.pump, t)) }
	local pump = WeaponMeshes.pieceCentre("Shotgun", "Pump")
	if pump then
		p.leftAt = { point = pump + V(0, -0.08, 0), piece = "Pump", w = track(spec.reach, t) }
	end
end

SPECS.Revolver = {
	time = 3.8,
	right = { { 0, Z }, { 0.2, V(-0.4, 0.32, 0.2) }, { 1.5, V(-0.32, 0.3, 0.2) }, { 1.65, V(-0.1, 0.1, 0.3) },
		{ 1.85, V(0, 0.05, 0.2) }, { 1.93, V(0, -0.06, 0.2) }, { 2.02, V(0, 0.12, 0.2) }, { 2.75, V(0, 0, 0.2) },
		{ 2.82, V(0, -0.1, 0.2) }, { 3.1, V(0, 0, 0.15) }, { 3.8, Z } },
	rightRot = { { 0, Z }, { 0.2, V(5, 15, 70) }, { 0.35, V(5, 15, 80) }, { 1.45, V(0, 15, 75) }, { 1.6, V(0, 0, -15) },
		{ 1.8, Z }, { 3.8, Z } },
	swing = { { 0.25, 0 }, { 0.38, 90 }, { 1.48, 90 }, { 1.6, 0 } },
	spin = { { 0.4, 0 }, { 1.35, 900 } },
	toss = { { 1.98, Z }, { 2.38, V(0, 1.3, 0.1) }, { 2.78, Z } },
	flip = { { 1.98, Z }, { 2.78, V(-360, 0, 0), true } },
}
function SPECS.Revolver.extra(p, t, spec)
	local c = WeaponMeshes.pieceCentre("Revolver", "Cylinder")
	if c then -- swings out to the gun's left on a crane under it, and spins on its own axis
		local pivot = c + V(-0.2, -0.2, 0)
		p.pieces = {
			Cylinder = CFrame.new(pivot) * CFrame.Angles(0, 0, math.rad(track(spec.swing, t))) * CFrame.new(-pivot)
				* CFrame.new(c) * CFrame.Angles(0, 0, math.rad(track(spec.spin, t))) * CFrame.new(-c),
		}
	end
	p.weapon = CFrame.new(track(spec.toss, t)) * angles(track(spec.flip, t))
end

SPECS.Knife = { -- tossed up, five turns end over end, caught
	time = 2.3,
	right = { { 0, Z }, { 0.12, V(0, -0.12, 0.1) }, { 0.22, V(0, 0.1, 0.1) }, { 1.85, V(0, 0, 0.1) },
		{ 1.95, V(0, -0.12, 0.1) }, { 2.3, Z } },
	toss = { { 0.2, Z }, { 1.05, V(-0.25, 1.1, 0.1) }, { 1.9, Z } },
	flip = { { 0.2, Z }, { 1.9, V(0, 0, 1800), true } }, -- in the screen plane, so every turn reads
}
function SPECS.Knife.extra(p, t, spec)
	p.weapon = CFrame.new(track(spec.toss, t)) * angles(track(spec.flip, t))
end

-- Turn the wrist left and lay the heavy end on the left palm, then pop it off the palm a few times
-- as a lever: the right fist dips and the wrist turns, the head lifts and lands back. The left palm
-- stays put the whole time.
local function rest()
	local hold, press = V(-0.2, 0.3, -0.2), V(-0.2, 0.25, -0.2)
	local palm = V(-0.5, 0.55, -0.2)
	local lying, flying = V(0, 10, 80), V(0, 10, 58)
	local right, roll = { { 0, Z }, { 0.4, hold } }, { { 0, Z }, { 0.4, lying } }
	for i, at in { 0.8, 1.35, 1.9 } do
		local high = i == 3 and V(0, 10, 48) or flying -- the last toss goes higher
		table.insert(right, { at, hold })
		table.insert(right, { at + 0.07, press }) -- the handle pushed down pops the head up
		table.insert(right, { at + 0.24, hold })
		table.insert(roll, { at + 0.04, lying })
		table.insert(roll, { at + 0.24, high })
		table.insert(roll, { at + 0.42, lying + V(0, 0, 3) }) -- lands a touch low...
		table.insert(roll, { at + 0.5, lying }) -- ...and settles
	end
	table.insert(right, { 2.9, hold })
	table.insert(right, { 3.6, Z })
	table.insert(roll, { 2.9, lying })
	table.insert(roll, { 3.6, Z })
	return {
		time = 3.6,
		right = right,
		left = { { 0, Z }, { 0.45, palm }, { 2.9, palm }, { 3.6, Z } },
		rightRot = roll,
	}
end
SPECS.Bat = rest()
SPECS.Axe = rest()

SPECS.Katana = { -- laid flat across the raised left arm and wiped, then a twirl and a few cuts
	time = 3.8,
	right = { { 0, Z }, { 0.35, V(-0.1, 0.4, 0) }, { 0.5, V(-0.1, 0.4, 0) }, { 1.2, V(0.6, 0.4, 0) }, { 1.4, V(0, 0.2, 0) },
		{ 2.2, V(-0.3, 0.2, -0.2) }, { 2.45, V(0.3, 0, -0.2) }, { 2.7, V(-0.1, 0.1, -0.1) }, { 3.8, Z } },
	rightRot = { { 0, Z }, { 0.35, V(0, 0, 88) }, { 1.2, V(0, 0, 88) }, { 1.4, Z }, { 1.5, Z }, { 1.9, V(0, -360, 0), true },
		{ 2.2, V(-50, -360, -20) }, { 2.45, V(20, -360, 25) }, { 2.7, V(-30, -360, -15) }, { 3.0, V(0, -360, 0) } }, -- -360 = rest
	left = { { 0, Z }, { 0.35, V(0.25, 0.85, 0.1) }, { 1.2, V(0.25, 0.85, 0.1) }, { 1.45, Z } },
}

SPECS.BoxingGloves = { -- knock the gloves together three times
	time = 1.6,
	right = { { 0, Z }, { 0.25, V(-0.1, 0.05, -0.35) }, { 0.38, V(-0.32, 0.05, -0.35) }, { 0.52, V(-0.1, 0.05, -0.35) },
		{ 0.66, V(-0.32, 0.05, -0.35) }, { 0.8, V(-0.1, 0.05, -0.35) }, { 0.94, V(-0.32, 0.05, -0.35) },
		{ 1.1, V(-0.1, 0.05, -0.35) }, { 1.6, Z } },
	left = { { 0, Z }, { 0.25, V(0.1, 0.05, -0.35) }, { 0.38, V(0.32, 0.05, -0.35) }, { 0.52, V(0.1, 0.05, -0.35) },
		{ 0.66, V(0.32, 0.05, -0.35) }, { 0.8, V(0.1, 0.05, -0.35) }, { 0.94, V(0.32, 0.05, -0.35) },
		{ 1.1, V(0.1, 0.05, -0.35) }, { 1.6, Z } },
}

local Inspect = {}

-- The pieces a weapon's inspect may move, so the caller can put them back when it stops.
Inspect.pieces = { Handgun = { "Mag", "Slide" }, Shotgun = { "Pump" }, Revolver = { "Cylinder" } }

function Inspect.duration(id: string): number
	return SPECS[id] and SPECS[id].time or GENERIC_TIME
end

function Inspect.pose(id: string, t: number)
	local spec = SPECS[id]
	if t >= Inspect.duration(id) then
		return nil
	end
	if not spec then
		return generic(id, t)
	end
	local p = {
		right = spec.right and track(spec.right, t) or Z,
		left = spec.left and track(spec.left, t) or nil,
		rightRot = spec.rightRot and angles(track(spec.rightRot, t)) or CFrame.identity,
	}
	if spec.extra then
		spec.extra(p, t, spec)
	end
	return p
end

return Inspect
