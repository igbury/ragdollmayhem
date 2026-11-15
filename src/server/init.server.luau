local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Attacks = require(ReplicatedStorage.Shared.Attacks)
local Ragdoll = require(ReplicatedStorage.Shared.Ragdoll)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Map = require(script.Map)
local Factory = require(script.Factory)
local Looks = require(script.Looks)
local Anims = require(script.Anims)

local PUNCH_RANGE = 11
local PUNCH_COOLDOWN = 0.2
local GRAB_RANGE = 15
local MAX_THROW_SPEED = 120
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
local IDLE_LINES = { "I could really go for a sandwich.", "Who is winning? I can't tell.", "Back off a bit, will you?", "Nice weather today." }
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
	loop = { [""] = true, sprint = true, wall1 = true, ["wall-1"] = true, cling = true, slide = true, crouch = true, dive = true },
	shot = { roll = true, flip = true, kick = true, jump = true, slam = true, dash = true },
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

local SPAWNS = { ARENA = CFrame.new(0, 5, 0), FACTORY = Factory.SPAWN }
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
-- Every body part keeps its own damage. Blunt hits bruise it (the skin goes lilac) and then break
-- the bone under it, bullets and blades open wounds that bleed, the axe takes limbs off. Blood
-- runs out through the wounds: under BLOOD_DROWSY the dummy slows down, under BLOOD_OUT it
-- passes out, under BLOOD_DEAD it has bled out. The client draws all of it (client/Fx.luau: blood,
-- puddles, the X-ray of the bone that was hit) from the "Wound" event, the "Bleeder" tag and the
-- attributes set in syncAttributes.
local BLOOD_DROWSY, BLOOD_OUT, BLOOD_DEAD = 60, 48, 40
local MAX_BLEED = 12 -- % of blood per second, however many holes there are
local SKIN = Color3.fromRGB(215, 215, 220)
local BRUISE = Color3.fromRGB(190, 172, 226)
local STUMP = Color3.fromRGB(24, 16, 62)
local WOUND = Color3.fromRGB(70, 22, 140)
local TORN = Color3.fromRGB(120, 52, 226) -- an exit wound: raw, the colour of the blood
local CHAR = Color3.fromRGB(58, 50, 52) -- burnt skin
local exitParams = RaycastParams.new()
exitParams.FilterType = Enum.RaycastFilterType.Include

-- [part name] = zone (ZONES), area (what a bruise is called), label (the part itself),
-- breakAt (blunt damage the bone takes), broken (what the break is called)
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

-- A leg gone or both broken: it stays down and drags itself.
local function grounded(d): boolean
	return d.legless or legHurt(d) >= 2
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

-- The cut a blade leaves: a narrow dark strip lying on the skin, at a random slant.
local function gash(on: BasePart, position: Vector3, facing: Vector3, length: number, width: number): Part
	local cut = stump(on, position, facing, width)
	cut.Name = "Wound"
	cut.Shape = Enum.PartType.Block
	cut.Size = Vector3.new(0.1, length, width)
	cut.Color = WOUND
	cut.CFrame *= CFrame.Angles(math.random() * math.pi, 0, 0) -- X is the way it faces: spin about it
	return cut
end

-- A part's skin colour from what it has been through: bruises turn it lilac, fire chars it.
local function paint(d, part: BasePart)
	local info, p = PARTS[part.Name], d.parts[part.Name]
	if not info then
		return
	end
	local skin = SKIN
	if p and p.bruise then
		skin = skin:Lerp(BRUISE, math.min(p.bruise / info.breakAt, 1))
	end
	if d.burn > 0 then
		skin = skin:Lerp(CHAR, math.min(d.burn / 8, 0.85))
	end
	part.Color = skin
	part:SetAttribute("Skin", skin ~= SKIN and skin or nil) -- the client puts this back after an X-ray
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
	part:SetNetworkOwner(nil)
	Debris:AddItem(gib, 60)

	cut = cut or part.Position
	local out = part.Position - cut
	out = out.Magnitude > 0.05 and out.Unit or dir
	stump(part, cut, -out)
	if parent and parent:IsA("BasePart") then
		bleed(d, stump(parent, cut, out), 4.5)
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
	d.risingUntil, d.digUntil = 0, 0
	for _, t in d.tracks do
		t:Stop(0)
	end
	if d.postureKey ~= "" then -- nor a lean: the spine goes back to straight under the ragdoll
		d.postureKey = ""
		Looks.posture(d.model, {})
	end
	Ragdoll.set(d.model, true)
	setOwner(d.model, d.heldBy)
	d.wakeAt = math.max(d.wakeAt, os.clock() + seconds + legHurt(d) * 2) -- bad legs: slower up
	if STATE_RANK[state] >= STATE_RANK[d.state] then
		setState(d, state)
	end
end

local function release(d, velocity: Vector3)
	if d.grab then
		d.grab:Destroy()
		d.grab = nil
	end
	if d.heldBy then
		held[d.heldBy] = nil
		d.heldBy = nil
	end
	setOwner(d.model, nil)
	if velocity.Magnitude > 0 then
		for _, part in d.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.AssemblyLinearVelocity = velocity
			end
		end
	end
	if d.state == "Held" then
		setState(d, "Knocked down")
	end
	d.wakeAt = math.max(d.wakeAt, os.clock() + 2.5)
end

local spawnDummy
local tryDodge -- Brain: fighting (the punch and weapon handlers above it ask it)

local function revive(d)
	if d.heldBy then
		release(d, Vector3.zero)
	end
	if next(d.lost) then -- limbs do not grow back: a whole new body, same name, same spot
		local cf = CFrame.new(d.model:GetPivot().Position + Vector3.yAxis * 3)
		local name = d.model.Name
		d.model:Destroy()
		task.spawn(spawnDummy, cf, name)
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
		if mark.Name == "Wound" then
			mark:Destroy()
		end
	end
	d.speed, d.limpSide, d.risingUntil = 8, nil, 0
	-- a fresh start for the mind too: it used to come back still fighting, still digging a grave,
	-- or bent over a wound it no longer has
	d.target, d.burying, d.digUntil, d.legless = nil, nil, 0, false
	d.morale, d.brain = d.baseMorale, nil
	d.humanoid.AutoRotate = true
	d.impact = nil
	table.clear(d.peaks)
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

local function kill(d, cause: string)
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
	Looks.face(model, face)
	if ragdolled then
		return -- the spine is limp; the lean is put back on the way up
	end
	local pose, key = {}, ""
	local wound = d.wound
	local ribs = d.parts.UpperTorso and d.parts.UpperTorso.broken
	if now < d.scaredUntil and not (wound and d.bleed > 0) then
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

-- Run from `from`, carrying what hurts: a hand stays on a wound that still bleeds, a broken leg
-- drags (the Heartbeat).
local function flee(d, from: Vector3, distance: number)
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local now = os.clock()
	local away = (root.Position - from) * Vector3.new(1, 0, 1)
	away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
	d.speed = pace(d) * 1.7
	d.humanoid:MoveTo(root.Position + away * distance)
	d.nextWander, d.calmAt = now + 4, now + 4
	local wound = d.lastWound
	if d.bleed > 0 and wound and wound.part.Parent == d.model then
		wound.untilTime = math.max(wound.untilTime, now + 4)
		d.wound = wound
	end
end

-- Personalities ------------------------------------------------------------------------------
-- Every dummy is born with one: Berserk goes for the nearest player or dummy on sight, Tough hits back and
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

local JOIN_LINES = { "Hey! Pick on someone your own size!", "Get that one!", "Nobody touches my friend!", "Oh, it's on now!" }
local function alarm(victim, position: Vector3, kind: string, from: Vector3?)
	local now = os.clock()
	for _, d in dummies do
		if d == victim or d.state ~= "Awake" or now < d.nextReact or d.target then
			continue
		end
		local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - position).Magnitude > 45 then
			continue
		end
		d.nextReact = now + math.random(3, 6)
		if kind == "death" then
			d.morale -= 15 -- seeing one of its own drop shakes it
		end
		-- the fighters among them pile in on whoever is beating up one of their own
		local culprit = kind == "hit" and from and playerAt(from)
		if culprit and (d.trait == "Tough" or d.trait == "Berserk" or (d.trait == "Hothead" and math.random() < 0.4)) then
			d.target = culprit
			say(d, pick(JOIN_LINES))
			continue
		end
		d.nextWander, d.calmAt = now + 4, now + 4
		if victim and victim.state ~= "Dead" and kind ~= "shot" and not d.limp and math.random() < 0.2 then
			say(d, "Hang on, I'm coming!")
			d.speed = 12
			d.humanoid:MoveTo(position)
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
	local power = scale or 1
	d.attackerAt = from or d.attackerAt -- the ground hitting it (impacts) is nobody to run from
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
			addInjury(d, info.broken)
			d.limp = d.limp or info.limb == "leg"
			if info.limb == "leg" then
				d.limpSide = d.limpSide or info.side -- the leg it drags (Anims.limp)
			end
			line = part.Name == "UpperTorso" and "Right in the ribs!" or nil
		end
		bone = "broken"
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
					mark = gash(part, point, -dir, power >= 4 and 1 or 0.45, power >= 4 and 0.16 or 0.08)
				else
					mark = stump(part, point, -dir, power >= 4 and 0.3 or 0.2)
					mark.Name = "Wound"
					mark.Color = WOUND
					-- where it comes out: back along the shot from beyond the part, onto the part alone
					exitParams.FilterDescendantsInstances = { part }
					local far = power >= 4 and workspace:Raycast(point + dir * 6, -dir * 6, exitParams)
					if far and (far.Position - point).Magnitude > 0.15 then
						local out = stump(part, far.Position, dir, 0.46)
						out.Name = "Wound"
						out.Color = TORN
						bleed(d, out, 0.8)
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
			if heavy or dead then
				burst = true
			else
				addInjury(d, "head wound")
				bleed(d, hole(), 2)
				d.hp -= 60
				bone = "ok"
			end
		elseif info.limb then
			if heavy then
				addInjury(d, `{info.side} {info.limb == "arm" and "arm" or "femoral"} artery`)
				bleed(d, hole(), 2.4)
			else
				addInjury(d, info.label .. " wound")
				bleed(d, hole(), 0.8)
			end
			if heavy or p.trauma >= 3 then
				addInjury(d, info.label .. " bone")
				breakBone()
			else
				bone = "ok"
			end
		else
			addInjury(d, info.label)
			bleed(d, hole(), heavy and 2 or 1)
			if heavy or p.trauma >= 3 then
				breakBone()
			else
				bone = "ok"
			end
		end
	elseif kind == "blade" then
		local heavy = power >= 4
		blood = heavy and 3 or 1
		-- the axe: a limb comes off at once, the head on a second blow or off a dead body
		if heavy and (info.limb or (info.zone == "Head" and (dead or p.trauma > power))) then
			cutOff = true
		elseif info.zone == "Head" then
			addInjury(d, "head wound")
			bleed(d, hole(), 2)
			d.hp -= 50
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
		p.bruise = (p.bruise or 0) + power
		paint(d, part)
		if p.trauma >= info.breakAt then
			breakBone()
		end
	end

	if not dead then
		d.hurtUntil = os.clock() + 1.6
		d.hp -= zone.damage * power
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
			playTrack(d, Anims.stagger):Play(0.03)
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
			addInjury(d, info.label .. " cut off")
			line = pick(LOSS_LINES[part.Name:match("Hand") and "hand" or part.Name:match("Foot") and "foot" or info.limb] or zone.lines)
			sever(d, part, dir)
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
	local attacker = from and (playerAt(from) or dummyAt(from, d))
	if attacker and not dead and d.state ~= "Dead" and d.target ~= attacker
		and (d.trait == "Tough" or d.trait == "Berserk" or (d.trait == "Hothead" and not badlyHurt(d))) then
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

function spawnDummy(cf: CFrame, as: string?)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	local name = as or pick(NAMES)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.WalkSpeed = 8

	Looks.buildFace(model:FindFirstChild("Head") :: BasePart)

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

	local trait = rollTrait()
	local d = {
		model = model,
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
		speed = 8, -- walk speed it wants; the Heartbeat sets WalkSpeed from it (and the limp)
		limpSide = nil :: string?, -- "left" / "right": the broken leg it drags
		risingUntil = 0, -- getting up (Anims): it does not move or pose until then
		trait = trait, -- its character (Personalities)
		baseMorale = MORALE[trait] or 50, -- how much fight it has in it (Brain: fighting)
		morale = MORALE[trait] or 50,
		brain = nil :: any, -- the fight it is in (Brain: fighting)
		peaks = {}, -- [part name] = { speed, dir }: its recent top speed (impacts)
		impact = nil :: any, -- { lost, part, dir }: a landing still under way (impacts)
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

local function trimDummies()
	local list = {}
	for _, d in dummies do
		table.insert(list, d)
	end
	if #list < MAX_DUMMIES then
		return
	end
	-- remove the oldest dead dummy, else the oldest one
	table.sort(list, function(a, b)
		if (a.state == "Dead") ~= (b.state == "Dead") then
			return a.state == "Dead"
		end
		return a.born < b.born
	end)
	list[1].model:Destroy()
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
		if part.Parent and part.Parent.Name == "Grave" and part:IsDescendantOf(Map.folder) then
			Map.blast(part.Position, 1.5, 25)
		end
		return
	end
	if tryDodge(d, player) then
		return -- it slipped the punch
	end
	hit(d, part, (part.Position - head.Position).Unit, nil, nil, nil, nil, head.Position)
end)

-- A gun pointed at a dummy: the client reports who it is aiming at a few times a second. The
-- dummy stops, begs and holds its hands up (updatePose) for as long as the reports keep coming.
local aimRemote = Instance.new("RemoteEvent")
aimRemote.Name = "Aim"
aimRemote.Parent = remotes
local SCARED_LINES = { "Don't shoot!", "Whoa, easy!", "I give up!", "Not me, not me!" }
local BLEEDING_LINES = { "I'm already bleeding!", "Please, I need a doctor!", "Haven't you done enough?", "It won't stop bleeding!" }
aimRemote.OnServerEvent:Connect(function(player, part)
	if rateLimited(player, 0.2, "aim") then -- the client sends one every 0.4 s
		return
	end
	local d = typeof(part) == "Instance" and dummyOf(part)
	local head = headOf(player)
	if not d or not head or d.state ~= "Awake" or d.target or (d.model:GetPivot().Position - head.Position).Magnitude > 60 then
		return
	end
	local now = os.clock()
	local wound = d.lastWound
	local bleeding = d.bleed > 0 and wound and wound.part.Parent == d.model
	if bleeding then -- hurt comes first: it presses on the wound instead of putting its hands up
		wound.untilTime = math.max(wound.untilTime, now + 1.5)
		d.wound = wound
	end
	if now >= d.scaredUntil then
		say(d, pick(bleeding and BLEEDING_LINES or SCARED_LINES))
		d.humanoid:MoveTo(d.model:GetPivot().Position) -- stand still
		local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local to = (head.Position - d.model:GetPivot().Position) * Vector3.new(1, 0, 1)
		if root and to.Magnitude > 1 then -- turns to face the gun
			root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
		end
	end
	d.scaredUntil = now + 1.5
	d.nextWander = math.max(d.nextWander, now + 2.5)
end)

grabRemote.OnServerEvent:Connect(function(player, action, arg)
	if action == "grab" then
		if typeof(arg) ~= "Instance" or not arg:IsA("BasePart") or held[player] then
			return
		end
		local d = dummyOf(arg)
		local head = headOf(player)
		if not d or d.heldBy or not head or (arg.Position - head.Position).Magnitude > GRAB_RANGE then
			return
		end
		d.heldBy = player
		held[player] = d
		local attachment = Instance.new("Attachment")
		attachment.Name = "GrabAttachment"
		local align = Instance.new("AlignPosition")
		align.Name = "GrabAlign"
		align.Mode = Enum.PositionAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.Position = arg.Position
		align.MaxForce = 40000
		align.MaxVelocity = 90
		align.Responsiveness = 40
		align.Parent = attachment
		attachment.Parent = arg
		d.grab = attachment
		knockDown(d, 0, "Held")
		if d.state == "Held" then
			say(d, pick(GRAB_LINES))
		end
	elseif action == "release" then
		local d = held[player]
		if d then
			local velocity = finite(arg) and arg or Vector3.zero
			if velocity.Magnitude > MAX_THROW_SPEED then
				velocity = velocity.Unit * MAX_THROW_SPEED
			end
			release(d, velocity)
		end
	end
end)

local MENU_ACTIONS = { map = true, spawn = true, revive = true, fall = true } -- slam / kick / dive: the handler below
actionRemote.OnServerEvent:Connect(function(player, action, arg)
	if not MENU_ACTIONS[action] or rateLimited(player, 0.25, "action") then
		return
	end
	if action == "map" and SPAWNS[arg] then
		player:SetAttribute("Map", arg)
		-- the maps are far apart and only what is near streams in: load the new one first, or the
		-- character lands in the void
		pcall(player.RequestStreamAroundAsync, player, SPAWNS[arg].Position, 5)
		if player.Character then
			player.Character:PivotTo(SPAWNS[arg])
		end
		return
	end
	local head = headOf(player)
	if not head then
		return
	end
	if action == "spawn" and finite(arg) and (arg - head.Position).Magnitude < 200 then
		trimDummies()
		spawnDummy(CFrame.new(arg + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	elseif action == "revive" then
		local d = typeof(arg) == "Instance" and dummyOf(arg)
		if d then
			revive(d)
		else
			for _, other in dummies do
				if (other.model:GetPivot().Position - head.Position).Magnitude < 40 then
					revive(other)
				end
			end
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

local function flat(root: BasePart): CFrame
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.zAxis
	return CFrame.lookAt(root.Position, root.Position + look)
end

-- `kind` says what did it: "fire" chars the skin a little more each time, "blast" (an explosion at
-- `from`) peppers the body with shrapnel and, close in, takes a limb off. Left out = plain force
-- (attacks, machines).
local BLAST_LIMBS = { "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftUpperArm", "RightUpperLeg" }
local function harm(d, damage: number, kind: string?, from: Vector3?)
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
		d.hp -= damage
		d.hurtUntil = os.clock() + 2
		d.daze += kind and 8 or 0
		if d.hp <= 0 then
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
			local mark = stump(part, part.Position + out * math.min(part.Size.X, part.Size.Z) * 0.45, out, 0.18)
			mark.Name = "Wound"
			mark.Color = WOUND
			bleed(d, mark, 0.5)
		end
		if dist < 7 then
			local limb = d.model:FindFirstChild(BLAST_LIMBS[math.random(#BLAST_LIMBS)]) :: BasePart?
			if limb then
				addInjury(d, PARTS[limb.Name].label .. " blown off")
				sever(d, limb, away)
			end
		end
		fxRemote:FireAllClients("Wound", nil, torso, torso.Position, away, dist < 7 and 3 or 2, nil, "blast")
	end
	express(d)
	syncAttributes(d)
end

-- Damage + launch every dummy in range. `radial` pushes away from the centre.
local function smash(position: Vector3, radius: number, damage: number, push: Vector3, radial: number, kind: string?)
	for _, d in dummies do
		local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
		local offset = torso and torso.Position - position
		if not offset or offset.Magnitude > radius then
			continue
		end
		if d.heldBy then
			release(d, Vector3.zero)
		end
		harm(d, damage, kind, position)
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

function ATTACKS.Barrage(root: BasePart)
	for _ = 1, 12 do
		if not root.Parent then
			return
		end
		local cf = flat(root)
		smash(cf.Position + cf.LookVector * 6, 7, 3, cf.LookVector * 14 + UP * 8, 0)
		task.wait(0.07)
	end
	local cf = flat(root)
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

attackRemote.OnServerEvent:Connect(function(player, id)
	local run = typeof(id) == "string" and ATTACKS[id]
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
	local cf = flat(root)
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
for _, weapon in Weapons do
	weaponById[weapon.id] = weapon
end

local function explode(position: Vector3)
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
			playTrack(d, Anims.stagger):Play(0.05)
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
		explode(position)
		return
	end
	-- molotov: breaks on the first thing it touches that is not the thrower
	local broken = false
	local function shatter()
		if broken then
			return
		end
		broken = true
		local position = p.Position
		p:Destroy()
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
local function rocket(weapon, char: Model, origin: Vector3, dir: Vector3)
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
	explode(position)
end

weaponRemote.OnServerEvent:Connect(function(player, id, dir)
	local weapon = typeof(id) == "string" and weaponById[id]
	local char = player.Character
	local head = headOf(player)
	if not weapon or not weapon.kind or not head or char:GetAttribute("Ragdolled") then
		return
	end
	if typeof(dir) ~= "Vector3" or dir ~= dir or dir.Magnitude < 0.5 or dir.Magnitude > 2 then
		return
	end
	dir = dir.Unit
	local ready = attackReady[player] or {}
	attackReady[player] = ready
	local now = os.clock()
	if now < (ready[id] or 0) then
		return
	end
	ready[id] = now + weapon.cd - 0.03
	if weapon.kind == "melee" then
		lastSwing[player] = now
	end
	if weapon.kind == "rocket" then -- the warhead is in the air for seconds: the handler runs on in its own thread
		task.spawn(rocket, weapon, char, head.Position, dir)
		return
	end

	if weapon.kind == "thrown" then
		throw(weapon, char, head.Position, dir)
		return
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	local origin = head.Position
	if weapon.kind == "gun" then -- a gunshot scares whoever hears it, hit or miss
		alarm(nil, origin, "shot", origin)
	end
	-- one ray, or a shotgun's spray of them (each pellet hits on its own)
	local rng = Random.new()
	for pellet = 1, weapon.pellets or 1 do
		local aim = dir
		if weapon.spread then
			local right = dir:Cross(Vector3.yAxis)
			right = right.Magnitude > 0.01 and right.Unit or Vector3.xAxis
			local up = right:Cross(dir).Unit
			aim = (dir + right * rng:NextNumber(-1, 1) * weapon.spread + up * rng:NextNumber(-1, 1) * weapon.spread).Unit
		end
		local result = workspace:Raycast(origin, aim * weapon.range, params)
		local target = result and result.Position or origin + aim * weapon.range
		fxRemote:FireAllClients("Shot", char, id, origin, target, result ~= nil)
		if not result then
			continue
		end
		if weapon.speed then -- knife flies there first
			task.wait((target - origin).Magnitude / weapon.speed)
		end
		local d = dummyOf(result.Instance)
		if d and weapon.kind == "melee" and tryDodge(d, player) then
			return -- ducked under the swing
		end
		if d then
			if result.Instance.Parent then
				hit(d, result.Instance, aim, weapon.dmg, weapon.push, weapon.hurt, target, origin)
			end
		elseif result.Instance:IsDescendantOf(gibFolder) then -- a loose limb: just knock it about
			result.Instance:ApplyImpulse(aim * result.Instance.AssemblyMass * weapon.push)
		elseif result.Instance.Name == "Pin" and not result.Instance.Anchored then -- bowling pins (Map)
			result.Instance:ApplyImpulse(aim * result.Instance.AssemblyMass * weapon.push)
		elseif weapon.chip and pellet == 1 then
			Map.blast(target, weapon.chip, 30)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		-- dying or respawning with a dummy in hand used to leave it "Held" for good: hanging in the
		-- air, owned by a client that no longer drives it
		if held[player] then
			release(held[player], Vector3.zero)
		end
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.Died:Connect(function()
			if held[player] then
				release(held[player], Vector3.zero)
			end
		end)
		char:WaitForChild("RightAnkle", 5) -- wait for the rig to finish loading
		task.wait()
		Ragdoll.setup(char)
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
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
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
	local best, bestRoot, bestDist = nil, nil, SIGHT
	sightParams.FilterDescendantsInstances = { dummyFolder, gibFolder }
	for _, other in dummies do
		local r = other.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dist = r and (r.Position - root.Position).Magnitude or math.huge
		if other ~= d and other.state ~= "Dead" and dist < bestDist
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
}
local TAUNT_LINES = { "Come on then!", "Your turn's coming.", "Is that all you've got?", "I'm next, I'm next!", "Get them!" }
local DODGE_LINES = { "Too slow!", "Missed me!", "Ha!", "Nope." }
local BREAK_LINES = { "I'm out!", "Nope, not today!", "This isn't worth it!", "I want my mom!" }
local WHIFF_LINES = { "Hold still!", "Where'd you go?", "Get back here!" }

local playerWake = setmetatable({}, { __mode = "k" }) -- [character] = token of its latest knock-down
-- Hurt a player and throw them. Their client owns their physics, so it does the flinging (Hazard);
-- `down` seconds > 0 also ragdolls them and stands them back up after (the latest knock-down wins).
local function knockPlayer(player: Player, humanoid: Humanoid, velocity: Vector3, damage: number, down: number)
	humanoid:TakeDamage(damage)
	local char = player.Character
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

local function targetRoot(target): BasePart?
	if typeof(target) == "Instance" then
		local char = (target :: Player).Character
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	return target.model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stopFighting(d)
	d.target, d.brain = nil, nil
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
	if name ~= "jab" then -- the heavy ones step into it
		root.AssemblyLinearVelocity += root.CFrame.LookVector * XZ * 12
	end
	task.delay(move.at, function()
		if d.target ~= target or d.state ~= "Awake" or d.model:GetAttribute("Ragdolled") or not root.Parent then
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
				playTrack(d, Anims.stagger):Play(0.05)
				if math.random() < 0.4 then
					say(d, pick(WHIFF_LINES))
				end
			end
			return
		end
		if typeof(target) == "Instance" then
			local char = (target :: Player).Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not char:GetAttribute("Ragdolled") then
				knockPlayer(target, hum, dir * move.push + Vector3.yAxis * move.up, move.damage, move.down)
			end
		elseif target.state ~= "Dead" then
			local head = d.model:FindFirstChild("Head") :: BasePart?
			local partName = name == "kick" and "LowerTorso" or (math.random() < 0.3 and "Head" or "UpperTorso")
			local part = target.model:FindFirstChild(partName) or other
			if head and part.Parent then
				hit(target, part, dir, move.power, 20 + move.push * 0.5, nil, nil, head.Position)
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
			d.humanoid:MoveTo(wp.Position)
		end
		return
	end
	b.path = nil
	if now >= d.nextLook then
		d.nextLook = now + 0.25
		local to = (goal - root.Position) * XZ
		d.humanoid:MoveTo(goal - (to.Magnitude > 0.1 and to.Unit * 2.8 or Vector3.zero))
	end
end

-- A punch or a swing is coming from `player`: a dummy fighting them may get out of the way.
-- True when it did (the blow misses).
function tryDodge(d, player: Player): boolean
	local b = d.brain
	local now = os.clock()
	if not b or d.target ~= player or d.state ~= "Awake" or d.limp or d.model:GetAttribute("Ragdolled")
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
	local gone = not (alive and other) or (other.Position - root.Position).Magnitude > 80
	local broken = d.trait ~= "Berserk" and (d.morale < MORALE_BREAK or (d.trait == "Hothead" and badlyHurt(d)))
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
	-- (sideways while it circles)
	local close = dist < 16 and dist > 0.5
	d.humanoid.AutoRotate = not close
	if close then
		local look = (root.CFrame.LookVector * XZ):Lerp(to.Unit, math.min(dt * 10, 1))
		if look.Magnitude > 0.05 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
		end
	end
	if now < b.busyUntil then
		return -- mid-blow
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
			d.humanoid:MoveTo(other.Position + Vector3.new(math.cos(b.angle), 0, math.sin(b.angle)) * CIRCLE_RADIUS)
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
		d.humanoid:MoveTo(root.Position) -- in range: plant the feet
		b.lastPos, b.movedAt = root.Position, now
	end
	if dist < 5.5 and math.abs(other.Position.Y - root.Position.Y) < 4 and now >= b.swingAt then
		strike(d, b, table.remove(b.queue, 1) or pickMove(d, b), target, now)
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
				d.humanoid:MoveTo(torso.Position - (to.Magnitude > 0.1 and to.Unit * 3 or Vector3.zero))
			end
			return
		end
		d.humanoid:MoveTo(root.Position)
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

local function behave(d, now: number): boolean
	local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
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
	if d.trait == "Berserk" or (d.trait == "Coward" and d.calmAt == 0) then
		local player, other = nearestPlayer(d, root)
		if d.trait == "Berserk" then
			local victim, _, victimDist = nearestDummy(d, root)
			local target = if victim and (not other or victimDist < (other.Position - root.Position).Magnitude) then victim else player
			if target then
				d.target = target
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
-- whatever stopped it. Falls, throws, slams and being launched by an attack all land through
-- hit(), as blunt damage on the part that struck: a fall of about 12 studs bruises, 25 or more
-- breaks bones, a long fall or a full-power throw knocks it out. Each part keeps its recent top speed, which
-- sinks at IMPACT_FADE: a landing spread over a few frames still counts in full, slowing down by
-- sliding or walking never does.
local IMPACT_PARTS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local IMPACT_SPEED = 50 -- studs/s lost before it hurts (calibration knob)
local IMPACT_PER_POWER = 15 -- every this many more studs/s is one more punch's worth
local IMPACT_FADE = 400 -- studs/s² the remembered top speed sinks by (gravity is 196)
local function impacts(d, now: number, dt: number)
	local peaks = d.peaks
	local worst, worstLost, worstPart, worstDir = -math.huge, 0, nil, nil
	for _, name in IMPACT_PARTS do
		local part = d.model:FindFirstChild(name) :: BasePart?
		if not part then
			continue
		end
		local v = part.AssemblyLinearVelocity
		local speed = v.Magnitude
		local peak = peaks[name]
		if not peak then
			peak = { speed = 0, dir = Vector3.yAxis, set = false } -- one table per part, reused every frame
			peaks[name] = peak
		end
		if not peak.set or speed >= peak.speed - IMPACT_FADE * dt then
			peak.speed, peak.dir, peak.set = speed, speed > 0.1 and v.Unit or Vector3.yAxis, true
			continue
		end
		peak.speed -= IMPACT_FADE * dt
		local lost = peak.speed - v.Magnitude
		-- the whole body landing at once (standing): the lowest part is the one that hit
		local score = lost - part.Position.Y * 0.05
		if lost > IMPACT_SPEED and score > worst then
			worst, worstLost, worstPart, worstDir = score, lost, part, peak.dir
		end
	end
	-- a landing takes a few frames: wait until the speed has stopped falling away, then count it all
	local pending = d.impact
	if worstPart and (not pending or worstLost > pending.lost) then
		d.impact = { lost = worstLost, part = worstPart, dir = worstDir }
	elseif pending then
		d.impact = nil
		for _, peak in peaks do
			peak.set = false
		end
		if now >= d.nextImpact and pending.part.Parent == d.model then
			d.nextImpact = now + 0.3 -- one blow per landing, not one per part
			local power = 0.5 + (pending.lost - IMPACT_SPEED) / IMPACT_PER_POWER
			d.daze += (power - 1) * 12 -- a hard landing shakes the whole body, not just the part that hit
			hit(d, pending.part, pending.dir, power, 0, "blunt", pending.part.Position)
		end
	end
end

local nextSync = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
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
		if d.bleed > 0 then
			-- a hand pressed on the wound halves the loss
			d.blood = math.max(0, d.blood - d.bleed * (d.pressing and 0.5 or 1) * dt)
			if d.blood <= 0 then
				stopBleeding(d) -- nothing left to drip
				d.deadSynced = false -- the HUD still has to show the empty gauge
			end
			if d.state ~= "Dead" then
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
		if d.state ~= "Dead" then
			impacts(d, now, dt)
		end
		if ragdolled then
			local down = grounded(d)
			if down and d.state == "Out cold" and not d.heldBy and now >= d.wakeAt then
				setState(d, "Knocked down") -- comes round, but stays down
			end
			if not down and not d.heldBy and d.state ~= "Dead" and now >= d.wakeAt then
				-- it gets up the way it lies: face down it pushes up and ends facing where its head
				-- was, on its back it sits up and ends facing its feet
				local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
				local faceUp = torso ~= nil and torso.CFrame.LookVector.Y > 0
				local headward = torso and torso.CFrame.UpVector * Vector3.new(1, 0, 1) or Vector3.zero
				Ragdoll.set(d.model, false)
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
					if down then
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
		if not rising then
			updatePose(d)
		end
		if d.calmAt > 0 and now >= d.calmAt then -- done running (flee)
			d.calmAt = 0
			d.speed = pace(d)
		end
		-- a broken leg: held stiff, and every step on it a hitch
		if d.limpSide then
			local limpTrack = playTrack(d, Anims.limp[d.limpSide])
			if not limpTrack.IsPlaying then
				limpTrack:Play()
			end
		end
		d.humanoid.WalkSpeed = rising and 0 or d.speed * (d.limpSide and 0.35 + 0.65 * math.abs(math.sin(now * 4)) or 1)
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
			d.humanoid:MoveTo(d.home + offset)
		end
		if now >= d.nextTalk then
			d.nextTalk = now + math.random(20, 45)
			say(d, pick(IDLE_LINES), "think")
		end
	end
end)

-- Factory machines: dummies go through harm(), players take Humanoid damage and are flung by
-- their own client (it owns their physics).
Factory.build(function(model, damage, velocity)
	local d = dummies[model]
	if d then
		if d.heldBy then
			release(d, Vector3.zero)
		end
		harm(d, damage)
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
	knockPlayer(player, humanoid, velocity, damage, 2.5)
end)
for _, spot in Factory.DUMMY_SPOTS do
	spawnDummy(CFrame.new(spot) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
end
Map.build()
for i = 1, 8 do
	local angle = i / 8 * math.pi * 2
	spawnDummy(CFrame.new(math.cos(angle) * 25, 4, math.sin(angle) * 25))
end
