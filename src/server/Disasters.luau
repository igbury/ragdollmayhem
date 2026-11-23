-- Natural disasters (shared/Disasters): tornado, tsunami, meteors, nuke, earthquake, volcano, lightning
-- storm, blizzard, UFO and zombie night, plus COMBOS (two at once, or one souped up). A loop picks a map
-- someone is playing every 3-4 minutes and sets one off around one of its players; SANDBOX + calls one
-- from the Toolbox (remote "Disaster", "trigger"); the admin panel any of them (force). One at a time
-- per map. Each starts LEAD s after its banner (countdown, siren); while it runs the map does not mend
-- (server/Map holds). The server only does the harm (through init.server's helpers, handed in by
-- start); every client in that map gets the numbers once ("start") and draws the rest itself
-- (client/Disasters). At the end the players there get a summary of the damage ("summary").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage.Shared.Disasters)
local Shop = require(ReplicatedStorage.Shared.Shop)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local Settings = require(ReplicatedStorage.Shared.Settings)
local Map = require(script.Parent.Map)
local Progress = require(script.Parent.Progress)

local Disasters = {}

local UP = Vector3.yAxis
local FLAT = Vector3.new(1, 0, 1)
-- init.server's helpers: hazard(model, damage, velocity, kind?), explode(position, sound, scale?),
-- each(fn(model, torso)), ignite(position) (a burning patch, yields ~5 s), freeze(model),
-- spawnZombie(cframe) -> Model?, burnAway(model)
local K
local remote: RemoteEvent
local busy = {} -- [map name] = true while one runs there
local lastCall = {} -- [Player] = os.clock() of their last SANDBOX + call

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { Map.folder, workspace:FindFirstChild("Baseplate") }

-- The floor under `p` (the map, else 3 studs under it).
local function floorAt(p: Vector3): Vector3
	local hit = workspace:Raycast(p + UP * 60, -UP * 200, floorParams)
	return if hit then hit.Position else p - UP * 3
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Waits until `t` s after `t0` (server time).
local function waitFor(t0: number, t: number)
	local left = t0 + t - now()
	if left > 0 then
		task.wait(left)
	end
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root and hum and hum.Health > 0 then root else nil
end

-- Who plays `map`; the ones in the tutorial only with `all` (they see a disaster, it never hits them).
local function playersIn(map: string, all: boolean?): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		-- not `all`: none in the tutorial or still new (server/Progress.isNew): no disaster goes off round
		-- them or hurts them in their first minutes
		if player:GetAttribute("Map") == map and (all or not (player:GetAttribute("Tutorial") or Progress.isNew(player))) then
			table.insert(list, player)
		end
	end
	return list
end

-- fn(model, part) for every dummy and every player's character in `map`; `part` is what to measure from.
local function victims(map: string, fn: (Model, BasePart) -> ())
	K.each(fn)
	for _, player in playersIn(map) do
		local root = rootOf(player)
		if root then
			fn(player.Character :: Model, root)
		end
	end
end

-- Everyone within `radius` of `at` is thrown out of it, harder near the middle.
local function burst(map: string, at: Vector3, radius: number, damage: number, push: number, lift: number, kind: string?)
	victims(map, function(model, part)
		local away = part.Position - at
		if away.Magnitude > radius then
			return
		end
		local f = 1 - away.Magnitude / radius
		local out = (away * FLAT).Magnitude > 0.1 and (away * FLAT).Unit or Vector3.xAxis
		K.hazard(model, damage * f, out * push * f + UP * lift * (0.4 + 0.6 * f), kind)
	end)
end

local function tell(map: string, ...)
	for _, player in playersIn(map, true) do
		remote:FireClient(player, ...)
	end
end

local function ring(rng: Random, centre: Vector3, r0: number, r1: number): Vector3
	local a = rng:NextNumber(0, math.pi * 2)
	return floorAt(centre + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(r0, r1))
end

local function flatDir(rng: Random): Vector3
	local a = rng:NextNumber(0, math.pi * 2)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- Each disaster: run(map, centre, t0, opts) does the harm from t0 on and returns once it is over.
-- `centre` is on the floor; `opts` is the combo it is part of (fire, mega) plus `around`, the player it
-- came for (nil when they are gone).
local RUN = {}

-- A player with RAGDOLL DAMAGE off on their SETTINGS page (shared/Settings): the tornadoes leave them be.
local function sparedByTornado(model: Model): boolean
	local player = Players:GetPlayerFromCharacter(model)
	return player ~= nil and Settings.get(player, "RagdollDamage") == false
end

-- TORNADOES of them, circling the player it came for and following them wherever they run (shared
-- tornadoOrbits / tornadoCentre: the clients work out the same places).
function RUN.Tornado(map: string, centre: Vector3, t0: number, opts)
	local seed = math.random(1, 2 ^ 30)
	local around = opts.around
	tell(map, "start", "Tornado", t0, { seed = seed, around = around, centre = centre, fire = opts.fire })
	local orbits = Shared.tornadoOrbits(seed)
	local radius, height = Shared.TORNADO_RADIUS, Shared.TORNADO_HEIGHT
	local nextTear, tear = 0, 1
	local middle = centre
	while true do
		local t = now() - t0
		if t > Shared.BY_ID.Tornado.duration then
			break
		end
		middle = Shared.tornadoCentre(around, middle)
		local feet = {}
		for i, orbit in orbits do
			feet[i] = middle + Shared.orbitAt(orbit, t)
		end
		victims(map, function(model, part)
			if t < 0 or sparedByTornado(model) then
				return
			end
			for _, foot in feet do
				local offset = (part.Position - foot) * FLAT
				local dist, rise = offset.Magnitude, part.Position.Y - foot.Y
				if dist <= radius and rise <= height and rise >= -6 then
					local out = if dist > 0.1 then offset.Unit else Vector3.xAxis
					local spin = UP:Cross(out) -- counter-clockwise from above, like the client's spin
					local pull = 1 - dist / radius
					local velocity = if rise > height * 0.7
						then out * 95 + spin * 40 + UP * 15 -- spat out of the top
						else spin * 38 - out * math.max(dist - 7, 0) * 3 + UP * (28 + 22 * pull) -- reeled in to a tight orbit, climbing
					K.hazard(model, if opts.fire then 2 else 1.2, velocity, if opts.fire and math.random() < 0.2 then "fire" else nil)
					return -- one funnel at a time has it
				end
			end
		end)
		if t >= 0 and os.clock() > nextTear then -- they rip up what they pass over, one after another
			nextTear = os.clock() + 0.5 / #feet
			tear = tear % #feet + 1
			Map.blast(floorAt(feet[tear] + UP * 20), 7, 55, nil, true)
		end
		task.wait(0.15)
	end
end

function RUN.Tsunami(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local dir = flatDir(rng)
	local origin = centre - dir * 220 -- reaches the players after ~5 s
	local side = UP:Cross(dir)
	tell(map, "start", "Tsunami", t0, { origin = origin, dir = dir })
	local hitAt = {} -- [Model] = os.clock() it was last thrown
	local swept = 0 -- how far along its path it has already flattened everything
	local nextTear = 0
	while true do
		local t = now() - t0
		if t > Shared.BY_ID.Tsunami.duration then
			break
		end
		local front = Shared.waveFront(t)
		victims(map, function(model, part)
			local along = (part.Position - origin):Dot(dir)
			if along > front + 3 or along < front - Shared.WAVE_DEPTH
				or math.abs((part.Position - origin):Dot(side)) > Shared.WAVE_WIDTH / 2
				or part.Position.Y > origin.Y + Shared.WAVE_HEIGHT then
				return
			end
			local last = hitAt[model]
			if last and os.clock() - last < 0.35 then
				return
			end
			hitAt[model] = os.clock()
			K.hazard(model, if last then 1 else 20, dir * (Shared.WAVE_SPEED + 40) + UP * 22)
		end)
		if t >= 0 and os.clock() > nextTear then -- the face flattens every building in its way: from where the
			nextTear = os.clock() + 0.2 -- last sweep stopped to just ahead of it, its whole width and height
			local ahead = front + 4
			local depth = ahead - swept + 2
			local mid = origin + dir * (ahead - depth / 2) + UP * (Shared.WAVE_HEIGHT / 2 + 2)
			Map.sweep(CFrame.lookAlong(mid, dir), Vector3.new(Shared.WAVE_WIDTH - 20, Shared.WAVE_HEIGHT + 8, depth), dir * (Shared.WAVE_SPEED + 30))
			swept = ahead
		end
		task.wait(0.1)
	end
end

function RUN.Meteors(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local rocks = {}
	for i = 1, 26 do
		table.insert(rocks, {
			at = floorAt(centre + flatDir(rng) * math.sqrt(rng:NextNumber()) * 75),
			land = 2.5 + (i - 1) * 0.55 + rng:NextNumber(0, 0.3), -- s after t0
			size = rng:NextNumber(0.9, 1.8),
		})
	end
	tell(map, "start", "Meteors", t0, { rocks = rocks })
	for _, rock in rocks do
		waitFor(t0, rock.land)
		K.explode(rock.at, Sfx.RPG_BOOM, rock.size)
		for _, player in playersIn(map) do -- explode() is the dummies' only
			local root = rootOf(player)
			local away = root and root.Position - rock.at
			local reach = 14 * rock.size
			if away and away.Magnitude < reach then
				local f = 1 - away.Magnitude / reach
				local out = if away.Magnitude > 0.1 then away.Unit else UP
				K.hazard(player.Character :: Model, 45 * f * rock.size, out * 60 * f + UP * 50 * f)
			end
		end
	end
	task.wait(1)
end

function RUN.Nuke(map: string, centre: Vector3, t0: number, opts)
	local rng = Random.new()
	local mega = if opts.mega then Shared.MEGA else 1
	local at = ring(rng, centre, 10, 35)
	tell(map, "start", "Nuke", t0, { at = at, mega = opts.mega })
	waitFor(t0, Shared.NUKE_FALL)
	K.explode(at, Sfx.RPG_BOOM, 3.5 * mega) -- the fireball: craters, kills and dismembers in ~45 studs
	task.spawn(function() -- the ring of wrecked buildings round it, a frame each: all at once hitched ~0.3 s
		for i = 1, 6 do
			task.wait()
			local b = i / 6 * math.pi * 2
			Map.blast(floorAt(at + Vector3.new(math.cos(b), 0, math.sin(b)) * 48 * mega), 14 * mega, 90, nil, true)
		end
	end)
	local reach = Shared.NUKE_RADIUS * mega
	victims(map, function(model, part)
		local away = part.Position - at
		local dist = away.Magnitude
		if dist > reach or (dist < 45 * mega and not Players:GetPlayerFromCharacter(model)) then
			return -- the fireball (explode) already had the dummies this close
		end
		local f = 1 - dist / reach
		local out = (away * FLAT).Magnitude > 0.1 and (away * FLAT).Unit or Vector3.xAxis
		K.hazard(model, 110 * f * f, out * (40 + 150 * f) + UP * (25 + 70 * f), if dist < 90 * mega then "fire" else nil)
	end)
	waitFor(t0, Shared.BY_ID.Nuke.duration)
end

-- The ground shakes everyone off their feet, cracks run out from the middle (the floor along them is
-- thrown up) and the buildings round it crumble.
function RUN.Earthquake(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local cracks = {}
	for i = 1, 5 do
		local dir = flatDir(rng)
		table.insert(cracks, { from = floorAt(centre + dir * rng:NextNumber(4, 18)), dir = dir, length = rng:NextNumber(55, 90), at = 0.5 + (i - 1) * 2.6 })
	end
	tell(map, "start", "Earthquake", t0, { centre = centre, cracks = cracks })
	for _, crack in cracks do
		task.spawn(function()
			waitFor(t0, crack.at)
			for s = 0, crack.length, 8 do -- the crack runs along, a slab every 0.08 s
				local p = floorAt(crack.from + crack.dir * (s + 4))
				Map.flip(CFrame.lookAlong(p, crack.dir), Vector3.new(5, 3, 8), UP * 28 + crack.dir * 6)
				burst(map, p, 6, 6, 10, 45)
				task.wait(0.08)
			end
		end)
	end
	local duration = Shared.BY_ID.Earthquake.duration
	local nextPlayers, nextCrumble = 0, 0
	waitFor(t0, 0)
	while now() - t0 < duration - 1 do
		local players = os.clock() > nextPlayers
		if players then
			nextPlayers = os.clock() + 1.6 -- players get thrown less often than the dummies: they have to play
		end
		victims(map, function(model, part)
			if (part.Position - centre).Magnitude > 140 then
				return
			end
			local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
			if isPlayer and not players then
				return
			end
			local shove = flatDir(rng) * rng:NextNumber(4, 10)
			K.hazard(model, if isPlayer then 2 else 0.4, shove + UP * rng:NextNumber(10, 20))
		end)
		if os.clock() > nextCrumble then -- buildings round it come down a chunk at a time
			nextCrumble = os.clock() + 1.1
			for _ = 1, 2 do
				Map.blast(ring(rng, centre, 10, 85) + UP * 6, 10, 30, nil, true)
			end
		end
		task.wait(0.4)
	end
	waitFor(t0, duration)
end

-- The volcano erupts: on the arena its own one in the lava fields (Map.CRATER), elsewhere a comic one
-- bursts out of the ground near the players (the client's model: it rises, erupts, sinks back). Either
-- way it lobs lava bombs, half at the players and half round itself; some leave burning pools.
function RUN.Volcano(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local duration = Shared.BY_ID.Volcano.duration
	local own = map == "ARENA"
	local at = if own then Vector3.new(Map.CRATER.X, centre.Y, Map.CRATER.Z) else ring(rng, centre, 25, 40) -- the cone's foot
	local crater = if own then Map.CRATER else at + UP * 15
	local start = if own then 1.5 else Shared.VOLCANO_RISE + 0.5 -- the arena's needs no time to grow
	local bombs = {}
	for i = 1, 40 do
		local t = start + (i - 1) * 0.42 + rng:NextNumber(0, 0.2)
		if t > duration - 5 then
			break
		end
		local to = if i % 2 == 0 then ring(rng, centre, 0, 60) else ring(rng, at, if own then 45 else 15, 90) -- not on the arena's cone: it would chew it up
		local reach = ((to - crater) * FLAT).Magnitude
		table.insert(bombs, { to = to, t = t, flight = math.min(1.3 + reach / 80, 4.5), size = rng:NextNumber(0.6, 1.2) })
	end
	tell(map, "start", "Volcano", t0, { at = if own then nil else at, crater = crater, bombs = bombs })
	for i, bomb in bombs do
		task.spawn(function()
			waitFor(t0, bomb.t + bomb.flight)
			K.explode(bomb.to, Sfx.RPG_BOOM, 0.7 * bomb.size)
			for _, player in playersIn(map) do
				local root = rootOf(player)
				local away = root and root.Position - bomb.to
				if away and away.Magnitude < 10 then
					K.hazard(player.Character :: Model, 25 * bomb.size, away.Unit * 40 + UP * 40, "fire")
				end
			end
			if i % 3 == 0 then
				K.ignite(bomb.to) -- a pool of burning lava, ~5 s
			end
		end)
	end
	waitFor(t0, if own then 1 else 0)
	if own then
		burst(map, crater, 26, 15, 70, 60) -- whoever stood on top is thrown off
	else
		Map.blast(at, 16, 70) -- the ground bursts where it comes up
		burst(map, at, 22, 15, 70, 50)
	end
	waitFor(t0, duration)
end

-- Thunderclouds over the players; a bolt every ~0.55 s, at someone (45%) or at whatever stands highest
-- under a random spot. Each target glows STRIKE_WARN s first ("strike"), then the bolt: a small blast,
-- and whoever it hit burns.
function RUN.Lightning(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local duration = Shared.BY_ID.Lightning.duration
	tell(map, "start", "Lightning", t0, { centre = centre })
	local n = 0
	while true do
		local t = 1 + n * 0.55
		if t > duration - 1.5 then
			break
		end
		waitFor(t0, t - Shared.STRIKE_WARN)
		local pick
		if rng:NextNumber() < 0.45 then
			local near = {}
			victims(map, function(model, part)
				if (part.Position - centre).Magnitude < 110 then
					table.insert(near, part)
				end
			end)
			pick = #near > 0 and near[rng:NextInteger(1, #near)].Position
		end
		local spot = pick or (centre + flatDir(rng) * rng:NextNumber(0, 100))
		local hit = workspace:Raycast(Vector3.new(spot.X, centre.Y + Shared.STORM_HEIGHT - 5, spot.Z), -UP * (Shared.STORM_HEIGHT + 40))
		local at = if hit then hit.Position else floorAt(spot)
		tell(map, "strike", at)
		task.delay(Shared.STRIKE_WARN, function()
			K.explode(at, Sfx.RPG_BOOM, 0.6)
			burst(map, at, 9, 30, 40, 45, "fire")
		end)
		n += 1
	end
	waitFor(t0, duration)
end

-- Freezing wind: dummies freeze solid now and then, ice spikes burst out of the ground (freezing or
-- launching whoever stands there), players get pushed along by the gusts.
function RUN.Blizzard(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local duration = Shared.BY_ID.Blizzard.duration
	local wind = flatDir(rng)
	local spikes = {}
	for i = 1, 14 do
		table.insert(spikes, { at = ring(rng, centre, 0, 80), t = 1 + (i - 1) * 1.1 + rng:NextNumber(0, 0.4) })
	end
	tell(map, "start", "Blizzard", t0, { centre = centre, wind = wind, spikes = spikes })
	for _, spike in spikes do
		task.spawn(function()
			waitFor(t0, spike.t)
			victims(map, function(model, part)
				if (part.Position - spike.at).Magnitude < 8 then
					if Players:GetPlayerFromCharacter(model) then
						K.hazard(model, 10, UP * 50)
					else
						K.freeze(model)
					end
				end
			end)
		end)
	end
	local nextGust = 0
	waitFor(t0, 0)
	while now() - t0 < duration - 1 do
		local gust = os.clock() > nextGust
		if gust then
			nextGust = os.clock() + 1.5
		end
		victims(map, function(model, part)
			if (part.Position - centre).Magnitude > 130 then
				return
			end
			if Players:GetPlayerFromCharacter(model) then
				if gust then
					K.hazard(model, 2, wind * 30 + UP * 6)
				end
			elseif rng:NextNumber() < 0.06 then
				K.freeze(model)
			end
		end)
		task.wait(0.5)
	end
	waitFor(t0, duration)
end

-- A saucer drifts over the players with its tractor beam on: whatever is under it floats up, the
-- dummies it reaches are held under the hull and spat out again a while later; now and then it zaps
-- the ground. The last 2 s it shoots off (UFO path: shared along over duration - 2).
function RUN.Ufo(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local duration = Shared.BY_ID.Ufo.duration
	local fly = duration - 2
	local start = flatDir(rng)
	local path = { floorAt(centre + start * 90) + UP * Shared.UFO_HEIGHT }
	for _ = 1, 4 do
		table.insert(path, ring(rng, centre, 0, 50) + UP * Shared.UFO_HEIGHT)
	end
	local zaps = {}
	for t = 2, fly - 1, 1.6 do
		table.insert(zaps, { t = t + rng:NextNumber(0, 0.5), at = ring(rng, centre, 0, 70) })
	end
	tell(map, "start", "Ufo", t0, { path = path, zaps = zaps })
	for _, zap in zaps do
		task.spawn(function()
			waitFor(t0, zap.t)
			K.explode(zap.at, Sfx.RPG_BOOM, 0.6)
		end)
	end
	local held = {} -- [Model] = os.clock() it reached the hull
	waitFor(t0, 0)
	while now() - t0 < fly do
		local t = now() - t0
		local pos = Shared.along(path, t, fly)
		local drift = (Shared.along(path, t + 0.1, fly) - pos) * 10
		local floorY = pos.Y - Shared.UFO_HEIGHT
		victims(map, function(model, part)
			local offset = (part.Position - pos) * FLAT
			if offset.Magnitude > Shared.UFO_BEAM or part.Position.Y < floorY - 6 then
				if held[model] then -- it moved off them: down they go
					held[model] = nil
				end
				return
			end
			local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
			if part.Position.Y > pos.Y - 7 then -- up under the hull
				held[model] = held[model] or os.clock()
				if isPlayer or os.clock() - held[model] > 2.5 then -- spat out
					held[model] = nil
					K.hazard(model, 10, flatDir(rng) * 70 + UP * 15)
				else
					K.hazard(model, 0.2, (pos - UP * 4 - part.Position) * 4 + drift)
				end
			else
				K.hazard(model, 0.3, UP * 32 - offset * 2 + drift)
			end
		end)
		task.wait(0.15)
	end
	waitFor(t0, duration)
end

-- Night falls; zombies climb out of graves round the players (one a tombstone each, the client's) and
-- go for whoever is near. At dawn the ones left burn away.
function RUN.Zombies(map: string, centre: Vector3, t0: number)
	local rng = Random.new()
	local duration = Shared.BY_ID.Zombies.duration
	local graves = {}
	for i = 1, 10 do
		table.insert(graves, { at = ring(rng, centre, 30, 70), t = 1.5 + (i - 1) * 0.7, yaw = rng:NextNumber(0, math.pi * 2) })
	end
	tell(map, "start", "Zombies", t0, { centre = centre, graves = graves })
	-- the zombies there were before: dawn leaves them be (ours are found again by kind and place, as
	-- dressing one swaps its model for a new one)
	local before = {}
	K.each(function(model)
		if model:GetAttribute("Kind") == "Zombie" then
			before[model] = true
		end
	end)
	for _, grave in graves do
		waitFor(t0, grave.t + 0.6) -- the tombstone first, then the zombie out of the ground in front of it
		K.spawnZombie(CFrame.new(grave.at + UP * 3) * CFrame.Angles(0, grave.yaw, 0))
	end
	waitFor(t0, duration - 3)
	tell(map, "dawn")
	K.each(function(model, torso)
		if model:GetAttribute("Kind") == "Zombie" and not before[model] and (torso.Position - centre).Magnitude < 250 then
			K.burnAway(model)
		end
	end)
	waitFor(t0, duration)
end

-- What it did, for the summary: watches the dummies round `centre` from now until the returned
-- function is called, which gives { bricks, flung, killed, height }.
local function watch(centre: Vector3)
	local alive, flung, peak = {}, {}, 0
	K.each(function(model, torso)
		if (torso.Position - centre).Magnitude < 250 and (model:GetAttribute("HP") or 1) > 0 then
			alive[model] = true
		end
	end)
	local bricks, on = Map.broken, true
	task.spawn(function()
		while on do
			K.each(function(model, torso)
				if (torso.Position - centre).Magnitude < 300 then
					if torso.AssemblyLinearVelocity.Magnitude > 45 then
						flung[model] = true
					end
					peak = math.max(peak, torso.Position.Y - centre.Y)
				end
			end)
			task.wait(0.25)
		end
	end)
	return function()
		on = false
		local killed, n = 0, 0
		for model in alive do
			if model.Parent and (model:GetAttribute("HP") or 1) <= 0 then
				killed += 1
			end
		end
		for _ in flung do
			n += 1
		end
		return { bricks = Map.broken - bricks, flung = n, killed = killed, height = math.floor(peak) }
	end
end

-- Set `id` (a kind or a COMBO) off in `map` round the player `around` (alive, checked by the callers).
-- `by`: who called it, for the banner.
local function begin(id: string, map: string, around: Player, by: Player?)
	local combo = Shared.COMBO[id]
	local parts = if combo then combo.parts else { id }
	local opts = table.clone(combo or {})
	opts.around = around
	busy[map] = true
	Map.holds += 1 -- nothing mends while it runs, and twice the loose cubes stay (server/Map)
	local centre = floorAt((rootOf(around) :: BasePart).Position)
	local t0 = now() + Shared.LEAD
	tell(map, "banner", id, by and by.DisplayName, t0)
	local done = watch(centre)
	task.spawn(function()
		local left = #parts
		for _, kind in parts do
			task.spawn(function()
				local ok, err = pcall(RUN[kind], map, centre, t0, opts)
				if not ok then
					warn("Disaster " .. kind .. " failed: " .. tostring(err))
				end
				left -= 1
			end)
		end
		repeat
			task.wait(0.5)
		until left == 0
		tell(map, "summary", id, done())
		Map.holds -= 1
		busy[map] = nil
	end)
end

local function onTrigger(player: Player, kind: any)
	if typeof(kind) ~= "string" or not RUN[kind] or Shop.locked(player, "SandboxPlus") then
		return
	end
	local map, root = player:GetAttribute("Map"), rootOf(player)
	if not map or not root or player:GetAttribute("Tutorial") or workspace:GetAttribute("TimeFrozen") then
		return
	end
	local since = os.clock() - (lastCall[player] or -math.huge)
	if since < Shared.COOLDOWN then
		remote:FireClient(player, "refused", "cooldown", Shared.COOLDOWN - since)
	elseif busy[map] then
		remote:FireClient(player, "refused", "busy")
	else
		lastCall[player] = os.clock()
		remote:FireClient(player, "accepted", Shared.COOLDOWN)
		begin(kind, map, player, player)
	end
end

-- The one that comes on its own: a random kind (now and then a combo) on a random map someone plays,
-- round one of them.
local function autoLoop()
	local rng = Random.new()
	while true do
		task.wait(rng:NextNumber(Shared.AUTO_MIN, Shared.AUTO_MAX))
		if workspace:GetAttribute("TimeFrozen") then
			continue
		end
		local maps, seen = {}, {}
		for _, player in Players:GetPlayers() do
			local map = player:GetAttribute("Map")
			if map and not busy[map] and not seen[map] and #playersIn(map) > 0 then
				seen[map] = true
				table.insert(maps, map)
			end
		end
		if #maps == 0 then
			continue
		end
		local map = maps[rng:NextInteger(1, #maps)]
		local people = playersIn(map)
		local around = people[rng:NextInteger(1, #people)]
		if rootOf(around) then
			local id = if rng:NextNumber() < Shared.COMBO_CHANCE
				then Shared.COMBOS[rng:NextInteger(1, #Shared.COMBOS)].id
				else Shared.KINDS[rng:NextInteger(1, #Shared.KINDS)].id
			begin(id, map, around)
		end
	end
end

-- The admin panel's test buttons (server/Admin): `id` (a kind or a combo; nil: a random kind) round
-- `player` now, without the pass, the cooldown or the tutorial check. Returns what happened.
function Disasters.force(player: Player, id: string?): string
	id = id or Shared.KINDS[math.random(#Shared.KINDS)].id
	local map, root = player:GetAttribute("Map"), rootOf(player)
	local entry = Shared.BY_ID[id] or Shared.COMBO[id]
	if not entry then
		return "No such disaster."
	elseif not map or not root then
		return "Get onto a map first."
	elseif busy[map] then
		return "One is already on here, wait for it to end."
	end
	begin(id, map, player, player)
	return `{entry.name} on its way.`
end

function Disasters.start(remotes: Folder, helpers)
	K = table.clone(helpers)
	-- everything a disaster does hurts DAMAGE times more (shared/Disasters); the shoves and blast radii stay
	K.hazard = function(model, damage, velocity, kind)
		helpers.hazard(model, damage * Shared.DAMAGE, velocity, kind)
	end
	K.explode = function(position, sound, scale)
		helpers.explode(position, sound, scale, Shared.DAMAGE)
	end
	K.ignite = function(position)
		helpers.ignite(position, Shared.DAMAGE)
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = "Disaster"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(function(player, action, kind)
		if action == "trigger" then
			onTrigger(player, kind)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastCall[player] = nil
	end)
	task.spawn(autoLoop)
end

return Disasters
