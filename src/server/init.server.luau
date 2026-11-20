local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Attacks = require(ReplicatedStorage.Shared.Attacks)
local Ragdoll = require(ReplicatedStorage.Shared.Ragdoll)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Shop = require(ReplicatedStorage.Shared.Shop)
local BoxingGloves = require(ReplicatedStorage.Shared.BoxingGloves)
local Map = require(script.Map)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local Impact = require(ReplicatedStorage.Shared.Impact)
local Factory = require(script.Factory)
local City = require(script.City)
local Port = require(script.Port)
local Looks = require(script.Looks)
local Anims = require(script.Anims)
local Monsters = require(script.Monsters)
local Arrows = require(script.Arrows)
local Wanted = require(script.Wanted)
local Progress = require(script.Progress)
local ShopServer = require(script.Shop)
local Tutorial = require(script.Tutorial)
local Outfits = require(script.Outfits)
local PoliceCar = require(script.PoliceCar)

local PUNCH_RANGE = 11
local PUNCH_COOLDOWN = 0.2
local GRAB_RANGE = 15
local MAX_THROW_SPEED = 120
-- studs a reported point of impact may lie from our copy of the body: a kicked one flies at up to
-- MAX_PUNT_SPEED and our copy trails the kicker's by a ping or so, plus their look-ahead
local MAX_STRUCK_GAP = 80
local MAX_SLAM_LOST = 140 -- studs/s a held body can lose in one hit, as its holder reports it (the grab drags at 90)
local MAX_DUMMIES = 30
local MAX_HP = 100

local NAMES = { "Noemi", "Jia", "Kofi", "Ruth", "Dot", "Fatima", "Wanda", "Thandi", "Milo", "Otto", "Bruno", "Ines" }
local ZONES = {
	Head = { damage = 14, daze = 20, lines = { "My head!", "Ow, I see stars...", "Not the face!" } },
	Chest = { damage = 10, daze = 14, lines = { "My chest!", "Oof!", "Can't... breathe..." } },
	Stomach = { damage = 8, daze = 12, lines = { "Oof, my stomach!", "Hey, cut it out!" } },
	Arm = { damage = 5, daze = 5, lines = { "Why the arm?", "Ow, my arm!" } },
	Leg = { damage = 5, daze = 6, lines = { "My leg!", "Ow, ow!" } },
}
local IDLE_LINES = { "I could really go for a sandwich.", "Who is winning? I can't tell.", "Back off a bit, will you?", "Nice weather today.",
	"Did I leave the oven on?", "I feel like someone is watching me.", "My knees still hurt from last time.", "Is it Friday yet?" }
local GRAB_LINES = { "Put me down!", "I said put me down!", "Whoa, whoa!" }
local STATE_RANK = { Awake = 0, ["Knocked down"] = 1, Held = 1, ["Out cold"] = 2, Dead = 3 }

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local punchRemote = Instance.new("RemoteEvent")
punchRemote.Name = "Punch"
punchRemote.Parent = remotes
local grabRemote = Instance.new("RemoteEvent")
grabRemote.Name = "Grab"
grabRemote.Parent = remotes
local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = "Action"
actionRemote.Parent = remotes
local attackRemote = Instance.new("RemoteEvent")
attackRemote.Name = "Attack"
attackRemote.Parent = remotes
local weaponRemote = Instance.new("RemoteEvent")
weaponRemote.Name = "Weapon"
weaponRemote.Parent = remotes
local equipRemote = Instance.new("RemoteEvent")
equipRemote.Name = "EquipWeapon"
equipRemote.Parent = remotes
local fxRemote = Instance.new("RemoteEvent")
fxRemote.Name = "Fx"
fxRemote.Parent = remotes
local hazardRemote = Instance.new("RemoteEvent") -- server -> client: fling your own character
hazardRemote.Name = "Hazard"
hazardRemote.Parent = remotes
-- Movement looks (animations, sounds) exist only on the client that plays them: it reports what
-- its body is doing here and the other clients replay it (client/Others.luau).
local moveRemote = Instance.new("RemoteEvent")
moveRemote.Name = "Move"
moveRemote.Parent = remotes
local MOVE_NAMES = {
	loop = { [""] = true, sprint = true, wall1 = true, ["wall-1"] = true, cling = true, slide = true,
		crouch = true, crouchIdle = true, dive = true },
	shot = { roll = true, flip = true, kick = true, jump = true, slam = true, dash = true,
		mantle = true, vault = true, slideEnter = true, slideExit = true, diveEnter = true },
}
local MOVE_RATE = 30 -- reports passed on per player per second; more are dropped
local moveBudget = {} -- [Player] = { start = os.clock(), count = number }
moveRemote.OnServerEvent:Connect(function(player, kind, name)
	local names = typeof(kind) == "string" and MOVE_NAMES[kind]
	if not names or typeof(name) ~= "string" or not names[name] then
		return
	end
	local now = os.clock()
	local budget = moveBudget[player]
	if not budget or now - budget.start > 1 then
		budget = { start = now, count = 0 }
		moveBudget[player] = budget
	end
	budget.count += 1
	if budget.count > MOVE_RATE then
		return
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			moveRemote:FireClient(other, player, kind, name)
		end
	end
end)

local CITY_ENABLED = false -- City Square is in development: not built, not in the menu. Flip to test it.
local PORT_ENABLED = true -- the Port (Port.luau) is new: false hides it again (and leave it out of client/Menu.luau MAPS)
local SPAWNS = { ARENA = CFrame.new(0, 5, 0), FACTORY = Factory.SPAWN, ["CITY SQUARE"] = CITY_ENABLED and City.SPAWN or nil, PORT = PORT_ENABLED and Port.SPAWN or nil }
-- Until PLAY picks a map the character waits here, anchored, away from every map (they lie on X, the port at +640 Z).
local MENU_HOLD = CFrame.new(0, 50, 3000)
remotes.Parent = ReplicatedStorage

local dummyFolder = Instance.new("Folder")
dummyFolder.Name = "Dummies"
dummyFolder.Parent = workspace

local dummies = {} -- [Model] = data
local held = {} -- [Player] = data
local lastUse = {} -- [Player] = { [bucket] = os.clock() } (rateLimited)
local lastSwing = {} -- [Player] = os.clock() of the last punch / melee swing (the dummies dodge it)

local description = Instance.new("HumanoidDescription")
for _, prop in { "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" } do
	description[prop] = Color3.fromRGB(215, 215, 220)
end
-- Rounded mannequin body instead of the blocky default: Roblox's own "ROBLOX Boy" body parts (bundle 109), smooth pill-shaped limbs.
description.Torso = 376532000
description.RightArm = 376531012
description.LeftArm = 376530220
description.LeftLeg = 376531300
description.RightLeg = 376531703

local function pick(list)
	return list[math.random(#list)]
end

-- Kinds of dummy, picked at random by weight: the catalog Shirt / Pants / Hat it wears, the
-- weapon it holds (`gear`, a Weapons id; DummyGear draws it, fight() uses it) and the traits it
-- may be born with (nil: any, rollTrait). Armed ones always hit back, so never a Mourner or Coward.
-- A hooligan is always Berserk: it goes for the Normal ones (nearestDummy), and the cops who see
-- it (alarm) shoot it, and then it goes for the cop that shot it (hit).
local KINDS = {
	Normal = { weight = 80, shirt = 14542273245, pants = 8020998573, -- green T-shirt, jeans
		brave = 0.3 }, -- share that stand up to a hooligan whatever their trait (weakly: WEAK)
	-- law: hunts a wanted player (Wanted); a cop carries the baton until 3 stars, then its handgun
	Cop = { weight = 15, shirt = 8166622899, pants = 4944607821, hat = "15752686682", gear = "Baton", traits = { "Tough" }, law = true },
	Hooligan = { weight = 5, shirt = 9672050492, pants = 4944607821, hat = "8268195375", gear = "Bat", -- black shirt, ski mask
		traits = { "Berserk" } },
	-- weight 0: only ever sent by Wanted (4 and 5 stars). `outfit`: the uniform Outfits welds on,
	-- `colors`: body colours under it (torso and arms, legs), `armor`: what a blow is worth on them.
	Soldier = { weight = 0, gear = "Rifle", traits = { "Tough" }, law = true, outfit = "Soldier", armor = 0.6,
		colors = { Color3.fromRGB(96, 108, 70), Color3.fromRGB(120, 110, 80) } },
	Heavy = { weight = 0, gear = "Rocket", traits = { "Tough" }, law = true, outfit = "Heavy", armor = 0.3,
		colors = { Color3.fromRGB(34, 36, 42), Color3.fromRGB(34, 36, 42) } },
	-- Toolbox only (weight 0). `colors` 3 and 4: arms and head, when not the torso's / the skin.
	Worker = { weight = 0, outfit = "Worker", -- hard hat, hi-vis vest, tool belt, boots
		colors = { Color3.fromRGB(59, 92, 140), Color3.fromRGB(44, 62, 92) } },
	Zombie = { weight = 0, outfit = "Zombie", traits = { "Berserk" }, zombie = true, -- see ZOMBIE
		colors = { Color3.fromRGB(184, 178, 160), Color3.fromRGB(74, 84, 104), Color3.fromRGB(127, 160, 90), Color3.fromRGB(127, 160, 90) } },
}
for _, kind in KINDS do
	local look = description:Clone()
	look.Shirt, look.Pants, look.HatAccessory = kind.shirt or 0, kind.pants or 0, kind.hat or ""
	if kind.colors then
		local arms = kind.colors[3] or kind.colors[1]
		look.TorsoColor, look.LeftArmColor, look.RightArmColor = kind.colors[1], arms, arms
		look.LeftLegColor, look.RightLegColor = kind.colors[2], kind.colors[2]
		look.HeadColor = kind.colors[4] or look.HeadColor
	end
	kind.description = look
end

-- Zombies (KINDS.Zombie, d.zombie). They feel no pain: no daze, no flinch, no fear, no running, no
-- words, and their HP never drops. They shamble at the nearest living thing (a player or a dummy
-- that is not one of them) with both arms straight out in front (updatePose) and bring them down on
-- it (ZOMBIE.swing). A broken arm hangs for good and does not hit; a broken leg (or one gone) puts
-- them down for good, and they drag themselves at it instead. Only the head kills them: a bullet
-- through it or a blade taking it off (hit). The functions come further down (Brain: fighting).
local ZOMBIE: any = {
	speed = 4, -- walk speed (a dummy's is 8)
	crawl_push = 30, -- each heave on the ground (a dummy's 11 drags it at a fifth of a stud a second)
	lines = { "Braaains...", "Uuurgh...", "Hhhrrr...", "Mmmnnngh...", "Grraaah..." },
	-- one blow; `at`: when it lands after the arms go up, `reach`: studs to the prey then
	claw = { damage = 9, push = 26, up = 6, power = 1.2, at = 0.45, reach = 5, recover = 1.4 },
	-- where each hand reaches (upper torso space; `sx` -1 left, 1 right): beyond arm's length, so the arm is straight
	rest = function(sx) return Vector3.new(sx * 0.7, 0.6, -4) end,
	raised = function(sx) return Vector3.new(sx * 0.5, 3.2, -1.6) end,
	slam = function(sx) return Vector3.new(sx * 0.4, -0.6, -2.6) end,
}
local function rollKind(): string
	local roll = math.random() * 100
	for name, kind in KINDS do
		roll -= kind.weight
		if roll <= 0 then
			return name
		end
	end
	return "Normal"
end

local function setOwner(model: Model, player: Player?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:CanSetNetworkOwnership() then
			part:SetNetworkOwner(player)
		end
	end
end

local function dummyOf(inst: Instance?)
	while inst and inst.Parent ~= dummyFolder do
		inst = inst.Parent
	end
	return inst and dummies[inst]
end

-- The bubble itself is drawn by the client (Speech): "talk", "shout" (a "!" in it), "think" ("...").
local function say(d, text: string, kind: string?)
	if d.zombie then -- no words left in it: a groan, now and then
		if math.random() < 0.5 then
			return
		end
		text, kind = pick(ZOMBIE.lines), "talk"
	end
	local m = d.model
	m:SetAttribute("Say", text)
	m:SetAttribute("SayKind", kind or (text:find("!") and "shout") or (text:find("%.%.%.") and "think") or "talk")
	m:SetAttribute("SayId", (m:GetAttribute("SayId") or 0) + 1)
end

local function setState(d, state: string)
	d.state = state
	d.model:SetAttribute("State", state)
end

-- Injuries --------------------------------------------------------------------
-- Every body part keeps its own damage. Hard blunt hits leave a bruise where they land and then break
-- the bone under it, bullets and blades open wounds that bleed, the axe takes limbs off. Blood
-- runs out through the wounds: under BLOOD_DROWSY the dummy slows down, under BLOOD_OUT it
-- passes out, under BLOOD_DEAD it has bled out. The client draws all of it (client/Fx.luau: blood,
-- puddles, the X-ray of the bone that was hit) from the "Wound" event, the "Bleeder" tag and the
-- attributes set in syncAttributes.
local BLOOD_DROWSY, BLOOD_OUT, BLOOD_DEAD = 60, 48, 40
local MAX_BLEED = 2 -- % of blood per second, however many holes there are: one that has lost a limb lives a while (hops, crawls, gets tended)
-- Bruises laid on the skin by markAt, each one blotch in a padded 1024 tile (assets/fx/make_bruise.py).
-- No blood in uploaded images: Roblox moderation strikes the account for it.
local BRUISE_IMAGES = { "rbxassetid://94993582040943", "rbxassetid://109249822084070", "rbxassetid://103002851312300" }
local BRUISE_PAD = 6.4 -- a tile is this many times wider than its blotch (PAD in make_bruise.py)
local BRUISE_RECT = Vector2.new(432, 160) -- where the blotch sits in the 1024 tile: offset, size (px)
local RASH = Color3.fromRGB(206, 146, 146) -- skin scraped raw along the ground
local BRUISE_AT = 1.5 -- blunt power that leaves a mark: a jab or a light punch does not, a haymaker, kick or bat does
local MAX_MARKS = 6 -- bruises per part
local STUMP = Color3.fromRGB(65, 12, 18)
local WOUND = Color3.fromRGB(104, 14, 22)
local TORN = Color3.fromRGB(178, 24, 35) -- an exit wound: raw, the colour of the blood
local CHAR = Color3.fromRGB(58, 50, 52) -- burnt skin
local exitParams = RaycastParams.new()
exitParams.FilterType = Enum.RaycastFilterType.Include

-- [part name] = zone (ZONES), area (what a bruise is called), label (the part itself),
-- breakAt (blunt damage that turns the bruise full colour; the bone takes BONE_TOUGH times that),
-- broken (what the break is called)
local BONE_TOUGH = 2 -- bones broke so often the X-ray was on every other hit
local BONE_TOUGH_WEAPON = 0.8 -- a bat or a pan is what breaks them: one bat swing takes an arm or a leg
local SHOT_BREAK = 6 -- trauma a part takes from light bullets before its bone goes (was 3)
local PARTS = {
	Head = { zone = "Head", area = "head", label = "head", breakAt = 5, broken = "cracked skull" },
	UpperTorso = { zone = "Chest", area = "chest", label = "ribs", breakAt = 3, broken = "broken ribs" },
	LowerTorso = { zone = "Stomach", area = "stomach", label = "stomach", breakAt = 4, broken = "broken pelvis" },
}
for _, side in { "Left", "Right" } do
	local s = side:lower()
	for name, label in { UpperArm = "upper arm", LowerArm = "forearm", Hand = "hand" } do
		PARTS[side .. name] = { zone = "Arm", limb = "arm", side = s, area = s .. " arm", label = `{s} {label}`, breakAt = 3, broken = `broken {s} arm` }
	end
	for name, label in { UpperLeg = "thigh", LowerLeg = "shin", Foot = "foot" } do
		PARTS[side .. name] = { zone = "Leg", limb = "leg", side = s, area = s .. " leg", label = `{s} {label}`, breakAt = 3, broken = `broken {s} leg` }
	end
end

local gibFolder = Instance.new("Folder") -- cut-off limbs
gibFolder.Name = "Gibs"
gibFolder.Parent = workspace

local function addInjury(d, text: string)
	if not table.find(d.injuries, text) then
		table.insert(d.injuries, text)
	end
end

-- How bad the legs are to stand on: 1 per broken leg, 0.4 per leg that is only hurt.
local function legHurt(d): number
	local total = 0
	for _, side in { "Left", "Right" } do
		local worst = 0
		for _, name in { "UpperLeg", "LowerLeg", "Foot" } do
			local p = d.parts[side .. name]
			if p then
				worst = math.max(worst, p.broken and 1 or 0.4)
			end
		end
		total += worst
	end
	return total
end

-- Body: what is left of a dummy's limbs and how it gets about on it (one table: the script is at
-- Luau's 200-locals limit; its functions that need the rest of the script come further down).
-- Limbs wear away under fire: every bullet or blade that lands on one adds to its `wear`
-- (WEAR by kind, times the blow's power), and past its TOUGH the piece comes off (hit), with
-- everything below it. The axe and the katana (CHOP) take a limb off at once. Blunt blows and
-- arrows never take one off: they break bones and bleed.
local Body: any = {
	TOUGH = { Hand = 3, Foot = 3, LowerArm = 5, LowerLeg = 6, UpperArm = 7, UpperLeg = 8 },
	WEAR = { bullet = 1, blade = 1.2 },
	CHOP = { Axe = true, Katana = true },
	ARROW = 0.5, -- an arrow wears a limb this much of a blade
	CRAWL_SPEED = 1.6,
	HOP_SPEED = 4.5,
	HOP_FALL = 0.12, -- chance a second of going over while it hops along
}
-- A limb ("Left" / "Right", "Arm" / "Leg") is gone once its upper or lower part is.
function Body.gone(d, side: string, limb: string): boolean
	return d.lost[side .. "Upper" .. limb] == true or d.lost[side .. "Lower" .. limb] == true
end
-- Arms it can still pull itself along or hit with: there, and not broken.
function Body.arms(d): number
	local n = 0
	for _, side in { "Left", "Right" } do
		if not Body.gone(d, side, "Arm") then
			local broken = false
			for _, name in { "UpperArm", "LowerArm" } do
				local p = d.parts[side .. name]
				broken = broken or (p ~= nil and p.broken)
			end
			n += if broken then 0 else 1
		end
	end
	return n
end
-- How it gets about now: "walk"; "limp" (a leg broken or a foot gone); "hop" (one leg gone, the
-- other sound); "crawl" (nothing to stand on, an arm to pull with); "down" (nothing to move with).
function Body.mobility(d): string
	local legs, bad = 0, 0 -- legs still there; of those, broken or footless
	for _, side in { "Left", "Right" } do
		if not Body.gone(d, side, "Leg") then
			legs += 1
			local hurt = d.lost[side .. "Foot"] == true
			for _, name in { "UpperLeg", "LowerLeg", "Foot" } do
				local p = d.parts[side .. name]
				hurt = hurt or (p ~= nil and p.broken)
			end
			bad += if hurt then 1 else 0
		end
	end
	if legs == 2 then
		return if bad == 0 then "walk" elseif bad == 1 then "limp" elseif Body.arms(d) > 0 then "crawl" else "down"
	elseif legs == 1 and bad == 0 then
		return "hop"
	end
	return if Body.arms(d) > 0 then "crawl" else "down"
end

-- No leg to stand on: it stays down (and crawls, if it has an arm; Heartbeat). A zombie: one leg
-- broken or gone is enough, and it drags itself (ZOMBIE.crawl).
local function grounded(d): boolean
	if d.zombie then
		return d.legless or legHurt(d) >= 1
	end
	local how = Body.mobility(d)
	return how == "crawl" or how == "down"
end

-- What the HUD calls the dummy's condition; the rules run on d.state.
local function statusOf(d): string
	if d.state == "Dead" then
		return d.cause or "Dead"
	elseif d.state == "Out cold" or d.state == "Held" then
		return d.state
	elseif d.state == "Knocked down" then
		if grounded(d) then
			return "Crawling"
		elseif d.blood < BLOOD_DROWSY then
			return "Drowsy"
		elseif d.wakeAt - os.clock() < 0.8 then
			return "Getting up"
		end
		return d.daze >= 30 and "Writhing" or "On the ground"
	elseif d.crawling then
		return "Crawling"
	elseif not d.zombie and Body.mobility(d) == "hop" then
		return "Hopping"
	elseif d.blood < BLOOD_DROWSY then
		return "Drowsy"
	end
	return #d.injuries > 0 and "Injured, upright" or "Awake"
end

local function syncAttributes(d)
	local model = d.model
	model:SetAttribute("HP", math.max(0, math.floor(d.hp)))
	model:SetAttribute("Blood", math.ceil(d.blood))
	model:SetAttribute("Pain", d.state == "Dead" and 0 or math.min(100, math.floor(d.daze * 1.4)))
	model:SetAttribute("Status", statusOf(d))
	-- the newest few, like a chart note: "Right arm artery, right upper arm bone, broken right arm"
	local text = table.concat(d.injuries, ", ", math.max(1, #d.injuries - 3))
	model:SetAttribute("Injuries", text:sub(1, 1):upper() .. text:sub(2))
	-- per part for the body diagram: 1 hurt, 2 broken, 3 gone
	local body = {}
	for name, p in d.parts do
		if not d.lost[name] then
			table.insert(body, `{name}:{p.broken and 2 or 1}`)
		end
	end
	for name in d.lost do
		table.insert(body, name .. ":3")
	end
	model:SetAttribute("Body", table.concat(body, ";"))
end

local function bleed(d, from: BasePart, rate: number)
	d.bleed = math.min(d.bleed + rate, MAX_BLEED)
	CollectionService:AddTag(from, "Bleeder")
end

local function stopBleeding(d)
	d.bleed = 0
	for _, part in d.model:GetDescendants() do
		CollectionService:RemoveTag(part, "Bleeder")
	end
end

-- The dark cap that closes a cut, on either side of it.
local function stump(on: BasePart, position: Vector3, facing: Vector3, size: number?): Part
	local width = size or math.min(on.Size.X, on.Size.Z) * 0.95
	local cap = Instance.new("Part")
	cap.Name = "Stump"
	cap.Shape = Enum.PartType.Cylinder
	cap.Size = Vector3.new(0.12, width, width)
	cap.Color = STUMP
	cap.Material = Enum.Material.SmoothPlastic
	cap.CanCollide, cap.CanQuery, cap.CanTouch, cap.Massless = false, false, false, true
	cap.CFrame = CFrame.lookAt(position, position + facing) * CFrame.Angles(0, math.pi / 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = on
	weld.Part1 = cap
	weld.Parent = cap
	cap.Parent = on
	return cap
end

-- Where `point` (about on `part`, the blow travelling along `dir`) really is on the skin, and which
-- way the skin faces there. The body's MeshParts collide as boxes (CollisionFidelity Box), so a ray
-- onto the part itself stops at its box, off the rounded skin, and a mark put there hangs in the air
-- by the shoulders and hips. So the ray goes onto a probe instead: an invisible copy of the part's
-- mesh that collides as its hull (made once per mesh, far out of the map, sized to the part), and
-- the hit comes back to the part. Until a probe is ready (or for a plain part, the head), the part's
-- box does. Rays: from just outside along `dir`, else straight in toward the middle.
local skinAt: (BasePart, Vector3, Vector3) -> (Vector3?, Vector3?)
do
	local PROBE_AT = CFrame.new(0, 5000, 0)
	local probes = {} -- [MeshId] = MeshPart, false while it is being made (or could not be)
	local probeParams = RaycastParams.new()
	probeParams.FilterType = Enum.RaycastFilterType.Include
	local folder: Folder? = nil
	local function probeFor(part: BasePart): MeshPart?
		if not part:IsA("MeshPart") or part.MeshId == "" then
			return nil
		end
		local id = part.MeshId
		if probes[id] == nil then
			probes[id] = false
			task.spawn(function()
				local ok, made = pcall(function()
					return game:GetService("AssetService"):CreateMeshPartAsync(id, { CollisionFidelity = Enum.CollisionFidelity.Hull })
				end)
				if not ok or not made then
					warn("skin probe for", id, made)
					return
				end
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = "SkinProbes"
					folder.Parent = workspace
				end
				made.Name, made.Transparency, made.Anchored = "Probe", 1, true
				made.CanCollide, made.CanTouch, made.CanQuery, made.CastShadow = false, false, true, false
				made.CFrame, made.Parent = PROBE_AT, folder
				probes[id] = made
			end)
		end
		return probes[id] or nil
	end
	skinAt = function(part: BasePart, point: Vector3, dir: Vector3): (Vector3?, Vector3?)
		if dir.Magnitude < 0.05 then
			dir = part.Position - point
			dir = if dir.Magnitude > 0.05 then dir else -Vector3.yAxis
		end
		dir = dir.Unit
		local probe = probeFor(part)
		local params, toProbe = exitParams, CFrame.identity -- the part itself, else its probe
		if probe then
			probe.Size = part.Size
			params, toProbe = probeParams, PROBE_AT * part.CFrame:Inverse()
			probeParams.FilterDescendantsInstances = { probe }
		else
			exitParams.FilterDescendantsInstances = { part }
		end
		local function cast(from: Vector3, along: Vector3)
			return workspace:Raycast(toProbe * from, toProbe:VectorToWorldSpace(along), params)
		end
		local hit = cast(point - dir * 3, dir * 6)
		if not hit then
			local out = point - part.Position
			out = if out.Magnitude > 0.05 then out.Unit else -dir
			hit = cast(part.Position + out * 6, -out * 6)
		end
		if not hit then
			return nil, nil
		end
		local back = toProbe:Inverse()
		return back * hit.Position, back:VectorToWorldSpace(hit.Normal)
	end
end

-- A wound lying flat on the skin where it was hit: a thin disc `size` across (a hole), or with
-- `length` a strip at a random slant (a cut), turned to the skin (not to the shot) and sunk to half
-- its thickness, so it sits on the body like paint instead of standing off it. nil: no skin found.
local MARK_THICK = 0.04
local function woundAt(part: BasePart, point: Vector3, dir: Vector3, size: number, color: Color3, length: number?): Part?
	local at, normal = skinAt(part, point, dir)
	if not at or not normal then
		return nil
	end
	local mark = Instance.new("Part")
	mark.Name, mark.Color, mark.Material = "Wound", color, Enum.Material.SmoothPlastic
	mark.CanCollide, mark.CanQuery, mark.CanTouch, mark.Massless, mark.CastShadow = false, false, false, true, false
	-- a cut is narrow, so a long one on a thin limb would overhang: never longer than the part is
	length = length and math.min(length, part.Size.Y * 0.8, math.max(part.Size.X, part.Size.Z) * 0.9)
	-- kept off the part's edges, so it does not hang past a corner: across the face it lies on, the
	-- middle stays half a mark in from each side
	local here, facing = part.CFrame:PointToObjectSpace(at), part.CFrame:VectorToObjectSpace(normal)
	local reach, half = (length or size) / 2, part.Size / 2
	local function keep(c: number, h: number, n: number): number
		return if math.abs(n) > 0.7 then c else math.clamp(c, -math.max(h - reach, 0), math.max(h - reach, 0))
	end
	local kept = part.CFrame:PointToWorldSpace(Vector3.new(keep(here.X, half.X, facing.X), keep(here.Y, half.Y, facing.Y), keep(here.Z, half.Z, facing.Z)))
	if (kept - at).Magnitude > 0.01 then -- moved in: back onto the skin there
		local again, againNormal = skinAt(part, kept, -normal)
		if again and againNormal then
			at, normal = again, againNormal
		end
	end
	-- X (the cylinder's axis, the block's thin side) along the skin's normal. A cut runs along the
	-- part, give or take a slant: round a rounded limb a straight strip would stand off at its ends,
	-- along it the skin is straight. A hole is round, any spin will do.
	local along = part.CFrame.UpVector - normal * part.CFrame.UpVector:Dot(normal)
	along = if along.Magnitude > 0.1 then along.Unit else normal:Cross(part.CFrame.RightVector).Unit
	along = CFrame.fromAxisAngle(normal, (math.random() - 0.5) * 0.9):VectorToWorldSpace(along)
	local function lay(piece: Part, center: Vector3, up: Vector3)
		piece.CFrame = CFrame.fromMatrix(center, up, (along - up * along:Dot(up)).Unit)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = part, piece, piece
		piece.Parent = part
	end
	if not length then
		mark.Shape = Enum.PartType.Cylinder
		mark.Size = Vector3.new(MARK_THICK, size, size)
		lay(mark, at, normal)
		return mark
	end
	-- a cut: short pieces end to end, each laid onto the skin where it lies, so the whole bends
	-- with the body (one long straight strip only touches a rounded chest in the middle)
	local pieces = math.max(1, math.ceil(length / 0.22))
	local step = length / pieces
	mark.Shape = Enum.PartType.Block
	local template = mark:Clone() -- before the first piece is welded on
	for i = 1, pieces do
		local piece = if i == 1 then mark else template:Clone()
		piece.Size = Vector3.new(MARK_THICK, step * 1.12, size) -- a hair long: no gaps where it bends
		local center = at + along * ((i - 0.5) * step - length / 2)
		local on, up = skinAt(part, center + normal * 0.3, -normal)
		if on and up and up:Dot(normal) > 0.6 then
			lay(piece, on, up)
		elseif i == 1 then
			lay(piece, at, normal) -- the first piece always shows (it is the one returned, it bleeds)
		end -- else: round the end of the part (a knee, an ankle): the cut stops short there
	end
	return mark
end

-- A mark (a bruise, one of `images`) laid straight onto the skin of `part` as a Texture: on the face of
-- the part that looks toward `toward` (the point the blow landed), or the side the blow came from
-- (`dir` is the way it travels), centred on the hit, `size` studs across. A Texture on a MeshPart
-- is projected onto the mesh itself, so it follows the body's curves. Each image is one blotch in a
-- big transparent tile (assets/fx/make_bruise.py), tiled so large that only that one copy shows.
-- A face's texture is centred on the face's middle, seen from outside: U to the right, V down, where
-- "up" is +Y on the sides and +Z on the top and bottom; the offset slides the image toward -U / -V
-- (measured in Studio on a block and on an R15 torso).
local function markAt(p, part: BasePart, toward: Vector3, dir: Vector3, size: number, images: { string })
	if (p.marks or 0) >= MAX_MARKS or dir.Magnitude < 0.05 then
		return
	end
	-- where the blow really met the skin: along its own path onto the part (no contact point, as with
	-- fists: the side it came from)
	if (toward - part.Position).Magnitude < 0.05 then
		toward = part.Position - dir.Unit * 2
	end
	local surfaceAt, surfaceNormal = skinAt(part, toward, dir.Unit)
	if not surfaceAt or not surfaceNormal then
		return
	end
	-- the face: the local axis the surface normal points along most
	local n = part.CFrame:VectorToObjectSpace(surfaceNormal)
	local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
	local normal, face
	if ax >= ay and ax >= az then
		normal, face = Vector3.new(math.sign(n.X), 0, 0), n.X > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	elseif ay >= az then
		normal, face = Vector3.new(0, math.sign(n.Y), 0), n.Y > 0 and Enum.NormalId.Top or Enum.NormalId.Bottom
	else
		normal, face = Vector3.new(0, 0, math.sign(n.Z)), n.Z > 0 and Enum.NormalId.Back or Enum.NormalId.Front
	end
	local head = part.Name == "Head"
	if head and face == Enum.NormalId.Bottom then
		return -- under the chin, against the neck: nothing shows
	end
	p.marks = (p.marks or 0) + 1
	local up = normal.Y ~= 0 and Vector3.zAxis or Vector3.yAxis
	local right = (-normal):Cross(up)
	local half = part.Size / 2
	local width, height = math.abs(right:Dot(half)) * 2, math.abs(up:Dot(half)) * 2
	local at = part.CFrame:PointToObjectSpace(surfaceAt)
	-- never so small the next copy of the tile reaches the face, never wider than the face itself
	size = math.clamp(size, math.max(width, height) / (BRUISE_PAD * 0.8 - 0.7), math.max(math.min(width, height) * 0.7, math.max(width, height) / (BRUISE_PAD * 0.8 - 0.7)))
	-- kept well off the face's edges: the body is rounded, its skin turns away from the face well
	-- before the box ends, and there the projected image smears round the side of the mesh
	local inset = size * 0.5 + math.min(width, height) * 0.15
	local u = math.clamp(at:Dot(right), -math.max(width / 2 - inset, 0), math.max(width / 2 - inset, 0))
	local v = math.clamp(at:Dot(up), -math.max(height / 2 - inset, 0), math.max(height / 2 - inset, 0))
	at = right * u + up * v + normal * at:Dot(normal)
	local stretchU, stretchV = 0.8 + math.random() * 0.4, 0.8 + math.random() * 0.4 -- a little longer one way
	local image = images[math.random(#images)]
	if head then
		-- the dynamic head's mesh draws no Texture, so the bruise goes on a SurfaceGui like the face
		-- (Looks.buildFace), cropped to the blotch. A SurfaceGui's canvas runs from its top-left seen
		-- from outside, +Y up on the sides; on the top its x runs along -Z and its y along +X.
		local across, down = right, -up
		if face == Enum.NormalId.Top then
			across, down = -Vector3.zAxis, Vector3.xAxis
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Bruise"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 100
		gui.LightInfluence = 1
		gui.ZOffset = -1 -- under the drawn face
		local w, h = math.abs(across:Dot(half)) * 2, math.abs(down:Dot(half)) * 2
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Image = image
		label.ImageRectOffset = Vector2.one * BRUISE_RECT.X
		label.ImageRectSize = Vector2.one * BRUISE_RECT.Y
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(at:Dot(across) / w + 0.5, at:Dot(down) / h + 0.5)
		label.Size = UDim2.fromScale(size * stretchU / w, size * stretchV / h)
		label.Rotation = math.random(0, 359)
		label.Parent = gui
		gui.Parent = part
		return
	end
	local tileU, tileV = size * BRUISE_PAD * stretchU, size * BRUISE_PAD * stretchV
	local mark = Instance.new("Texture")
	mark.Name = "Bruise"
	mark.Texture = image
	mark.Face = face
	mark.StudsPerTileU, mark.StudsPerTileV = tileU, tileV
	mark.OffsetStudsU, mark.OffsetStudsV = tileU / 2 - at:Dot(right), tileV / 2 + at:Dot(up)
	mark.Parent = part
end

-- A part's skin colour from what it has been through: scraping rubs it raw, fire chars it.
local function paint(d, part: BasePart)
	local info, p = PARTS[part.Name], d.parts[part.Name]
	if not info then
		return
	end
	-- from the part's own colour as it was born (a zombie's green, a soldier's olive), not plain skin
	local base = part:GetAttribute("BaseColor") or part.Color
	part:SetAttribute("BaseColor", base)
	local skin = base
	if p and p.rash then
		skin = skin:Lerp(RASH, math.min(p.rash / info.breakAt, 1))
	end
	if d.burn > 0 then
		skin = skin:Lerp(CHAR, math.min(d.burn / 8, 0.85))
	end
	part.Color = skin
	part:SetAttribute("Skin", skin ~= base and skin or nil) -- the client puts this back after an X-ray
end

local function jointParts(j: Instance): (Instance?, Instance?)
	if j:IsA("Motor6D") or j:IsA("NoCollisionConstraint") or j:IsA("WeldConstraint") then
		return (j :: any).Part0, (j :: any).Part1
	end
	local a0, a1 = (j :: any).Attachment0, (j :: any).Attachment1
	return a0 and a0.Parent, a1 and a1.Parent
end

-- Cut `part` off the body, with everything that hangs from it (an upper arm takes the forearm
-- and the hand along). The piece becomes one stiff loose model in workspace.Gibs.
local function sever(d, part: BasePart, dir: Vector3): Model
	local model = d.model
	local kids, joints = {}, {}
	for _, j in model:GetDescendants() do
		if j:IsA("Motor6D") or j:IsA("AnimationConstraint") then
			local p0, p1 = jointParts(j)
			if p0 and p1 then
				kids[p0] = kids[p0] or {}
				table.insert(kids[p0], p1)
			end
		end
		if j:IsA("JointInstance") or j:IsA("Constraint") or j:IsA("NoCollisionConstraint") or j:IsA("WeldConstraint") then
			table.insert(joints, j)
		end
	end
	local set, list = {}, {}
	local function take(p)
		if set[p] then
			return
		end
		set[p] = true
		table.insert(list, p)
		for _, kid in kids[p] or {} do
			take(kid)
		end
	end
	take(part)
	local function inside(p: Instance): boolean -- the piece's parts and what is stuck on them (stumps)
		return set[p] or set[p.Parent] or false
	end

	local cut: Vector3?, parent: BasePart? = nil, nil
	for _, j in joints do
		local p0, p1 = jointParts(j)
		if not (p0 and p1) then
			continue
		end
		local in0, in1 = inside(p0), inside(p1)
		if in0 ~= in1 then
			if j:IsA("Motor6D") then
				cut, parent = (j.Part0.CFrame * j.C0).Position, in0 and p1 or p0
			elseif not cut and j:IsA("Constraint") and j.Attachment0 then
				cut, parent = j.Attachment0.WorldPosition, in0 and p1 or p0
			end
			j:Destroy()
		elseif in0 and not j:IsA("WeldConstraint") and not j:IsA("NoCollisionConstraint") then
			j:Destroy() -- joints inside the piece: welded stiff below
		end
	end

	local gib = Instance.new("Model")
	gib.Name = "Gib"
	for i, p in list do
		d.lost[p.Name] = true
		CollectionService:RemoveTag(p, "Bleeder")
		p:SetAttribute("RagCollide", nil)
		p.CanCollide = true
		p.Parent = gib
		if i > 1 then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = part
			weld.Part1 = p
			weld.Parent = p
		end
	end
	gib.Parent = gibFolder
	if not part.Anchored then -- anchored while time is stopped (Sandbox.freeze): no owner to set
		part:SetNetworkOwner(nil)
	end
	Debris:AddItem(gib, 60)

	cut = cut or part.Position
	local out = part.Position - cut
	out = out.Magnitude > 0.05 and out.Unit or dir
	stump(part, cut, -out)
	if parent and parent:IsA("BasePart") then
		bleed(d, stump(parent, cut, out), 1.6) -- slow enough to crawl or hop off on it for a while (or be tended, Body.help)
		-- where the hands go once it is back up (see Poses): just off the stump
		d.wound = { part = parent, at = parent.CFrame:PointToObjectSpace(cut + out * 0.3), untilTime = os.clock() + 14 }
		d.lastWound = d.wound
	end
	part:ApplyImpulse((dir + Vector3.yAxis * 0.6) * part.AssemblyMass * 22)
	part:ApplyAngularImpulse(Random.new():NextUnitVector() * part.AssemblyMass * 6)
	d.legless = d.legless or PARTS[part.Name].limb == "leg"
	return gib
end

local function dropPose(d) -- see Poses
	for _, ik in d.poses do
		ik:Destroy()
	end
	table.clear(d.poses)
	d.poseKey = ""
	d.pressing = false
end

local function knockDown(d, seconds: number, state: string)
	dropPose(d) -- a limp body holds no pose
	d.crawling = false -- flat out: it crawls again once it comes round (Heartbeat)
	d.risingUntil, d.digUntil = 0, 0
	for _, t in d.tracks do
		t:Stop(0)
	end
	if d.postureKey ~= "" then -- nor a lean: the spine goes back to straight under the ragdoll
		d.postureKey = ""
		Looks.posture(d.model, {})
	end
	Ragdoll.set(d.model, true)
	setOwner(d.model, d.heldBy or d.looseOwner)
	d.wakeAt = math.max(d.wakeAt, os.clock() + seconds + legHurt(d) * 2) -- bad legs: slower up
	if STATE_RANK[state] >= STATE_RANK[d.state] then
		setState(d, state)
	end
end

-- `owner`: the player who let go keeps simulating the body (and throws it themself) until it comes
-- to rest (or LOOSE_MAX), then the Heartbeat loop gives it to the server. Taking it at once snapped it back to the
-- server's copy, a ping old, and froze it for a moment: the lag spike on every drop.
local LOOSE_MAX = 4 -- s the releaser keeps it at most

-- A body held with F does not collide with players: pressed against your legs it used to lift you
-- onto it and walk you up into the air. It goes back to colliding UNHELD_AFTER after it is let go,
-- once it is clear of you.
local PhysicsService = game:GetService("PhysicsService")
PhysicsService:RegisterCollisionGroup("Players")
PhysicsService:RegisterCollisionGroup("Held")
PhysicsService:CollisionGroupSetCollidable("Held", "Players", false)
local UNHELD_AFTER = 0.6
local function setGroup(model: Instance, group: string)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

local function release(d, velocity: Vector3, owner: Player?)
	local by = owner or d.heldBy -- thrown, dropped or carried into a machine: theirs (Wanted)
	if by then
		d.blame, d.blameAt, d.blameWeapon = by, os.clock(), "Body"
	end
	if d.dragging then
		task.delay(UNHELD_AFTER, function()
			if not d.dragging and d.model.Parent then
				setGroup(d.model, "Default")
			end
		end)
	end
	if d.grab then
		d.grab:Destroy()
		d.grab = nil
	end
	if d.heldBy then
		held[d.heldBy] = nil
		d.heldBy = nil
	end
	d.dragging, d.raking, d.furrowAt = nil, nil, nil
	d.looseOwner, d.looseSince = owner, os.clock()
	if not owner then
		setOwner(d.model, nil)
		if velocity.Magnitude > 0 then
			for _, part in d.model:GetDescendants() do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = velocity
				end
			end
		end
	end
	if d.state == "Held" then
		setState(d, "Knocked down")
	end
	d.impactState = Impact.new() -- the server takes the hits again, from fresh speeds
	d.wakeAt = math.max(d.wakeAt, os.clock() + 2.5)
end

local spawnDummy
local knockPlayer -- below (Brain); a soldier's rocket (rocket) also throws players
local tryDodge -- Brain: fighting (the punch and weapon handlers above it ask it)
local landImpact -- impacts, below (grab "slam" asks it)

local function revive(d)
	if d.heldBy or d.looseOwner then -- the server moves it: it has to own it
		release(d, Vector3.zero)
	end
	if next(d.lost) then -- limbs do not grow back: a whole new body, same name, same spot
		local cf = CFrame.new(d.model:GetPivot().Position + Vector3.yAxis * 3)
		local name = d.model.Name
		local kind, look = d.model:GetAttribute("Kind"), d.model:GetAttribute("Look") -- same person, same clothes
		d.model:Destroy()
		task.spawn(spawnDummy, cf, name, kind, d.trait, look)
		return
	end
	stopBleeding(d)
	d.hp, d.daze, d.injuries, d.wakeAt = MAX_HP, 0, {}, 0
	d.blood, d.parts, d.cause, d.limp, d.burn, d.hurtUntil, d.calmAt = 100, {}, nil, false, 0, 0, 0
	for _, part in d.model:GetChildren() do
		if part:IsA("BasePart") then
			paint(d, part) -- clean skin again
		end
	end
	for key in d.limpJoints do
		d.limpJoints[key] = 0 -- the Heartbeat drives them again
	end
	d.wound, d.lastWound, d.scaredUntil, d.attackerAt = nil, nil, 0, nil
	for _, mark in d.model:GetDescendants() do
		if mark.Name == "Wound" or mark.Name == "Bruise" then
			mark:Destroy()
		end
	end
	d.speed, d.limpSide, d.risingUntil = d.zombie and ZOMBIE.speed or 8, nil, 0
	-- a fresh start for the mind too: it used to come back still fighting, still digging a grave,
	-- or bent over a wound it no longer has
	d.target, d.burying, d.digUntil, d.legless = nil, nil, 0, false
	d.crawling = false
	if d.helping then
		Body.stopHelping(d)
	end
	d.blame, d.blameAt = nil, nil
	d.morale, d.brain = d.baseMorale, nil
	d.humanoid.AutoRotate = true
	d.impactState = Impact.new()
	dropPose(d)
	d.postureKey = ""
	Looks.posture(d.model, {})
	for _, t in d.tracks do
		t:Stop(0)
	end
	Ragdoll.set(d.model, false)
	setState(d, "Awake")
	syncAttributes(d)
end

-- Toolbox extras: TEAMS and TIME STOP (one table: the script is at Luau's 200-locals limit)
local Sandbox: any = { frozen = false, userFrozen = false, frozenParts = {}, frozenTracks = {} }

-- TEAMS (Toolbox, SANDBOX + in shared/Shop): up to 4; a dummy in one goes after the nearest dummy of
-- another (behave, nearestDummy), never a teammate, and does not lose its nerve. A coloured dot over
-- its head shows which.
Sandbox.MAX_SPAWN = 5 -- dummies one SPAWN (Toolbox) puts down at most
Sandbox.TEAM_COLORS = { Color3.fromRGB(232, 70, 56), Color3.fromRGB(40, 110, 220), Color3.fromRGB(90, 180, 60), Color3.fromRGB(252, 200, 50) }
function Sandbox.setTeam(d, team: number?)
	d.team = team
	d.model:SetAttribute("Team", team)
	local head = d.model:FindFirstChild("Head")
	local mark = head and head:FindFirstChild("TeamMark")
	if mark and not team then
		mark:Destroy()
	elseif head and team then
		if not mark then
			mark = Instance.new("BillboardGui")
			mark.Name, mark.Size, mark.StudsOffset, mark.LightInfluence = "TeamMark", UDim2.fromScale(0.9, 0.9), Vector3.new(0, 2.2, 0), 0
			mark.MaxDistance = 150
			local dot = Instance.new("Frame")
			dot.Name, dot.Size, dot.BorderSizePixel = "Dot", UDim2.fromScale(1, 1), 0
			Instance.new("UICorner", dot).CornerRadius = UDim.new(0.5, 0)
			local ring = Instance.new("UIStroke")
			ring.Thickness, ring.Color, ring.Parent = 3, Color3.fromRGB(20, 20, 24), dot
			dot.Parent = mark
			mark.Parent = head
		end
		(mark :: any).Dot.BackgroundColor3 = Sandbox.TEAM_COLORS[team]
	end
	local target = d.target
	if team and target and typeof(target) ~= "Instance" and target.team == team then -- now on its side
		d.target, d.brain = nil, nil
		local guard = d.tracks[Anims.guard]
		if guard then
			guard:Stop(0.3)
		end
	end
end

-- TIME STOP: every dummy holds still where it is, anchored, its animations paused and its brain off
-- (the Heartbeat skips it); time on puts it all back. On while the Toolbox button (SANDBOX +) has it
-- on (userFrozen), so they can be set up, and while every player is still in the menu (inMenu): the
-- world waits for PLAY.
-- Sandbox.frozenParts: [BasePart] = true, anchored by the stop; Sandbox.frozenTracks: [AnimationTrack] = its speed
function Sandbox.freeze(d)
	d.frozen = true
	if d.heldBy or d.looseOwner then
		release(d, Vector3.zero)
	end
	for _, part in d.model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			part.Anchored = true
			Sandbox.frozenParts[part] = true
		end
	end
	local animator = d.humanoid:FindFirstChildOfClass("Animator")
	for _, track in animator and animator:GetPlayingAnimationTracks() or {} do
		Sandbox.frozenTracks[track] = track.Speed
		track:AdjustSpeed(0)
	end
end
function Sandbox.inMenu(): boolean
	local players = Players:GetPlayers()
	for _, player in players do
		if player:GetAttribute("Map") then
			return false
		end
	end
	return #players > 0
end
function Sandbox.setFrozen(on: boolean)
	Sandbox.frozen = on
	if on then
		return -- the Heartbeat freezes each dummy (new ones too, once they have landed)
	end
	for part in Sandbox.frozenParts do
		if part.Parent then
			part.Anchored = false
		end
	end
	for track, speed in Sandbox.frozenTracks do
		track:AdjustSpeed(speed)
	end
	table.clear(Sandbox.frozenParts)
	table.clear(Sandbox.frozenTracks)
	for _, d in dummies do
		d.frozen = nil
		-- unanchoring hands a part to the nearest player's client (automatic ownership): the server
		-- has to own its dummies, or it can no longer stand them up, walk them or make them crawl
		setOwner(d.model, nil)
	end
end

-- Joints that go limp on their own while the dummy stays on its feet (Ragdoll.joints).
local LIMP = {
	left = { "LeftShoulder", "LeftElbow", "LeftWrist" },
	right = { "RightShoulder", "RightElbow", "RightWrist" },
	neck = { "Neck" },
	waist = { "Waist" },
}
local function limp(d, key: string, seconds: number)
	d.limpJoints[key] = math.max(d.limpJoints[key] or 0, os.clock() + seconds)
	Ragdoll.joints(d.model, LIMP[key], true)
	setOwner(d.model, nil) -- the loose limb is its own assembly now; keep it on the server
end

local BLAME_FOR = 300 -- seconds a player answers for a death they set going (shot, thrown, set on fire: Wanted)
-- Respawning: a dummy that dies is replaced at once by a new one somewhere behind the player who
-- killed it (else the nearest player), where they are not looking. The bodies stay where they fell;
-- only past MAX_BODIES do the oldest go (bodies do not count toward MAX_DUMMIES, the living, see
-- trimDummies). The tutorial's dummies are its own business (server/Tutorial). `run` is below, by trimDummies.
local RESPAWN: any = { MAX_BODIES = 45, BEHIND = { 30, 22, 14 } }

-- Who did what is happening to `d` now: whoever's action this thread is running (Wanted.act: their
-- attack, their rocket, their grenade's fuse, their molotov's fire, their arrow; false for a soldier's
-- rocket), else the last one who hurt, threw, dropped or carried it (a landing, a bleed-out, a machine
-- it was thrown into). Nobody: a dummy's own fight, a fall it took by itself.
local function blameOf(d): (Player?, string?)
	local by, weapon = Wanted.culprit(), Wanted.weapon()
	if by == nil and d.blameAt and os.clock() - d.blameAt < BLAME_FOR then
		by, weapon = d.blame, d.blameWeapon
	end
	return by or nil, weapon
end

local function kill(d, cause: string)
	if d.state ~= "Dead" then
		local by, weapon = blameOf(d)
		if by and not d.zombie and not d.model:GetAttribute("TutorialFor") then -- no crime: a zombie, the tutorial's dummies
			Wanted.crime(by, d.model:GetAttribute("Kind"))
		end
		if by then -- a kill for the weapon progression (zombies count)
			Progress.credit(by, weapon)
		end
		d.diedAt = os.clock() -- the oldest bodies go first (RESPAWN)
		task.defer(RESPAWN.run, d, by)
	end
	d.cause = cause
	d.deadSynced = false -- one last HUD update (the Heartbeat), then it rests
	knockDown(d, math.huge, "Dead")
end

-- Poses -------------------------------------------------------------------------
-- IKControls on the Humanoid bend the animated body: a hand held on the wound, both hands up at
-- gunpoint. The hand goes to a point just off the skin, so it does not sink into the body. IK only
-- moves driven joints: the pose is dropped when the body goes limp (knockDown) and worked out
-- again from d.wound / d.scaredUntil once it is back on its feet (updatePose, from the Heartbeat).
local HAND_CLEAR = 0.38 -- how far off the skin a hand rests: half a hand thick, so the palm lies on the body
local REACH_ACROSS = 0.3 -- of the chest width: how far past the middle a hand gets with the elbow in front
local CLUTCHABLE = { Head = true, UpperTorso = true, LowerTorso = true, LeftUpperLeg = true, RightUpperLeg = true }

local function armFree(d, side: string): boolean
	return not d.limpJoints[side:lower()]
		and d.model:FindFirstChild(side .. "UpperArm") ~= nil
		and d.model:FindFirstChild(side .. "LowerArm") ~= nil
		and d.model:FindFirstChild(side .. "Hand") ~= nil
end

local function spot(on: BasePart, name: string, at: Vector3): Attachment
	local a = on:FindFirstChild(name) :: Attachment?
	if not a then
		a = Instance.new("Attachment")
		a.Name = name
		a.Parent = on
	end
	a.Position = at
	return a
end

-- Bring one hand to `target`. `elbow` (a point in the upper torso's space) is where the elbow is
-- pulled toward: without it the solver takes the shortest way and the forearm goes straight
-- through the chest; with the elbow held out in front, the arm folds round the body instead.
local function reach(d, side: string, target: Attachment, elbow: Vector3)
	local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
	local ik = Instance.new("IKControl")
	ik.Name = "Reach" .. side
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = d.model[side .. "UpperArm"]
	ik.EndEffector = d.model[side .. "Hand"]
	ik.Target = target
	if torso then
		ik.Pole = spot(torso, "Elbow" .. side, elbow)
	end
	ik.SmoothTime = 0.15
	ik.Parent = d.humanoid
	table.insert(d.poses, ik)
end

-- Remember where it hurts; the hands go there while the dummy is up. `seconds` is how long.
local function clutch(d, part: BasePart, point: Vector3, seconds: number)
	local at = part.CFrame:PointToObjectSpace(point)
	if at.Z > 0 and PARTS[part.Name].zone ~= "Head" then
		-- hit in the back: no hand gets there (the solver flails), so it holds the same spot in front
		at = Vector3.new(at.X * 0.6, at.Y, -part.Size.Z / 2)
	end
	-- off the surface, away from the middle of the part (a hit dead centre: out the front)
	local out = at.Magnitude > 0.05 and at.Unit or -Vector3.zAxis
	d.wound = { part = part, at = at + out * HAND_CLEAR, untilTime = os.clock() + seconds }
	d.lastWound = d.wound
end

local function updatePose(d)
	if d.zombie then
		-- both arms straight out in front, whatever hurts; a broken or lost arm hangs (armFree).
		-- ZOMBIE.swing moves these same targets to hit.
		local key = "zombie" .. (armFree(d, "Left") and "L" or "") .. (armFree(d, "Right") and "R" or "")
		local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
		if key ~= d.poseKey and torso then
			dropPose(d)
			d.poseKey = key
			for _, side in { "Left", "Right" } do
				if armFree(d, side) then
					local sx = side == "Left" and -1 or 1
					reach(d, side, spot(torso, "ZombieReach" .. side, ZOMBIE.rest(sx)), Vector3.new(sx * 2, 0.6, -1))
				end
			end
		end
		return
	end
	local now = os.clock()
	local wound = d.wound
	if wound and (now >= wound.untilTime or wound.part.Parent ~= d.model) then
		wound, d.wound = nil, nil
	end
	local scared = now < d.scaredUntil and not (wound and d.bleed > 0) -- bleeding: the hands stay on the wound
	local key = (scared and "up" or wound and wound.part.Name .. tostring(wound.at) or "")
		.. (armFree(d, "Left") and "L" or "") .. (armFree(d, "Right") and "R" or "")
	if key == d.poseKey then
		return
	end
	dropPose(d)
	d.poseKey = key
	local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
	if scared and torso then
		for _, side in { "Left", "Right" } do
			if armFree(d, side) then
				local sx = side == "Left" and -1 or 1
				-- elbows out to the sides, forearms straight up
				reach(d, side, spot(torso, "HandsUp" .. side, Vector3.new(sx * 1.5, 1.9, -0.5)), Vector3.new(sx * 2.6, 0.2, 0.2))
			end
		end
	elseif wound and torso then
		local info = PARTS[wound.part.Name]
		local onTorso = wound.part == torso or wound.part.Name == "LowerTorso"
		local front = -(torso.Size.Z / 2 + HAND_CLEAR) -- the palm lies on the chest, not in it
		-- an arm is held with the other hand, the chest with both, the rest with whichever is free
		local sides = info.side == "left" and { "Right" } or info.side == "right" and { "Left" } or { "Right", "Left" }
		for _, side in sides do
			if not armFree(d, side) then
				continue
			end
			local sx = side == "Left" and -1 or 1
			local on, at = torso, nil
			if info.limb == "arm" then
				-- the hurt arm hangs out of reach: the other hand comes across the front of the chest
				-- to that shoulder, as far over as its own shoulder lets it
				at = Vector3.new(-sx * torso.Size.X * REACH_ACROSS, torso.Size.Y * 0.2, front)
			elseif wound.part == torso then
				-- a wound on the chest (or the stump of a whole arm): each hand goes as near to it as
				-- it can get, the two side by side rather than through each other
				local x = math.clamp(wound.at.X, -torso.Size.X * REACH_ACROSS, torso.Size.X * REACH_ACROSS)
				at = Vector3.new(x + sx * 0.28, wound.at.Y, front)
			else
				on, at = wound.part, wound.at
			end
			-- elbow forward and down on the hand's own side: upper arm along the ribs, forearm across
			-- the front. For the head it goes up and out instead.
			local elbow = Vector3.new(sx * 1.5, -1.0, -1.6)
			if wound.part.Name == "Head" then
				elbow = Vector3.new(sx * 2.2, 0.6, -0.8)
			elseif not onTorso and info.limb ~= "arm" then
				elbow = Vector3.new(sx * 1.8, -0.6, 0.6) -- reaching down to a leg: elbow back
			end
			reach(d, side, spot(on, "ClutchAt" .. side, at), elbow)
			d.pressing = true
			if not onTorso or wound.part.Name == "LowerTorso" then
				break -- one hand is enough
			end
		end
	end
end

-- Face and posture (server/Looks.luau) follow what is happening to the dummy. Worked out a few
-- times a second from the Heartbeat and at once when it is hit.
local function express(d)
	local now = os.clock()
	local model = d.model
	local ragdolled = model:GetAttribute("Ragdolled")
	local face = "calm"
	if d.state == "Dead" then
		face = "dead"
	elseif d.state == "Out cold" then
		face = "out"
	elseif now < d.hurtUntil or (ragdolled and d.daze >= 30) or d.state == "Held" then
		face = "hurt"
	elseif now < d.scaredUntil or d.calmAt > 0 then
		face = "scared"
	elseif d.blood < BLOOD_DROWSY then
		face = "dizzy"
	elseif ragdolled or #d.injuries > 0 then
		face = "angry" -- hurt and not happy about it
	end
	if d.zombie and d.state ~= "Dead" then
		face = "angry" -- teeth bared, always
	end
	Looks.face(model, face)
	if ragdolled then
		return -- the spine is limp; the lean is put back on the way up
	end
	local pose, key = {}, ""
	local wound = d.wound
	local ribs = d.parts.UpperTorso and d.parts.UpperTorso.broken
	if d.zombie then
		pose, key = { Waist = Vector3.new(-0.18, 0, 0.06), Neck = Vector3.new(-0.2, 0, 0.25) }, "zombie" -- hunched, head lolling
	elseif now < d.scaredUntil and not (wound and d.bleed > 0) then
		pose, key = { Waist = Vector3.new(0.14, 0, 0), Neck = Vector3.new(0.1, 0, 0) }, "scared" -- leaning away
	elseif wound and (wound.part.Name == "UpperTorso" or wound.part.Name == "LowerTorso") then
		pose, key = { Waist = Vector3.new(-0.45, 0, 0), Neck = Vector3.new(-0.3, 0, 0) }, "doubled" -- over the wound
	elseif wound and PARTS[wound.part.Name].side then
		local lean = PARTS[wound.part.Name].side == "left" and 0.14 or -0.14
		pose, key = { Waist = Vector3.new(-0.12, 0, lean), Neck = Vector3.new(-0.18, 0, lean) }, "favour" .. lean
	elseif wound and wound.part.Name == "Head" then
		pose, key = { Waist = Vector3.new(-0.15, 0, 0), Neck = Vector3.new(-0.35, 0, 0.2) }, "head"
	elseif d.blood < BLOOD_DROWSY then
		pose, key = { Waist = Vector3.new(-0.18, 0, 0.06), Neck = Vector3.new(-0.5, 0, 0) }, "drowsy" -- head hanging
	elseif ribs then
		pose, key = { Waist = Vector3.new(-0.22, 0, 0), Neck = Vector3.new(-0.1, 0, 0) }, "sore"
	elseif d.limp then
		pose, key = { Waist = Vector3.new(-0.08, 0, 0.12) }, "limp"
	end
	if key ~= d.postureKey then
		d.postureKey = key
		Looks.posture(model, pose)
	end
end

-- Other dummies see and hear what happens: they shout, run from it, now and then run to help.
local WITNESS_LINES = {
	shot = { "That's a real gun!", "Get down!", "Who's shooting?!" },
	hit = { "Hey! Leave them alone!", "Stop that!", "Get that one!" },
	death = { "Oh no...", "They're not moving!", "I saw that!" },
	cut = { "Is that a leg?!", "I'm going to be sick.", "Not the axe!" },
}
local function pace(d): number
	if d.zombie then
		return ZOMBIE.speed
	end
	if d.crawling then
		return Body.CRAWL_SPEED
	elseif Body.mobility(d) == "hop" then
		return Body.HOP_SPEED
	end
	return (d.limp or d.blood < BLOOD_DROWSY) and 3.5 or 8
end
local function playTrack(d, animation: Animation): AnimationTrack
	local track = d.tracks[animation]
	if not track then
		track = d.animator:LoadAnimation(animation)
		d.tracks[animation] = track
	end
	return track
end

-- A reaction interrupts the visible attack AND its pending damage callback.
-- Otherwise Action3/4 attacks cover the flinch and a cancelled punch still hits.
local function reactToHit(d, direction: Vector3?)
	if d.zombie then -- feels nothing: no flinch, and a blow does not stop its swing
		return
	end
	for _, animation in { Anims.punch, Anims.haymaker, Anims.kick, Anims.dodge, Anims.taunt } do
		local track = d.tracks[animation]
		if track and track.IsPlaying then
			track:Stop(0.035)
		end
	end
	for _, animation in Anims.staggers do
		local track = d.tracks[animation]
		if track and track.IsPlaying then
			track:Stop(0.035)
		end
	end
	if d.brain then
		d.brain.swingToken = (d.brain.swingToken or 0) + 1
		d.brain.busyUntil = math.max(d.brain.busyUntil or 0, os.clock() + 0.3)
	end
	local root = d.model:FindFirstChild("HumanoidRootPart")
	local localDir = root and direction and root.CFrame:VectorToObjectSpace(direction) or Vector3.zAxis
	local side = math.abs(localDir.X) > math.abs(localDir.Z)
		and (localDir.X > 0 and "right" or "left") or (localDir.Z < 0 and "back" or "front")
	playTrack(d, Anims.staggers[side]):Play(0.035)
end

-- Walking round walls ---------------------------------------------------------------------------
-- Every walk goes through walkTo: the dummy keeps the goal and, a few times a second (steer, from
-- the Heartbeat), feels ahead at waist height. A clear line walks straight at the goal; a wall in
-- the way turns it off to the open side, and it keeps to that side for a while, so it follows the
-- wall round instead of swinging back and forth, until the goal is in the clear again. Low things
-- (a kerb, a step) pass under the feeler: the humanoid steps or jumps them as before.
local FEEL_AHEAD = 7 -- studs it looks ahead
local FEEL_RADIUS = 1.4 -- about half the body's width
local FEEL_HEIGHT = 0.5 -- above the root: the waist
local GOAL_TIME = 8 -- a walk gives up after this, like Humanoid:MoveTo
local STEER_EVERY = 0.15
local SIDE_TIME = 1.5 -- how long it keeps to the side it picked
local TURNS = { 25, 50, 75, 100, 125, 150 } -- degrees off the line to the goal, tried on each side
local FLAT = Vector3.new(1, 0, 1)
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude
wallParams.RespectCanCollide = true -- only what would actually stop it
local wallFilterAt = -1

local function clearWay(from: Vector3, dir: Vector3, length: number): boolean
	local now = os.clock()
	if now ~= wallFilterAt then -- once a frame: bodies are not walls, they get pushed past
		wallFilterAt = now
		local list: { Instance } = { dummyFolder }
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(list, player.Character)
			end
		end
		wallParams.FilterDescendantsInstances = list
	end
	return workspace:Spherecast(from, FEEL_RADIUS, dir * length, wallParams) == nil
end

local function steer(d, now: number)
	local goal = d.goal
	if not goal or now < d.steerAt then
		return
	end
	d.steerAt = now + STEER_EVERY
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local to = root and (goal - root.Position) * FLAT
	if not root or not to or now > d.goalUntil or to.Magnitude < 1.5 then
		d.goal = nil
		return
	end
	local dist = to.Magnitude
	local dir = to / dist
	local from = root.Position + Vector3.yAxis * FEEL_HEIGHT
	local ahead = math.min(dist - FEEL_RADIUS, FEEL_AHEAD) -- a wall just behind the goal is not in the way
	if ahead < 0.5 or clearWay(from, dir, ahead) then
		d.humanoid:MoveTo(goal)
		return
	end
	-- the order turns are tried in: on a side it already keeps to, every angle on that side before
	-- the other (else it hops across whenever the far side opens a little sooner); fresh, the
	-- smallest turn either way
	local tries = {}
	if now < (d.sideUntil or 0) then
		for _, side in { d.avoidSide, -d.avoidSide } do
			for _, deg in TURNS do
				table.insert(tries, deg * side)
			end
		end
	else
		local first = math.random() < 0.5 and 1 or -1
		for _, deg in TURNS do
			table.insert(tries, deg * first)
			table.insert(tries, -deg * first)
		end
	end
	for _, deg in tries do
		local turned = CFrame.Angles(0, math.rad(deg), 0):VectorToWorldSpace(dir)
		if clearWay(from, turned, FEEL_AHEAD) then
			d.avoidSide, d.sideUntil = math.sign(deg), now + SIDE_TIME
			d.humanoid:MoveTo(root.Position + turned * FEEL_AHEAD)
			return
		end
	end
	d.humanoid:MoveTo(root.Position - dir * FEEL_AHEAD) -- boxed in: back out
end

-- Walk to `goal`, round any wall on the way.
local function walkTo(d, goal: Vector3)
	d.goal, d.goalUntil, d.steerAt = goal, os.clock() + GOAL_TIME, 0
	steer(d, os.clock())
end

-- Straight to `at` with no steering: a path waypoint (already round the walls), or its own spot
-- to stand still.
local function walkStraight(d, at: Vector3)
	d.goal = nil
	d.humanoid:MoveTo(at)
end

-- Run from `from`, carrying what hurts: a hand stays on a wound that still bleeds, a broken leg
-- drags (the Heartbeat). A hooligan never runs, however badly it is hurt, nor does a zombie.
local function flee(d, from: Vector3, distance: number)
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or d.gear == "Bat" or d.zombie then
		return
	end
	local now = os.clock()
	local away = (root.Position - from) * Vector3.new(1, 0, 1)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
	d.speed = pace(d) * 1.7
	walkTo(d, root.Position + away * distance)
	d.nextWander, d.calmAt = now + 4, now + 4
	local wound = d.lastWound
	if d.bleed > 0 and wound and wound.part.Parent == d.model then
		wound.untilTime = math.max(wound.untilTime, now + 4)
		d.wound = wound
	end
end

-- Personalities ------------------------------------------------------------------------------
-- Every dummy is born with one. None ever starts on a player: a player only gets hit back by the dummy it hit.
-- Berserk goes for the nearest dummy on sight, Tough hits back and
-- keeps at it however badly it is hurt, Hothead hits back but gives up once something is broken
-- or it bleeds hard, Mourner buries the dead, Coward runs at the very sight of a player.
local TRAITS = { { "Berserk", 5 }, { "Tough", 20 }, { "Hothead", 20 }, { "Mourner", 50 }, { "Coward", 5 } }
local MORALE = { Berserk = 100, Tough = 90, Hothead = 60, Mourner = 40, Coward = 15 } -- starting morale
local function rollTrait(): string
	local roll = math.random() * 100
	for _, t in TRAITS do
		roll -= t[2]
		if roll <= 0 then
			return t[1]
		end
	end
	return "Mourner"
end

-- Broken bones, a bad bleed or not much blood left: a Hothead has had enough.
local function badlyHurt(d): boolean
	for _, p in d.parts do
		if p.broken then
			return true
		end
	end
	return d.bleed >= 2 or d.blood < BLOOD_DROWSY or next(d.lost) ~= nil
end

-- The player whose head is at `from` (where hit() says the blow came from).
local function playerAt(from: Vector3): Player?
	for _, player in Players:GetPlayers() do
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head and (head.Position - from).Magnitude < 4 then
			return player
		end
	end
	return nil
end

-- The dummy (not `victim`) whose head is at `from`: a Berserk punching it.
local function dummyAt(from: Vector3, victim): any
	for _, d in dummies do
		local head = d.model:FindFirstChild("Head") :: BasePart?
		if d ~= victim and d.state ~= "Dead" and head and (head.Position - from).Magnitude < 4 then
			return d
		end
	end
	return nil
end

local COP_SIGHT = 70 -- a cop this close to a hooligan beating someone up goes after it
local COP_LINES = { "Freeze!", "Police! Drop it!", "You're under arrest!", "Hands where I can see them!" }
local function alarm(victim, position: Vector3, kind: string, from: Vector3?)
	local now = os.clock()
	local culprit = victim and from and dummyAt(from, victim)
	local thug = culprit and culprit.gear == "Bat" and not victim.gear and culprit or nil
	for _, d in dummies do
		if d.zombie then -- takes no notice of anything but its prey
			continue
		end
		local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if thug and d.law and d.state == "Awake" and d.target ~= thug
			and not (d.target and typeof(d.target) == "Instance") -- a player it is fighting comes first
			and root and (root.Position - position).Magnitude < COP_SIGHT then
			d.target = thug
			say(d, pick(COP_LINES), "shout")
			continue
		end
		if d == victim or d.state ~= "Awake" or now < d.nextReact or d.target then
			continue
		end
		if not root or (root.Position - position).Magnitude > 45 then
			continue
		end
		d.nextReact = now + math.random(3, 6)
		if kind == "death" then
			d.morale -= 15 -- seeing one of its own drop shakes it
		end
		-- never piles in on a player: a dummy only fights a player who hit it
		d.nextWander, d.calmAt = now + 4, now + 4
		if victim and victim.state ~= "Dead" and kind ~= "shot" and not d.limp and math.random() < 0.2 then
			say(d, "Hang on, I'm coming!")
			d.speed = 12
			walkTo(d, position)
			continue
		end
		if math.random() < 0.7 then
			say(d, pick(WITNESS_LINES[kind]))
		end
		flee(d, from or position, 22)
	end
end

local ANGRY_LINES = { "That's it!", "You want a fight?!", "Come here!", "Oh, you're dead now!" }
local BERSERK_LINES = { "YOU!", "Get over here!", "I've been waiting for this." }
local GIVE_UP_LINES = { "Okay, okay, I'm done!", "Not worth it!", "I give up!" }
local COWARD_LINES = { "Nope, nope, nope!", "Stay away from me!", "Help!" }
local MOURN_LINES = { "Oh no... I'll take care of you.", "Someone has to do it.", "Poor thing." }
local LEG_LINES = { "My leg won't hold me!", "Whoa-", "Ow, the leg!" }
local WAKE_LINES = { "That's the last time you do that.", "I'm okay. I think.", "Ow. Ow. Ow.", "Stay away from me!" }
local LOSS_LINES = { arm = { "My arm!", "That was my good arm!" }, leg = { "My leg!", "I needed that!" }, hand = { "My hand!" }, foot = { "My foot!" } }
local SHOT_LINES = { "I felt that in my teeth.", "Is it meant to move like that?", "That's a real gun!" }

-- `scale` multiplies the zone damage and `push` is the knockback speed (weapons); a punch is 1 / 30.
-- `kind` is the weapon's `hurt` (blunt when left out), `pos` the point that was hit.
-- `from` is where the attacker stands: the dummy and the ones watching run from there.
local function hit(d, part: BasePart, dir: Vector3, scale: number?, push: number?, kind: string?, pos: Vector3?, from: Vector3?)
	local power = (scale or 1) * d.armor
	d.attackerAt = from or d.attackerAt -- the ground hitting it (impacts) is nobody to run from
	local attacker = from and (playerAt(from) or dummyAt(from, d))
	-- for the wanted level (kill): a player, or false when a dummy did it. A dummy only counts if it
	-- is armed or fighting this one: a blast (smash) hits from a point by the victim, and whoever
	-- stands there is not the culprit.
	local culprit = Wanted.culprit()
	if typeof(culprit) == "Instance" then
		Tutorial.event(culprit, "hit") -- the controls hints (server/Tutorial)
		if culprit:GetAttribute("Tutorial") then
			power *= 2 -- a player still in the tutorial hits twice as hard
		end
	end
	if culprit ~= nil then
		d.blame, d.blameAt, d.blameWeapon = culprit, os.clock(), Wanted.weapon()
	elseif typeof(attacker) == "Instance" then
		d.blame, d.blameAt, d.blameWeapon = attacker, os.clock(), nil
	elseif attacker and (attacker.gear or attacker.target == d) then
		d.blame, d.blameAt, d.blameWeapon = false, os.clock(), nil
	end
	-- the SETTINGS page of whoever answers for the blow: HP it takes (DAMAGE), how easily bones go (BONES)
	local by = blameOf(d)
	local scaler = if typeof(by) == "Instance" then by else nil
	local harmScale = Progress.Settings.get(scaler, "DamageScale")
	local brittle = Progress.Settings.get(scaler, "BoneScale")
	if not PARTS[part.Name] then -- the root box: count it as the torso
		part = d.model:FindFirstChild("UpperTorso") or d.model:FindFirstChild("LowerTorso")
		if not part then
			return
		end
	end
	local info = PARTS[part.Name]
	local zone = ZONES[info.zone]
	local point = pos or part.Position
	local dead = d.state == "Dead"
	local p = d.parts[part.Name]
	if not p then
		p = { trauma = 0, broken = false }
		d.parts[part.Name] = p
	end
	p.trauma += power

	-- what the client shows: `bone` X-rays the part ("broken" draws the break), `blood` sprays
	local bone, blood, line = nil, 0, nil
	local cutOff, burst = false, false
	local function breakBone()
		if not p.broken then
			p.broken = true
			local by = blameOf(d)
			if by then
				Progress.add(by, "StatBones") -- the STATS page
			end
			Sfx.play(Sfx.BONE, point)
			addInjury(d, info.broken)
			d.limp = d.limp or info.limb == "leg"
			if info.limb == "leg" then
				d.limpSide = d.limpSide or info.side -- the leg it drags (Anims.limp)
			end
			line = part.Name == "UpperTorso" and "Right in the ribs!" or nil
			bone = "broken" -- the X-ray and the CRACK! only when it goes, not on every later hit to it
		end
	end
	-- the mark a bullet or a blade leaves; the blood comes out of it. A few per part, then the
	-- part itself stands in (a rifle would cover it in discs).
	-- Each weapon leaves its own: a bullet a small hole going in (and a torn, wider one coming out
	-- the far side when it is a heavy round), a knife a short slit, the axe a long gash.
	local mark: BasePart? = nil
	local function hole(): BasePart
		if not mark then
			p.holes = (p.holes or 0) + 1
			mark = part
			if p.holes <= 5 then
				if kind == "blade" then
					mark = woundAt(part, point, dir, power >= 4 and 0.16 or 0.08, WOUND, power >= 4 and 1 or 0.45) or part
				else
					mark = woundAt(part, point, dir, power >= 4 and 0.3 or 0.2, WOUND) or part
					-- where it comes out: back along the shot from beyond the part, onto the part alone
					exitParams.FilterDescendantsInstances = { part }
					local far = power >= 4 and workspace:Raycast(point + dir * 6, -dir * 6, exitParams)
					if far and (far.Position - point).Magnitude > 0.15 then
						local out = woundAt(part, far.Position, -dir, 0.46, TORN)
						if out then
							bleed(d, out, 0.8)
						end
					end
				end
			end
		end
		return mark :: BasePart
	end

	if kind == "bullet" then
		local heavy = power >= 4
		blood = heavy and 2 or 1
		line = pick(SHOT_LINES)
		if info.zone == "Head" then
			if heavy or dead or d.zombie then -- any bullet takes a zombie's head off
				burst = true
			else
				addInjury(d, "head wound")
				bleed(d, hole(), 2)
				d.hp -= 60 * harmScale
				bone = "ok"
			end
		elseif info.limb then
			if heavy then
				addInjury(d, `{info.side} {info.limb == "arm" and "arm" or "femoral"} artery`)
				bleed(d, hole(), 1.4)
			else
				addInjury(d, info.label .. " wound")
				bleed(d, hole(), 0.8)
			end
			if heavy or p.trauma >= SHOT_BREAK / brittle then
				addInjury(d, info.label .. " bone")
				breakBone()
			else
				bone = "ok"
			end
		else
			addInjury(d, info.label)
			bleed(d, hole(), heavy and 2 or 1)
			if heavy or p.trauma >= SHOT_BREAK / brittle then
				breakBone()
			else
				bone = "ok"
			end
		end
	elseif kind == "blade" then
		local heavy = power >= 4
		blood = heavy and 3 or 1
		-- the axe or the katana (Body.CHOP; any heavy blade but an arrow, from a dummy): a limb comes
		-- off at once, the head on a second blow or off a dead body
		local chop = heavy and (Body.CHOP[Wanted.weapon() or ""] or (Wanted.weapon() == nil and from ~= nil))
		if chop and (info.limb or (info.zone == "Head" and (dead or p.trauma > power))) then
			cutOff = true
		elseif info.zone == "Head" then
			addInjury(d, "head wound")
			bleed(d, hole(), 2)
			d.hp -= 50 * harmScale
			bone = "ok"
		elseif heavy then
			addInjury(d, info.label)
			bleed(d, hole(), 2)
			breakBone()
		else
			addInjury(d, "stab wound, " .. info.label)
			bleed(d, hole(), 1.2)
		end
	else
		addInjury(d, "bruised " .. info.area)
		-- a blunt weapon comes with someone swinging it (`from`); a fall or a throw has nobody
		local weapon = kind == "blunt" and from ~= nil
		if p.trauma >= info.breakAt * (weapon and BONE_TOUGH_WEAPON or BONE_TOUGH) / brittle then
			breakBone()
		end
		if power >= BRUISE_AT then
			-- from a small knock to a big blotch
			markAt(p, part, point, dir, (0.3 + math.random() * 0.45) * (0.7 + power * 0.25), BRUISE_IMAGES)
		end
	end
	-- a limb wears away under bullets and blades: past its TOUGH it comes off, all below it too (Body)
	if info.limb and not cutOff and Body.WEAR[kind or ""] then
		p.wear = (p.wear or 0) + Body.WEAR[kind] * power * (if Wanted.weapon() == "Bow" then Body.ARROW else 1)
		local tough = Body.TOUGH[part.Name:match("^%u%l+(%u.+)$") or ""]
		if tough and p.wear >= tough then
			cutOff = true
		end
	end

	if not dead and d.zombie then
		-- no pain: HP, daze and nerve stay put and it does not flinch. Only what breaks stops it.
		d.hp, d.daze, d.morale = MAX_HP, 0, d.baseMorale
		if info.zone == "Head" and (burst or cutOff) then
			kill(d, "Dead")
		elseif cutOff or grounded(d) then
			knockDown(d, 1.6, "Knocked down") -- a broken or lost leg keeps it down for good (grounded)
		elseif info.limb == "arm" and p.broken then
			limp(d, info.side, math.huge)
		end
	elseif not dead then
		d.hurtUntil = os.clock() + 1.6
		if d.helping then
			Body.stopHelping(d) -- hit while it tends someone: it has its own troubles now
		end
		d.hp -= zone.damage * power * harmScale
		d.morale -= zone.damage * power * (d.trait == "Tough" and 0.5 or 1)
		d.daze += zone.daze * (kind and kind ~= "blunt" and 1.5 or 1)
		local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not d.model:GetAttribute("Ragdolled") then
			-- still on its feet: the blow shoves it back a step
			root.AssemblyLinearVelocity += dir * Vector3.new(1, 0, 1) * math.min(6 + power * 5, 20)
		end
		if d.hp <= 0 or burst or (cutOff and part.Name == "Head") then
			kill(d, "Dead")
		elseif d.daze >= 75 then
			knockDown(d, 8, "Out cold")
		elseif d.daze >= 45 or d.model:GetAttribute("Ragdolled") then
			knockDown(d, 3, "Knocked down")
		elseif info.limb == "leg" or cutOff or (kind and kind ~= "blunt" and power >= 4) or (power >= 2.5 and info.limb ~= "arm") then
			knockDown(d, 1.6, "Knocked down") -- legs taken out, a heavy bullet or a bat to the body: down they go
		elseif info.limb == "arm" then
			-- only the arm that was hit goes limp and swings; a broken one never comes back
			limp(d, info.side, p.broken and math.huge or 1.6)
		elseif info.zone == "Head" then
			limp(d, "neck", 0.5) -- the head snaps back
		else
			limp(d, "waist", 0.35) -- doubles over for a moment
		end
		if d.state == "Awake" and not d.model:GetAttribute("Ragdolled") and os.clock() >= d.risingUntil then
			-- still up: the blow rocks it back, and a fight it is in loses a beat
			reactToHit(d, dir)
			if d.brain then
				d.brain.swingAt = math.max(d.brain.swingAt, os.clock() + 0.4)
				table.clear(d.brain.queue)
			end
		end
	end

	-- the body is limp by now (knockDown or dead), so the joints can be cut
	if burst then
		addInjury(d, "head burst")
		sever(d, part, dir):Destroy()
		fxRemote:FireAllClients("Burst", nil, point, dir)
	else
		if cutOff then
			addInjury(d, info.label .. (if kind == "bullet" then " shot off" else " cut off"))
			line = pick(LOSS_LINES[part.Name:match("Hand") and "hand" or part.Name:match("Foot") and "foot" or info.limb] or zone.lines)
			sever(d, part, dir)
			Body.lost(d, part)
		end
		fxRemote:FireAllClients("Wound", nil, part, point, dir, blood, bone, cutOff and "cut" or kind or "blunt")
		if not cutOff and (CLUTCHABLE[part.Name] or info.limb == "arm") then
			clutch(d, part, point, p.broken and 12 or 6)
		end
	end
	express(d)

	if d.state == "Awake" or d.state == "Knocked down" or d.state == "Held" then
		say(d, line or pick(zone.lines))
	end
	syncAttributes(d)
	alarm(d, point, (not dead and d.state == "Dead") and "death" or cutOff and "cut" or kind == "bullet" and "shot" or "hit", from)
	local hooligan = attacker and typeof(attacker) ~= "Instance" and attacker.gear == "Bat"
	local teammate = attacker and typeof(attacker) ~= "Instance" and d.team and attacker.team == d.team
	if attacker and not dead and not teammate and d.state ~= "Dead" and d.target ~= attacker
		and not grounded(d) and Body.mobility(d) ~= "hop" and Body.usable(d, "jab") -- nothing left to fight with: no threats
		and (d.trait == "Tough" or d.trait == "Berserk" or (d.trait == "Hothead" and not badlyHurt(d)) or (hooligan and d.brave)) then
		d.target = attacker -- it hits back (behave), on its feet again if it went down
		say(d, pick(ANGRY_LINES))
	end
	if d.state == "Awake" and from and not d.target then -- still on its feet: it gets away from whoever did that
		flee(d, from, 24)
	end

	if part.Parent and not cutOff then
		part:ApplyImpulse((dir + Vector3.yAxis * 0.3) * part.AssemblyMass * (push or 30))
		part:ApplyAngularImpulse(Random.new():NextUnitVector() * part.AssemblyMass * 12)
	end
end

-- `forceTrait`: its character instead of the kind's or a random one (the tutorial's never hit back).
-- `look`: a KINDS name to dress it as instead of its own kind (a revive keeps the "Look" it had)
function spawnDummy(cf: CFrame, as: string?, forceKind: string?, forceTrait: string?, look: string?)
	local kindName = forceKind or rollKind()
	local kind = KINDS[kindName]
	local wear = look and KINDS[look] or kind
	local model = Players:CreateHumanoidModelFromDescription(wear.description, Enum.HumanoidRigType.R15)
	for _, part in model:GetChildren() do -- the skin probes (skinAt) start building now, not on the first hit
		if part:IsA("MeshPart") then
			skinAt(part, part.Position, -Vector3.yAxis)
		end
	end
	local name = as or pick(NAMES)
	model.Name = name
	model:SetAttribute("Kind", kindName)
	model:SetAttribute("Look", look)
	model:SetAttribute("Gear", kind.gear) -- set before it is parented, so clients get it with the model
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 8

	Looks.buildFace(Looks.plainHead(model))
	if wear.outfit then
		Outfits.dress(model, wear.outfit)
	end

	model:PivotTo(cf)
	model.Parent = dummyFolder
	Ragdoll.setup(model)
	setOwner(model, nil)

	-- The rig's Animate is a LocalScript (won't run on an NPC), so borrow its animations here.
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animate = model:FindFirstChild("Animate")
	local function track(slot)
		local folder = animate and animate:FindFirstChild(slot)
		local anim = folder and folder:FindFirstChildOfClass("Animation")
		return anim and animator:LoadAnimation(anim)
	end
	local idle, walk = track("idle"), track("walk")
	if idle then
		idle.Looped = true
		idle:Play()
	end
	if walk then
		walk.Looped = true
		humanoid.Running:Connect(function(speed)
			if speed > 0.5 and not walk.IsPlaying then
				walk:Play()
			elseif speed <= 0.5 and walk.IsPlaying then
				walk:Stop()
			end
		end)
	end

	local trait = forceTrait or kind.traits and pick(kind.traits) or rollTrait()
	local d = {
		model = model,
		gear = kind.gear, -- "Baton" / "Handgun" / "Bat" / "Rifle" / "Rocket" / nil: what it fights with
		law = kind.law, -- police or army (Wanted)
		armor = kind.armor or 1, -- what a blow or a blast is worth on it
		brave = math.random() < (kind.brave or 0), -- stands up to a hooligan (KINDS)
		zombie = kind.zombie, -- see ZOMBIE

		humanoid = humanoid,
		home = cf.Position,
		hp = MAX_HP,
		daze = 0,
		injuries = {},
		blood = 100, -- %
		bleed = 0, -- % per second
		parts = {}, -- [part name] = { trauma = number, broken = boolean }
		lost = {}, -- [part name] = true, cut off
		poses = {}, -- IKControls of the pose it holds (see Poses)
		poseKey = "",
		postureKey = "", -- the lean it has (express)
		hurtUntil = 0, -- its face shows the last hit until then
		burn = 0, -- times the fire has had it
		animator = animator,
		tracks = {}, -- [Animation] = its loaded track (playTrack)
		speed = kind.zombie and ZOMBIE.speed or 8, -- walk speed it wants; the Heartbeat sets WalkSpeed from it (and the limp)
		limpSide = nil :: string?, -- "left" / "right": the broken leg it drags
		risingUntil = 0, -- getting up (Anims): it does not move or pose until then
		trait = trait, -- its character (Personalities)
		baseMorale = MORALE[trait] or 50, -- how much fight it has in it (Brain: fighting)
		morale = MORALE[trait] or 50,
		brain = nil :: any, -- the fight it is in (Brain: fighting)
		impactState = Impact.new(), -- recent top speeds and a landing under way (impacts)
		nextImpact = 0,
		target = nil :: Player?, -- the player it is going for
		nextLook = 0, -- next look round for players and the dead (behave)
		nextSwing = 0, -- next punch at its target
		burying = nil :: any, -- the dead dummy it is burying
		digUntil = 0, -- 0: not digging yet
		wound = nil :: any, -- { part, at, untilTime }: where the hands go
		lastWound = nil :: any, -- the newest wound, kept after the hands leave it (gunpoint)
		pressing = false, -- a hand is on the wound: it bleeds slower
		scaredUntil = 0, -- a gun is on it: hands up
		nextReact = 0, -- to what happens around it (alarm)
		calmAt = 0, -- stops running then
		nextTwitch = 0, -- writhing / crawling on the ground
		attackerAt = nil :: Vector3?,
		limpJoints = {}, -- [LIMP key] = os.clock() it is driven again (math.huge = broken arm)
		legless = false, -- lost part of a leg: cannot stand again
		limp = false, -- broken leg
		cause = nil :: string?, -- shown once dead
		wakeAt = 0,
		nextWander = os.clock() + math.random() * 4,
		nextTalk = os.clock() + math.random(10, 30),
		state = "Awake",
		born = os.clock(),
	}
	dummies[model] = d
	model:SetAttribute("Trait", d.trait)
	model.Destroying:Connect(function()
		if d.heldBy then
			held[d.heldBy] = nil
		end
		dummies[model] = nil
	end)
	setState(d, "Awake")
	syncAttributes(d)
	return d
end

-- One still copy of each kind, dressed like spawnDummy dresses it, for the Toolbox's character
-- tiles (client/Toolbox.luau draws them in ViewportFrames).
task.spawn(function()
	local previews = Instance.new("Folder")
	previews.Name = "ToolboxPreviews"
	for kindName, kind in KINDS do
		local ok, err = pcall(function()
			local model = Players:CreateHumanoidModelFromDescription(kind.description, Enum.HumanoidRigType.R15)
			model.Name = kindName
			Looks.buildFace(Looks.plainHead(model))
			if kind.outfit then
				Outfits.dress(model, kind.outfit)
			end
			-- outside workspace the accessory welds never solve: put each hat on its body attachment
			for _, acc in model:GetChildren() do
				local handle = acc:IsA("Accessory") and acc:FindFirstChild("Handle") :: BasePart?
				local own = handle and handle:FindFirstChildOfClass("Attachment")
				local body: Attachment? = nil
				for _, part in model:GetChildren() do
					body = body or (own and part:IsA("BasePart") and part:FindFirstChild(own.Name) :: Attachment?)
				end
				if body then
					(handle :: BasePart).CFrame = body.WorldCFrame * (own :: Attachment).CFrame:Inverse()
				end
			end
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				elseif d:IsA("LuaSourceContainer") then
					d:Destroy()
				end
			end
			model.Parent = previews
		end)
		if not ok then
			warn("toolbox preview", kindName, err)
		end
	end
	PoliceCar.preview().Parent = previews
	previews.Parent = ReplicatedStorage
end)

-- Room for one more living dummy: at MAX_DUMMIES living the oldest of them goes. Bodies do not
-- count; they have their own cap (RESPAWN.MAX_BODIES).
local function trimDummies(limit: number?) -- `limit`: a lower cap than MAX_DUMMIES (SANDBOX + in shared/Shop)
	local living = {}
	for _, d in dummies do
		if d.state ~= "Dead" then
			table.insert(living, d)
		end
	end
	if #living < math.min(limit or MAX_DUMMIES, MAX_DUMMIES) then
		return
	end
	table.sort(living, function(a, b)
		return a.born < b.born
	end)
	living[1].model:Destroy()
end

function RESPAWN.run(d, by)
	if d.model:GetAttribute("TutorialFor") or not d.model.Parent then
		return
	end
	-- past MAX_BODIES bodies the oldest go (one carried by someone stays a while longer)
	local bodies = {}
	for _, other in dummies do
		if other.state == "Dead" and not other.heldBy then
			table.insert(bodies, other)
		end
	end
	if #bodies > RESPAWN.MAX_BODIES then
		table.sort(bodies, function(a, b)
			return (a.diedAt or a.born) < (b.diedAt or b.born)
		end)
		for k = 1, #bodies - RESPAWN.MAX_BODIES do
			bodies[k].model:Destroy()
		end
	end
	-- whose back it appears behind: the killer, else the player nearest the body
	local player = if typeof(by) == "Instance" and by:IsA("Player") then by else nil
	local body = d.model:GetPivot().Position
	if not player then
		local best = math.huge
		for _, other in Players:GetPlayers() do
			local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r and (r.Position - body).Magnitude < best then
				player, best = other, (r.Position - body).Magnitude
			end
		end
	end
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.zAxis
	local ground = RaycastParams.new()
	local skip = { dummyFolder, gibFolder }
	for _, other in Players:GetPlayers() do
		table.insert(skip, other.Character)
	end
	ground.FilterDescendantsInstances = skip
	for _, dist in RESPAWN.BEHIND do -- the furthest spot behind them that has ground under it
		local spot = root.Position - look * dist + root.CFrame.RightVector * math.random(-8, 8)
		local hit = workspace:Raycast(spot + Vector3.yAxis * 60, -Vector3.yAxis * 160, ground)
		if hit and hit.Normal.Y > 0.6 then
			trimDummies()
			spawnDummy(CFrame.new(hit.Position + Vector3.yAxis * 4) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
			return
		end
	end
end

-- One timer per player AND per kind of request: a punch, a spawn and the aim reports used to share
-- a single timer, so a kick (which sends "kick" on Action, then a Punch) ate its own punch and a
-- G right after a click did nothing.
local function rateLimited(player: Player, cooldown: number, bucket: string?): boolean
	local now = os.clock()
	local times = lastUse[player]
	if not times then
		times = {}
		lastUse[player] = times
	end
	local key = bucket or "default"
	if now - (times[key] or 0) < cooldown then
		return true
	end
	times[key] = now
	return false
end

-- A Vector3 that physics can take: no NaN, no infinity (a NaN velocity on a part can wreck the whole assembly).
local function finite(v: any): boolean
	return typeof(v) == "Vector3" and v == v and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function headOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("Head") :: BasePart?
end

punchRemote.OnServerEvent:Connect(function(player, part)
	Wanted.act(player, "Fists") -- whatever this does to a dummy is on them
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or rateLimited(player, PUNCH_COOLDOWN, "punch") then
		return
	end
	lastSwing[player] = os.clock() -- the dummies see the punch coming (Brain: dodging)
	local d = dummyOf(part)
	local head = headOf(player)
	if not head or (part.Position - head.Position).Magnitude > PUNCH_RANGE then
		return
	end
	if not d then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not player.Character:GetAttribute("Ragdolled") then
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { player.Character }
			local delta = part.Position - head.Position
			local result = delta.Magnitude > 0.01 and workspace:Raycast(head.Position, delta.Unit * (delta.Magnitude + 1), params)
			if result and result.Instance:IsDescendantOf(part:FindFirstAncestorOfClass("Model")) then
				if Monsters.damage(result.Instance, 14, delta, player) then return end
			end
		end
		if part.Parent and part.Parent.Name == "Grave" and part:IsDescendantOf(Map.folder) then
			Map.blast(part.Position, 1.5, 25)
		end
		return
	end
	if tryDodge(d, player) then
		return -- it slipped the punch
	end
	Sfx.play(Sfx.PUNCH, part.Position, player) -- the puncher played it already (punch / kick)
	hit(d, part, (part.Position - head.Position).Unit, nil, nil, nil, nil, head.Position)
end)

-- A gun pointed at a dummy: the client reports who it is aiming at a few times a second. The
-- dummy stops, begs and holds its hands up (updatePose) for as long as the reports keep coming.
local aimRemote = Instance.new("RemoteEvent")
aimRemote.Name = "Aim"
aimRemote.Parent = remotes
local SCARED_LINES = { "Don't shoot!", "Whoa, easy!", "I give up!", "Not me, not me!" }
local BLEEDING_LINES = { "I'm already bleeding!", "Please, I need a doctor!", "Haven't you done enough?", "It won't stop bleeding!" }
local DRAW_LINES = { "Drop the weapon!", "Gun! Gun!", "That's it!", "You asked for it!" }
-- what a dummy holds (gear): DummyGear on the clients swaps the model in its hand
local function setGear(d, gear)
	if d.gear ~= gear then
		d.gear = gear
		d.model:SetAttribute("Gear", gear)
	end
end
aimRemote.OnServerEvent:Connect(function(player, part)
	if rateLimited(player, 0.2, "aim") then -- the client sends one every 0.4 s
		return
	end
	local d = typeof(part) == "Instance" and dummyOf(part)
	local head = headOf(player)
	if not d or not head or d.state ~= "Awake" or d.target or d.zombie or (d.model:GetPivot().Position - head.Position).Magnitude > 60
		or player:GetAttribute("NeverWanted") then -- NEVER WANTED: a cop in your sights does not draw on you
		return
	end
	local now = os.clock()
	-- a cop on the beat (baton) kept in the sights for 2-3 s: some time in the next 5 s it draws its
	-- handgun and opens fire (copFight), even worse a shot than a Wanted cop's (d.drawn)
	if d.model:GetAttribute("Kind") == "Cop" and d.gear == "Baton" and not d.drawAt then
		if now - (d.aimedLast or 0) > 1 then -- a fresh aim: the reports come every 0.4 s
			d.aimedSince, d.aimNeed = now, 2 + math.random()
		end
		d.aimedLast = now
		if now - d.aimedSince >= d.aimNeed then
			d.drawAt = now + math.random() * 5
			task.delay(d.drawAt - now, function()
				d.drawAt = nil
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if not dummies[d.model] or d.state == "Dead" or d.zombie or (d.target and d.target ~= player)
					or not player.Parent or not hum or hum.Health <= 0 then
					return
				end
				setGear(d, "Handgun")
				d.drawn, d.target, d.scaredUntil = true, player, 0
				say(d, pick(DRAW_LINES), "shout")
			end)
		end
	end
	local wound = d.lastWound
	local bleeding = d.bleed > 0 and wound and wound.part.Parent == d.model
	if bleeding then -- hurt comes first: it presses on the wound instead of putting its hands up
		wound.untilTime = math.max(wound.untilTime, now + 1.5)
		d.wound = wound
	end
	if now >= d.scaredUntil then
		say(d, pick(bleeding and BLEEDING_LINES or SCARED_LINES))
		walkStraight(d, d.model:GetPivot().Position) -- stand still
		local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local to = (head.Position - d.model:GetPivot().Position) * Vector3.new(1, 0, 1)
		if root and to.Magnitude > 1 then -- turns to face the gun
			root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
		end
	end
	d.scaredUntil = now + 1.5
	d.nextWander = math.max(d.nextWander, now + 2.5)
end)

-- The punt (held with F, looking ahead, one click: the holder heaves it up and front-kicks it away):
-- the kick itself is a PUNT_HURT blunt blow, and for PUNT_TIME after it the body is marked, so the
-- first thing it hits takes a blow PUNT_POWER times harder than a throw would give, breaks the floor
-- or wall there a little (PUNT_BLAST): chunks, no burst effect.
local PUNT_HURT = 1.1
local PUNT_TIME = 3
local PUNT_POWER = 1.8
local PUNT_BLAST = 2.4 -- radius it smashes where it lands (Map.blast, PUNT_BLAST_POWER)
local PUNT_BLAST_POWER = 55
local PUNT_HITS = 3 -- hits that break the map while it is marked (the client's PUNT_HITS)
local MAX_PUNT_SPEED = 200
Sandbox.THROWN_SPEED = 25 -- studs/s a let-go body needs to count as thrown (STATS)

grabRemote.OnServerEvent:Connect(function(player, action, arg, ...)
	Wanted.act(player, "Body") -- whatever this does to a dummy is on them
	if action == "grab" then
		if typeof(arg) ~= "Instance" or not arg:IsA("BasePart") or held[player] then
			return
		end
		local d = dummyOf(arg)
		local head = headOf(player)
		-- F reaches a little further for the chest (by the collar), see DRAG_CHEST_REACH on the client
		local reach = GRAB_RANGE + (((...) == "drag" and arg.Name == "UpperTorso") and 4 or 0)
		if not d or d.heldBy or not head or (arg.Position - head.Position).Magnitude > reach then
			return
		end
		d.heldBy = player
		d.dragging = (...) == "drag" -- F: by the chest in one hand, ground into the floor on a sprint (scrape)
		d.throwFrom = nil
		d.looseOwner = nil -- caught again mid-flight: the new holder owns it (knockDown below)
		held[player] = d
		local attachment = Instance.new("Attachment")
		attachment.Name = "GrabAttachment"
		local align = Instance.new("AlignPosition")
		align.Name = "GrabAlign"
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.Position = arg.Position
		-- held in one hand (F) it is gripped hard: it stays at your side and is pressed down where
		-- you push it, instead of swinging along after you
		align.MaxForce = d.dragging and 90000 or 40000
		align.MaxVelocity = d.dragging and 200 or 90
		align.Responsiveness = d.dragging and 90 or 40
		align.Parent = attachment
		if d.dragging then
			setGroup(d.model, "Held")
			-- F: gripped by the clothes at the collar and held rigid in the fist - the chest goes where
			-- the hand goes and stays turned the way the holder turns it (they set CFrame each frame);
			-- only the limbs swing
			align.RigidityEnabled = true
			if arg.Name == "UpperTorso" then
				attachment.Position = Vector3.new(0, arg.Size.Y * 0.4, -arg.Size.Z * 0.3)
			end
			local turn = Instance.new("AlignOrientation")
			turn.Name = "GrabTurn"
			turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
			turn.Attachment0 = attachment
			turn.RigidityEnabled = true
			turn.CFrame = arg.CFrame.Rotation
			turn.Parent = attachment
		end
		attachment.Parent = arg
		d.grab = attachment
		if d.dragging then
			Tutorial.event(player, "grab") -- held by F: next, the kick
		end
		knockDown(d, 0, "Held")
		if d.state == "Held" then
			say(d, pick(GRAB_LINES))
		end
	elseif action == "slam" then
		-- the holder swung it into something: arg is the part that struck, then the speed it lost
		-- and the way it was going (shared/Impact, run on their client, which owns the body)
		-- (or let go of, while it is still theirs to simulate: release)
		local d = typeof(arg) == "Instance" and dummyOf(arg)
		-- and, kicked, the point it struck as they see it (our copy of the body lags behind theirs)
		local lost, dir, at = ...
		if not d or (d.heldBy ~= player and d.looseOwner ~= player) or arg.Parent ~= d.model or not arg:IsA("BasePart")
			or typeof(lost) ~= "number" or lost ~= lost or not finite(dir) or dir.Magnitude < 0.5 then
			return
		end
		if not finite(at) or (at - arg.Position).Magnitude > MAX_STRUCK_GAP then
			at = nil
		end
		landImpact(d, arg, dir.Unit, math.min(lost, MAX_SLAM_LOST), player, at)
	elseif action == "rake" then
		-- held in one hand and raked through the ground (the holder looks down with the mouse held):
		-- scrape() below ploughs a furrow while it is on
		local d = held[player]
		if d and d.dragging then
			d.raking = arg == true
			d.furrowAt = nil
		end
	elseif action == "punt" then
		local d = held[player]
		local torso = d and d.dragging and d.model:FindFirstChild("UpperTorso") :: BasePart?
		local head = headOf(player)
		if not torso or not head or not finite(arg) or arg.Magnitude < 1 or (torso.Position - head.Position).Magnitude > 14 then
			return
		end
		d.punt = { by = player, untilTime = os.clock() + PUNT_TIME }
		fxRemote:FireAllClients("Punt", nil, torso.Position, arg.Unit)
		hit(d, torso, arg.Unit, PUNT_HURT, 0, "blunt", torso.Position, head.Position)
		Tutorial.event(player, "punt")
	elseif action == "release" then
		local d = held[player]
		if d then
			local velocity = finite(arg) and arg or Vector3.zero
			local cap = d.punt and os.clock() < d.punt.untilTime and MAX_PUNT_SPEED or MAX_THROW_SPEED
			if velocity.Magnitude > cap then
				velocity = velocity.Unit * cap
			end
			if velocity.Magnitude > Sandbox.THROWN_SPEED then -- a throw or a punt, not a drop: the STATS page
				Progress.add(player, "StatThrown")
				d.throwFrom = d.model:GetPivot().Position -- how far it got: the loose check in the Heartbeat
			end
			release(d, velocity, player) -- the thrower applies the velocity: it owns the body
		end
	end
end)

-- Toolbox blocks (client/Toolbox.luau): anchored GRID cubes, one folder, capped per player.
local BLOCK_SIZE = 4

local BLOCK_MATERIALS = { Brick = true, Ground = true, Grass = true, Wood = true, Metal = true, Slate = true } -- the map's own (client/Toolbox.luau)
local builtFolder = Instance.new("Folder")
builtFolder.Name = "Built"
builtFolder.Parent = workspace
local blockOverlap = OverlapParams.new()
blockOverlap.FilterType = Enum.RaycastFilterType.Include
blockOverlap.FilterDescendantsInstances = { builtFolder }
Map.breakable(builtFolder) -- blasts break built blocks too (Map.blast)
-- What a player has built, in whole blocks: a hit block leaves smaller pieces behind.
local function blockCount(player: Player): number
	local volume = 0
	for _, block in builtFolder:GetChildren() do
		if block:GetAttribute("Owner") == player.UserId then
			volume += block.Size.X * block.Size.Y * block.Size.Z
		end
	end
	return volume / BLOCK_SIZE ^ 3
end
local function clearBlocks(player: Player)
	for _, block in builtFolder:GetChildren() do
		if block:GetAttribute("Owner") == player.UserId then
			block:Destroy()
		end
	end
end
Players.PlayerRemoving:Connect(clearBlocks)

local MENU_ACTIONS = { map = true, menu = true, spawn = true, clearspawn = true, team = true, freeze = true, revive = true, fall = true, build = true, unbuild = true, clearbuild = true, setting = true } -- slam / kick / dive: the handler below
actionRemote.OnServerEvent:Connect(function(player, action, arg, extra, extra2, extra3)
	local building = action == "build" or action == "unbuild"
	local quick = building or action == "setting" -- clicking + / - on the SETTINGS page fast
	if not MENU_ACTIONS[action] or rateLimited(player, quick and 0.08 or 0.25, if building then "build" elseif quick then "setting" else "action") then
		return
	end
	if action == "map" and player:GetAttribute("Tutorial") then
		arg = "ARENA" -- the tutorial is only on the arena (server/Tutorial)
	end
	if action == "menu" and player:GetAttribute("Map") then -- back to the menu (M): off the map, held still, as before PLAY
		if held[player] then
			release(held[player], Vector3.zero)
		end
		player:SetAttribute("Map", nil) -- Sandbox.inMenu: with nobody in a map, time stops
		local char = player.Character
		if char then
			if char:GetAttribute("Ragdolled") then
				Ragdoll.set(char, false)
			end
			char:PivotTo(MENU_HOLD)
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.AssemblyLinearVelocity = Vector3.zero
				root.Anchored = true
			end
		end
		return
	end
	if action == "map" and SPAWNS[arg] then
		player:SetAttribute("Map", arg)
		-- the maps are far apart and only what is near streams in: load the new one first, or the
		-- character lands in the void
		pcall(player.RequestStreamAroundAsync, player, SPAWNS[arg].Position, 5)
		local char = player.Character
		if char then
			char:PivotTo(SPAWNS[arg])
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = false
			end
		end
		if arg == "ARENA" then
			Tutorial.begin(player) -- only for someone who has not done it
		end
		return
	end
	local head = headOf(player)
	if not head then
		return
	end
	local plus = not Shop.locked(player, "SandboxPlus") -- SANDBOX + (shared/Shop): every kind, higher caps
	if action == "spawn" and extra == "PoliceCar" and finite(arg) and (arg - head.Position).Magnitude < 200 then
		-- one drivable car where the aim is, nose away from the player (server/PoliceCar)
		local flat = (arg - head.Position) * Vector3.new(1, 0, 1)
		local look = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
		local spot = PoliceCar.fit(arg + Vector3.new(0, 1, 0), look) -- no room (a wall, someone): no car
		if spot then
			PoliceCar.spawn(spot, player)
		end
	elseif action == "spawn" and finite(arg) and (arg - head.Position).Magnitude < 200 then
		local kind = typeof(extra) == "string" and KINDS[extra] and extra or nil
		if kind and Shop.SANDBOX.kinds[kind] and not plus then
			return
		end
		local count = math.clamp(math.floor(tonumber(extra3) or 1), 1, Sandbox.MAX_SPAWN) -- the Toolbox's HOW MANY
		for i = 1, count do -- the first on the spot, the rest in a ring round it
			local a = i * 2.4
			local at = arg + (if i == 1 then Vector3.zero else Vector3.new(math.cos(a), 0, math.sin(a)) * 5)
			trimDummies(Shop.SANDBOX.dummies[plus and 2 or 1])
			local d = spawnDummy(CFrame.new(at + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0), nil, kind)
			if plus and d and Sandbox.TEAM_COLORS[extra2] then -- spawned straight into the picked team
				Sandbox.setTeam(d, extra2)
			end
		end
	elseif action == "clearspawn" then -- Toolbox WORLD: every dummy goes, the tutorial's stay, and the cars
		PoliceCar.clear()
		for _, d in table.clone(dummies) do
			if not d.model:GetAttribute("TutorialFor") and not d.heldBy then
				d.model:Destroy()
			end
		end
	elseif action == "team" and plus and typeof(arg) == "Instance" and (extra == 0 or Sandbox.TEAM_COLORS[extra]) then
		local d = dummyOf(arg)
		if d and d.state ~= "Dead" then
			Sandbox.setTeam(d, if extra == 0 then nil else extra)
		end
	elseif action == "freeze" and plus then
		Sandbox.userFrozen = not Sandbox.userFrozen -- the Heartbeat applies it
		workspace:SetAttribute("TimeFrozen", Sandbox.userFrozen)
	elseif action == "build" and finite(arg) and (arg - head.Position).Magnitude < 200 and typeof(extra) == "Color3"
		and BLOCK_MATERIALS[extra2] and (plus or not Shop.SANDBOX.materials[extra2])
		and blockCount(player) < Shop.SANDBOX.blocks[plus and 2 or 1] then
		local size = Vector3.one * (BLOCK_SIZE - 0.1) -- a hair smaller: touching neighbours are not overlaps
		if #workspace:GetPartBoundsInBox(CFrame.new(arg), size, blockOverlap) > 0 then
			return
		end
		local block = Instance.new("Part")
		block.Name, block.Size, block.Position, block.Anchored = "Block", Vector3.one * BLOCK_SIZE, arg, true
		block.Color, block.Material = extra, Enum.Material[extra2]
		block.TopSurface, block.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		block:SetAttribute("Owner", player.UserId)
		block:SetAttribute("Piece", Vector3.one * (BLOCK_SIZE / 4)) -- breaks into bricks like the map's cubes
		block.Parent = builtFolder
	elseif action == "unbuild" and typeof(arg) == "Instance" and arg.Parent == builtFolder
		and (arg.Position - head.Position).Magnitude < 200 then
		local at = arg.Position
		arg:Destroy()
		Map.dropUnbuilt(at, BLOCK_SIZE) -- what it held up comes down
	elseif action == "clearbuild" then
		clearBlocks(player)
	elseif action == "setting" and Progress.SETTINGS[arg] and type(extra) == Progress.SETTINGS[arg] and extra == extra then -- client/Music, saved (not NaN)
		local range = Progress.Settings.RANGE[arg] or { 0, 1 }
		player:SetAttribute(arg, if type(extra) == "number" then math.clamp(math.round(extra * 10) / 10, range[1], range[2]) else extra)
		if arg == "NeverWanted" and extra == true then
			Wanted.clear(player) -- the stars go now, and the hunters with them
		end
		Progress.touch(player)
	elseif action == "revive" then
		local d = typeof(arg) == "Instance" and dummyOf(arg)
		-- the dummy aimed at, else the nearest down one close by: only ever one (it used to raise
		-- everyone within 40 studs, and players took that for the dead getting up on their own)
		if not d then
			local best = 8
			for _, other in dummies do
				local far = (other.model:GetPivot().Position - head.Position).Magnitude
				if (other.state == "Dead" or other.state == "Out cold") and far < best then
					d, best = other, far
				end
			end
		end
		if d then
			revive(d)
		end
	elseif action == "fall" then
		local char = player.Character
		if char then
			Ragdoll.set(char, not char:GetAttribute("Ragdolled"))
		end
	end
end)

-- Attacks ---------------------------------------------------------------------
-- Timings here must match the client timelines in client/Fx.luau.
local UP = Vector3.yAxis
local attackReady = {} -- [Player] = { [id] = os.clock() }
local cooldownOf = {}
for _, attack in Attacks do
	cooldownOf[attack.id] = attack.cd
end

-- The breakable surface under `position` (factory decks count), so blasts land on your floor.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { Map.folder }
local function ground(position: Vector3): Vector3
	local hit = workspace:Raycast(position + UP * 2, -UP * 30, groundParams)
	return hit and hit.Position or Vector3.new(position.X, position.Y - 3, position.Z)
end

local function flat(root: BasePart, dir: Vector3?): CFrame
	local look = (dir or root.CFrame.LookVector) * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.zAxis
	return CFrame.lookAt(root.Position, root.Position + look)
end

-- `kind` says what did it: "fire" chars the skin a little more each time, "blast" (an explosion at
-- `from`) peppers the body with shrapnel and, close in, takes a limb off. Left out = plain force
-- (attacks, machines).
local BLAST_LIMBS = { "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftUpperArm", "RightUpperLeg" }
local function harm(d, damage: number, kind: string?, from: Vector3?)
	damage *= d.armor
	local culprit = Wanted.culprit()
	if culprit ~= nil then
		d.blame, d.blameAt, d.blameWeapon = culprit, os.clock(), Wanted.weapon()
	end
	local dead = d.state == "Dead"
	local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
	if kind == "fire" then
		d.burn += 1
		addInjury(d, d.burn >= 5 and "severe burns" or "burns")
		for _, part in d.model:GetChildren() do
			if part:IsA("BasePart") then
				paint(d, part)
			end
		end
	end
	if not dead then
		local by = blameOf(d)
		d.hp -= damage * Progress.Settings.get(if typeof(by) == "Instance" then by else nil, "DamageScale")
		d.hurtUntil = os.clock() + 2
		d.daze += kind and 8 or 0
		if d.zombie then
			d.hp, d.daze = MAX_HP, 0 -- thrown about, burned, crushed: never killed (only the head does that, hit)
			knockDown(d, 1.5, "Knocked down")
		elseif d.hp <= 0 then
			kill(d, kind == "fire" and "Dead: burned" or kind == "blast" and "Dead: blown up" or "Dead")
		else
			knockDown(d, 4, "Knocked down")
		end
	end
	if kind == "blast" and torso and from then
		local away = torso.Position - from
		local dist = away.Magnitude
		away = dist > 0.1 and away.Unit or UP
		addInjury(d, "blast injuries")
		for _ = 1, 3 do -- shrapnel
			local part = (d.model:FindFirstChild(BLAST_LIMBS[math.random(#BLAST_LIMBS)]) or torso) :: BasePart
			local out = Random.new():NextUnitVector()
			local mark = woundAt(part, part.Position + out * 2, -out, 0.18, WOUND)
			if mark then
				bleed(d, mark, 0.5)
			end
		end
		for _ = 1, if dist < 4 then 2 elseif dist < 7 then 1 else 0 do -- close up: a limb or two goes
			local limb = d.model:FindFirstChild(BLAST_LIMBS[math.random(#BLAST_LIMBS)]) :: BasePart?
			if limb then
				addInjury(d, PARTS[limb.Name].label .. " blown off")
				sever(d, limb, away)
				Body.lost(d, limb)
			end
		end
		fxRemote:FireAllClients("Wound", nil, torso, torso.Position, away, dist < 7 and 3 or 2, nil, "blast")
	end
	express(d)
	syncAttributes(d)
end

-- Damage + launch every dummy in range. `radial` pushes away from the centre.
-- The body part of `d` nearest `position` (what a blow from there lands on first).
local function nearestPart(d, position: Vector3): BasePart?
	local best, bestDist = nil, math.huge
	for name in PARTS do
		local part = d.model:FindFirstChild(name) :: BasePart?
		local dist = part and (part.Position - position).Magnitude
		if dist and dist < bestDist then
			best, bestDist = part, dist
		end
	end
	return best
end

-- Everything within `radius` takes `damage` and is flung. Without a `kind` (the 1-6 attacks, the
-- ground slam and kicks) it is a blunt blow on the part nearest the hit, through hit(): bruises,
-- broken bones and the body chart, the same HP as before. Fire and blasts keep their own wounds (harm).
local function smash(position: Vector3, radius: number, damage: number, push: Vector3, radial: number, kind: string?)
	Monsters.blast(position, radius, damage)
	for _, d in dummies do
		local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
		local offset = torso and torso.Position - position
		if not offset or offset.Magnitude > radius then
			continue
		end
		if d.heldBy or d.looseOwner then -- the server flings it below: it has to own it for that
			release(d, Vector3.zero)
		end
		local part = not kind and damage > 0 and nearestPart(d, position)
		if part then
			harm(d, 0, nil, position) -- knocks it down; the HP goes through hit
			local away = part.Position - position
			hit(d, part, away.Magnitude > 0.1 and away.Unit or UP, damage / ZONES[PARTS[part.Name].zone].damage, 0, "blunt", position + away * 0.9) -- the side facing the blast
		else
			harm(d, damage, kind, position)
		end
		local out = offset * Vector3.new(1, 0, 1)
		out = out.Magnitude > 0.1 and out.Unit or Vector3.zero
		local velocity = push + (out + UP * 0.6) * radial
		if velocity.Magnitude == 0 then
			continue -- damage only (fire)
		end
		local spin = Random.new():NextUnitVector() * 18
		for _, part in d.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = velocity
				part.AssemblyAngularVelocity = spin
			end
		end
	end
end

local ATTACKS = {}

function ATTACKS.Barrage(root: BasePart, aim: CFrame)
	for _ = 1, 12 do
		if not root.Parent then
			return
		end
		local cf = flat(root, aim.LookVector) -- follows the body, keeps the aimed direction
		smash(cf.Position + cf.LookVector * 6, 7, 3, cf.LookVector * 14 + UP * 8, 0)
		task.wait(0.07)
	end
	local cf = flat(root, aim.LookVector)
	local target = ground(cf.Position + cf.LookVector * 8)
	Map.blast(target, 6, 60)
	smash(target, 9, 12, cf.LookVector * 85 + UP * 35, 0)
end

function ATTACKS.Fist(_, cf: CFrame)
	local target = ground(cf.Position + cf.LookVector * 22)
	task.wait(0.5)
	Map.blast(target, 11, 75)
	smash(target, 15, 35, cf.LookVector * 40, 70)
end

function ATTACKS.Flip(_, cf: CFrame)
	local centre = ground(cf.Position + cf.LookVector * 18)
	task.wait(0.45)
	Map.flip(CFrame.lookAt(centre - UP, centre - UP + cf.LookVector), Vector3.new(20, 6, 28), UP * 75 + cf.LookVector * 30)
	smash(centre, 15, 20, cf.LookVector * 30 + UP * 85, 0)
end

function ATTACKS.Slash(_, cf: CFrame)
	for i = 1, 9 do
		local point = ground(cf.Position + cf.LookVector * (4 + 5 * i))
		Map.blast(point, 4.5, 45)
		smash(point, 7, 14, cf.LookVector * 45 + UP * 30, 0)
		task.wait(0.05)
	end
end

function ATTACKS.Nova(_, cf: CFrame)
	local centre = ground(cf.Position)
	task.wait(0.6)
	Map.blast(centre, 17, 60, 9) -- ring crater, caster keeps an island
	smash(centre, 24, 25, Vector3.zero, 75)
end

function ATTACKS.Ult(_, cf: CFrame)
	local target = ground(cf.Position + cf.LookVector * 16)
	task.wait(1.1)
	Map.blast(target, 26, 110, 0)
	smash(target, 36, 100, cf.LookVector * 40, 130)
end

attackRemote.OnServerEvent:Connect(function(player, id, look)
	if Shop.locked(player, "Anime") then -- the abilities are the ANIME ATTACKS pass (shared/Shop)
		return
	end
	Wanted.act(player, "Ability") -- whatever this does to a dummy is on them
	local run = typeof(id) == "string" and ATTACKS[id]
	-- where the player is looking (the camera); anything odd falls back to the body's facing
	if typeof(look) ~= "Vector3" or look ~= look or look.Magnitude < 0.5 or look.Magnitude > 2 then
		look = nil
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not run or not root or char:GetAttribute("Ragdolled") then
		return
	end
	local ready = attackReady[player] or {}
	attackReady[player] = ready
	local now = os.clock()
	if now < (ready[id] or 0) then
		return
	end
	ready[id] = now + cooldownOf[id] - 0.1
	local cf = flat(root, look)
	fxRemote:FireAllClients(id, char, cf)
	run(root, cf)
end)

-- Ground slam: the client reports how fast it hit the ground in slam mode; crater and damage
-- scale with that speed. A kick thrown while sprinting ("kick") hits the ground in front the
-- same way, at a fixed strength, and also knocks things forward. A dive kick ("dive", thrown in
-- the air) is that kick landing where the foot is: on whoever is there, wherever that is, with the
-- crater only when the ground is close under it.
local KICK_POWER = 45 -- crater radius 8.4, centred far enough ahead that you do not run into your own hole
local SLAM_MAX_SPEED = 250 -- ponytail: client-reported speed, clamped; check against server physics if cheating matters
local slamReady = {}
actionRemote.OnServerEvent:Connect(function(player, action, speed)
	Wanted.act(player, "Fists") -- whatever this does to a dummy is on them (a kick, a dive, a slam)
	local dive = action == "dive"
	local kick = action == "kick" or dive
	if not kick and (action ~= "slam" or typeof(speed) ~= "number" or speed ~= speed) then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local now = os.clock()
	if not root or char:GetAttribute("Ragdolled") or now < (slamReady[player] or 0) then
		return
	end
	slamReady[player] = now + (kick and 0.6 or 0.4)
	local s = kick and KICK_POWER or math.clamp(speed, 0, SLAM_MAX_SPEED)
	local radius = 3 + s * 0.12
	local look = flat(root).LookVector
	local ahead = root.Position + look * (dive and 4 or kick and 9 or 0)
	local centre = ground(ahead)
	if not dive or (centre - ahead).Magnitude < 8 then
		fxRemote:FireAllClients("Slam", nil, centre, radius)
		Map.blast(centre, radius, 25 + s * 0.7)
	end
	smash(dive and ahead or centre, radius * 1.4, s * 0.5, kick and look * s or Vector3.zero, 30 + s * 0.6)
end)

-- Weapons ---------------------------------------------------------------------
local weaponById = {}
local inventoryIds = {}
for _, weapon in Weapons do
	weaponById[weapon.id] = weapon
	inventoryIds[weapon.id] = true
	if weapon.slash then weaponById[weapon.slash.id] = weapon.slash end
	if weapon.heavy then weaponById[weapon.heavy.id] = weapon.heavy end
end

local boxingState = {}
local function clearBoxing(player: Player)
	local state = boxingState[player]
	if not state then return end
	boxingState[player] = nil
	if state.character.Parent then
		state.character:SetAttribute("Guarding", nil)
	end
	for _, track in state.tracks do
		track:Stop(0.1)
		track:Destroy()
	end
	state.model:Destroy()
end

equipRemote.OnServerEvent:Connect(function(player, id)
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if typeof(id) ~= "string" or not inventoryIds[id] or not humanoid or humanoid.Health <= 0 then return end
	if not Progress.has(player, id) then return end -- not unlocked yet (shared/Progression)
	if char:GetAttribute("EquippedWeapon") == id then return end
	if rateLimited(player, 0.05, "equip") then return end
	char:SetAttribute("BowDrawAt", nil)
	clearBoxing(player)
	char:SetAttribute("EquippedWeapon", id)
	if id ~= "BoxingGloves" then return end
	local model = BoxingGloves.attach(char)
	if not model then
		char:SetAttribute("EquippedWeapon", nil) -- allow a retry when R15 hands finish replicating
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local state = { character = char, model = model, tracks = {}, nextHand = "right" }
	boxingState[player] = state
	-- Reuse the game's authored upper-body boxing clips. The legs remain free to walk/run.
	for name, animation in { guard = Anims.guard, left = Anims.punch, right = Anims.haymaker, block = Anims.block } do
		if animator and animation.AnimationId ~= "" then
			local ok, track = pcall(animator.LoadAnimation, animator, animation)
			if ok then
				track.Priority = name == "guard" and Enum.AnimationPriority.Action or Enum.AnimationPriority.Action3
				track.Looped = name == "guard"
				state.tracks[name] = track
			end
		end
	end
	if state.tracks.guard then state.tracks.guard:Play(0.15) end
end)

local function explode(position: Vector3, sound: string)
	Sfx.play({ sound, 1, 1 }, position)
	fxRemote:FireAllClients("Boom", nil, position, 9)
	Map.blast(position, 9, 70)
	smash(position, 13, 45, Vector3.zero, 80, "blast")
end

local function ignite(position: Vector3)
	fxRemote:FireAllClients("Fire", nil, position, 8, 5)
	Map.blast(position, 2.5, 30)
	for _ = 1, 10 do
		smash(position, 8, 6, Vector3.zero, 0, "fire")
		task.wait(0.5)
	end
end

-- A tomato: harmless, humiliating. It bursts on the first thing it meets, everyone sees the red
-- splash and the stain it leaves (client Fx "Splat"), a dummy it hits flinches, wipes its face
-- and says something about it; the touchy ones come for you. A player it hits gets red all over
-- the screen ("Splatted", only on that player's client).
local TOMATO_RED = Color3.fromRGB(215, 30, 25)
local TOMATO_LINES = { "My shirt!", "Did you just...", "A TOMATO?!", "Ew! EW!", "You'll pay for that!", "Who does that?!", "It's in my eyes!" }
local function tomato(p: BasePart, char: Model, owner: Player?)
	local done = false
	local function splat(other: BasePart?)
		if done or not p.Parent then
			return
		end
		done = true
		local position, velocity = p.Position, p.AssemblyLinearVelocity
		p:Destroy()
		local dir = velocity.Magnitude > 1 and velocity.Unit or -UP
		fxRemote:FireAllClients("Splat", nil, position, dir, other)
		local d = other and dummyOf(other)
		if d and d.state ~= "Dead" and not d.model:GetAttribute("Ragdolled") then
			reactToHit(d, dir)
			say(d, pick(TOMATO_LINES), "shout")
			local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
			if torso then
				torso.AssemblyLinearVelocity += dir * Vector3.new(6, 0, 6)
			end
			if owner and (d.trait == "Tough" or d.trait == "Berserk" or (d.trait == "Hothead" and math.random() < 0.6)) then
				d.target = owner
			end
			return
		end
		local victim = other and other.Parent and Players:GetPlayerFromCharacter(other.Parent)
		if victim then
			fxRemote:FireClient(victim, "Splatted", nil)
		end
	end
	p.Touched:Connect(function(other)
		if not other:IsDescendantOf(char) and not other:IsDescendantOf(p) then
			splat(other)
		end
	end)
	task.delay(5, splat)
end

local function throw(weapon, char: Model, origin: Vector3, dir: Vector3)
	local p = Instance.new("Part")
	if weapon.id == "Tomato" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 0.85
		p.Color = TOMATO_RED
		p.Material = Enum.Material.SmoothPlastic
	elseif weapon.id == "Grenade" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 1.1
		p.Color = Color3.fromRGB(60, 80, 50)
	else
		p.Size = Vector3.new(0.6, 1.4, 0.6)
		p.Color = Color3.fromRGB(200, 120, 40)
		p.Material = Enum.Material.Glass
		p.Transparency = 0.25
	end
	p.Position = origin + dir * 2.5
	p.Name = weapon.id
	p:SetAttribute("Projectile", true) -- clients swap in the detailed mesh
	p.Parent = workspace
	p:SetNetworkOwner(nil)
	p.AssemblyLinearVelocity = dir * weapon.speed + UP * 12
	p.AssemblyAngularVelocity = Vector3.new(8, 0, 8)
	if weapon.id == "Tomato" then
		local stem = Instance.new("Part") -- welded after the ball is in place, so it rides along
		stem.Size = Vector3.new(0.3, 0.12, 0.3)
		stem.Color = Color3.fromRGB(60, 140, 50)
		stem.CanCollide, stem.CanQuery, stem.CanTouch, stem.Massless = false, false, false, true
		stem.CFrame = p.CFrame * CFrame.new(0, 0.42, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = p, stem
		weld.Parent = stem
		stem.Parent = p
		tomato(p, char, Players:GetPlayerFromCharacter(char))
		return
	end
	if weapon.id == "Grenade" then
		task.wait(2)
		local position = p.Position
		p:Destroy()
		explode(position, Sfx.GRENADE_BOOM)
		return
	end
	-- molotov: breaks on the first thing it touches that is not the thrower
	local by = Players:GetPlayerFromCharacter(char)
	local broken = false
	local function shatter()
		if broken then
			return
		end
		broken = true
		Wanted.act(by, "Molotov") -- the fire is the thrower's doing
		local position = p.Position
		p:Destroy()
		Sfx.play(Sfx.SHATTER, position)
		ignite(position)
	end
	p.Touched:Connect(function(other)
		if not other:IsDescendantOf(char) then
			shatter()
		end
	end)
	task.delay(4, shatter)
end

-- A rocket: a warhead flown straight along the aim (stepped by hand and raycast each frame, so it
-- never tunnels through a thin wall at speed), trailing fire and smoke, that blows up on the
-- first thing it meets or at the end of its range.
local function rocket(weapon, char: Model, origin: Vector3, dir: Vector3, npc: boolean?)
	Wanted.act(if npc then false else Players:GetPlayerFromCharacter(char), "Rocket")
	local p = Instance.new("Part")
	p.Name = "Rocket"
	p.Size = Vector3.new(0.7, 0.7, 2.4)
	p.Color = Color3.fromRGB(80, 96, 64)
	p.Material = Enum.Material.Metal
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	local tip = Instance.new("Part")
	tip.Shape = Enum.PartType.Ball
	tip.Size = Vector3.one * 0.75
	tip.Color = Color3.fromRGB(220, 60, 50)
	tip.Anchored, tip.CanCollide, tip.CanQuery, tip.CanTouch = true, false, false, false
	tip.Parent = p
	local fire = Instance.new("Fire")
	fire.Size, fire.Heat = 4, 0
	fire.Parent = p
	local smoke = Instance.new("Smoke")
	smoke.Size, smoke.RiseVelocity, smoke.Opacity = 2.5, 1, 0.35
	smoke.Color = Color3.fromRGB(200, 196, 190)
	smoke.Parent = p
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char, p }
	local position = origin + dir * 3
	p.CFrame = CFrame.lookAt(position, position + dir)
	p.Parent = workspace
	alarm(nil, origin, "shot", origin)
	local travelled = 0
	while travelled < weapon.range do
		local dt = RunService.Heartbeat:Wait()
		local step = dir * weapon.speed * dt
		local result = workspace:Raycast(position, step, params)
		if result then
			position = result.Position - dir * 0.5
			break
		end
		position += step
		travelled += step.Magnitude
		p.CFrame = CFrame.lookAt(position, position + dir)
		tip.CFrame = p.CFrame * CFrame.new(0, 0, -1.3)
	end
	p:Destroy()
	-- Rocket jump: a player's rocket aimed down into the ground at their own feet is a small pop
	-- (a fraction of the blast, crater and throw) that sends them up and on along where they face.
	-- The client flings itself (it owns its physics): Hazard with `boost`.
	local root = not npc and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local shooter = root and Players:GetPlayerFromCharacter(char)
	local under = root and root.Position - position
	if shooter and under and dir.Y < -0.5 and under.Y > 0 and under.Magnitude < 8 and (under * Vector3.new(1, 0, 1)).Magnitude < 5 then
		local UP_SPEED, FORWARD_SPEED = 85, 55 -- ~18 studs up (a double jump is ~8)
		Sfx.play({ Sfx.RPG_BOOM, 1.25, 0.45 }, position)
		fxRemote:FireAllClients("Boom", nil, position, 2.5)
		Map.blast(position, 2, 20)
		smash(position, 5, 8, Vector3.zero, 20, "blast")
		local face = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		face = face.Magnitude > 0.01 and face.Unit or Vector3.zero
		hazardRemote:FireClient(shooter, face * FORWARD_SPEED + Vector3.yAxis * UP_SPEED, true)
		return
	end
	explode(position, Sfx.RPG_BOOM)
	if npc then -- explode only throws dummies: a soldier's rocket is for the player
		for _, player in Players:GetPlayers() do
			local c = player.Character
			local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			local away = r and r.Position - position
			if away and hum and hum.Health > 0 and away.Magnitude < 13 then
				local push = (away.Magnitude > 0.1 and away.Unit or Vector3.yAxis) * 70 + Vector3.yAxis * 45
				knockPlayer(player, hum, push, 27 * (1 - away.Magnitude / 13) + 5, 2)
			end
		end
	end
end

-- How far the shooter's own idea of their head may sit from ours. Their body is theirs to move, so
-- ours trails it (a stride or two when strafing); shooting from ours left the shot behind the model.
local MAX_ORIGIN_DRIFT = 8 -- ponytail: trusted within this; tighten (or rewind positions) if cheating matters

local AIMED_PELLETS = 0.3 -- an aimed shotgun throws its pellets in this share of the hip cone

-- An aimed swing (aimSwing weapons): swing = (side, up, power) from the client's circle. Power 0..1
-- scales damage 0.6..1.4x and knockback 0.5..1.5x (0.5 = the plain swing); the knockback leans the
-- way the line points. The hit ray itself stays on the crosshair.
local function aimedSwing(weapon, swing, dir: Vector3): (number, number, Vector3)
	if not weapon.aimSwing or typeof(swing) ~= "Vector3" or not finite(swing) then return 1, 1, dir end
	local p = math.clamp(swing.Z, 0, 1)
	local side = Vector3.new(swing.X, swing.Y, 0)
	side = side.Magnitude > 1 and side.Unit or side
	local right = dir:Cross(Vector3.yAxis)
	right = right.Magnitude > 0.01 and right.Unit or Vector3.xAxis
	local up = right:Cross(dir).Unit
	return 0.6 + 0.8 * p, 0.5 + p, (dir + (right * side.X + up * side.Y) * 0.9).Unit
end

-- The bat aimed mostly down hammers the body into the ground like a nail: upright, sunk to the
-- waist..chest (harder = deeper), stuck there a few seconds, then it pops out and flops. Aimed mostly
-- up it launches it. Runs after hit() (the same frame, so the limbs still hold the pose they had),
-- and wins over hit's own shove.
local BURY_SINK, BURY_HOLD = 1.5, 2.5 -- studs and seconds at no power; full power adds as much again (sink) / 2 s
local function batBlow(d, swing)
	if typeof(swing) ~= "Vector3" or not finite(swing) or math.abs(swing.Y) < 0.6 then return end
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local p = math.clamp(swing.Z, 0, 1)
	if d.heldBy or d.looseOwner then -- the server moves it below: it has to own it for that
		release(d, Vector3.zero)
	end
	local parts = {}
	for _, part in d.model:GetDescendants() do
		if part:IsA("BasePart") then table.insert(parts, part) end
	end
	if swing.Y > 0 then
		knockDown(d, 2 + 2 * p, "Knocked down")
		local velocity, spin = Vector3.yAxis * (45 + 55 * p), Random.new():NextUnitVector() * 10
		for _, part in parts do
			part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = velocity, spin
		end
		return
	end
	local hold = BURY_HOLD + 2 * p
	knockDown(d, hold + 1.5, "Knocked down")
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { d.model, dummyFolder }
	local floor = workspace:Raycast(root.Position + Vector3.yAxis * 2, Vector3.yAxis * -10, params)
	local point = floor and floor.Position or root.Position - Vector3.yAxis * 3
	if floor and floor.Instance:IsDescendantOf(Map.folder) then
		Map.blast(point, DIG_RADIUS * (0.6 + 0.4 * p), DIG_POWER * 0.5) -- breakable floor cracks round it
	end
	d.digs = (d.digs or 0) + 1
	fxRemote:FireAllClients("Pound", nil, point, d.digs)
	Sfx.play(Sfx.THUD, point)
	-- stood up straight where it was (facing kept), feet at the floor, then pushed down into it
	local sink = BURY_SINK * (1 + p)
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.zAxis
	local standing = root.Position.Y - point.Y -- the root's height over the floor while standing (~3)
	local upright = CFrame.lookAt(point, point + look) + Vector3.yAxis * (math.clamp(standing, 2.5, 3.5) - sink)
	local move = upright * root.CFrame:Inverse()
	for _, part in parts do
		part.Anchored = true
		part.CFrame = move * part.CFrame
	end
	local token = {}
	d.buried = token -- a second blow while it is stuck restarts the clock
	task.delay(hold, function()
		if d.buried ~= token then return end
		d.buried = nil
		for _, part in parts do
			if part.Parent then
				part.CFrame += Vector3.yAxis * (sink + 0.3) -- out of the hole before physics takes it back
				part.Anchored = false
			end
		end
	end)
end

weaponRemote.OnServerEvent:Connect(function(player, id, dir, from, aimed, swing)
	Wanted.act(player, if typeof(id) == "string" then id else nil) -- whatever this does to a dummy is on them
	local weapon = typeof(id) == "string" and weaponById[id]
	local char = player.Character
	local head = headOf(player)
	if not weapon or not weapon.kind or not head or char:GetAttribute("Ragdolled") then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if char:GetAttribute("EquippedWeapon") ~= (weapon.equipId or id) then return end
	if id == "BoxingGloves" and (char:GetAttribute("EquippedWeapon") ~= id or char:GetAttribute("Guarding")
		or not boxingState[player] or boxingState[player].character ~= char) then return end
	if id == "BoxingHeavy" and (not char:GetAttribute("Guarding")
		or not boxingState[player] or boxingState[player].character ~= char) then return end -- only out of the block
	if weapon.equipId and char:GetAttribute("EquippedWeapon") ~= weapon.equipId then return end
	if not finite(dir) or dir.Magnitude < 0.5 or dir.Magnitude > 2 then
		return
	end
	dir = dir.Unit
	local origin = head.Position
	if typeof(from) == "Vector3" and from == from and (from - origin).Magnitude < MAX_ORIGIN_DRIFT then
		origin = from
	end
	local ready = attackReady[player] or {}
	attackReady[player] = ready
	local now = os.clock()
	local cooldownId = weapon.cooldownGroup or id
	if now < (ready[cooldownId] or 0) then
		return
	end
	local bowCharge = 0
	if weapon.kind == "bow" then
		local drawAt = char:GetAttribute("BowDrawAt")
		char:SetAttribute("BowDrawAt", nil)
		if not drawAt or now - drawAt < 0.08 then return end
		bowCharge = math.clamp((now - drawAt) / 1.1, 0, 1)
	end
	ready[cooldownId] = now + weapon.cd - 0.03
	if id == "BoxingGloves" then
		local state = boxingState[player]
		local side = state.nextHand
		state.nextHand = side == "right" and "left" or "right"
		local previous = state.tracks[state.nextHand]
		if previous then previous:Stop(0.04) end
		local track = state.tracks[side]
		if track then track:Play(0.035, 1, side == "right" and 3.125 or 1.4) end
	elseif id == "BoxingHeavy" then -- the lead (left) hand, slower and heavier than a jab
		local track = boxingState[player].tracks.left
		if track then track:Play(0.05, 1, 1) end
	end
	if weapon.kind == "melee" then
		lastSwing[player] = now
	end
	local sounds = Sfx.WEAPON[id] or {}
	if sounds.fire then
		Sfx.play(sounds.fire, origin, player) -- the shooter heard it already (useWeapon)
	end
	if weapon.kind == "bow" then
		Arrows.fire(origin, dir, weapon.speed * (0.4 + 0.6 * bowCharge), char, function(result, direction)
			Wanted.act(player, "Bow")
			local damage = weapon.dmg * (0.25 + 0.75 * bowCharge)
			if Monsters.damage(result.Instance, damage * 10, direction, player) then return end
			local d = dummyOf(result.Instance)
			if d and result.Instance.Parent then hit(d, result.Instance, direction, damage, weapon.push, "blade", result.Position, origin) end
			fxRemote:FireAllClients("Shot", char, "Knife", result.Position - direction * 0.5, result.Position, true, false)
		end)
		return
	end
	if weapon.kind == "rocket" then -- the warhead is in the air for seconds: the handler runs on in its own thread
		task.spawn(rocket, weapon, char, origin, dir)
		return
	end

	if weapon.kind == "thrown" then
		throw(weapon, char, origin, dir)
		return
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	if weapon.kind == "gun" then -- a gunshot scares whoever hears it, hit or miss
		alarm(nil, origin, "shot", origin)
	end
	-- one ray, or a shotgun's spray of them (each pellet hits on its own)
	local rng = Random.new()
	local cone = (weapon.spread or 0) * (aimed == true and AIMED_PELLETS or 1)
	local dmgScale, pushScale, blowDir = aimedSwing(weapon, swing, dir)
	if id == "KnifeSlash" then
		task.wait(0.09) -- the blade reaches the target during the visible cut
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if player.Character ~= char or not head.Parent or char:GetAttribute("Ragdolled")
			or not humanoid or humanoid.Health <= 0 or char:GetAttribute("EquippedWeapon") ~= "Knife" then return end
		origin = head.Position
	end
	for pellet = 1, weapon.pellets or 1 do
		local aim = dir
		if cone > 0 then
			local right = dir:Cross(Vector3.yAxis)
			right = right.Magnitude > 0.01 and right.Unit or Vector3.xAxis
			local up = right:Cross(dir).Unit
			aim = (dir + right * rng:NextNumber(-1, 1) * cone + up * rng:NextNumber(-1, 1) * cone).Unit
		end
		local result = workspace:Raycast(origin, aim * weapon.range, params)
		local target = result and result.Position or origin + aim * weapon.range
		fxRemote:FireAllClients("Shot", char, id, origin, target, result ~= nil, pellet == 1)
		if not result then
			if sounds.swing then
				Sfx.play(sounds.swing, origin, player) -- the swinger predicted it (useWeapon)
			end
			continue
		end
		if weapon.speed then -- knife flies there first
			task.wait((target - origin).Magnitude / weapon.speed)
		end
		local blow = weapon.aimSwing and blowDir or aim -- which way it knocks things
		if Monsters.damage(result.Instance, (weapon.dmg or 1) * dmgScale * 10, blow, player) then continue end
		local d = dummyOf(result.Instance)
		if d and weapon.kind == "melee" and not weapon.knockdown and tryDodge(d, player) then
			return -- ducked under the swing
		end
		if d then
			if sounds.hit then -- a melee swinger predicted it; a knife only lands after its flight
				Sfx.play(sounds.hit, target, weapon.kind == "melee" and player or nil)
			end
			if result.Instance.Parent then
				hit(d, result.Instance, blow, weapon.dmg and weapon.dmg * dmgScale, weapon.push and weapon.push * pushScale, weapon.hurt, target, origin)
			end
			if id == "Bat" and d.model.Parent then
				batBlow(d, swing)
			end
			if weapon.knockdown and d.state ~= "Dead" then -- the heavy left: down every time it lands
				knockDown(d, weapon.knockdown, "Knocked down")
			end
		elseif result.Instance:IsDescendantOf(gibFolder) then -- a loose limb: just knock it about
			result.Instance:ApplyImpulse(blow * result.Instance.AssemblyMass * weapon.push * pushScale)
		elseif result.Instance.Name == "Pin" and not result.Instance.Anchored then -- bowling pins (Map)
			result.Instance:ApplyImpulse(blow * result.Instance.AssemblyMass * weapon.push * pushScale)
		elseif weapon.chip and pellet == 1 then
			Map.blast(target, weapon.chip, 30)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		clearBoxing(player)
		-- dying or respawning with a dummy in hand used to leave it "Held" for good: hanging in the
		-- air, owned by a client that no longer drives it
		if held[player] then
			release(held[player], Vector3.zero)
		end
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.Died:Connect(function()
			Wanted.clear(player)
			clearBoxing(player)
			if held[player] then
				release(held[player], Vector3.zero)
			end
		end)
		char:WaitForChild("RightAnkle", 5) -- wait for the rig to finish loading
		task.wait()
		Ragdoll.setup(char)
		setGroup(char, "Players")
		char.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				part.CollisionGroup = "Players"
			end
		end)
		-- Ragdoll.setup turns RequiresNeck off, so losing the body to the void no longer kills on its
		-- own: without this, running off the edge leaves the player with no character for good.
		char.ChildRemoved:Connect(function(child)
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if child.Name == "HumanoidRootPart" and humanoid then
				humanoid.Health = 0
			end
		end)
		local map = player:GetAttribute("Map")
		if map then
			pcall(player.RequestStreamAroundAsync, player, SPAWNS[map].Position, 5)
			char:PivotTo(SPAWNS[map])
		else -- still in the menu: off the map, where nobody can hit it and it cannot fall
			char:PivotTo(MENU_HOLD)
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = true
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	clearBoxing(player)
	if held[player] then
		release(held[player], Vector3.zero)
	end
	lastUse[player] = nil
	lastSwing[player] = nil
	attackReady[player] = nil
	for _, d in dummies do -- nobody keeps chasing a player who left
		if d.target == player then
			d.target, d.brain = nil, nil
			d.humanoid.AutoRotate = true
		end
	end
	slamReady[player] = nil
	moveBudget[player] = nil
end)

-- What its personality makes it do while it is up and not busy getting up. Returns true while it
-- is fighting or burying (no wandering then).
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
local SIGHT = 45
Sandbox.TEAM_SIGHT = 120 -- a dummy in a team (Toolbox TEAMS) looks this far for the other teams

local function nearestPlayer(d, root: BasePart): (Player?, BasePart?)
	local best, bestRoot, bestDist = nil, nil, SIGHT
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local other = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and humanoid.Health > 0 and other then
			local dist = (other.Position - root.Position).Magnitude
			sightParams.FilterDescendantsInstances = { dummyFolder, gibFolder, char }
			if dist < bestDist and not workspace:Raycast(root.Position + Vector3.yAxis * 1.5, other.Position - root.Position, sightParams) then
				best, bestRoot, bestDist = player, other, dist
			end
		end
	end
	return best, bestRoot
end

-- The nearest dummy still alive that `d` can see (a Berserk goes for those too).
local function nearestDummy(d, root: BasePart): (any, BasePart?, number)
	local best, bestRoot, bestDist = nil, nil, if d.team then Sandbox.TEAM_SIGHT else SIGHT
	sightParams.FilterDescendantsInstances = { dummyFolder, gibFolder }
	for _, other in dummies do
		local r = other.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dist = r and (r.Position - root.Position).Magnitude or math.huge
		if other ~= d and other.state ~= "Dead" and dist < bestDist
			and not (d.gear == "Bat" and other.gear and not d.team) -- a hooligan picks on the unarmed ones
			and not (d.zombie and other.zombie) -- zombies leave their own alone
			and not (d.team and other.team == d.team) -- teammates (Toolbox TEAMS)
			and not (d.team and not other.team) -- a team fights the other teams only
			and not workspace:Raycast(root.Position + Vector3.yAxis * 1.5, r.Position - root.Position, sightParams) then
			best, bestRoot, bestDist = other, r, dist
		end
	end
	return best, bestRoot, bestDist
end

-- Brain: fighting ----------------------------------------------------------------------------
-- A fight reads like a film brawl instead of a queue of dummies walking into your fists:
--  * at most ENGAGE_SLOTS dummies press one target at a time (the nearest ones); the rest circle
--    it at CIRCLE_RADIUS, strafing and taunting, and step in as soon as a slot frees up;
--  * every blow is telegraphed: a guard stance while it fights, the jab is quick, the haymaker
--    and the kick wind up first (Anims), so a player who watches can get out of the way;
--  * it reads the player's swings: when a punch or a bat comes, a dummy fighting that player may
--    duck aside so the blow misses (tryDodge, asked by punchRemote / weaponRemote), then counters;
--  * a blow that lands on a player throws them, and the heavy ones knock them down (knockPlayer);
--  * morale: every hit takes some, seeing a body drop takes more; under MORALE_BREAK it breaks off
--    and runs (a Berserk never does), and it comes back slowly while nothing hurts it;
--  * stuck on something on the way (a wall, a crate): it jumps, then finds a path round it.
-- `d.target` is a Player, or another dummy's record (Berserk, or hitting back at one).
local PathfindingService = game:GetService("PathfindingService")
local XZ = Vector3.new(1, 0, 1)
local ENGAGE_SLOTS = 2
local CIRCLE_RADIUS = 10
local MORALE_BREAK = 20
local WEAK = 0.35 -- what an unarmed dummy's blows are worth on a hooligan: it fights back, but it is no match
local DODGE = { Berserk = 0.2, Tough = 0.35, Hothead = 0.25, Mourner = 0.12, Coward = 0.3 } -- chance to slip a blow
-- [trait] = weights of { jab, combo (jab, jab, haymaker), haymaker, kick }
local STYLE = {
	Berserk = { 2, 3, 4, 2 },
	Tough = { 3, 2, 2, 3 },
	Hothead = { 4, 2, 2, 1 },
	Mourner = { 5, 1, 1, 1 },
	Coward = { 5, 0, 1, 1 },
}
local STYLE_MOVES = { "jab", "combo", "haymaker", "kick" }
-- at: when it lands (Anims), damage / push / up / down: what it does to a player (down = seconds
-- ragdolled), reach: how close the target must still be when it lands, recover: until the next
-- blow, power: the punch it counts as on a dummy
local MOVES = {
	jab = { anim = Anims.punch, at = Anims.PUNCH_HIT, damage = 6, push = 22, up = 8, down = 0, reach = 5.5, recover = 0.45, power = 0.8 },
	haymaker = { anim = Anims.haymaker, at = Anims.HAYMAKER_HIT, damage = 15, push = 62, up = 30, down = 1.4, reach = 6, recover = 1.0, power = 2,
		shout = { "HRAAH!", "Eat this!", "Night night!" } },
	kick = { anim = Anims.kick, at = Anims.KICK_HIT, damage = 11, push = 52, up = 16, down = 0.9, reach = 6.5, recover = 0.8, power = 1.6,
		shout = { "HYAH!", "Boot!" } },
	-- a hooligan's baseball bat (gear "Bat"): the haymaker's wind-up, longer reach, a harder hit
	bat = { anim = Anims.haymaker, at = Anims.HAYMAKER_HIT, damage = 18, push = 85, up = 28, down = 1.6, reach = 7.5, recover = 1.1, power = 2.5,
		weapon = "Bat", shout = { "Home run!", "Batter up!", "OI!" } },
	-- a cop's baton (gear "Baton", up to 2 stars): quick, lighter than the bat, now and then a knock-down
	baton = { anim = Anims.haymaker, at = Anims.HAYMAKER_HIT, damage = 4.5, push = 38, up = 12, down = 0.7, reach = 6.5, recover = 0.75, power = 0.75,
		weapon = "Baton", shout = { "Stop resisting!", "On the ground!", "You're nicked!", "Drop it!" } },
}
-- a cop's handgun (gear "Handgun"): it keeps its distance and fires at this pace; `spread` is how
-- far off the target's middle a shot may go (studs at the target), so some miss
-- Rifle and Rocket: soldiers (Wanted, 4 stars up); a rocket flies (rocket) instead of a hit ray.
local SOLDIER_LINES = { "Target sighted!", "Contact!", "Engaging!", "Light them up!", "Rocket out!" }
local GUN = {
	-- `aim`: chance a shot is on target, { at NEAR studs or closer, at full range }, straight in between
	Handgun = { damage = 4.5, push = 22, range = 40, keep = 14, every = 0.9, jitter = 0.7, spread = 1.6, aim = { 0.4, 0.15 } },
	Rifle = { damage = 3, push = 14, range = 60, keep = 22, every = 0.22, jitter = 0.12, spread = 2.4, lines = SOLDIER_LINES },
	Rocket = { range = 70, keep = 30, every = 4, jitter = 2, spread = 1.2, lines = SOLDIER_LINES },
}
local DRAWN_AIM = 0.5 -- a cop that drew on someone aiming at it (d.drawn): its hit chance times this
local TAUNT_LINES = { "Come on then!", "Your turn's coming.", "Is that all you've got?", "I'm next, I'm next!", "Get them!" }
local DODGE_LINES = { "Too slow!", "Missed me!", "Ha!", "Nope." }
local BREAK_LINES = { "I'm out!", "Nope, not today!", "This isn't worth it!", "I want my mom!" }
local WHIFF_LINES = { "Hold still!", "Where'd you go?", "Get back here!" }

local playerWake = setmetatable({}, { __mode = "k" }) -- [character] = token of its latest knock-down
-- Hurt a player and throw them. Their client owns their physics, so it does the flinging (Hazard);
-- `down` seconds > 0 also ragdolls them and stands them back up after (the latest knock-down wins).
-- A player with the boxing guard up (right mouse, "Guarding") blocks it: no damage, no knock-down,
-- only a shove and the thud on the gloves; `unblockable` (machines, not attacks) goes through.
function knockPlayer(player: Player, humanoid: Humanoid, velocity: Vector3, damage: number, down: number, unblockable: boolean?)
	local char = player.Character
	if not unblockable and char and char:GetAttribute("Guarding") and not char:GetAttribute("Ragdolled") then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			Sfx.play(Sfx.WEAPON.BoxingGloves.hit, root.Position)
		end
		hazardRemote:FireClient(player, velocity * 0.2)
		return
	end
	if char and char:GetAttribute("God") then
		damage = 0 -- the admin panel's god mode: still thrown about, never hurt
	end
	humanoid:TakeDamage(damage)
	if down > 0 and char and humanoid.Health > 0 then
		Ragdoll.set(char, true)
		local token = {}
		playerWake[char] = token
		task.delay(down, function()
			if playerWake[char] == token and char.Parent and humanoid.Health > 0 then
				Ragdoll.set(char, false)
			end
		end)
	end
	hazardRemote:FireClient(player, velocity)
end

actionRemote.OnServerEvent:Connect(function(player, action, arg)
	if action == "guard" then -- the boxing block: held while the right mouse is (knockPlayer)
		local char = player.Character
		local state = boxingState[player]
		local up = arg == true and state ~= nil and state.character == char and not char:GetAttribute("Ragdolled")
		if char and (char:GetAttribute("Guarding") == true) ~= up then
			char:SetAttribute("Guarding", up or nil)
			local block = state and state.tracks.block
			if block then
				if up then block:Play(0.1) else block:Stop(0.15) end
			end
		end
		return
	end
	if action == "bowCancel" then
		if player.Character then player.Character:SetAttribute("BowDrawAt", nil) end
		return
	end
	if action == "bowDraw" then
		if rateLimited(player, 0.15, "bowDraw") then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not char:GetAttribute("Ragdolled") and char:GetAttribute("EquippedWeapon") == "Bow" then
			if not char:GetAttribute("BowDrawAt") then char:SetAttribute("BowDrawAt", os.clock()) end
		end
		return
	end
end)

local function targetRoot(target): BasePart?
	if typeof(target) == "Instance" then
		local char = (target :: Player).Character
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return target.model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stopFighting(d)
	d.target, d.brain = nil, nil
	if d.drawn then -- drawn on someone aiming at it: holstered again, unless Wanted has it hunting
		d.drawn = nil
		if not d.hunt then
			setGear(d, "Baton")
		end
	end
	d.humanoid.AutoRotate = true
	local guard = d.tracks[Anims.guard]
	if guard and guard.IsPlaying then
		guard:Stop(0.3)
	end
end

-- 1 for the dummy nearest the target among those going for it, 2 for the next, and so on.
local function queuePlace(d, target, at: Vector3, dist: number): number
	local place = 1
	for _, other in dummies do
		if other ~= d and other.target == target and other.brain and other.state == "Awake" then
			local r = other.model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r and ((r.Position - at) * XZ).Magnitude < dist then
				place += 1
			end
		end
	end
	return place
end

local function pickMove(d, b): string
	if d.gear == "Bat" then
		return math.random() < 0.8 and "bat" or "kick"
	end
	if d.gear == "Baton" then
		return math.random() < 0.85 and "baton" or "kick"
	end
	local weights = STYLE[d.trait] or STYLE.Mourner
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = math.random() * total
	for i, w in weights do
		roll -= w
		if roll <= 0 then
			if STYLE_MOVES[i] == "combo" then
				b.queue = { "jab", "haymaker" }
				return "jab"
			end
			return STYLE_MOVES[i]
		end
	end
	return "jab"
end

local function strike(d, b, name: string, target, now: number)
	local move = MOVES[name]
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	b.busyUntil = now + move.at + 0.12
	b.swingAt = now + move.recover + (#b.queue > 0 and 0 or 0.3 + math.random() * 0.6)
	if move.shout and math.random() < 0.45 then
		say(d, pick(move.shout), "shout")
	end
	playTrack(d, move.anim):Play(0.05)
	local sounds = move.weapon and Sfx.WEAPON[move.weapon]
	if sounds then
		Sfx.play(sounds.swing, root.Position)
	end
	b.swingToken = (b.swingToken or 0) + 1
	local swingToken = b.swingToken
	if name ~= "jab" then -- the heavy ones step into it
		root.AssemblyLinearVelocity += root.CFrame.LookVector * XZ * 12
	end
	task.delay(move.at, function()
		if b.swingToken ~= swingToken or d.target ~= target or d.state ~= "Awake"
			or d.model:GetAttribute("Ragdolled") or not root.Parent then
			return
		end
		local other = targetRoot(target)
		if not other then
			return
		end
		local to = other.Position - root.Position
		local flatTo = to * XZ
		local dir = flatTo.Magnitude > 0.1 and flatTo.Unit or root.CFrame.LookVector * XZ
		if flatTo.Magnitude >= move.reach or math.abs(to.Y) > 4.5 or dir:Dot(root.CFrame.LookVector) < 0.2 then
			-- swung at air: a heavy blow that misses throws it off balance, an opening for the player
			if name ~= "jab" then
				b.swingAt = math.max(b.swingAt, os.clock() + 0.7)
				reactToHit(d, -root.CFrame.LookVector)
				if math.random() < 0.4 then
					say(d, pick(WHIFF_LINES))
				end
			end
			return
		end
		if sounds then -- the bat's arc and crack, as when a player swings it
			fxRemote:FireAllClients("Shot", d.model, move.weapon, root.Position, other.Position, true)
			Sfx.play(sounds.hit, other.Position)
		end
		if typeof(target) == "Instance" then
			local char = (target :: Player).Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not char:GetAttribute("Ragdolled") then
				-- a cop hurts and shoves a player but never knocks them down
				local down = if d.model:GetAttribute("Kind") == "Cop" then 0 else move.down
				knockPlayer(target, hum, dir * move.push + Vector3.yAxis * move.up, move.damage, down)
			end
		elseif target.state ~= "Dead" then
			local head = d.model:FindFirstChild("Head") :: BasePart?
			local partName = name == "kick" and "LowerTorso" or (math.random() < 0.3 and "Head" or "UpperTorso")
			local part = target.model:FindFirstChild(partName) or other
			if head and part.Parent then
				local weak = not d.gear and target.gear == "Bat" and WEAK or 1
				hit(target, part, dir, move.power * weak, (20 + move.push * 0.5) * weak, nil, nil, head.Position)
			end
		end
	end)
end

-- Toward the target, round whatever is in the way.
local function chase(d, b, root: BasePart, goal: Vector3, now: number)
	if (root.Position - b.lastPos).Magnitude > 1 then
		b.lastPos, b.movedAt = root.Position, now
	end
	local stuck = now - b.movedAt
	if stuck > 0.8 and now >= b.nextJump then
		b.nextJump = now + 1.2
		d.humanoid.Jump = true
	end
	if stuck > 1.6 and now >= b.pathAt then
		b.pathAt = now + 2.5
		local from = root.Position
		task.spawn(function()
			local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
			local ok = pcall(path.ComputeAsync, path, from, goal)
			if ok and path.Status == Enum.PathStatus.Success and d.brain == b then
				b.path, b.step, b.pathUntil = path:GetWaypoints(), 2, os.clock() + 4
				b.movedAt = os.clock()
			end
		end)
	end
	local path = b.path
	if path and b.step <= #path and now < b.pathUntil then
		local wp = path[b.step]
		if ((wp.Position - root.Position) * XZ).Magnitude < 2.5 then
			b.step += 1
		elseif now >= d.nextLook then
			d.nextLook = now + 0.2
			if wp.Action == Enum.PathWaypointAction.Jump then
				d.humanoid.Jump = true
			end
			walkStraight(d, wp.Position)
		end
		return
	end
	b.path = nil
	if now >= d.nextLook then
		d.nextLook = now + 0.25
		local to = (goal - root.Position) * XZ
		walkTo(d, goal - (to.Magnitude > 0.1 and to.Unit * 2.8 or Vector3.zero))
	end
end

-- A cop's fight (gear "Handgun"): it keeps about COP.keep studs off, squares up (fight turns it)
-- and fires while it can see the target; out of sight or too far, it closes in. Its bullets hit
-- whatever is in the way, as a player's do, so a bystander can catch one.
local function copFight(d, b, root: BasePart, other: BasePart, target, to: Vector3, now: number)
	local COP = GUN[d.gear]
	local NEAR = 10 -- studs: a cop's best aim (GUN aim) from this close in
	local dist = to.Magnitude
	local hand = (d.model:FindFirstChild("RightHand") or root) :: BasePart
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { d.model, gibFolder }
	local targetModel = if typeof(target) == "Instance" then (target :: Player).Character else target.model
	local sight = workspace:Raycast(hand.Position, other.Position - hand.Position, params)
	local clear = targetModel ~= nil and (sight == nil or sight.Instance:IsDescendantOf(targetModel))
	d.speed = pace(d) * 1.5
	if dist > COP.range * 0.7 or not clear then
		chase(d, b, root, other.Position, now)
	elseif now >= d.nextLook then
		d.nextLook = now + 0.3
		-- too close: back off to shooting distance, else plant the feet
		walkStraight(d, if dist < COP.keep * 0.6 and dist > 0.1 then root.Position - to.Unit * 6 else root.Position)
		b.lastPos, b.movedAt = root.Position, now
	end
	local facing = dist > 0.1 and (root.CFrame.LookVector * XZ).Unit:Dot(to.Unit) > 0.85
	if not clear or not facing or dist > COP.range or now < b.swingAt then
		return
	end
	b.swingAt = now + COP.every + math.random() * COP.jitter
	if not b.warned then
		b.warned = true
		say(d, pick(COP.lines or COP_LINES), "shout")
	end
	local origin = hand.Position
	local aimAt = other.Position + Random.new():NextUnitVector() * math.random() * COP.spread
	if COP.aim then
		-- a set hit chance by distance: on target, or wide of it by 3-6 studs (never grazing it by luck)
		local t = math.clamp((dist - NEAR) / (COP.range - NEAR), 0, 1)
		local chance = COP.aim[1] + (COP.aim[2] - COP.aim[1]) * t
		if d.drawn then
			chance *= DRAWN_AIM
		end
		if math.random() < chance then
			aimAt = other.Position
		else
			local wide = Random.new():NextUnitVector() * Vector3.new(1, 0.5, 1)
			aimAt = other.Position + (wide.Magnitude > 0.1 and wide.Unit or Vector3.xAxis) * (3 + math.random() * 3)
		end
	end
	local dir = (aimAt - origin).Unit
	if d.gear == "Rocket" then
		Sfx.play(Sfx.WEAPON.Rocket.fire, origin)
		task.spawn(rocket, weaponById.Rocket, d.model, origin, dir, true)
		return
	end
	local result = workspace:Raycast(origin, dir * COP.range * 1.5, params)
	local landed = result and result.Position or origin + dir * COP.range * 1.5
	Sfx.play(Sfx.WEAPON[d.gear].fire, origin)
	fxRemote:FireAllClients("Shot", d.model, d.gear, origin, landed, result ~= nil, true)
	alarm(nil, origin, "shot", origin)
	if not result then
		return
	end
	local victim = dummyOf(result.Instance)
	local player = Players:GetPlayerFromCharacter(result.Instance:FindFirstAncestorOfClass("Model"))
	local hum = player and player.Character:FindFirstChildOfClass("Humanoid")
	if victim and victim ~= d and result.Instance.Parent then
		hit(victim, result.Instance, dir, 1.5, COP.push, "bullet", result.Position, (d.model:FindFirstChild("Head") or root).Position)
	elseif hum and hum.Health > 0 then
		knockPlayer(player, hum, dir * COP.push + Vector3.yAxis * 6, COP.damage, 0)
	end
end

-- A punch or a swing is coming from `player`: a dummy fighting them may get out of the way.
-- True when it did (the blow misses).
function tryDodge(d, player: Player): boolean
	local b = d.brain
	local now = os.clock()
	if not b or d.target ~= player or d.state ~= "Awake" or d.limp or d.zombie or d.model:GetAttribute("Ragdolled")
		or now < b.nextDodge or now < b.busyUntil or now < d.risingUntil then
		return false
	end
	b.nextDodge = now + 1.6 -- one try per flurry: hold the button and the next one lands
	if math.random() >= (DODGE[d.trait] or 0.2) then
		return false
	end
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local side = root.CFrame.RightVector * (math.random() < 0.5 and -1 or 1)
	root.AssemblyLinearVelocity += side * 30 - root.CFrame.LookVector * 8
	playTrack(d, Anims.dodge):Play(0.05)
	if math.random() < 0.5 then
		say(d, pick(DODGE_LINES))
	end
	b.queue = { "jab" } -- and straight back in with a counter
	b.swingAt = math.min(b.swingAt, now + 0.35)
	return true
end

local function fight(d, root: BasePart, now: number)
	local target = d.target
	local player = typeof(target) == "Instance" and target :: Player or nil
	local victim = not player and target or nil
	local char = player and player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local other = targetRoot(target)
	local alive = if victim then dummies[victim.model] ~= nil and victim.state ~= "Dead" else player.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
	local gone = not (alive and other) or (other.Position - root.Position).Magnitude > (d.hunt and 250 or d.team and Sandbox.TEAM_SIGHT + 10 or 80) -- a hunter (Wanted) or a team chases from far
	local broken = d.trait ~= "Berserk" and not d.team and (d.morale < MORALE_BREAK or (d.trait == "Hothead" and badlyHurt(d)))
	if gone or broken then
		stopFighting(d)
		d.speed = pace(d)
		if not gone then
			say(d, pick(d.morale < MORALE_BREAK and BREAK_LINES or GIVE_UP_LINES))
			flee(d, other.Position, 28)
		end
		return
	end
	local b = d.brain
	if not b then
		b = {
			swingAt = now + 0.3, busyUntil = 0, queue = {}, nextDodge = 0,
			angle = math.random() * math.pi * 2, spin = math.random() < 0.5 and -1 or 1, t = now,
			nextTaunt = now + 2 + math.random() * 3,
			lastPos = root.Position, movedAt = now, nextJump = 0, pathAt = 0, path = nil, step = 0, pathUntil = 0,
		}
		d.brain = b
	end
	local dt = now - b.t
	b.t = now
	local guard = playTrack(d, Anims.guard)
	if not guard.IsPlaying then
		guard:Play(0.25)
	end

	local to = (other.Position - root.Position) * XZ
	local dist = to.Magnitude
	-- close in it squares up to the target; the humanoid alone would turn to where it walks
	-- (sideways while it circles). Turned by spin, not by writing root.CFrame: that write every
	-- frame cancels the humanoid's walk, and it crept along and hopped "unstuck" in place.
	local close = dist < (GUN[d.gear] and GUN[d.gear].range or 16) and dist > 0.5
	d.humanoid.AutoRotate = not close
	if close then
		local look = root.CFrame.LookVector * XZ
		local turn = math.atan2(look:Cross(to).Y, look:Dot(to)) -- signed yaw to the target, radians
		root.AssemblyAngularVelocity = Vector3.new(0, math.clamp(turn * 10, -12, 12), 0)
	end
	if now < b.busyUntil then
		return -- mid-blow
	end

	if GUN[d.gear] then
		copFight(d, b, root, other, target, to, now)
		return
	end

	if queuePlace(d, target, other.Position, dist) > ENGAGE_SLOTS then
		-- waiting its turn: round and round at a distance, now and then the other way, egging on
		b.angle += b.spin * 0.6 * dt
		if math.random() < dt * 0.25 then
			b.spin = -b.spin
		end
		d.speed = pace(d) * 1.1
		if now >= d.nextLook then
			d.nextLook = now + 0.3
			walkTo(d, other.Position + Vector3.new(math.cos(b.angle), 0, math.sin(b.angle)) * CIRCLE_RADIUS)
		end
		if now >= b.nextTaunt and dist < 20 then
			b.nextTaunt = now + 4 + math.random() * 4
			playTrack(d, Anims.taunt):Play(0.1)
			if math.random() < 0.6 then
				say(d, pick(TAUNT_LINES))
			end
		end
		return
	end

	d.speed = pace(d) * 1.8
	if dist > 4 then
		chase(d, b, root, other.Position, now)
	elseif now >= d.nextLook then
		d.nextLook = now + 0.3
		walkStraight(d, root.Position) -- in range: plant the feet
		b.lastPos, b.movedAt = root.Position, now
	end
	if dist < ((d.gear == "Bat" or d.gear == "Baton") and 7 or 5.5) and math.abs(other.Position.Y - root.Position.Y) < 4 and now >= b.swingAt then
		-- only what it still has to hit with (Body.usable): no jab without a left arm, no kick on one leg
		local move = Body.usable(d, table.remove(b.queue, 1) or pickMove(d, b))
		if not move then
			stopFighting(d)
			say(d, pick(GIVE_UP_LINES))
			flee(d, other.Position, 28)
			return
		end
		strike(d, b, move, target, now)
	end
end

-- Zombies (see ZOMBIE at KINDS) ------------------------------------------------------------------
-- The nearest living thing it can see: a player or a dummy that is not a zombie.
function ZOMBIE.prey(d, root: BasePart): (any, BasePart?)
	local player, playerRoot = nearestPlayer(d, root)
	local victim, victimRoot, dist = nearestDummy(d, root)
	if player and playerRoot and (playerRoot.Position - root.Position).Magnitude < dist then
		return player, playerRoot
	end
	return victim, victimRoot
end

-- One blow lands on `target` (a Player or a dummy's record) whose root is `other`.
function ZOMBIE.land(d, target, other: BasePart, dir: Vector3)
	local claw = ZOMBIE.claw
	if typeof(target) == "Instance" then
		local char = (target :: Player).Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and not char:GetAttribute("Ragdolled") then
			knockPlayer(target, hum, dir * claw.push + Vector3.yAxis * claw.up, claw.damage, 0)
		end
	elseif target.state ~= "Dead" then
		local head = d.model:FindFirstChild("Head") :: BasePart?
		local part = target.model:FindFirstChild(math.random() < 0.3 and "Head" or "UpperTorso") or other
		if head and part.Parent then
			hit(target, part, dir, claw.power, 20 + claw.push * 0.5, nil, nil, head.Position)
		end
	end
end

-- Both working arms go up over the head and come down on the prey: the arms-out pose's IK targets
-- (updatePose) move, so the swing is the same arms, straight. A broken arm has no target and stays down.
function ZOMBIE.swing(d, b, target, now: number)
	local claw = ZOMBIE.claw
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
	if not (root and torso) then
		return
	end
	b.busyUntil = now + claw.at + 0.15
	b.swingAt = now + claw.recover + math.random() * 0.5
	b.swingToken = (b.swingToken or 0) + 1
	local token = b.swingToken
	local function arms(at)
		for _, side in { "Left", "Right" } do
			local a = torso:FindFirstChild("ZombieReach" .. side) :: Attachment?
			if a and armFree(d, side) then
				a.Position = at(side == "Left" and -1 or 1)
			end
		end
	end
	arms(ZOMBIE.raised)
	task.delay(claw.at * 0.6, function()
		if b.swingToken == token then
			arms(ZOMBIE.slam)
		end
	end)
	task.delay(claw.at, function()
		if b.swingToken ~= token or d.target ~= target or d.state ~= "Awake" or d.model:GetAttribute("Ragdolled") or not root.Parent then
			return
		end
		local other = targetRoot(target)
		local to = other and other.Position - root.Position
		if not (other and to) or (to * XZ).Magnitude > claw.reach + 0.5 or math.abs(to.Y) > 4.5 then
			return -- it moved away
		end
		ZOMBIE.land(d, target, other, (to * XZ).Magnitude > 0.1 and (to * XZ).Unit or root.CFrame.LookVector)
	end)
	task.delay(claw.at + 0.4, function()
		if torso.Parent then
			arms(ZOMBIE.rest)
		end
	end)
end

-- Behave, for a zombie: after its prey (found again whenever it is lost), slowly, round walls, and a
-- blow whenever it is in reach and has an arm to hit with. False while there is nothing to go for
-- (it wanders, slowly).
function ZOMBIE.fight(d, root: BasePart, now: number): boolean
	local target = d.target
	local other = target and targetRoot(target)
	local alive = false
	if other and typeof(target) == "Instance" then
		local hum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		alive = hum ~= nil and hum.Health > 0
	elseif other then
		alive = dummies[target.model] ~= nil and target.state ~= "Dead"
	end
	if not alive or (other.Position - root.Position).Magnitude > 80 then
		if d.target then
			stopFighting(d)
		end
		if now < d.nextLook then
			return false
		end
		d.nextLook = now + 0.5
		target, other = ZOMBIE.prey(d, root)
		if not (target and other) then
			return false
		end
		d.target = target
		say(d, "") -- a groan (say)
	end
	local b = d.brain
	if not b then
		b = { swingAt = now + 0.5, busyUntil = 0, lastPos = root.Position, movedAt = now, nextJump = 0, pathAt = 0, path = nil, step = 0, pathUntil = 0 }
		d.brain = b
	end
	d.speed = ZOMBIE.speed
	local to = (other.Position - root.Position) * XZ
	local dist = to.Magnitude
	-- close in it turns to face the prey (as fight does: by spin, not by writing the CFrame)
	local close = dist > 0.5 and dist < 8
	d.humanoid.AutoRotate = not close
	if close then
		local look = root.CFrame.LookVector * XZ
		root.AssemblyAngularVelocity = Vector3.new(0, math.clamp(math.atan2(look:Cross(to).Y, look:Dot(to)) * 6, -6, 6), 0)
	end
	if now < b.busyUntil then
		return true
	end
	if dist > 3.5 then
		chase(d, b, root, other.Position, now)
	elseif now >= d.nextLook then
		d.nextLook = now + 0.3
		walkStraight(d, root.Position)
		b.lastPos, b.movedAt = root.Position, now
	end
	if (armFree(d, "Left") or armFree(d, "Right")) and dist < ZOMBIE.claw.reach
		and math.abs(other.Position.Y - root.Position.Y) < 4 and now >= b.swingAt then
		ZOMBIE.swing(d, b, target, now)
	end
	return true
end

-- On the ground for good (grounded): it drags itself at the nearest prey and claws at it in reach.
function ZOMBIE.crawl(d, torso: BasePart, now: number)
	local target, other = ZOMBIE.prey(d, torso)
	if not (target and other) then
		return
	end
	local to = (other.Position - torso.Position) * XZ
	if to.Magnitude > 0.1 then
		torso:ApplyImpulse((to.Unit + Vector3.yAxis * 0.25) * torso.AssemblyMass * ZOMBIE.crawl_push)
	end
	if to.Magnitude < 4 and now >= d.nextSwing and (armFree(d, "Left") or armFree(d, "Right")) then
		d.nextSwing = now + 1.5
		ZOMBIE.land(d, target, other, to.Magnitude > 0.1 and to.Unit or torso.CFrame.LookVector)
	end
end

local function claimable(body): boolean
	local by = body.claimedBy
	return body.state == "Dead" and not body.heldBy and not (by and by.burying == body and dummies[by.model] and by.state ~= "Dead")
end

local function bury(d, root: BasePart, now: number)
	local body = d.burying
	local torso = body.model:FindFirstChild("UpperTorso") or body.model:FindFirstChild("HumanoidRootPart")
	if not dummies[body.model] or body.state ~= "Dead" or body.heldBy or not torso then
		d.burying, d.digUntil = nil, 0 -- revived, carried off or gone
		playTrack(d, Anims.dig):Stop()
		return
	end
	local to = (torso.Position - root.Position) * Vector3.new(1, 0, 1)
	if d.digUntil == 0 then
		if to.Magnitude > 4 then
			if now >= d.nextLook then
				d.nextLook = now + 0.5
				walkTo(d, torso.Position - (to.Magnitude > 0.1 and to.Unit * 3 or Vector3.zero))
			end
			return
		end
		walkStraight(d, root.Position)
		if to.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
		end
		d.digUntil = now + 4
		playTrack(d, Anims.dig):Play(0.3)
	elseif now >= d.digUntil then
		playTrack(d, Anims.dig):Stop(0.3)
		local ground = Vector3.new(torso.Position.X, root.Position.Y - d.humanoid.HipHeight - root.Size.Y / 2, torso.Position.Z)
		local facing = to.Magnitude > 0.1 and to.Unit or Vector3.zAxis
		-- the stone at the far end, the mound toward the digger
		Map.grave(CFrame.lookAt(ground, ground + facing), body.model.Name)
		say(d, `Rest easy, {body.model.Name}.`)
		body.model:Destroy()
		d.burying, d.digUntil = nil, 0
	end
end

-- Body: what losing a limb does to a dummy, and how it carries on without it ------------------------
Body.BEG = { "Please, no more!", "I have a family!", "Stay back! Stay back!", "Okay, you win! You win!", "Not again, please!" }
Body.HURT = { "Somebody... help...", "I can't feel my legs.", "Where's my arm?", "So cold...", "Is anyone there?" }
Body.HELP = { "Hold on, I've got you!", "Don't move, I'm coming!", "Stay with me!" }
Body.THANKS = { "Thank you...", "I owe you one.", "You saved me." }
Body.HELP_TIME = 4 -- s it holds someone's wounds before the bleeding stops

-- An arm it can still hit with: there, hand and all, and not broken.
function Body.armOk(d, side: string): boolean
	if Body.gone(d, side, "Arm") or d.lost[side .. "Hand"] then
		return false
	end
	for _, name in { "UpperArm", "LowerArm" } do
		local p = d.parts[side .. name]
		if p and p.broken then
			return false
		end
	end
	return true
end

-- The blow it means to throw, or the next best one it still can (a jab is the left hand, a
-- haymaker or a swing of its weapon the right, a kick takes two good legs); nil: nothing left.
function Body.usable(d, name: string): string?
	local can = {
		jab = Body.armOk(d, "Left"),
		haymaker = Body.armOk(d, "Right"),
		bat = Body.armOk(d, "Right"),
		baton = Body.armOk(d, "Right"),
		kick = Body.mobility(d) == "walk",
	}
	if can[name] then
		return name
	end
	for _, other in { "jab", "haymaker", "kick" } do
		if can[other] then
			return other
		end
	end
	return nil
end

-- A piece came off (hit, a blast): the shock of it, the weapon it can no longer hold, and no more
-- fighting if it cannot stand or has no arm left to hit with.
function Body.lost(d, part: BasePart)
	local info = PARTS[part.Name]
	if not info or d.state == "Dead" or d.zombie then
		return
	end
	if info.limb == "arm" and info.side == "right" and d.gear then
		setGear(d, nil) -- the hand it held its weapon in is gone
	end
	if part.Name:match("Foot$") then
		d.limpSide = d.limpSide or info.side -- it walks on the stump
	end
	d.morale -= if d.trait == "Tough" or d.trait == "Berserk" then 15 else 45
	d.daze += 25
	local how = Body.mobility(d)
	if d.target and (how == "hop" or how == "crawl" or how == "down" or Body.usable(d, "jab") == nil) then
		stopFighting(d)
	end
	if d.helping then
		Body.stopHelping(d)
	end
end

-- Comes round on the ground with no leg to stand on but an arm to pull with: it lies flat and
-- crawls from now on (Anims.crawl), facing where its head was.
function Body.startCrawl(d, now: number)
	local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
	local headward = torso and torso.CFrame.UpVector * XZ or Vector3.zero
	dropPose(d)
	Ragdoll.set(d.model, false)
	-- re-joined, the body is a new assembly that the nearest player's client takes on its own, and
	-- only the owner can stand a humanoid up: the server takes it back, then stands it up
	setOwner(d.model, nil)
	d.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and headward.Magnitude > 0.3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + headward)
	end
	d.crawling = true
	setState(d, "Awake")
	d.speed = pace(d)
	d.nextWander = now + 4
	playTrack(d, Anims.crawl):Play(0)
	for key in d.limpJoints do -- a broken arm stays limp: it pulls with the other
		Ragdoll.joints(d.model, LIMP[key], true)
	end
	if math.random() < 0.7 then
		say(d, pick(Body.HURT))
	end
end

-- The clip for how it gets about now (Body.mobility), played as fast as it really goes: the
-- limp, the hop on the leg it has left or the crawl. Hopping along it now and then goes over.
function Body.gait(d, rising: boolean, dt: number)
	local how = Body.mobility(d)
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speed = root and (root.AssemblyLinearVelocity * XZ).Magnitude or 0
	local moving = not rising and speed > 0.25
	local function drive(animation: Animation?, on: boolean, full: number)
		if not animation then
			return
		end
		local track = playTrack(d, animation)
		if on then
			if not track.IsPlaying then
				track:Play(0.18)
			end
			track:AdjustSpeed(if moving then math.clamp(speed / full, 0.3, 2) else 0)
		elseif track.IsPlaying then
			track:Stop(0.2)
		end
	end
	for side, animation in Anims.limp do
		drive(animation, how == "limp" and d.limpSide == side and not d.crawling, 3.5)
	end
	local stand = if Body.gone(d, "Left", "Leg") then "right" else "left"
	for side, animation in Anims.hop do
		drive(animation, how == "hop" and side == stand and not d.crawling, Body.HOP_SPEED)
	end
	drive(Anims.crawl, d.crawling == true, Body.CRAWL_SPEED)
	if how == "hop" and moving and math.random() < Body.HOP_FALL * dt then
		say(d, pick(LEG_LINES))
		knockDown(d, 1.2, "Knocked down")
	end
end

function Body.stopHelping(d)
	local other = d.helping
	if other and other.helpedBy == d then
		other.helpedBy = nil
	end
	d.helping, d.helpSince = nil, nil
	if Anims.dig then
		playTrack(d, Anims.dig):Stop(0.3)
	end
end

-- Kneels by `d.helping` and holds its wounds: after HELP_TIME the bleeding stops.
function Body.help(d, root: BasePart, now: number): boolean
	local other = d.helping
	local torso = other.model:FindFirstChild("UpperTorso") :: BasePart?
	if not dummies[other.model] or other.state == "Dead" or other.bleed <= 0 or not torso or other.heldBy then
		if other.state == "Dead" then
			say(d, "No, no, no...")
		end
		Body.stopHelping(d)
		return false
	end
	local to = (torso.Position - root.Position) * XZ
	if to.Magnitude > 3.5 then
		if now >= d.nextLook then
			d.nextLook = now + 0.4
			walkTo(d, torso.Position - (if to.Magnitude > 0.1 then to.Unit * 2.5 else Vector3.zero))
		end
		d.helpSince = nil
		return true
	end
	if not d.helpSince then
		d.helpSince = now
		walkStraight(d, root.Position)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
		if Anims.dig then
			playTrack(d, Anims.dig):Play(0.3)
		end
	elseif now - d.helpSince >= Body.HELP_TIME then
		stopBleeding(other)
		other.morale = math.min(other.baseMorale, other.morale + 30)
		if other.state ~= "Out cold" then
			say(other, pick(Body.THANKS))
		end
		say(d, "There. You'll make it.")
		Body.stopHelping(d)
	end
	return true
end

-- Before anything else it would do (behave): a dummy that cannot stand, or has no arm left, does
-- not fight on; it begs a player who comes near and gets away from them as best it can, and lies
-- moaning otherwise. A whole, calm one may go and tend a badly hurt one that is bleeding (a Mourner
-- always, the brave ones too). True: it is busy with that.
function Body.cope(d, root: BasePart, now: number): boolean
	local how = Body.mobility(d)
	if how == "hop" or how == "crawl" or how == "down" or Body.usable(d, "jab") == nil then
		if d.target then
			stopFighting(d)
		end
		if d.burying then
			d.burying.claimedBy, d.burying = nil, nil
		end
		if d.helping then
			Body.stopHelping(d)
		end
		if now < (d.nextCope or 0) then
			return true
		end
		d.nextCope = now + 0.5
		local _, other = nearestPlayer(d, root)
		local near = other and (other.Position - root.Position) * XZ
		if near and near.Magnitude < 16 then
			if now >= (d.nextBeg or 0) then
				d.nextBeg = now + 4 + math.random() * 3
				say(d, pick(Body.BEG), "shout")
			end
			d.speed = pace(d) * 1.4
			walkTo(d, root.Position - (if near.Magnitude > 0.1 then near.Unit else root.CFrame.LookVector) * 12)
			d.nextWander = now + 6
			return true
		end
		if now >= (d.nextMoan or 0) then
			d.nextMoan = now + 10 + math.random() * 10
			say(d, pick(Body.HURT), "think")
		end
		d.speed = pace(d)
		d.nextWander = math.max(d.nextWander, now + 12) -- like this it does not wander about
		return true
	end
	if d.helping then
		return Body.help(d, root, now)
	end
	if d.target or d.burying or d.calmAt > 0 or d.team or now < (d.nextHelpLook or 0)
		or not (d.trait == "Mourner" or d.brave) then
		return false
	end
	d.nextHelpLook = now + 1.5
	local best, bestDist = nil, 50
	for _, other in dummies do
		local torso = other.model:FindFirstChild("UpperTorso") :: BasePart?
		local dist = torso and (torso.Position - root.Position).Magnitude or math.huge
		if other ~= d and dist < bestDist and other.state ~= "Dead" and not other.zombie and not other.helpedBy
			and not other.heldBy and other.bleed > 0
			and (other.crawling or other.state ~= "Awake" or other.blood < BLOOD_DROWSY or Body.mobility(other) ~= "walk") then
			best, bestDist = other, dist
		end
	end
	if best then
		d.helping, best.helpedBy = best, d
		say(d, pick(Body.HELP), "shout")
		d.speed = pace(d) * 1.5
		return true
	end
	return false
end

local function behave(d, now: number): boolean
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	if d.zombie then
		return ZOMBIE.fight(d, root, now)
	end
	if Body.cope(d, root, now) then -- crippled, or tending someone (Body)
		return true
	end
	if d.target then
		fight(d, root, now)
		return d.target ~= nil
	end
	if d.burying then
		bury(d, root, now)
		return true
	end
	if now < d.nextLook then
		return false
	end
	d.nextLook = now + 0.5
	if d.team then -- Toolbox TEAMS: after the nearest one of another team, whatever its trait
		local enemy = nearestDummy(d, root)
		if enemy then
			d.target = enemy
			say(d, pick(BERSERK_LINES))
			return true
		end
		return false
	end
	if d.trait == "Berserk" or (d.trait == "Coward" and d.calmAt == 0) then
		local player, other = nearestPlayer(d, root)
		if d.trait == "Berserk" then
			-- never starts on a player by itself: players only get hit back
			local victim = nearestDummy(d, root)
			if victim then
				d.target = victim
				say(d, pick(BERSERK_LINES))
				return true
			end
		elseif player and other and (other.Position - root.Position).Magnitude < 30 then
			say(d, pick(COWARD_LINES))
			flee(d, other.Position, 30)
		end
	elseif d.trait == "Mourner" and d.calmAt == 0 then
		local best, bestDist = nil, 60
		for _, body in dummies do
			local torso = body.model:FindFirstChild("UpperTorso") :: BasePart?
			local dist = torso and (torso.Position - root.Position).Magnitude or math.huge
			if body ~= d and dist < bestDist and claimable(body) then
				best, bestDist = body, dist
			end
		end
		if best then
			best.claimedBy, d.burying = d, best
			say(d, pick(MOURN_LINES))
			d.speed = pace(d)
			return true
		end
	end
	return false
end

-- Hitting the ground (or a wall) hard: a body part whose speed falls away fast took a blow from
-- whatever stopped it (shared/Impact). Falls, throws, slams, being launched by an attack and being
-- swung into things while held all land through hit(), as blunt damage on the part that struck: a
-- fall of about 12 studs bruises, 25 or more breaks bones, a long fall or a full-power throw knocks it out.
-- `skip`: the holder who played the thud already.
function landImpact(d, part: BasePart, dir: Vector3, lost: number, skip: Player?, at: Vector3?)
	local now = os.clock()
	if now < d.nextImpact and not (at and d.punt) then -- a kicked body ploughing into a wall always lands
		return
	end
	d.nextImpact = now + 0.3 -- one blow per landing, not one per part
	local power = Impact.power(lost)
	if d.punt and now < d.punt.untilTime then
		-- punted: the first thing it ploughs into takes the kick's full force (see PUNT_POWER), and each of
		-- its first PUNT_HITS hits breaks a little where it struck.
		-- `at`: where the kicker saw it plough into something standing (a wall, a pillar - never the
		-- floor it skids on; our copy of their body lags behind, often still in the air). Any other
		-- landing is just a landing.
		if at then
			d.punt.hits = (d.punt.hits or 0) + 1
			if d.punt.hits == 1 then
				power = math.max(power, 1) * PUNT_POWER
				d.daze += 25
			end
			if d.punt.hits >= PUNT_HITS then
				d.punt = nil
			end
			Map.blast(at, PUNT_BLAST, PUNT_BLAST_POWER, nil, true) -- the wall, not the floor at its foot
		end
	end
	Sfx.play(Sfx.THUD, part.Position, skip)
	-- RAGDOLL DAMAGE off (the host's SETTINGS page): it lands with a thud, nothing hurts or breaks
	if Progress.Settings.get(Progress.Settings.host(), "RagdollDamage") then
		d.daze += (power - 1) * 12 -- a hard landing shakes the whole body, not just the part that hit
		hit(d, part, dir, power, 0, "blunt", part.Position + dir * 0.5) -- the side that struck the ground
	end
	-- the tutorial's dummies (server/Tutorial) die of any blow against a wall, so a kick into one always
	-- pays off: a wall is where the kicker saw it strike something standing (`at`), or anything it hit
	-- going more sideways than down (a landing comes from above)
	if d.state ~= "Dead" and d.model:GetAttribute("TutorialFor") and (at ~= nil or dir.Y > -0.6) then
		kill(d, "Dead")
		syncAttributes(d)
	end
end

local function impacts(d, dt: number)
	local landed = Impact.step(d.impactState, d.model, dt)
	if landed then
		landImpact(d, landed.part, landed.dir, landed.lost)
	end
end

-- Held by the chest (F) and ground into the floor on a sprint: it scrapes along the ground. Dust and a grind where it
-- rubs, and the skin there goes raw (a bruise that builds up, "road rash") - no HP, no broken bones.
local SCRAPE_SPEED = 6 -- studs/s the body has to be going
local SCRAPE_EVERY = 0.2
-- raked (the holder looks down with the mouse held): it ploughs from a slower walk, more often, and
-- the furrow is laid in stretches that join up (Fx "Furrow")
local RAKE_MIN_SPEED = 2
local RAKE_EVERY = 0.1
local scrapeParams = RaycastParams.new()
scrapeParams.FilterType = Enum.RaycastFilterType.Exclude
local function scrape(d, now: number)
	local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
	if not torso or now < (d.nextScrape or 0) then
		return
	end
	-- how fast it goes, from where it was last time: the holder simulates it, and the server's copy of
	-- a client-owned body reads no velocity
	local last, lastAt = d.scrapeFrom, d.scrapeFromAt
	d.scrapeFrom, d.scrapeFromAt = torso.Position, now
	if not last or now - lastAt > 0.5 then
		return
	end
	local velocity = (torso.Position - last) * XZ / math.max(now - lastAt, 1 / 60)
	if velocity.Magnitude < (d.raking and RAKE_MIN_SPEED or SCRAPE_SPEED) then
		return
	end
	scrapeParams.FilterDescendantsInstances = { dummyFolder, gibFolder, d.heldBy and d.heldBy.Character }
	-- pressed down, not just carried (raked, it is held by the collar with its back and legs in the
	-- ground: the chest itself rides higher)
	local floor = workspace:Raycast(torso.Position, -UP * (d.raking and 3.5 or 2), scrapeParams)
	if not floor then
		d.furrowAt = nil
		return -- off the ground (swung up, over a drop): nothing to rub on
	end
	d.nextScrape = now + (d.raking and RAKE_EVERY or SCRAPE_EVERY)
	if d.raking then
		-- raked: one unbroken furrow, each stretch joined to the last (a new one after a gap)
		local from = d.furrowAt
		if not from or (from - floor.Position).Magnitude > 5 then
			from = floor.Position - velocity.Unit * 0.6
		end
		d.furrowAt = floor.Position
		-- the holder lays their own (see furrowStep, client): theirs is where the body really is
		for _, other in Players:GetPlayers() do
			if other ~= d.heldBy then
				fxRemote:FireClient(other, "Furrow", nil, from, floor.Position, floor.Normal, velocity.Magnitude)
			end
		end
	else
		fxRemote:FireAllClients("Scrape", nil, floor.Position, velocity.Unit)
	end
	if now >= (d.nextScrapeSound or 0) then
		d.nextScrapeSound = now + (d.raking and 0.25 or 0.45)
		Sfx.play(Sfx.SCRAPE, floor.Position)
	end
	-- pushed down chest first: the chest and the face take it
	for _, name in { "UpperTorso", "Head" } do
		local part = d.model:FindFirstChild(name) :: BasePart?
		if part then
			local p = d.parts[name]
			if not p then
				p = { trauma = 0, broken = false }
				d.parts[name] = p
			end
			p.rash = (p.rash or 0) + (d.raking and 0.08 or 0.06)
			paint(d, part)
		end
	end
	addInjury(d, "road rash")
end

local nextSync = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	local stop = Sandbox.userFrozen or Sandbox.inMenu() -- TIME STOP
	if stop ~= Sandbox.frozen then
		Sandbox.setFrozen(stop)
	end
	local sync = now >= nextSync -- blood and status tick over on the HUD a few times a second
	if sync then
		nextSync = now + 0.3
	end
	for _, d in dummies do
		-- fell off the map (or the engine took its root / torso at FallenPartsDestroyHeight): the
		-- shell used to stay in the list for good, holding one of the MAX_DUMMIES slots and running
		-- the whole loop below on a body with no root
		local core = d.model:FindFirstChild("UpperTorso") :: BasePart?
		if not core or not d.model:FindFirstChild("HumanoidRootPart") or core.Position.Y < workspace.FallenPartsDestroyHeight + 40 then
			d.model:Destroy()
			continue
		end
		if Sandbox.frozen and (d.frozen or now - d.born > 0.8) then -- TIME STOP: still; a new one lands first
			if not d.frozen then
				Sandbox.freeze(d)
			end
			continue
		end
		if d.dragging and d.heldBy then
			scrape(d, now)
		end
		if d.bleed > 0 then
			-- a hand pressed on the wound halves the loss
			d.blood = math.max(0, d.blood - d.bleed * (d.pressing and 0.5 or 1) * dt)
			if d.blood <= 0 then
				stopBleeding(d) -- nothing left to drip
				d.deadSynced = false -- the HUD still has to show the empty gauge
			end
			if d.state ~= "Dead" and not d.zombie then -- a zombie runs dry and keeps coming
				if d.blood < BLOOD_DEAD then
					kill(d, "Dead: bled out")
				elseif d.blood < BLOOD_OUT and d.state ~= "Out cold" then
					knockDown(d, 6, "Out cold")
				end
			end
		end
		-- a dead body that has stopped bleeding has nothing new to show; hit() and harm() sync it
		if sync and (d.state ~= "Dead" or d.bleed > 0 or not d.deadSynced) then
			d.deadSynced = d.state == "Dead"
			syncAttributes(d)
			express(d)
		end
		local ragdolled = d.model:GetAttribute("Ragdolled")
		if d.looseOwner then -- let go: back to the server once it lies still (no snap), or after LOOSE_MAX
			local since = now - d.looseSince
			if since > LOOSE_MAX or (since > 0.5 and core.AssemblyLinearVelocity.Magnitude < 1.5) or not d.looseOwner.Parent then
				if d.throwFrom and d.looseOwner.Parent then -- landed: the longest throw (STATS)
					local flown = (core.Position - d.throwFrom) * Vector3.new(1, 0, 1)
					Progress.best(d.looseOwner, "StatThrow", math.floor(flown.Magnitude))
				end
				d.throwFrom = nil
				d.looseOwner = nil
				setOwner(d.model, nil)
				d.impactState = Impact.new()
			end
		end
		-- held or just let go: whoever simulates it sees the hits and reports them (grab "slam")
		if d.state ~= "Dead" and not d.heldBy and not d.looseOwner then
			impacts(d, dt)
		end
		if ragdolled then
			local down = grounded(d)
			if down and d.state == "Out cold" and not d.heldBy and now >= d.wakeAt then
				setState(d, "Knocked down") -- comes round, but stays down
			end
			-- no leg to stand on but an arm to pull with: it comes round and crawls (Body)
			if down and not d.zombie and d.state == "Knocked down" and not d.heldBy and not d.looseOwner
				and now >= d.wakeAt and Body.mobility(d) == "crawl" then
				Body.startCrawl(d, now)
				continue
			end
			if not down and not d.heldBy and d.state ~= "Dead" and now >= d.wakeAt then
				-- it gets up the way it lies: face down it pushes up and ends facing where its head
				-- was, on its back it sits up and ends facing its feet
				local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
				local faceUp = torso ~= nil and torso.CFrame.LookVector.Y > 0
				local headward = torso and torso.CFrame.UpVector * Vector3.new(1, 0, 1) or Vector3.zero
				Ragdoll.set(d.model, false)
				setOwner(d.model, nil) -- re-joined it is a new assembly a nearby client would take (Body.startCrawl)
				d.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and headward.Magnitude > 0.3 then
					root.CFrame = CFrame.lookAt(root.Position, root.Position + (faceUp and -headward or headward))
				end
				local hurt = legHurt(d)
				local rate = hurt >= 1 and 0.55 or hurt > 0 and 0.8 or 1 -- bad legs: slower up
				local rise = Anims.LENGTH / rate
				local track = playTrack(d, faceUp and Anims.fromBack or Anims.fromFront)
				track:Play(0)
				track:AdjustSpeed(rate)
				d.risingUntil = now + rise
				setState(d, "Awake")
				d.speed = pace(d)
				d.nextWander = now + rise + 2
				for key in d.limpJoints do -- standing up drives every joint again: broken arms stay limp
					Ragdoll.joints(d.model, LIMP[key], true)
				end
				-- back on its feet: a word about it, and away from whoever did it. On a broken leg it
				-- may stand for a moment before the leg gives and it goes down again.
				local gives = hurt >= 1 and math.random() < 0.6
				if not gives and math.random() < 0.6 then
					say(d, (d.limpJoints.left or d.limpJoints.right) and "I can't feel my arm." or pick(WAKE_LINES))
				end
				task.delay(rise + (gives and 0.2 + math.random() * 0.5 or 0), function()
					if not d.model.Parent or d.state ~= "Awake" or d.model:GetAttribute("Ragdolled") then
						return
					end
					if gives then
						say(d, pick(LEG_LINES))
						knockDown(d, 1, "Knocked down")
					elseif not d.target and d.attackerAt and root and (root.Position - d.attackerAt).Magnitude < 40 then
						flee(d, d.attackerAt, 18)
					end
				end)
			elseif d.state == "Knocked down" and not d.heldBy and now >= d.nextTwitch then
				-- awake on the ground: in pain it writhes, without a leg it drags itself away
				d.nextTwitch = now + 0.25 + math.random() * 0.3
				local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
				if torso and (down or d.daze >= 30) then
					local names = { "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg", "Head" }
					local limb = d.model:FindFirstChild(names[math.random(#names)]) :: BasePart?
					if limb then
						limb:ApplyImpulse(Random.new():NextUnitVector() * limb.AssemblyMass * 22)
					end
					if down and d.zombie then
						ZOMBIE.crawl(d, torso, now)
					elseif down then
						local away = (torso.Position - (d.attackerAt or torso.Position + torso.CFrame.UpVector)) * Vector3.new(1, 0, 1)
						if away.Magnitude > 0.1 then
							torso:ApplyImpulse((away.Unit + Vector3.yAxis * 0.25) * torso.AssemblyMass * 11)
						end
					end
				end
			end
			continue
		end
		local rising = now < d.risingUntil
		if not rising and not d.crawling then -- crawling, the arms pull: no hand to a wound
			updatePose(d)
		end
		if d.calmAt > 0 and now >= d.calmAt then -- done running (flee)
			d.calmAt = 0
			d.speed = pace(d)
		end
		-- how it gets about on what it has left: the limp, the hop or the crawl, each clip's cadence
		-- matched to how fast it really goes (Body.gait)
		if not d.zombie then
			Body.gait(d, rising, dt)
		end
		d.humanoid.WalkSpeed = rising and 0 or d.speed
		for key, untilTime in d.limpJoints do
			if now >= untilTime then
				d.limpJoints[key] = nil
				Ragdoll.joints(d.model, LIMP[key], false)
			end
		end
		d.daze = math.max(0, d.daze - 8 * dt)
		d.morale = math.min(d.baseMorale, d.morale + 2.5 * dt) -- the nerve comes back while nothing hurts
		local busy = not rising and behave(d, now)
		if now >= d.nextWander and not rising and not busy then
			d.nextWander = now + math.random(4, 9)
			local offset = Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
			walkTo(d, d.home + offset)
		end
		if not rising then
			steer(d, now)
		end
		if now >= d.nextTalk then
			d.nextTalk = now + math.random(20, 45)
			say(d, pick(if d.crawling or next(d.lost) or d.bleed > 0 then Body.HURT else IDLE_LINES), "think") -- hurt: no small talk
		end
	end
end)

-- Factory machines and the arena's lava (Map): dummies go through harm() (`kind` "fire" burns), players
-- take Humanoid damage and are flung by their own client (it owns their physics).
local function hazard(model: Model, damage: number, velocity: Vector3, kind: string?)
	local d = dummies[model]
	if d then
		if d.heldBy or d.looseOwner then -- the server flings it: it has to own it
			release(d, Vector3.zero)
		end
		harm(d, damage, kind)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = velocity
			end
		end
		return
	end
	local player = Players:GetPlayerFromCharacter(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not player or humanoid.Health <= 0 then
		return
	end
	knockPlayer(player, humanoid, velocity, damage, 2.5, true)
end
Factory.build(hazard)
for _, spot in Factory.DUMMY_SPOTS do
	spawnDummy(CFrame.new(spot) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
end
Map.build(hazard)
Monsters.start(remotes, knockPlayer)
if CITY_ENABLED then
	City.build()
	for _, spot in City.DUMMY_SPOTS do
		spawnDummy(CFrame.new(spot) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	end
end
if PORT_ENABLED then
	Port.build()
	for _, spot in Port.DUMMY_SPOTS do
		spawnDummy(CFrame.new(spot) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	end
end
for i = 1, 8 do
	local angle = i / 8 * math.pi * 2
	spawnDummy(CFrame.new(math.cos(angle) * 25, 4, math.sin(angle) * 25))
end
Wanted.start({
	dummies = dummies,
	law = function(d) return d.law == true end,
	arm = setGear,
	spawn = function(cf, kind)
		trimDummies()
		return spawnDummy(cf, nil, kind)
	end,
	stop = stopFighting,
	exclude = function()
		local list = { dummyFolder, gibFolder }
		for _, player in Players:GetPlayers() do
			table.insert(list, player.Character)
		end
		return list
	end,
})

-- weapon progression: kill counters, loaded and saved per player (server/Progress)
Progress.start()
-- the admin panel (server/Admin, client/AdminPanel): owner and Studio only
require(script.Admin).start(remotes, {
	dummies = dummies,
	spawn = spawnDummy,
	revive = revive,
	kill = function(d)
		kill(d, "Dead")
		syncAttributes(d)
	end,
	trim = trimDummies,
	wanted = Wanted.set,
	freeze = function(): boolean
		Sandbox.userFrozen = not Sandbox.userFrozen -- the Heartbeat applies it
		workspace:SetAttribute("TimeFrozen", Sandbox.userFrozen)
		return Sandbox.userFrozen
	end,
	berserk = function(d)
		d.trait, d.morale, d.baseMorale = "Berserk", 100, 100
		d.nextLook = 0
	end,
})
ShopServer.start()
-- the first-time tutorial on the arena (server/Tutorial)
Tutorial.start({
-- the host's GRAVITY and GRAVE ZOMBIES settings (server/World)
require(script.World).start({ spawn = spawnDummy, trim = trimDummies, play = playTrack })
	spawn = function(cf: CFrame, kind: string?): Model
		trimDummies()
		-- a Mourner: never hits back (only the Tough, Berserk and Hothead ones do, hit)
		return spawnDummy(cf, nil, kind, "Mourner").model
	end,
	dummies = function(): { Model }
		local list = {}
		for model in dummies do
			table.insert(list, model)
		end
		return list
	end,
	restock = function() -- the arena's dummies as the server puts them at start
		for i = 1, 8 do
			local angle = i / 8 * math.pi * 2
			trimDummies()
			spawnDummy(CFrame.new(math.cos(angle) * 25, 4, math.sin(angle) * 25))
		end
	end,
	done = Progress.touch,
})
