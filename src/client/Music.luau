-- Background music (the note button, top right, turns it off): the tracks in assets/music (uploaded as Audio), one after another in random
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

-- Sound settings (the toolbox's SETTINGS page, client/Toolbox, and the note button): music on / off,
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

-- A note button in the top-right corner, over the menu too: music on / off.
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "MusicToggle", false, 20 -- above the menu (10)
local button = Instance.new("TextButton")
button.AnchorPoint, button.Position, button.Size = Vector2.new(1, 0), UDim2.new(1, -12, 0, 8), UDim2.fromOffset(44, 44)
button.Font, button.TextSize, button.Text = Enum.Font.GothamBold, 26, "♪"
button.TextColor3, button.Parent = Color3.fromRGB(20, 20, 24), gui
local stroke = Instance.new("UIStroke")
stroke.Thickness, stroke.ApplyStrokeMode, stroke.Parent = 3, Enum.ApplyStrokeMode.Border, button
local slash = Instance.new("Frame") -- crossed out while off
slash.AnchorPoint, slash.Position, slash.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.new(1, 4, 0, 4)
slash.Rotation, slash.BackgroundColor3, slash.BorderSizePixel, slash.Parent = -45, Color3.fromRGB(232, 70, 56), 0, button
local function show()
	local off = Music.get("MusicOff")
	button.BackgroundColor3 = if off then Color3.fromRGB(150, 150, 156) else Color3.fromRGB(252, 200, 50)
	slash.Visible = off
end
show()
Music.changed:Connect(show)
button.Activated:Connect(function()
	Music.set("MusicOff", not Music.get("MusicOff"))
end)
gui.Parent = player:WaitForChild("PlayerGui")

return Music
