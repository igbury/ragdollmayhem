-- Background music (the toolbox SETTINGS page turns it off): the tracks in assets/music (uploaded as Audio), one after another in random
-- order, for as long as the client runs. Every track plays once before any comes round again, and
-- the same one never plays twice in a row. Local: each player hears their own playlist.

local SoundService = game:GetService("SoundService")

local TRACKS = {
	"128113376650255", -- assets/music/BrasslineGroove.ogg
	"119750987716963", -- assets/music/BasementBounce.ogg
	"127062696629842", -- assets/music/BasslineCircuit.ogg
	"82250586192277", -- assets/music/BasslineCipher.ogg
}
local VOLUME = 0.35
local LOAD_TIMEOUT = 10 -- a track that has not loaded by then (still in moderation, say) is skipped

local sound = Instance.new("Sound")
sound.Name = "Music"
sound.Volume = VOLUME
sound.Parent = SoundService

local rng = Random.new()
local bag = {} -- tracks still to play this round, taken from the end
local last: string? = nil

local function playNext()
	if #bag == 0 then
		bag = table.clone(TRACKS)
		rng:Shuffle(bag)
		if #bag > 1 and bag[#bag] == last then
			bag[1], bag[#bag] = bag[#bag], bag[1] -- the new round would open with the track just heard
		end
	end
	local id = table.remove(bag)
	last = id
	sound.SoundId = "rbxassetid://" .. id
	sound:Play()
	task.delay(LOAD_TIMEOUT, function()
		if last == id and not sound.IsLoaded then
			playNext()
		end
	end)
end

sound.Ended:Connect(playNext)
playNext()

-- Sound settings (the toolbox SETTINGS page, client/Toolbox): music on / off,
-- music volume and effects volume, saved with the progress (server/Progress; the server keeps them
-- as player attributes on "setting"). Every other sound in the world plays through the Effects group.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local action = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action") :: RemoteEvent

local Music = { TRACKS = TRACKS }
local DEFAULTS = { MusicOff = false, MusicVolume = 1, SfxVolume = 1, NeverWanted = false } -- NeverWanted: the toolbox WORLD page (server Wanted)
local mine = {} -- set here and not yet back from the server: shows at once
local changed = Instance.new("BindableEvent")
Music.changed = changed.Event -- (name) after any setting changes

function Music.get(name: string): any
	local v = mine[name]
	if v == nil then
		v = player:GetAttribute(name)
	end
	if v == nil then
		v = DEFAULTS[name]
	end
	return v
end

local effects = Instance.new("SoundGroup")
effects.Name, effects.Parent = "Effects", SoundService
local function apply()
	sound.Volume = if Music.get("MusicOff") then 0 else VOLUME * Music.get("MusicVolume")
	effects.Volume = Music.get("SfxVolume")
end

function Music.set(name: string, value: any)
	mine[name] = value
	apply()
	changed:Fire(name)
	action:FireServer("setting", name, value)
end

for name in DEFAULTS do
	player:GetAttributeChangedSignal(name):Connect(function()
		if player:GetAttribute(name) == mine[name] then
			mine[name] = nil -- the server has it now
		end
		apply()
		changed:Fire(name)
	end)
end
local function route(s: Instance)
	if s:IsA("Sound") and s ~= sound and not s.SoundGroup then
		s.SoundGroup = effects
	end
end
for _, s in workspace:GetDescendants() do
	route(s)
end
workspace.DescendantAdded:Connect(route)
apply()

return Music
