-- The first-time tutorial. A player who has not done it (the "Tutorial" attribute, saved by Progress)
-- skips the menu and lands on the arena (client/Menu; the server allows no other map). There:
--  1. "kill": the arena is emptied of its dummies (unless someone else is playing in it right then), a
--     glass cage goes up round the spawn between its four pillars (walls and roof thick enough that a
--     kicked body never goes through: MAX_PUNT_SPEED 200 is under a stud per physics step), and one plain
--     dummy is put in it with the player, marked "TutorialFor" = their UserId (client/TutorialHud
--     outlines them in yellow through walls). They never hit back (Calm), the player's blows count
--     double until it is done, one slammed into a wall always dies, and their deaths bring no police
--     (main script: spawnDummy, hit, landImpact, kill).
--  2. "pick": once one of them is dead, buy the pistol in the Arsenal and take it (it costs less than a kill
--     pays, shared/Progression; a dummy someone else took out pays them nothing, so they take out another).
--  3. done: the cage shatters, the tutorial dummies go and, once the shards are gone, the arena fills up again
--     the way the server starts it. Until then nothing happens outside the cage (no dummies, no disasters).
-- The step is the player's "TutorialStep" attribute ("kill" / "pick").
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Funnels = require(script.Parent.Funnels)
local Sfx = require(game:GetService("ReplicatedStorage").Shared.Sfx)

local Tutorial = {}

local COUNT = 1 -- dummies put out (in the cage)
local KILLS = 1 -- of them to kill (they earn the pistol)
local ARENA_REACH = 260 -- a dummy this close to the arena's centre belongs to it (the other maps are far off)

local hooks -- set by Tutorial.start
local running = {} -- [player] = { dummies = { Model }, cleared = boolean, cage = Folder }

-- The cage: the spawn's four pillars stand at x, z = +-20..24, so the walls' inner faces sit just behind
-- theirs (no face shared with a pillar's: no z-fighting) and the roof caps them.
local IN, THICK, TALL = 20.5, 6, 30
local OUT = IN + THICK
local CAGE = { -- { size, centre }
	{ Vector3.new(OUT * 2, TALL + 1, THICK), Vector3.new(0, TALL / 2 - 0.5, IN + THICK / 2) },
	{ Vector3.new(OUT * 2, TALL + 1, THICK), Vector3.new(0, TALL / 2 - 0.5, -IN - THICK / 2) },
	{ Vector3.new(THICK, TALL + 1, IN * 2), Vector3.new(IN + THICK / 2, TALL / 2 - 0.5, 0) },
	{ Vector3.new(THICK, TALL + 1, IN * 2), Vector3.new(-IN - THICK / 2, TALL / 2 - 0.5, 0) },
	{ Vector3.new(OUT * 2, THICK, OUT * 2), Vector3.new(0, TALL + THICK / 2, 0) },
}
local GLASS = Color3.fromRGB(170, 220, 255)
local SHARD = 3.5 -- studs: the little cubes a wall breaks into (one layer of them, in the wall's middle)
local SHARD_KEEP = 0.6 -- of them actually thrown (about 430 parts, gone in 4 s)
local FALLEN = 4 -- s after the shatter: the shards are gone, the arena fills up again

local function glass(size: Vector3, position: Vector3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Position = position
	p.Anchored = true
	p.Material = Enum.Material.Glass
	p.Color = GLASS
	p.Transparency = 0.35
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function buildCage(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "TutorialCage"
	for _, wall in CAGE do
		glass(wall[1], wall[2], folder)
	end
	folder.Parent = workspace
	return folder
end

-- each wall falls apart into flying shards, outward from the middle of the cage
local function shatter(cage: Folder)
	for _, wall in cage:GetChildren() do
		local size, centre = wall.Size, wall.Position
		-- the thin axis (THICK) gets one layer, the other two a grid of SHARD cubes
		local function count(a: number): number
			return if a <= THICK then 1 else math.round(a / SHARD)
		end
		local n = Vector3.new(count(size.X), count(size.Y), count(size.Z))
		local piece = size / n
		for x = 1, n.X do
			for y = 1, n.Y do
				for z = 1, n.Z do
					if math.random() > SHARD_KEEP then
						continue
					end
					local at = centre - size / 2 + piece * Vector3.new(x - 0.5, y - 0.5, z - 0.5)
					local shard = glass(Vector3.one * SHARD * (0.6 + math.random() * 0.35), at, workspace)
					shard.Anchored = false
					shard.CollisionGroup = "Debris" -- server/Map: shards pass through each other
					local out = (at - Vector3.new(0, 4, 0)).Unit
					shard.AssemblyLinearVelocity = out * (20 + math.random() * 25) + Vector3.yAxis * math.random() * 15
					shard.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
					Debris:AddItem(shard, 3 + math.random())
				end
			end
		end
	end
	Sfx.play(Sfx.ICE_SHATTER, Vector3.new(0, 6, 0))
	cage:Destroy()
end

local function inArena(model: Model): boolean
	return model:GetPivot().Position.Magnitude < ARENA_REACH
end

-- someone besides `player` playing in the arena (not in the menu, not in their own tutorial)
local function othersPlaying(player: Player): boolean
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("Map") == "ARENA" and not other:GetAttribute("Tutorial") then
			return true
		end
	end
	return false
end

local function finish(player: Player, completed: boolean)
	local run = running[player]
	if not run then
		return
	end
	running[player] = nil
	for _, model in run.dummies do
		model:Destroy()
	end
	if completed then
		shatter(run.cage)
	else
		run.cage:Destroy()
	end
	if run.cleared then
		-- as if the game had just loaded, once the cage has come down
		task.delay(if completed then FALLEN else 0, hooks.restock)
	end
	if completed and player.Parent then
		player:SetAttribute("Tutorial", false)
		hooks.done(player) -- saved: it never comes again
		Funnels.tutorial(player, 4)
	end
	player:SetAttribute("TutorialStep", nil)
end

-- `player` has just been put in the arena (client/Menu sends a first-timer there at once).
function Tutorial.begin(player: Player)
	if running[player] or not player:GetAttribute("Tutorial") then
		return
	end
	local run = { dummies = {}, cleared = false, cage = buildCage() }
	running[player] = run
	if not othersPlaying(player) then
		run.cleared = true
		for _, model in hooks.dummies() do
			if inArena(model) then
				model:Destroy()
			end
		end
	end
	for i = 1, COUNT do
		local angle = (i - 1) / COUNT * math.pi * 2 -- the first one straight ahead of the spawn (it faces -Z)
		local at = Vector3.new(math.sin(angle) * 12, 4, -math.cos(angle) * 12)
		local model = hooks.spawn(CFrame.lookAt(at, Vector3.new(0, 4, 0)), "Normal")
		model:SetAttribute("TutorialFor", player.UserId)
		table.insert(run.dummies, model)
	end
	player:SetAttribute("TutorialStep", "kill")
	Funnels.tutorial(player, 2)
end

function Tutorial.start(h)
	hooks = h
	Players.PlayerRemoving:Connect(function(player)
		finish(player, false)
	end)
	task.spawn(function()
		while true do
			task.wait(0.3)
			for player, run in running do
				local step = player:GetAttribute("TutorialStep")
				if step == "kill" then
					local dead = 0
					for _, model in run.dummies do
						if not model.Parent or model:GetAttribute("State") == "Dead" then
							dead += 1
						end
					end
					if dead >= KILLS then
						player:SetAttribute("TutorialStep", "pick")
						Funnels.tutorial(player, 3)
					end
				elseif step == "pick" then
					local char = player.Character
					if char and char:GetAttribute("EquippedWeapon") == "Handgun" then
						finish(player, true)
					end
				end
			end
		end
	end)
end

-- The controls hints (saved like the tutorial, "HintsDone"; shown on a line of their own, so they run
-- during the tutorial too): the first time the player hits a ragdoll, "grab it with F"; once they hold one by F, "look ahead and click to kick it
-- into a wall"; the kick ends them. The step is the "Hint" attribute ("grab" / "kick"), and a "Hint"
-- of "done" for a moment after the kick (client/TutorialHud). `what`: "hit", "grab" (with F), "drop" (let go of it, unkicked: the hints end, never shown again) or "punt".
function Tutorial.event(player: Player, what: string)
	if player:GetAttribute("HintsDone") ~= false then
		return -- done before, or not loaded yet
	end
	local step = player:GetAttribute("Hint")
	if what == "hit" and step == nil then
		player:SetAttribute("Hint", "grab")
	elseif what == "grab" and (step == nil or step == "grab") then -- grabbing first skips its own hint
		player:SetAttribute("Hint", "kick")
	elseif what == "drop" and step == "kick" then -- let go unkicked: the kick step is skipped, for good (saved)
		player:SetAttribute("HintsDone", true)
		player:SetAttribute("Hint", nil)
		hooks.done(player)
	elseif what == "punt" and step == "kick" then
		player:SetAttribute("HintsDone", true)
		player:SetAttribute("Hint", "done")
		hooks.done(player) -- saved: they never come again
		task.delay(3, function()
			if player.Parent and player:GetAttribute("Hint") == "done" then
				player:SetAttribute("Hint", nil)
			end
		end)
	end
end

return Tutorial
