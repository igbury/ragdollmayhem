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
	shot = { roll = true, flip = true, kick = true, jump = true, slam = true },
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
local lastUse = {} -- [Player] = os.clock()

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

local function say(d, text: string)
	d.speech.Text = text
	d.speech.Visible = true
	local token = {}
	d.speechToken = token
	task.delay(2.5, function()
		if d.speechToken == token then
			d.speech.Visible = false
		end
	end)
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

-- What the HUD calls the dummy's condition; the rules run on d.state.
local function statusOf(d): string
	if d.state == "Dead" then
		return d.cause or "Dead"
	elseif d.state == "Out cold" or d.state == "Held" then
		return d.state
	elseif d.state == "Knocked down" then
		if d.legless then
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

	if part.Name == "Head" then -- the speech bubble stays with the body
		local bubble = part:FindFirstChildOfClass("BillboardGui")
		local torso = model:FindFirstChild("UpperTorso")
		if bubble and torso then
			bubble.StudsOffset = Vector3.new(0, 2.6, 0)
			bubble.Parent = torso
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
end

local function knockDown(d, seconds: number, state: string)
	dropPose(d) -- a limp body holds no pose
	if d.postureKey ~= "" then -- nor a lean: the spine goes back to straight under the ragdoll
		d.postureKey = ""
		Looks.posture(d.model, {})
	end
	Ragdoll.set(d.model, true)
	setOwner(d.model, d.heldBy)
	d.wakeAt = math.max(d.wakeAt, os.clock() + seconds)
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
	d.wound, d.scaredUntil, d.attackerAt = nil, 0, nil
	for _, mark in d.model:GetDescendants() do
		if mark.Name == "Wound" then
			mark:Destroy()
		end
	end
	d.humanoid.WalkSpeed = 8
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
end

local function updatePose(d)
	local now = os.clock()
	local wound = d.wound
	if wound and (now >= wound.untilTime or wound.part.Parent ~= d.model) then
		wound, d.wound = nil, nil
	end
	local scared = now < d.scaredUntil
	local key = (scared and "up" or wound and wound.part.Name .. wound.untilTime or "")
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
	if now < d.scaredUntil then
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
local function alarm(victim, position: Vector3, kind: string, from: Vector3?)
	local now = os.clock()
	for _, d in dummies do
		if d == victim or d.state ~= "Awake" or now < d.nextReact then
			continue
		end
		local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - position).Magnitude > 45 then
			continue
		end
		d.nextReact = now + math.random(3, 6)
		d.nextWander, d.calmAt = now + 4, now + 4
		if victim and victim.state ~= "Dead" and kind ~= "shot" and not d.limp and math.random() < 0.2 then
			say(d, "Hang on, I'm coming!")
			d.humanoid.WalkSpeed = 12
			d.humanoid:MoveTo(position)
			continue
		end
		if math.random() < 0.7 then
			say(d, pick(WITNESS_LINES[kind]))
		end
		local away = (root.Position - (from or position)) * Vector3.new(1, 0, 1)
		away = away.Magnitude > 0.1 and away.Unit or Vector3.xAxis
		d.humanoid.WalkSpeed = pace(d) * 1.7
		d.humanoid:MoveTo(root.Position + away * 22)
	end
end

local WAKE_LINES = { "That's the last time you do that.", "I'm okay. I think.", "Ow. Ow. Ow.", "Stay away from me!" }
local LOSS_LINES = { arm = { "My arm!", "That was my good arm!" }, leg = { "My leg!", "I needed that!" }, hand = { "My hand!" }, foot = { "My foot!" } }
local SHOT_LINES = { "I felt that in my teeth.", "Is it meant to move like that?", "That's a real gun!" }

-- `scale` multiplies the zone damage and `push` is the knockback speed (weapons); a punch is 1 / 30.
-- `kind` is the weapon's `hurt` (blunt when left out), `pos` the point that was hit.
-- `from` is where the attacker stands: the dummy and the ones watching run from there.
local function hit(d, part: BasePart, dir: Vector3, scale: number?, push: number?, kind: string?, pos: Vector3?, from: Vector3?)
	local power = scale or 1
	d.attackerAt = from
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

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 30)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.MaxDistance = 80
	local speech = Instance.new("TextLabel")
	speech.Size = UDim2.fromScale(1, 1)
	speech.AutomaticSize = Enum.AutomaticSize.X
	speech.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	speech.BackgroundTransparency = 0.25
	speech.TextColor3 = Color3.fromRGB(255, 200, 80)
	speech.Font = Enum.Font.GothamMedium
	speech.TextSize = 14
	speech.Visible = false
	speech.Parent = gui
	gui.Parent = model:FindFirstChild("Head")
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

	local d = {
		model = model,
		humanoid = humanoid,
		speech = speech,
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
		wound = nil :: any, -- { part, at, untilTime }: where the hands go
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

local function rateLimited(player: Player, cooldown: number): boolean
	local now = os.clock()
	if now - (lastUse[player] or 0) < cooldown then
		return true
	end
	lastUse[player] = now
	return false
end

local function headOf(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("Head") :: BasePart?
end

punchRemote.OnServerEvent:Connect(function(player, part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or rateLimited(player, PUNCH_COOLDOWN) then
		return
	end
	local d = dummyOf(part)
	local head = headOf(player)
	if not d or not head or (part.Position - head.Position).Magnitude > PUNCH_RANGE then
		return
	end
	hit(d, part, (part.Position - head.Position).Unit, nil, nil, nil, nil, head.Position)
end)

-- A gun pointed at a dummy: the client reports who it is aiming at a few times a second. The
-- dummy stops, begs and holds its hands up (updatePose) for as long as the reports keep coming.
local aimRemote = Instance.new("RemoteEvent")
aimRemote.Name = "Aim"
aimRemote.Parent = remotes
local SCARED_LINES = { "Don't shoot!", "Whoa, easy!", "I give up!", "Not me, not me!" }
aimRemote.OnServerEvent:Connect(function(player, part)
	local d = typeof(part) == "Instance" and dummyOf(part)
	local head = headOf(player)
	if not d or not head or d.state ~= "Awake" or (d.model:GetPivot().Position - head.Position).Magnitude > 60 then
		return
	end
	local now = os.clock()
	if now >= d.scaredUntil then
		say(d, pick(SCARED_LINES))
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
			local velocity = typeof(arg) == "Vector3" and arg or Vector3.zero
			if velocity.Magnitude > MAX_THROW_SPEED then
				velocity = velocity.Unit * MAX_THROW_SPEED
			end
			release(d, velocity)
		end
	end
end)

actionRemote.OnServerEvent:Connect(function(player, action, arg)
	if rateLimited(player, 0.25) then
		return
	end
	if action == "map" and SPAWNS[arg] then
		player:SetAttribute("Map", arg)
		if player.Character then
			player.Character:PivotTo(SPAWNS[arg])
		end
		return
	end
	local head = headOf(player)
	if not head then
		return
	end
	if action == "spawn" and typeof(arg) == "Vector3" and (arg - head.Position).Magnitude < 200 then
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

local function throw(weapon, char: Model, origin: Vector3, dir: Vector3)
	local p = Instance.new("Part")
	if weapon.id == "Grenade" then
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

	if weapon.kind == "thrown" then
		throw(weapon, char, head.Position, dir)
		return
	end
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	local origin = head.Position
	local result = workspace:Raycast(origin, dir * weapon.range, params)
	local target = result and result.Position or origin + dir * weapon.range
	fxRemote:FireAllClients("Shot", char, id, origin, target, result ~= nil)
	if weapon.kind == "gun" then -- a gunshot scares whoever hears it, hit or miss
		alarm(nil, origin, "shot", origin)
	end
	if not result then
		return
	end
	if weapon.speed then -- knife flies there first
		task.wait((target - origin).Magnitude / weapon.speed)
	end
	local d = dummyOf(result.Instance)
	if d then
		if result.Instance.Parent then
			hit(d, result.Instance, dir, weapon.dmg, weapon.push, weapon.hurt, target, origin)
		end
	elseif result.Instance:IsDescendantOf(gibFolder) then -- a loose limb: just knock it about
		result.Instance:ApplyImpulse(dir * result.Instance.AssemblyMass * weapon.push)
	elseif weapon.chip then
		Map.blast(target, weapon.chip, 30)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid")
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
			char:PivotTo(SPAWNS[map])
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	if held[player] then
		release(held[player], Vector3.zero)
	end
	lastUse[player] = nil
	attackReady[player] = nil
	slamReady[player] = nil
	moveBudget[player] = nil
end)

local nextSync = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	local sync = now >= nextSync -- blood and status tick over on the HUD a few times a second
	if sync then
		nextSync = now + 0.3
	end
	for _, d in dummies do
		if d.bleed > 0 then
			d.blood = math.max(0, d.blood - d.bleed * dt)
			if d.blood <= 0 then
				stopBleeding(d) -- nothing left to drip
			end
			if d.state ~= "Dead" then
				if d.blood < BLOOD_DEAD then
					kill(d, "Dead: bled out")
				elseif d.blood < BLOOD_OUT and d.state ~= "Out cold" then
					knockDown(d, 6, "Out cold")
				end
			end
		end
		if sync then
			syncAttributes(d)
			express(d)
		end
		local ragdolled = d.model:GetAttribute("Ragdolled")
		if ragdolled then
			if d.legless and d.state == "Out cold" and not d.heldBy and now >= d.wakeAt then
				setState(d, "Knocked down") -- comes round, but stays down
			end
			if not d.legless and not d.heldBy and d.state ~= "Dead" and now >= d.wakeAt then
				Ragdoll.set(d.model, false)
				setState(d, "Awake")
				d.humanoid.WalkSpeed = pace(d)
				d.nextWander = now + 2
				for key in d.limpJoints do -- standing up drives every joint again: broken arms stay limp
					Ragdoll.joints(d.model, LIMP[key], true)
				end
				-- back on its feet: a word about it, and away from whoever did it
				if math.random() < 0.6 then
					say(d, (d.limpJoints.left or d.limpJoints.right) and "I can't feel my arm." or pick(WAKE_LINES))
				end
				local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if d.attackerAt and root then
					local away = (root.Position - d.attackerAt) * Vector3.new(1, 0, 1)
					if away.Magnitude > 0.1 and away.Magnitude < 40 then
						d.humanoid:MoveTo(root.Position + away.Unit * 18)
						d.nextWander = now + 5
					end
				end
			elseif d.state == "Knocked down" and not d.heldBy and now >= d.nextTwitch then
				-- awake on the ground: in pain it writhes, without a leg it drags itself away
				d.nextTwitch = now + 0.25 + math.random() * 0.3
				local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
				if torso and (d.legless or d.daze >= 30) then
					local names = { "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg", "Head" }
					local limb = d.model:FindFirstChild(names[math.random(#names)]) :: BasePart?
					if limb then
						limb:ApplyImpulse(Random.new():NextUnitVector() * limb.AssemblyMass * 22)
					end
					if d.legless then
						local away = (torso.Position - (d.attackerAt or torso.Position + torso.CFrame.UpVector)) * Vector3.new(1, 0, 1)
						if away.Magnitude > 0.1 then
							torso:ApplyImpulse((away.Unit + Vector3.yAxis * 0.25) * torso.AssemblyMass * 11)
						end
					end
				end
			end
			continue
		end
		updatePose(d)
		if d.calmAt > 0 and now >= d.calmAt then -- done running (alarm)
			d.calmAt = 0
			d.humanoid.WalkSpeed = pace(d)
		end
		for key, untilTime in d.limpJoints do
			if now >= untilTime then
				d.limpJoints[key] = nil
				Ragdoll.joints(d.model, LIMP[key], false)
			end
		end
		d.daze = math.max(0, d.daze - 8 * dt)
		if now >= d.nextWander then
			d.nextWander = now + math.random(4, 9)
			local offset = Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
			d.humanoid:MoveTo(d.home + offset)
		end
		if now >= d.nextTalk then
			d.nextTalk = now + math.random(20, 45)
			say(d, pick(IDLE_LINES))
		end
	end
end)

-- Factory machines: dummies go through harm(), players take Humanoid damage and are flung by
-- their own client (it owns their physics).
local wakeToken = setmetatable({}, { __mode = "k" })
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
	humanoid:TakeDamage(damage)
	Ragdoll.set(model, true)
	hazardRemote:FireClient(player, velocity)
	local token = {}
	wakeToken[model] = token
	task.delay(2.5, function()
		if wakeToken[model] == token and model.Parent and humanoid.Health > 0 then
			Ragdoll.set(model, false)
		end
	end)
end)
for _, spot in Factory.DUMMY_SPOTS do
	spawnDummy(CFrame.new(spot) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
end
Map.build()
for i = 1, 8 do
	local angle = i / 8 * math.pi * 2
	spawnDummy(CFrame.new(math.cos(angle) * 25, 4, math.sin(angle) * 25))
end
