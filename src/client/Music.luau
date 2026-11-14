-- Background music: the tracks in assets/music (uploaded as Audio), one after another in random
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

return TRACKS
