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
-- ElevenLabs clips (assets/sfx/gen/<name>.mp3, made by assets/sfx/elevenlabs_gen.py), by file name
-- in capitals. Ids: assets/sfx/gen/assets.json.
--@generated-sfx-begin
Sfx.ARM_RIP = "77640094945176"
Sfx.ARROW_HIT_BODY = "71873942760622"
Sfx.ARROW_HIT_WALL = "80319953360396"
Sfx.AXE_HIT = "115661794232070"
Sfx.BAT_HIT = "115238448058948"
Sfx.BATON_HIT = "123940620148236"
Sfx.BODY_FALL = "104618117748086"
Sfx.BODY_SCRAPE_LOOP = "118300805981349"
Sfx.BODY_THUD = "110119269111710"
Sfx.BOIL_BLAST = "97911914460350"
Sfx.BOIL_SIZZLE = "113528140766610"
Sfx.BOW_DRAW = "134050846791593"
Sfx.BOW_RELEASE = "76135229303027"
Sfx.BULLET_HIT_BODY = "114569729544482"
Sfx.BULLET_HIT_CONCRETE = "105030234443458"
Sfx.BULLET_HIT_METAL = "125515939548026"
Sfx.BULLET_HIT_WOOD = "128838386116181"
Sfx.C4_BEEP = "117636856606826"
Sfx.C4_STICK = "93374716716764"
Sfx.CAR_CRASH = "71252438577829"
Sfx.CAR_DOOR = "90634633575501"
Sfx.CAR_ENGINE_DRIVE_LOOP = "77417049282986"
Sfx.CAR_ENGINE_IDLE_LOOP = "88965245287813"
Sfx.CAR_HORN = "81976256574648"
Sfx.CHAINSAW_REV = "129958120653550"
Sfx.CITY_AMBIENCE_LOOP = "76505637533482"
Sfx.COMIC_BOOK_CLOSE = "79079157069537"
Sfx.COMIC_BOOK_OPEN = "111308078990691"
Sfx.COMIC_PAGE_TURN = "82122354228220"
Sfx.CROWBAR_HIT = "86103049574714"
Sfx.DASH_WHOOSH = "131320486711563"
Sfx.DRY_FIRE_CLICK = "74851855184549"
Sfx.DUMMY_SHOUT = "139411605642960"
Sfx.DUMMY_TALK = "117288890674383"
Sfx.DUMMY_THINK = "87648860761076"
Sfx.FACTORY_PRESS_SLAM = "100457768843106"
Sfx.FIRE_BURNING_LOOP = "120990485517192"
Sfx.FLAMETHROWER_BURST = "105778965941542"
Sfx.FROST_RAY = "132972245835424"
Sfx.GLASS_BOTTLE_SHATTER = "114576883501259"
Sfx.HARPOON_FIRE = "109368172093538"
Sfx.HARPOON_REEL = "132479081664639"
Sfx.HEAVY_GATE_SLIDE = "120654279942960"
Sfx.HELICOPTER_ROTOR_LOOP = "84171383695662"
Sfx.ICE_FREEZE = "111305399115984"
Sfx.ICE_SHATTER = "79843959446676"
Sfx.KNIFE_HIT = "127431794336583"
Sfx.LAND_HARD = "131366497218246"
Sfx.LAND_SOFT = "135526888359094"
Sfx.LANDMINE_ARM = "127518349798319"
Sfx.LASSO_THROW = "79328237436714"
Sfx.LIGHTSABER_HIT = "109658332722829"
Sfx.LIGHTSABER_SWING = "73098053227959"
Sfx.MELEE_SWING_HEAVY = "121555358052897"
Sfx.MELEE_SWING_LIGHT = "71345544909357"
Sfx.MINIGUN_SHOT = "130974156031887"
Sfx.MINIGUN_SPIN_UP = "131052992492325"
Sfx.POLICE_SIREN_LOOP = "71332322195250"
Sfx.RELOAD_PISTOL = "109484197581848"
Sfx.RELOAD_RIFLE = "115476979902720"
Sfx.REVOLVER_SHOT = "115818250999401"
Sfx.ROCKET_FLIGHT_LOOP = "113264530267992"
Sfx.ROCKET_JUMP_POP = "101413284476089"
Sfx.SHOTGUN_PUMP = "94633012941848"
Sfx.SHOTGUN_SHOT = "117229013127458"
Sfx.SLEDGEHAMMER_SLAM = "130568679725455"
Sfx.SNIPER_SHOT = "104464912204799"
Sfx.SPEAR_STAB = "110593610162886"
-- the syringes (free Creator Store clips, loaded and measured in Studio 2026-11-25): the jab 0.57 s,
-- the heal 1.43 s, the poisoned dummy choking 2.51 s (ProSoundEffects)
Sfx.SYRINGE_JAB = "113781899146705"
Sfx.SYRINGE_HEAL = "132624504008840"
Sfx.POISON_CHOKE = "9113800060"
Sfx.TASER_ZAP = "96777932211472"
Sfx.TIRE_SCREECH = "133635771779455"
Sfx.TNT_FUSE = "120888223565853"
Sfx.TUTORIAL_STEP = "81461008352748"
Sfx.UI_CLICK = "74787779862916"
Sfx.UI_CLOSE = "106829372762895"
Sfx.UI_ERROR = "113016093645980"
Sfx.UI_HOVER = "100146818444058"
Sfx.UI_NOTIFICATION = "105356332104461"
Sfx.UI_OPEN = "77975344600211"
Sfx.UI_PURCHASE = "116716135785943"
Sfx.WALK_LOOP = "111970200059466"
Sfx.WANTED_ALARM = "124634864087599"
Sfx.WANTED_STAR_UP = "126583542411242"
Sfx.WIND_LOOP = "132678556420314"
Sfx.ZOMBIE_ATTACK = "76277944158842"
Sfx.ZOMBIE_DEATH = "107053972938700"
Sfx.ZOMBIE_GROAN_1 = "106133929374938"
Sfx.ZOMBIE_GROAN_2 = "127002472717700"
Sfx.ZOMBIE_HURT = "82752464835555"
--@generated-sfx-end

-- seconds of silence at the head of a clip, by asset id
Sfx.TRIM = {
	[Sfx.PAN_HIT] = 0.3,
	[Sfx.THROW] = 0.11,
	[Sfx.BONE] = 1.34,
	["122753128464765"] = 0.05, -- Jump (init.client)
	["112506453896973"] = 0.09, -- Run, looped (init.client)
	-- generated clips that open on near-silence (measured on assets/sfx/gen: where they get audible)
	[Sfx.UI_CLICK] = 0.275,
	[Sfx.UI_CLOSE] = 0.025,
	[Sfx.CAR_DOOR] = 0.27,
	[Sfx.SHOTGUN_PUMP] = 0.08,
	[Sfx.HARPOON_FIRE] = 0.055,
	[Sfx.RELOAD_RIFLE] = 0.235,
	[Sfx.RELOAD_PISTOL] = 0.14,
}

-- Per weapon: fire (as it is used, before anything is hit), hit (on a body), swing (a melee miss).
-- Each is { id, pitch?, volume? }; weapons without their own clip borrow one at another pitch.
local BULLET = { Sfx.BULLET_HIT_BODY, 1, 0.9 } -- a round landing on a body
Sfx.WEAPON = {
	Bow = { fire = { Sfx.BOW_RELEASE, 1, 0.8 } },
	BoxingGloves = { hit = { Sfx.PUNCH, 0.9, 0.95 }, swing = { Sfx.MELEE_SWING_LIGHT, 1.1, 0.5 } },
	BoxingHeavy = { hit = { Sfx.PUNCH, 0.65, 1 }, swing = { Sfx.MELEE_SWING_HEAVY, 1.1, 0.6 } },
	Handgun = { fire = { Sfx.HANDGUN }, hit = BULLET },
	Revolver = { fire = { Sfx.REVOLVER_SHOT }, hit = BULLET },
	Shotgun = { fire = { Sfx.SHOTGUN_SHOT }, hit = BULLET },
	Rifle = { fire = { Sfx.RIFLE }, hit = BULLET },
	Sniper = { fire = { Sfx.SNIPER_SHOT }, hit = BULLET },
	Rocket = { fire = { Sfx.RPG_SHOT } },
	Grenade = { fire = { Sfx.THROW } },
	Tomato = { fire = { Sfx.THROW, 1.15 } },
	Molotov = { fire = { Sfx.THROW, 0.9 } },
	Knife = { fire = { Sfx.KNIFE }, hit = { Sfx.KNIFE_HIT } },
	KnifeSlash = { hit = { Sfx.KNIFE_HIT, 1.2, 0.7 }, swing = { Sfx.MELEE_SWING_LIGHT, 1, 0.6 } },
	Katana = { hit = { Sfx.KATANA_HIT }, swing = { Sfx.MELEE_SWING_LIGHT, 0.85 } },
	Pan = { hit = { Sfx.PAN_HIT }, swing = { Sfx.MELEE_SWING_HEAVY, 1.1 } },
	Bat = { hit = { Sfx.BAT_HIT }, swing = { Sfx.MELEE_SWING_HEAVY } },
	Baton = { hit = { Sfx.BATON_HIT }, swing = { Sfx.MELEE_SWING_LIGHT, 0.9 } }, -- cops
	Axe = { hit = { Sfx.AXE_HIT }, swing = { Sfx.MELEE_SWING_HEAVY, 0.9 } },
	-- the comic set: their own ElevenLabs clips (assets/sfx/elevenlabs_gen.py), each falling back to a
	-- borrowed one while it is not uploaded / approved yet (its Sfx name is nil until then)
	Crowbar = { hit = { Sfx.CROWBAR_HIT or Sfx.BAT_HIT, Sfx.CROWBAR_HIT and 1 or 1.1 }, swing = { Sfx.MELEE_SWING_LIGHT, 1.1 } },
	Sledgehammer = { hit = { Sfx.SLEDGEHAMMER_SLAM or Sfx.AXE_HIT, Sfx.SLEDGEHAMMER_SLAM and 1 or 0.75 }, swing = { Sfx.MELEE_SWING_HEAVY, 0.8 } },
	Spear = { hit = { Sfx.SPEAR_STAB or Sfx.KNIFE_HIT, Sfx.SPEAR_STAB and 1 or 0.9 }, swing = { Sfx.MELEE_SWING_LIGHT, 0.9 } },
	Lightsaber = { hit = { Sfx.LIGHTSABER_HIT or Sfx.KATANA_HIT, Sfx.LIGHTSABER_HIT and 1 or 1.2 },
		swing = { Sfx.LIGHTSABER_SWING or Sfx.MELEE_SWING_LIGHT, Sfx.LIGHTSABER_SWING and 1 or 1.3 } },
	Chainsaw = { fire = Sfx.CHAINSAW_REV and { Sfx.CHAINSAW_REV, 1, 0.8 } or nil }, -- once every HUSH s
	Lasso = { fire = { Sfx.LASSO_THROW or Sfx.DASH_WHOOSH, Sfx.LASSO_THROW and 1 or 1.2, 0.8 } },
	Taser = { fire = { Sfx.TASER_ZAP or Sfx.HANDGUN, Sfx.TASER_ZAP and 1 or 1.6, 0.8 }, hit = { Sfx.PUNCH, 1.1 } },
	Frostgun = { fire = { Sfx.FROST_RAY or Sfx.REVOLVER_SHOT, Sfx.FROST_RAY and 1 or 1.5 } },
	Boilgun = { fire = { Sfx.BOIL_BLAST or Sfx.SHOTGUN_SHOT, Sfx.BOIL_BLAST and 1 or 1.3 } },
	Flamethrower = { fire = { Sfx.FLAMETHROWER_BURST or Sfx.DASH_WHOOSH, Sfx.FLAMETHROWER_BURST and 1 or 0.6, 0.7 } }, -- once every HUSH s
	Minigun = { fire = { Sfx.MINIGUN_SHOT or Sfx.RIFLE, Sfx.MINIGUN_SHOT and 1 or 1.25, 0.7 }, hit = BULLET },
	Harpoon = { fire = { Sfx.HARPOON_FIRE or Sfx.BOW_RELEASE, Sfx.HARPOON_FIRE and 1 or 0.8 }, hit = { Sfx.KNIFE_HIT, 1 } },
	Grapple = { fire = { Sfx.HARPOON_FIRE or Sfx.BOW_RELEASE, Sfx.HARPOON_FIRE and 1.3 or 1 }, hit = { Sfx.CROWBAR_HIT, 0.8 } },
	Gravgun = { fire = { Sfx.ROCKET_JUMP_POP, 0.7 }, hit = { Sfx.BODY_THUD, 0.9 } },
	BalloonGun = { fire = { Sfx.ROCKET_JUMP_POP, 1.6, 0.8 } },
	Balloon = { fire = { Sfx.ROCKET_JUMP_POP, 2.4, 0.35 } },
	LeafBlower = { fire = { Sfx.DASH_WHOOSH, 0.45, 0.9 } }, -- once every HUSH s
	Shield = { fire = { Sfx.DASH_WHOOSH, 1.3, 0.8 } },
	WebShot = { fire = { Sfx.LASSO_THROW or Sfx.DASH_WHOOSH, 1.5, 0.8 } },
	GroundSlam = { fire = { Sfx.SLEDGEHAMMER_SLAM or Sfx.AXE_HIT, Sfx.SLEDGEHAMMER_SLAM and 0.8 or 0.6 } }, -- on landing
	CosmicPower = { fire = { Sfx.TASER_ZAP or Sfx.HANDGUN, Sfx.TASER_ZAP and 0.75 or 1.6, 0.7 } }, -- once every HUSH s
	FlameOn = { fire = { Sfx.FLAMETHROWER_BURST or Sfx.DASH_WHOOSH, Sfx.FLAMETHROWER_BURST and 1.3 or 0.8, 0.8 } },
	FlameBeam = { fire = { Sfx.FLAMETHROWER_BURST or Sfx.DASH_WHOOSH, Sfx.FLAMETHROWER_BURST and 0.85 or 0.6, 0.6 } }, -- once every HUSH s
	LaserVisor = { fire = { Sfx.TASER_ZAP or Sfx.HANDGUN, Sfx.TASER_ZAP and 2.2 or 2.4, 0.45 } },
	TNT = { fire = { Sfx.THROW, 0.8 } },
	C4 = { fire = { Sfx.THROW, 1.1 } },
	Landmine = { fire = { Sfx.THROW, 0.7 } },
	DeathSyringe = { fire = { Sfx.SYRINGE_JAB } },
	HealSyringe = { fire = { Sfx.SYRINGE_JAB } },
	SleepSyringe = { fire = { Sfx.SYRINGE_JAB } },
	SpeedSyringe = { fire = { Sfx.SYRINGE_JAB } },
	JellySyringe = { fire = { Sfx.SYRINGE_JAB } },
	HeliumSyringe = { fire = { Sfx.SYRINGE_JAB } },
	ShrinkSyringe = { fire = { Sfx.SYRINGE_JAB } },
	GiantSyringe = { fire = { Sfx.SYRINGE_JAB } },
	FireSyringe = { fire = { Sfx.SYRINGE_JAB } },
	ExplosiveSyringe = { fire = { Sfx.SYRINGE_JAB } },
	ZombieSyringe = { fire = { Sfx.SYRINGE_JAB } },
}
-- s between fire sounds of the fast auto weapons (server/Specials.hushed, client useWeapon)
Sfx.HUSH = { Flamethrower = 0.45, Chainsaw = 0.5, LeafBlower = 0.3, CosmicPower = 0.35, FlameBeam = 0.45 }
Sfx.SHATTER = { Sfx.GLASS_BOTTLE_SHATTER, 1, 0.8 } -- a molotov bottle breaking
Sfx.THUD = { Sfx.BODY_THUD, 1, 1 } -- a body hitting the ground or a wall hard (impacts)
-- a bullet's impact on what is not a body, by material (anything else: concrete)
local SURFACE = {
	[Enum.Material.Metal] = Sfx.BULLET_HIT_METAL, [Enum.Material.DiamondPlate] = Sfx.BULLET_HIT_METAL,
	[Enum.Material.CorrodedMetal] = Sfx.BULLET_HIT_METAL, [Enum.Material.Foil] = Sfx.BULLET_HIT_METAL,
	[Enum.Material.Wood] = Sfx.BULLET_HIT_WOOD, [Enum.Material.WoodPlanks] = Sfx.BULLET_HIT_WOOD,
}
function Sfx.surface(part: BasePart): { any }
	return { SURFACE[part.Material] or Sfx.BULLET_HIT_CONCRETE, 1, 0.6 }
end
-- what a dummy's speech bubble sounds like, by its kind ("groan": a zombie)
Sfx.VOICE = {
	talk = Sfx.DUMMY_TALK, shout = Sfx.DUMMY_SHOUT, think = Sfx.DUMMY_THINK,
	groan = { Sfx.ZOMBIE_GROAN_1, Sfx.ZOMBIE_GROAN_2 },
}

-- A looping sound on `parent` (a part, or SoundService for a 2D one), started at once. On the
-- server it plays for everyone (a playing Sound replicates); on a client only there.
function Sfx.loop(parent: Instance, id: string?, volume: number?, range: number?): Sound
	local s = Instance.new("Sound")
	s.SoundId = if id then "rbxassetid://" .. id else "" -- (a clip not uploaded yet: silent)
	s.Looped = true
	s.Volume = volume or 0.6
	s.RollOffMaxDistance = range or 200
	s.Parent = parent
	s:Play()
	return s
end
Sfx.SCRAPE = { Sfx.STONE, 0.45, 0.35 } -- a dragged body grinding along the ground (F)

-- Hits never repeat one sample: each one a client plays (Sfx.playLocal) lands HIT_PITCH higher or lower
-- at random, and a clip with kin here takes turns with them, never the same twice running. Each kin is
-- { id, pitch, volume } times the asked-for ones. Only clips already in this table: none new.
Sfx.HIT_PITCH = 0.1
Sfx.VARY = {
	[Sfx.PUNCH] = { { Sfx.PUNCH, 1, 1 }, { Sfx.PUNCH, 0.9, 1 }, { Sfx.PUNCH, 1.12, 0.95 }, { Sfx.BODY_THUD, 1.3, 0.6 } },
	[Sfx.BAT_HIT] = { { Sfx.BAT_HIT, 1, 1 }, { Sfx.BATON_HIT, 0.85, 1 } },
	[Sfx.BATON_HIT] = { { Sfx.BATON_HIT, 1, 1 }, { Sfx.BAT_HIT, 1.15, 0.9 } },
	[Sfx.KNIFE_HIT] = { { Sfx.KNIFE_HIT, 1, 1 }, { Sfx.SPEAR_STAB, 1.1, 0.8 } },
	[Sfx.BODY_THUD] = { { Sfx.BODY_THUD, 1, 1 }, { Sfx.BODY_FALL, 1, 1 }, { Sfx.LAND_HARD, 0.9, 0.9 } },
	[Sfx.BULLET_HIT_BODY] = { { Sfx.BULLET_HIT_BODY, 1, 1 }, { Sfx.BULLET_HIT_BODY, 0.88, 1 }, { Sfx.ARROW_HIT_BODY, 1.25, 0.7 } },
}
-- what counts as a hit (pitch varied): every weapon's hit, the body thuds, the bullets' surface hits
Sfx.HITS = {
	[Sfx.PUNCH] = true, [Sfx.BODY_THUD] = true, [Sfx.BODY_FALL] = true, [Sfx.LAND_HARD] = true, [Sfx.BONE] = true,
	[Sfx.BULLET_HIT_CONCRETE] = true, [Sfx.BULLET_HIT_METAL] = true, [Sfx.BULLET_HIT_WOOD] = true,
	[Sfx.ARROW_HIT_BODY] = true, [Sfx.ARROW_HIT_WALL] = true,
}
for _, w in Sfx.WEAPON do
	if w.hit then
		Sfx.HITS[w.hit[1]] = true
	end
end

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

-- The dummies' voices (their speech-bubble gibberish, the zombies' groans), all of them round the
-- player together: at most VOICE_ROUND, each VOICE_GAP s after the one before, then VOICE_REST s of
-- quiet before the next round (a quiet spell that long starts a fresh round too). Sound effects
-- (hits, thuds, weapons) are not counted.
local VOICE_ROUND, VOICE_GAP, VOICE_REST = 3, 5, 15
local voiceIds = {}
for _, key in { "DUMMY_TALK", "DUMMY_SHOUT", "DUMMY_THINK", "ZOMBIE_GROAN_1", "ZOMBIE_GROAN_2", "ZOMBIE_HURT", "ZOMBIE_DEATH", "ZOMBIE_ATTACK" } do
	if Sfx[key] then
		voiceIds[Sfx[key]] = true
	end
end
local voiced, lastVoice, restUntil = 0, -math.huge, 0
local function voiceAllowed(): boolean
	local now = os.clock()
	if now < restUntil or now - lastVoice < VOICE_GAP then
		return false
	end
	if voiced >= VOICE_ROUND or now - lastVoice > VOICE_REST then
		voiced = 0 -- the rest is over (or it has been quiet that long): a new round
	end
	voiced += 1
	lastVoice = now
	if voiced >= VOICE_ROUND then
		restUntil = now + VOICE_REST
	end
	return true
end

local hitRng = Random.new()
local turn: { [string]: number } = {} -- the kin (Sfx.VARY) each hit clip played last
function Sfx.playLocal(spec: string | { any }, position: Vector3)
	local id, pitch, volume = spec, 1, nil
	if typeof(spec) == "table" then
		id, pitch, volume = spec[1], spec[2] or 1, spec[3]
	end
	if Sfx.HITS[id] then
		local kin = Sfx.VARY[id]
		if kin then
			local n = #kin
			local i = ((turn[id] or hitRng:NextInteger(0, n - 1)) + hitRng:NextInteger(1, n - 1)) % n
			turn[id] = i
			local k = kin[i + 1]
			id, pitch, volume = k[1], pitch * k[2], (volume or 0.8) * k[3]
		end
		pitch *= hitRng:NextNumber(1 - Sfx.HIT_PITCH, 1 + Sfx.HIT_PITCH)
	end
	local template = templates[id]
	if not template or (voiceIds[id] and not voiceAllowed()) then
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

-- A flat (not 3D) one-shot for the interface, through the Effects volume (client/Music), at a pitch (default 1).
function Sfx.ui(id: string, volume: number?, pitch: number?)
	local template = templates[id]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = pitch or 1
	sound.SoundGroup = game:GetService("SoundService"):FindFirstChild("Effects") :: SoundGroup?
	sound.Parent = game:GetService("SoundService")
	sound:Play()
	Debris:AddItem(sound, 5)
end

ReplicatedStorage:WaitForChild("Sfx").OnClientEvent:Connect(Sfx.playLocal)

return Sfx
