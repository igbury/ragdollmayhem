-- Natural disasters (server/Disasters runs them, client/Disasters draws them). One comes on its own
-- every AUTO_MIN..AUTO_MAX seconds on a map someone is playing (now and then a COMBO instead);
-- SANDBOX + (shared/Shop) can call one from the Toolbox's WORLD page, once every COOLDOWN seconds.
-- Each starts LEAD seconds after its banner (the countdown and the siren). Server and clients both
-- work out where a moving one is from the same numbers (along, waveFront), so nothing streams per frame.
local Disasters = {}

Disasters.AUTO_MIN, Disasters.AUTO_MAX = 180, 240
Disasters.COOLDOWN = 30
Disasters.LEAD = 4 -- s of countdown between the banner and the strike
Disasters.COMBO_CHANCE = 0.15 -- of the ones that come on their own
Disasters.DAMAGE = 5 -- every disaster's damage (to dummies and players) times this; the blasts' reach stays

-- in the Toolbox's order
Disasters.KINDS = {
	{ id = "Tornado", name = "TORNADO", color = Color3.fromRGB(120, 130, 150), duration = 24, word = "WHOOOSH!" },
	{ id = "Tsunami", name = "TSUNAMI", color = Color3.fromRGB(40, 120, 220), duration = 12, word = "SPLOOOSH!" },
	{ id = "Meteors", name = "METEORS", color = Color3.fromRGB(240, 110, 30), duration = 18, word = "KA-THOOM!" },
	{ id = "Nuke", name = "NUKE", color = Color3.fromRGB(90, 200, 60), duration = 20, word = "KA-BLAAAM!" },
	{ id = "Earthquake", name = "QUAKE", color = Color3.fromRGB(150, 105, 60), duration = 16, word = "RUMBLE!" },
	{ id = "Volcano", name = "VOLCANO", color = Color3.fromRGB(220, 60, 30), duration = 22, word = "BLAMMO!" },
	{ id = "Lightning", name = "STORM", color = Color3.fromRGB(235, 200, 40), duration = 18, word = "KRA-KOOM!" },
	{ id = "Blizzard", name = "BLIZZARD", color = Color3.fromRGB(120, 200, 240), duration = 18, word = "BRRRR!" },
	{ id = "Ufo", name = "UFO", color = Color3.fromRGB(110, 220, 90), duration = 22, word = "ZWOOP!" },
	{ id = "Zombies", name = "ZOMBIE NIGHT", color = Color3.fromRGB(95, 120, 60), duration = 40, word = "BRAAAINS!" },
}
Disasters.BY_ID = {}
for _, kind in Disasters.KINDS do
	Disasters.BY_ID[kind.id] = kind
end

-- Two at once, or one souped up (`fire`: the tornado sets what it carries alight; `mega`: the nuke at
-- MEGA times the size). Only the ones that come on their own, and the admin panel.
Disasters.COMBOS = {
	{ id = "FireTornado", name = "FIRE TORNADO", color = Color3.fromRGB(255, 110, 30), parts = { "Tornado" }, fire = true },
	{ id = "MeteorWave", name = "METEOR TSUNAMI", color = Color3.fromRGB(90, 90, 230), parts = { "Tsunami", "Meteors" } },
	{ id = "MegaNuke", name = "MEGA NUKE", color = Color3.fromRGB(60, 230, 60), parts = { "Nuke" }, mega = true },
	{ id = "Superstorm", name = "SUPERSTORM", color = Color3.fromRGB(170, 150, 40), parts = { "Lightning", "Tornado" } },
}
Disasters.COMBO = {}
for _, combo in Disasters.COMBOS do
	Disasters.COMBO[combo.id] = combo
end
Disasters.MEGA = 1.6

Disasters.TORNADO_RADIUS = 24 -- studs from the funnel's axis that it grabs
Disasters.TORNADO_HEIGHT = 90
Disasters.WAVE_SPEED = 42 -- studs/s
Disasters.WAVE_HEIGHT = 40 -- the wave mesh (client/DisasterMeshes) at 10x is ~43 high
Disasters.WAVE_WIDTH = 280
Disasters.WAVE_DEPTH = 26 -- how deep the breaking front is, along its travel
Disasters.NUKE_FALL = 7 -- s from the siren to the blast
Disasters.NUKE_RADIUS = 170 -- the shockwave's reach
Disasters.UFO_HEIGHT = 46 -- above the floor
Disasters.UFO_BEAM = 13 -- the tractor beam's radius
Disasters.VOLCANO_RISE = 2.5 -- s it takes to grow out of the ground
Disasters.STORM_HEIGHT = 110 -- the thunderclouds, above the floor
Disasters.STRIKE_WARN = 0.5 -- s a lightning target glows before the bolt

-- Where something moving evenly along `path` over `duration` s is at `t` (the tornado, the UFO).
function Disasters.along(path: { Vector3 }, t: number, duration: number): Vector3
	local legs = #path - 1
	local f = math.clamp(t / duration, 0, 1) * legs
	local i = math.min(math.floor(f) + 1, legs)
	return path[i]:Lerp(path[i + 1], f - (i - 1))
end

-- The tornadoes circle the player they came for (server/Disasters sends who, and a seed): TORNADOES
-- of them, each on its own orbit: its radius, speed and way round, swinging in and out a little.
Disasters.TORNADOES = 4
function Disasters.tornadoOrbits(seed: number): { { r: number, w: number, a: number, phase: number } }
	local rng = Random.new(seed)
	local orbits = {}
	for i = 1, Disasters.TORNADOES do
		orbits[i] = {
			r = rng:NextNumber(28, 58),
			w = rng:NextNumber(0.22, 0.4) * (if i % 2 == 0 then -1 else 1),
			a = (i - 1) / Disasters.TORNADOES * math.pi * 2 + rng:NextNumber(-0.4, 0.4),
			phase = rng:NextNumber(0, math.pi * 2),
		}
	end
	return orbits
end

-- Where a tornado on `orbit` is at `t` s, from the middle it circles.
function Disasters.orbitAt(orbit, t: number): Vector3
	local a = orbit.a + orbit.w * t
	local r = orbit.r + 10 * math.sin(t * 0.6 + orbit.phase)
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- The middle they circle at that moment: the player's feet (followed wherever they run), at the
-- floor height it started on; where they were last when they are gone.
function Disasters.tornadoCentre(around: Player?, last: Vector3): Vector3
	local char = around and around.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then Vector3.new(root.Position.X, last.Y, root.Position.Z) else last
end

-- How far from its start line the wave's face is at `t` s.
function Disasters.waveFront(t: number): number
	return Disasters.WAVE_SPEED * t
end

-- Where a lava bomb (Volcano) launched from `from` to `to` over `flight` s is at `t` s: a lob.
function Disasters.lob(from: Vector3, to: Vector3, flight: number, t: number): Vector3
	local a = math.clamp(t / flight, 0, 1)
	return from:Lerp(to, a) + Vector3.yAxis * (from - to).Magnitude * 0.45 * 4 * a * (1 - a)
end

return Disasters
