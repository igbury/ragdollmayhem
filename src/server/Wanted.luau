-- Wanted level. Killing dummies heats a player up (cops and soldiers count more than anyone else);
-- the heat shows as 0..5 stars (player attribute "Wanted", drawn by the client's WantedHud).
--  * 1-2 stars: cops come at the player with batons (cops who see it; from 2, waves of them);
--  * 3 stars: the cops draw their handguns;
--  * 4 stars: soldiers with rifles;
--  * 5 stars: soldiers, and helicopters that rope down Heavies (armoured, rocket launchers).
-- Each star costs much more heat than the one before: 4 and 5 take a real massacre.
-- Nothing killed for COOL_AFTER seconds and the heat drains; dying clears it.
-- The main script owns the dummies: start() gets what it needs from it (api).
local Players = game:GetService("Players")
local Helicopter = require(script.Parent.Helicopter)

local Wanted = {}

local HEAT = { Cop = 2, Soldier = 3, Heavy = 5 } -- per kill, by the victim's kind; anyone else: 1
local STARS = { 1, 6, 16, 45, 70 } -- heat for each star
local COOL_AFTER = 25 -- seconds after the last kill before the heat drains
local COOL_RATE = 0.4 -- heat per second while it drains, plus 1% of the heat
local GUNS_AT = 3 -- stars from which cops shoot instead of using the baton
local WAVE_EVERY = 18 -- seconds between waves
local WAVES = { -- [stars] = who each wave brings; "Heli" = a helicopter with HELI on board
	[2] = { "Cop", "Cop" },
	[3] = { "Cop", "Cop", "Cop" },
	[4] = { "Soldier", "Soldier", "Soldier" },
	[5] = { "Soldier", "Soldier", "Heli" },
}
local HELI = { "Heavy", "Heavy", "Heavy" }
local MAX_HUNTERS = 10 -- after one player at once
local SIGHT = 80 -- a cop on the map this close joins in
local SPAWN_FROM, SPAWN_TO = 45, 65 -- how far from the player a wave turns up

local heat, lastKill, nextWave = {}, {}, {}

local function stars(player: Player): number
	local n = 0
	for i, need in STARS do
		if (heat[player] or 0) >= need then
			n = i
		end
	end
	return n
end

-- `kind`: the dead dummy's kind (its "Kind" attribute).
function Wanted.crime(player: Player, kind: string?)
	local before = stars(player)
	heat[player] = math.min((heat[player] or 0) + (HEAT[kind] or 1), STARS[#STARS] + 10)
	lastKill[player] = os.clock()
	if stars(player) > before and WAVES[stars(player)] then
		nextWave[player] = math.min(nextWave[player] or math.huge, os.clock() + 4) -- a new star brings its wave soon
	end
	player:SetAttribute("Wanted", stars(player))
end

-- Who answers for what the running thread does to dummies: a player's remote handler, their
-- rocket in flight, their grenade's fuse, their molotov's fire all act for them; a soldier's rocket
-- acts for nobody (false). Per thread, so it holds across waits inside one attack and two players'
-- attacks never mix. nil: nothing said (dummies' own fights, the Heartbeat).
-- `weapon`: what it is done with (a Weapons id, "Body" for a thrown body, ...), for the kill counters
-- behind the weapon progression (server/Progress).
local acting = setmetatable({}, { __mode = "k" }) -- [thread] = Player | false
local actingWith = setmetatable({}, { __mode = "k" }) -- [thread] = weapon id
function Wanted.act(by: Player | false | nil, weapon: string?)
	acting[coroutine.running()] = by
	actingWith[coroutine.running()] = weapon
end
function Wanted.culprit(): Player | false | nil
	return acting[coroutine.running()]
end
function Wanted.weapon(): string?
	return actingWith[coroutine.running()]
end

function Wanted.clear(player: Player)
	if heat[player] then
		heat[player] = 0 -- the loop calls the hunters off next tick
	end
	lastKill[player], nextWave[player] = nil, nil
	player:SetAttribute("Wanted", 0)
end

Players.PlayerRemoving:Connect(function(player)
	heat[player], lastKill[player], nextWave[player] = nil, nil, nil
end)

-- api = {
--   dummies: { [Model]: d },            the live dummies (d.state, d.gear, d.target, d.model)
--   law: (d) -> boolean,                police or army: hunts a wanted player
--   arm: (d, gear) -> (),               gives it that weapon (a cop's baton or handgun)
--   spawn: (CFrame, kind) -> d?,        a new dummy of that kind
--   stop: (d) -> (),                    it stops fighting
--   exclude: () -> { Instance },        what a spawn's ground ray ignores (bodies)
-- }
function Wanted.start(api)
	local params = RaycastParams.new()
	local function enlist(d, player: Player)
		d.sent = true -- came for this player: it leaves once the heat is gone
		d.hunt, d.target = player, player
	end
	local function spawnNear(root: BasePart, kind: string, player: Player)
		local angle = math.random() * math.pi * 2
		local at = root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (SPAWN_FROM + math.random() * (SPAWN_TO - SPAWN_FROM))
		params.FilterDescendantsInstances = api.exclude()
		local ground = workspace:Raycast(at + Vector3.yAxis * 60, Vector3.yAxis * -160, params)
		-- off the edge of the map, in the port's water (terrain), or up on something tall (the port's
		-- crane, a container stack) the player is nowhere near: no one from that side this time
		if not ground or ground.Instance == workspace.Terrain or ground.Position.Y > root.Position.Y + 12 then
			return false
		end
		local d = api.spawn(CFrame.lookAt(ground.Position + Vector3.yAxis * 4, root.Position * Vector3.new(1, 0, 1) + Vector3.yAxis * (ground.Position.Y + 4)), kind)
		if d then
			enlist(d, player)
		end
		return d ~= nil
	end

	-- the player's gear rule for a cop: baton, or the handgun from GUNS_AT stars
	local function armCop(d, n: number)
		if d.model:GetAttribute("Kind") == "Cop" then
			api.arm(d, n >= GUNS_AT and "Handgun" or "Baton")
		end
	end

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local h = heat[player]
				if not h then
					continue
				end
				if now - (lastKill[player] or 0) > COOL_AFTER then
					heat[player] = h - COOL_RATE - h * 0.01
				end
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local n = stars(player)
				if player:GetAttribute("Wanted") ~= n then
					player:SetAttribute("Wanted", n)
				end
				if n == 0 then
					heat[player] = nil
					-- called off: the ones sent go home, the rest are cops on the beat again
					for _, d in api.dummies do
						if d.hunt == player then
							d.hunt = nil
							armCop(d, 0)
							if d.target == player then
								api.stop(d)
							end
							if d.sent and d.state ~= "Dead" then
								task.delay(6, function()
									if not d.hunt and d.model.Parent then
										d.model:Destroy()
									end
								end)
							end
						end
					end
					continue
				end
				if not root or not hum or hum.Health <= 0 then
					continue
				end
				local hunters = 0
				for _, d in api.dummies do
					if d.state == "Dead" or not api.law(d) then
						continue
					end
					local r = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
					local near = r and (r.Position - root.Position).Magnitude < SIGHT
					if d.hunt == player or (near and not d.hunt and not d.target) then
						d.hunt = player
						hunters += 1
						armCop(d, n)
						if d.target ~= player and d.state == "Awake" then
							d.target = player -- back on it after it lost them or ran off to recover
						end
					end
				end
				local wave = WAVES[n]
				if wave and now >= (nextWave[player] or 0) then
					nextWave[player] = now + WAVE_EVERY
					for _, kind in wave do
						if hunters >= MAX_HUNTERS then
							break
						end
						if kind == "Heli" and player:GetAttribute("Map") == "FACTORY" then
							-- a helicopter can't get under the factory's roof (it would hover in it and
							-- fly through the walls): its Heavies come in on foot instead
							for _, trooper in HELI do
								if hunters < MAX_HUNTERS and spawnNear(root, trooper, player) then
									hunters += 1
								end
							end
						elseif kind == "Heli" then
							hunters += #HELI
							local over = root.Position
							task.spawn(Helicopter.drop, over, HELI, function(cf, trooper)
								local d = api.spawn(cf, trooper)
								if d and heat[player] then
									enlist(d, player)
								elseif d then
									d.model:Destroy() -- called off while it flew in
								end
							end)
						elseif spawnNear(root, kind, player) then
							hunters += 1
						end
					end
				end
			end
		end
	end)
end

Wanted.stars = stars
return Wanted
