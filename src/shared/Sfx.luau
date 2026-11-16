-- One-shot 3D sounds. The server decides when (Sfx.play) and every client plays it at once from
-- preloaded copies; the shooter's own fire / throw / swing it plays locally the moment they
-- attack (Sfx.playLocal), and the server leaves them out of that broadcast, so there is no
-- round trip in what you hear from your own hands. TRIM skips the silence some clips start with
-- (measured in Studio with an AudioAnalyzer).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Sfx = {
	BRICK = "99979284489687",
	STONE = "95716327097503",
	METAL = "82015215050535",
	WOOD = "91067684183061",
	RPG_SHOT = "123120847246203",
	RPG_BOOM = "98111262596373",
	HANDGUN = "101755660572820",
	RIFLE = "87119325463074",
	GRENADE_BOOM = "110439013089203",
	THROW = "125987954246356", -- grenade / tomato / molotov throw, and a pan or katana swing that hits nothing
	KNIFE = "119732358906555",
	KATANA_HIT = "104210420639839",
	PAN_HIT = "109731609598890",
	BONE = "102667030126870", -- a bone breaking
	PUNCH = "102245289680572", -- a fist (or a kick) landing on a body
}

-- seconds of silence at the head of a clip, by asset id
Sfx.TRIM = {
	[Sfx.PAN_HIT] = 0.3,
	[Sfx.THROW] = 0.11,
	[Sfx.BONE] = 1.34,
	["122753128464765"] = 0.05, -- Jump (init.client)
	["112506453896973"] = 0.09, -- Run, looped (init.client)
}

-- Per weapon: fire (as it is used, before anything is hit), hit (on a body), swing (a melee miss).
-- Each is { id, pitch?, volume? }; weapons without their own clip borrow one at another pitch.
Sfx.WEAPON = {
	Bow = { fire = { Sfx.THROW, 1.45, 0.55 } },
	BoxingGloves = { hit = { Sfx.PUNCH, 0.9, 0.95 }, swing = { Sfx.THROW, 1.35, 0.35 } },
	Handgun = { fire = { Sfx.HANDGUN } },
	Revolver = { fire = { Sfx.HANDGUN, 0.8, 1 } },
	Shotgun = { fire = { Sfx.HANDGUN, 0.6, 1 } },
	Rifle = { fire = { Sfx.RIFLE } },
	Sniper = { fire = { Sfx.RIFLE, 0.6, 1 } },
	Rocket = { fire = { Sfx.RPG_SHOT } },
	Grenade = { fire = { Sfx.THROW } },
	Tomato = { fire = { Sfx.THROW, 1.15 } },
	Molotov = { fire = { Sfx.THROW, 0.9 } },
	Knife = { fire = { Sfx.KNIFE }, hit = { Sfx.KATANA_HIT, 1.35 } },
	KnifeSlash = { hit = { Sfx.KATANA_HIT, 1.6, 0.7 }, swing = { Sfx.THROW, 1.3, 0.5 } },
	Katana = { hit = { Sfx.KATANA_HIT }, swing = { Sfx.THROW } },
	Pan = { hit = { Sfx.PAN_HIT }, swing = { Sfx.THROW } },
	Bat = { hit = { Sfx.PAN_HIT, 0.8 }, swing = { Sfx.THROW, 0.85 } },
	Axe = { hit = { Sfx.KATANA_HIT, 0.75 }, swing = { Sfx.THROW, 0.8 } },
}
Sfx.SHATTER = { Sfx.METAL, 1.7, 0.6 } -- a molotov bottle breaking
Sfx.THUD = { Sfx.PUNCH, 0.7, 1 } -- a body hitting the ground or a wall hard (impacts)
Sfx.SCRAPE = { Sfx.STONE, 0.45, 0.35 } -- a dragged body grinding along the ground (F)

-- Skip a clip's leading silence (also on every loop).
function Sfx.prepare(sound: Sound)
	local trim = Sfx.TRIM[sound.SoundId:match("%d+") or ""]
	if trim then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(trim, 600)
	end
end

local remote: UnreliableRemoteEvent
if RunService:IsServer() then
	remote = Instance.new("UnreliableRemoteEvent")
	remote.Name = "Sfx"
	remote.Parent = ReplicatedStorage

	-- Everyone hears it at `position`, except `skip` (who already played it locally).
	-- `sound` is an asset id or { id, pitch?, volume? }.
	function Sfx.play(sound: string | { any }, position: Vector3, skip: Player?)
		for _, p in game:GetService("Players"):GetPlayers() do
			if p ~= skip then
				remote:FireClient(p, sound, position)
			end
		end
	end
	return Sfx
end

-- Client: one loaded template per clip; each play is a clone of it (no fetch, no wait).
local templates: { [string]: Sound } = {}
local folder = Instance.new("Folder")
folder.Name = "SfxTemplates"
folder.Parent = game:GetService("SoundService")
for key, id in Sfx do
	if typeof(id) == "string" then
		local s = Instance.new("Sound")
		s.Name = key
		s.SoundId = "rbxassetid://" .. id
		s.RollOffMaxDistance = 250
		Sfx.prepare(s)
		s.Parent = folder
		templates[id] = s
	end
end
task.spawn(function()
	game:GetService("ContentProvider"):PreloadAsync(folder:GetChildren())
end)

function Sfx.playLocal(spec: string | { any }, position: Vector3)
	local id, pitch, volume = spec, 1, nil
	if typeof(spec) == "table" then
		id, pitch, volume = spec[1], spec[2] or 1, spec[3]
	end
	local template = templates[id]
	if not template then
		return
	end
	local at = Instance.new("Attachment")
	at.Position = position -- Terrain sits at the origin, so local = world
	local sound = template:Clone()
	sound.Volume = volume or 0.8
	sound.PlaybackSpeed = pitch
	sound.Parent = at
	at.Parent = workspace.Terrain
	sound:Play()
	Debris:AddItem(at, 10) -- longest clip (grenade boom) is 8 s
end

ReplicatedStorage:WaitForChild("Sfx").OnClientEvent:Connect(Sfx.playLocal)

return Sfx
