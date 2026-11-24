-- The first-time tutorial. A player who has not done it (the "Tutorial" attribute, saved by Progress)
-- skips the menu and lands on the arena (client/Menu; the server allows no other map). There:
--  1. "kill": the arena is emptied of its dummies (unless someone else is playing in it right then) and
--     five plain ones are put round the spawn, marked "TutorialFor" = their UserId (client/TutorialHud
--     outlines them in yellow through walls). They never hit back (Calm), the player's blows count
--     double until it is done, one slammed into a wall always dies, and their deaths bring no police
--     (main script: spawnDummy, hit, landImpact, kill).
--  2. "pick": once one of them is dead, buy the pistol in the Arsenal and take it (it costs less than a kill
--     pays, shared/Progression; a dummy someone else took out pays them nothing, so they take out another).
--  3. done: the tutorial dummies go and the arena fills up again the way the server starts it.
-- The step is the player's "TutorialStep" attribute ("kill" / "pick").
local Players = game:GetService("Players")

local Funnels = require(script.Parent.Funnels)

local Tutorial = {}

local COUNT = 5 -- dummies put out
local KILLS = 1 -- of them to kill (they earn the pistol)
local ARENA_REACH = 260 -- a dummy this close to the arena's centre belongs to it (the other maps are far off)

local hooks -- set by Tutorial.start
local running = {} -- [player] = { dummies = { Model }, cleared = boolean }

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
	if run.cleared then
		hooks.restock() -- as if the game had just loaded
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
	local run = { dummies = {}, cleared = false }
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
		local angle = (i - 0.5) / COUNT * math.pi * 2
		local at = Vector3.new(math.cos(angle) * 18, 4, math.sin(angle) * 18 + 6)
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
-- of "done" for a moment after the kick (client/TutorialHud). `what`: "hit", "grab" (with F), "drop" (let go of it, unkicked: back to "grab") or "punt".
function Tutorial.event(player: Player, what: string)
	if player:GetAttribute("HintsDone") ~= false then
		return -- done before, or not loaded yet
	end
	local step = player:GetAttribute("Hint")
	if what == "hit" and step == nil then
		player:SetAttribute("Hint", "grab")
	elseif what == "grab" and (step == nil or step == "grab") then -- grabbing first skips its own hint
		player:SetAttribute("Hint", "kick")
	elseif what == "drop" and step == "kick" then
		player:SetAttribute("Hint", "grab")
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
