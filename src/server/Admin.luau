-- Admin panel, server side (client/AdminPanel draws it). Only admins get it: whoever owns the game
-- (the creator, or rank 254+ in the owning group), anyone in ADMINS, and everyone in Studio. They
-- get the player attribute "Admin"; every request on the "Admin" remote is checked against it again.
-- What it can do comes from init.server.luau (api, below): it works on the dummies and the player who
-- asked, never on anyone else.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shop = require(ReplicatedStorage.Shared.Shop)
local Progression = require(ReplicatedStorage.Shared.Progression)

local Admin = {}

local ADMINS = {} -- [UserId] = true: extra admins besides the owner
local UNLOCK_KILLS = 100000 -- enough of every counter for every weapon (shared/Progression)
local SPAWN_COUNT = 5
local STATS = { "StatBones", "StatThrown", "StatCombo", "StatThrow", "StatPlaytime" }

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() or ADMINS[player.UserId] then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
	return ok and rank >= 254
end

-- api = {
--   dummies: { [Model]: d }, spawn: (cf, kind?) -> d?, revive: (d) -> (), kill: (d) -> (),
--   freeze: () -> boolean (toggles TIME STOP, returns it), wanted: (player, stars) -> (),
--   berserk: (d) -> () (fights the nearest dummy from now on), trim: () -> () (room for one more),
-- }
function Admin.start(remotes: Folder, api)
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Admin"
	remote.Parent = remotes

	local function onJoin(player: Player)
		if isAdmin(player) then
			player:SetAttribute("Admin", true)
		end
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerAdded:Connect(onJoin)

	local function around(player: Player, count: number, kind: string?)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		for i = 1, count do
			local a = i / count * math.pi * 2
			api.trim()
			api.spawn(CFrame.new(root.Position + root.CFrame.LookVector * 14 + Vector3.new(math.cos(a), 0, math.sin(a)) * 6 + Vector3.yAxis * 2), kind)
		end
	end

	local ACTIONS = {
		weapons = function(player)
			for _, attribute in Progression.ATTRIBUTE do
				player:SetAttribute(attribute, UNLOCK_KILLS)
			end
			return "Every weapon unlocked."
		end,
		reset = function(player)
			for _, attribute in Progression.ATTRIBUTE do
				player:SetAttribute(attribute, 0)
			end
			for _, stat in STATS do
				player:SetAttribute(stat, 0)
			end
			return "Kills and stats back to zero."
		end,
		god = function(player)
			local char = player.Character
			if not char then
				return nil
			end
			char:SetAttribute("God", not char:GetAttribute("God"))
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
			return if char:GetAttribute("God") then "God mode on." else "God mode off."
		end,
		speed = function(player)
			local fast = not player:GetAttribute("AdminFast")
			player:SetAttribute("AdminFast", fast) -- the client doubles its own walk and sprint speed
			return if fast then "Super speed on." else "Super speed off."
		end,
		heal = function(player)
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
			return "Healed."
		end,
		pass = function(player, key)
			if typeof(key) ~= "string" or not Shop.item(key) then
				return nil
			end
			local attribute = Shop.attribute(key)
			player:SetAttribute(attribute, not player:GetAttribute(attribute))
			return `{Shop.item(key).name}: {if player:GetAttribute(attribute) then "given" else "taken away"}.`
		end,
		wanted = function(player, stars)
			if typeof(stars) ~= "number" or stars ~= stars then
				return nil
			end
			api.wanted(player, math.clamp(math.floor(stars), 0, 5))
			return `Wanted: {math.clamp(math.floor(stars), 0, 5)} stars.`
		end,
		spawn = function(player)
			around(player, SPAWN_COUNT, nil)
			return `{SPAWN_COUNT} dummies spawned.`
		end,
		zombies = function(player)
			around(player, SPAWN_COUNT, "Zombie")
			return `{SPAWN_COUNT} zombies spawned.`
		end,
		soldiers = function(player)
			around(player, 3, "Soldier")
			return "3 soldiers spawned."
		end,
		reviveall = function()
			local n = 0
			for _, d in api.dummies do
				if not d.model:GetAttribute("TutorialFor") then
					api.revive(d)
					n += 1
				end
			end
			return `{n} dummies revived.`
		end,
		killall = function()
			local n = 0
			for _, d in api.dummies do
				if d.state ~= "Dead" and not d.model:GetAttribute("TutorialFor") then
					api.kill(d)
					n += 1
				end
			end
			return `{n} dummies dropped.`
		end,
		removeall = function()
			local n = 0
			for _, d in table.clone(api.dummies) do
				if not d.model:GetAttribute("TutorialFor") and not d.heldBy then
					d.model:Destroy()
					n += 1
				end
			end
			return `{n} dummies removed.`
		end,
		brawl = function()
			local n = 0
			for _, d in api.dummies do
				if d.state ~= "Dead" and not d.zombie and not d.model:GetAttribute("TutorialFor") then
					api.berserk(d)
					n += 1
				end
			end
			return `{n} dummies are fighting each other.`
		end,
		freeze = function()
			return if api.freeze() then "Time stopped." else "Time running."
		end,
	}

	local lastUse = {}
	remote.OnServerEvent:Connect(function(player, action, arg)
		if not player:GetAttribute("Admin") or typeof(action) ~= "string" or not ACTIONS[action] then
			return
		end
		local now = os.clock()
		if now - (lastUse[player] or 0) < 0.2 then
			return
		end
		lastUse[player] = now
		local ok, result = pcall(ACTIONS[action], player, arg)
		remote:FireClient(player, if ok then result or "Nothing to do." else "That did not work.")
		if not ok then
			warn("Admin", action, result)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)
end

return Admin
