-- Kill counters behind the weapon progression (shared/Progression has the rules). They live on the
-- player as attributes (Kills, RangedKills, ThrownKills), so the client sees its locks change at once,
-- and are saved in a DataStore: loaded on joining, written on leaving, every SAVE_EVERY while they
-- change, and when the server shuts down. Without DataStore access (Studio with API access off) they
-- only last the session.
local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = require(ReplicatedStorage.Shared.Progression)
local Shop = require(ReplicatedStorage.Shared.Shop)
local Settings = require(ReplicatedStorage.Shared.Settings)
local Funnels = require(script.Parent.Funnels)

local Progress = {}
-- Settings (shared/Settings; the toolbox SETTINGS page): attribute = its type. Saved as they are.
Progress.Funnels = Funnels -- reached through here by the main server script (its locals limit)
Progress.Settings = Settings -- for the main server script, which is at Luau's 200-locals limit
Progress.SETTINGS = {}
for name, default in Settings.DEFAULTS do
	Progress.SETTINGS[name] = type(default)
end

local SAVE_EVERY = 60
local GROUP_CHECK = 15 -- seconds between membership checks for those not in the group yet
local GROUP_ID = if game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 0
local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, "WeaponProgress1")
if not ok then
	warn("Progress: no DataStore, kills last this session only:", store)
	store = nil
end
-- The menu's STATS page (client/Menu), kept and saved with the counters. "add" stats sum up, "best"
-- ones keep the highest. StatThrow and StatWalked are in studs, StatPlaytime in seconds.
local STATS = { StatBones = "add", StatThrown = "add", StatWalked = "add", StatThrow = "best", StatPlaytime = "add" }
local PLAYTIME_STEP = 10
local WALK_STEP = 0.5 -- seconds between position samples for StatWalked
local WALK_MAX = 30 -- studs per sample above which it was not walking (a teleport, a respawn, a fling)
local lastAt = {} -- [player] = where their root was at the last walk sample
local loaded = {} -- [player] = true once their saved counters are in (no save before that: it would wipe them)
local dirty = {} -- [player] = true: changed since the last save

local function snapshot(player: Player)
	local data = {}
	for counter, attribute in Progression.ATTRIBUTE do
		data[counter] = player:GetAttribute(attribute) or 0
	end
	data.stats = {}
	for stat in STATS do
		data.stats[stat] = player:GetAttribute(stat) or 0
	end
	data.tutorial = player:GetAttribute("Tutorial") == false -- done (server/Tutorial)
	data.hints = player:GetAttribute("HintsDone") == true -- the controls hints too
	data.settings = {}
	for name in Progress.SETTINGS do
		data.settings[name] = player:GetAttribute(name)
	end
	data.funnels = Funnels.save(player)
	return data
end

local function save(player: Player)
	if not (store and loaded[player] and dirty[player]) then
		return
	end
	dirty[player] = nil
	local data = snapshot(player)
	local done, err = pcall(store.SetAsync, store, tostring(player.UserId), data)
	if not done then
		dirty[player] = true -- try again next round
		warn("Progress: save failed for", player.Name, err)
	end
end

local function load(player: Player)
	for _, attribute in Progression.ATTRIBUTE do
		player:SetAttribute(attribute, player:GetAttribute(attribute) or 0)
	end
	for stat in STATS do
		player:SetAttribute(stat, player:GetAttribute(stat) or 0)
	end
	if not store then
		loaded[player] = true
		player:SetAttribute("Tutorial", true) -- nothing saved: every session starts with it
		player:SetAttribute("HintsDone", false)
		player:SetAttribute("ProgressLoaded", true)
		Funnels.load(player, nil)
		return
	end
	local done, data = pcall(store.GetAsync, store, tostring(player.UserId))
	if not done then
		warn("Progress: load failed for", player.Name, data) -- not marked loaded: this session never saves over it
		player:SetAttribute("Tutorial", true)
		player:SetAttribute("HintsDone", false)
		player:SetAttribute("ProgressLoaded", true) -- the client stops waiting for it all the same
		Funnels.load(player, nil) -- this session's only: it is never saved
		return
	end
	if player.Parent and type(data) == "table" then
		for counter, attribute in Progression.ATTRIBUTE do
			-- kills made while loading add to the saved ones
			player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + (tonumber(data[counter]) or 0))
		end
		local saved = type(data.stats) == "table" and data.stats or {}
		for stat, how in STATS do
			local have, old = player:GetAttribute(stat) or 0, tonumber(saved[stat]) or 0
			player:SetAttribute(stat, if how == "add" then have + old else math.max(have, old))
		end
	end
	player:SetAttribute("Tutorial", not (type(data) == "table" and data.tutorial == true))
	player:SetAttribute("HintsDone", type(data) == "table" and data.hints == true)
	local settings = type(data) == "table" and type(data.settings) == "table" and data.settings or {}
	for name, kind in Progress.SETTINGS do
		if type(settings[name]) == kind and player:GetAttribute(name) == nil then -- not changed while loading
			player:SetAttribute(name, settings[name])
		end
	end
	loaded[player] = true
	player:SetAttribute("ProgressLoaded", true)
	Funnels.load(player, type(data) == "table" and data.funnels)
end

-- `player` killed a dummy with `weapon` (a Weapons id; nil, "Body" or an ability count as a plain kill).
-- 2X KO counts each kill Shop.KO_WORTH times.
function Progress.credit(player: Player, weapon: string?)
	local worth = Shop.owns(player, "DoubleKO") and Shop.KO_WORTH or 1
	for _, counter in Progression.counters(weapon) do
		local attribute = Progression.ATTRIBUTE[counter]
		player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + worth)
	end
	Funnels.kill(player, weapon)
	dirty[player] = true
end

-- One more of a summed stat (StatBones, StatThrown).
function Progress.add(player: Player, stat: string, amount: number?)
	player:SetAttribute(stat, (player:GetAttribute(stat) or 0) + (amount or 1))
	dirty[player] = true
end

-- A new record for a "best" stat (StatThrow), if it beats the old one.
function Progress.best(player: Player, stat: string, value: number)
	if value > (player:GetAttribute(stat) or 0) then
		player:SetAttribute(stat, value)
		dirty[player] = true
	end
end

-- Something to save has changed for `player` (the tutorial done).
function Progress.touch(player: Player)
	dirty[player] = true
end

-- Whether `player` has weapon `id` unlocked (the server's check on equipping it).
function Progress.has(player: Player, id: string): boolean
	return Progression.missing(player, id) == nil
end

-- InGroup (shared/Progression's group rule): GetGroupsAsync, not IsInGroup, which caches a "no"
-- for the whole session and would miss someone joining mid-game.
local function checkGroup(player: Player)
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if not ok then
		return
	end
	for _, g in groups do
		if g.Id == GROUP_ID then
			player:SetAttribute(Progression.GROUP_ATTRIBUTE, true)
			return
		end
	end
end

function Progress.start()
	Funnels.changed = Progress.touch
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		loaded[player], dirty[player], lastAt[player] = nil, nil, nil
		Funnels.forget(player)
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
		task.wait(2)
	end)
	task.spawn(function()
		-- ponytail: polls non-members every GROUP_CHECK s; a client remote after the join prompt if 15 s feels slow
		while GROUP_ID ~= 0 do
			for _, player in Players:GetPlayers() do
				if not player:GetAttribute(Progression.GROUP_ATTRIBUTE) then
					task.spawn(checkGroup, player)
				end
			end
			task.wait(GROUP_CHECK)
		end
	end)
	task.spawn(function() -- distance walked: on foot on the ground in a map (not ragdolled, seated or flying)
		while true do
			task.wait(WALK_STEP)
			for _, player in Players:GetPlayers() do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = char and char:FindFirstChildOfClass("Humanoid")
				local was = lastAt[player]
				lastAt[player] = root and root.Position
				if not (root and humanoid and was and player:GetAttribute("ProgressLoaded") and player:GetAttribute("Map")) then
					continue
				end
				if humanoid.Sit or humanoid.FloorMaterial == Enum.Material.Air or char:GetAttribute("Ragdolled") then
					continue
				end
				local step = ((root.Position - was) * Vector3.new(1, 0, 1)).Magnitude
				if step > 0.2 and step < WALK_MAX then
					Progress.add(player, "StatWalked", step)
				end
			end
		end
	end)
	task.spawn(function() -- playtime counts only in a map, not in the menu
		while true do
			task.wait(PLAYTIME_STEP)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("ProgressLoaded") and player:GetAttribute("Map") then
					Progress.add(player, "StatPlaytime", PLAYTIME_STEP)
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(SAVE_EVERY)
			for player in dirty do
				save(player)
			end
		end
	end)
end

return Progress
