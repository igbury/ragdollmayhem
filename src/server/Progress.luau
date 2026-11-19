-- Kill counters behind the weapon progression (shared/Progression has the rules). They live on the
-- player as attributes (Kills, RangedKills, ThrownKills), so the client sees its locks change at once,
-- and are saved in a DataStore: loaded on joining, written on leaving, every SAVE_EVERY while they
-- change, and when the server shuts down. Without DataStore access (Studio with API access off) they
-- only last the session.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = require(ReplicatedStorage.Shared.Progression)

local Progress = {}

local SAVE_EVERY = 60
local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, "WeaponProgress1")
if not ok then
	warn("Progress: no DataStore, kills last this session only:", store)
	store = nil
end
local loaded = {} -- [player] = true once their saved counters are in (no save before that: it would wipe them)
local dirty = {} -- [player] = true: changed since the last save

local function snapshot(player: Player)
	local data = {}
	for counter, attribute in Progression.ATTRIBUTE do
		data[counter] = player:GetAttribute(attribute) or 0
	end
	data.tutorial = player:GetAttribute("Tutorial") == false -- done (server/Tutorial)
	data.hints = player:GetAttribute("HintsDone") == true -- the controls hints too
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
	if not store then
		loaded[player] = true
		player:SetAttribute("Tutorial", true) -- nothing saved: every session starts with it
		player:SetAttribute("HintsDone", false)
		player:SetAttribute("ProgressLoaded", true)
		return
	end
	local done, data = pcall(store.GetAsync, store, tostring(player.UserId))
	if not done then
		warn("Progress: load failed for", player.Name, data) -- not marked loaded: this session never saves over it
		player:SetAttribute("Tutorial", true)
		player:SetAttribute("HintsDone", false)
		player:SetAttribute("ProgressLoaded", true) -- the client stops waiting for it all the same
		return
	end
	if player.Parent and type(data) == "table" then
		for counter, attribute in Progression.ATTRIBUTE do
			-- kills made while loading add to the saved ones
			player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + (tonumber(data[counter]) or 0))
		end
	end
	player:SetAttribute("Tutorial", not (type(data) == "table" and data.tutorial == true))
	player:SetAttribute("HintsDone", type(data) == "table" and data.hints == true)
	loaded[player] = true
	player:SetAttribute("ProgressLoaded", true)
end

-- `player` killed a dummy with `weapon` (a Weapons id; nil, "Body" or an ability count as a plain kill).
function Progress.credit(player: Player, weapon: string?)
	for _, counter in Progression.counters(weapon) do
		local attribute = Progression.ATTRIBUTE[counter]
		player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + 1)
	end
	dirty[player] = true
end

-- Something to save has changed for `player` (the tutorial done).
function Progress.touch(player: Player)
	dirty[player] = true
end

-- Whether `player` has weapon `id` unlocked (the server's check on equipping it).
function Progress.has(player: Player, id: string): boolean
	return Progression.missing(player, id) == nil
end

function Progress.start()
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		loaded[player], dirty[player] = nil, nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
		task.wait(2)
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
