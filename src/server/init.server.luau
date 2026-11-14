local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attacks = require(ReplicatedStorage.Shared.Attacks)
local Ragdoll = require(ReplicatedStorage.Shared.Ragdoll)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Map = require(script.Map)
local Factory = require(script.Factory)

local PUNCH_RANGE = 11
local PUNCH_COOLDOWN = 0.2
local GRAB_RANGE = 15
local MAX_THROW_SPEED = 120
local MAX_DUMMIES = 30
local MAX_HP = 100

local NAMES = { "Noemi", "Jia", "Kofi", "Ruth", "Dot", "Fatima", "Wanda", "Thandi", "Milo", "Otto", "Bruno", "Ines" }
local ZONES = {
	Head = { damage = 14, daze = 20, injury = "Bruised head", lines = { "My head!", "Ow, I see stars...", "Not the face!" } },
	Chest = { damage = 10, daze = 14, injury = "Broken ribs", lines = { "My chest!", "Oof!", "Can't... breathe..." } },
	Stomach = { damage = 8, daze = 12, injury = "Bruised stomach", lines = { "Oof, my stomach!", "Hey, cut it out!" } },
	Arm = { damage = 5, daze = 5, injury = "Bruised arm", lines = { "Why the arm?", "Ow, my arm!" } },
	Leg = { damage = 5, daze = 6, injury = "Bruised leg", lines = { "My leg!", "Ow, ow!" } },
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

local function pick(list)
	return list[math.random(#list)]
end

local function zoneOf(name: string): string
	if name == "Head" then
		return "Head"
	elseif name == "UpperTorso" then
		return "Chest"
	elseif name == "LowerTorso" then
		return "Stomach"
	elseif name:find("Arm") or name:find("Hand") then
		return "Arm"
	end
	return "Leg"
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

local function syncAttributes(d)
	d.model:SetAttribute("HP", math.max(0, math.floor(d.hp)))
	d.model:SetAttribute("Injuries", table.concat(d.injuries, ", "))
end

local function knockDown(d, seconds: number, state: string)
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

local function revive(d)
	if d.heldBy then
		release(d, Vector3.zero)
	end
	d.hp, d.daze, d.hits, d.injuries, d.wakeAt = MAX_HP, 0, {}, {}, 0
	Ragdoll.set(d.model, false)
	setState(d, "Awake")
	syncAttributes(d)
end

-- `scale` multiplies the zone damage and `push` is the knockback speed (weapons); a punch is 1 / 30.
local function hit(d, part: BasePart, dir: Vector3, scale: number?, push: number?)
	if d.state == "Dead" then
		part:ApplyImpulse(dir * part.AssemblyMass * (push or 25))
		return
	end
	local zoneName = zoneOf(part.Name)
	local zone = ZONES[zoneName]
	d.hp -= zone.damage * (scale or 1)
	d.daze += zone.daze
	d.hits[zoneName] = (d.hits[zoneName] or 0) + 1
	if d.hits[zoneName] == 2 then
		table.insert(d.injuries, zone.injury)
	end

	if d.hp <= 0 then
		knockDown(d, math.huge, "Dead")
	elseif d.daze >= 60 then
		knockDown(d, 8, "Out cold")
	elseif d.daze >= 30 or d.model:GetAttribute("Ragdolled") then
		knockDown(d, 3, "Knocked down")
	else
		knockDown(d, 1.2, "Knocked down") -- every punch flops them, light ones just briefly
	end
	if d.state == "Awake" or d.state == "Knocked down" or d.state == "Held" then
		say(d, pick(zone.lines))
	end
	syncAttributes(d)

	part:ApplyImpulse((dir + Vector3.yAxis * 0.3) * part.AssemblyMass * (push or 30))
	part:ApplyAngularImpulse(Random.new():NextUnitVector() * part.AssemblyMass * 12)
end

local function spawnDummy(cf: CFrame)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	local name = pick(NAMES)
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
		hits = {},
		injuries = {},
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
	hit(d, part, (part.Position - head.Position).Unit)
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

local function harm(d, damage: number)
	if d.state == "Dead" then
		return
	end
	d.hp -= damage
	if d.hp <= 0 then
		knockDown(d, math.huge, "Dead")
	else
		knockDown(d, 4, "Knocked down")
	end
	syncAttributes(d)
end

-- Damage + launch every dummy in range. `radial` pushes away from the centre.
local function smash(position: Vector3, radius: number, damage: number, push: Vector3, radial: number)
	for _, d in dummies do
		local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
		local offset = torso and torso.Position - position
		if not offset or offset.Magnitude > radius then
			continue
		end
		if d.heldBy then
			release(d, Vector3.zero)
		end
		harm(d, damage)
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

-- Weapons ---------------------------------------------------------------------
local weaponById = {}
for _, weapon in Weapons do
	weaponById[weapon.id] = weapon
end

local function explode(position: Vector3)
	fxRemote:FireAllClients("Boom", nil, position, 9)
	Map.blast(position, 9, 70)
	smash(position, 13, 45, Vector3.zero, 80)
end

local function ignite(position: Vector3)
	fxRemote:FireAllClients("Fire", nil, position, 8, 5)
	Map.blast(position, 2.5, 30)
	for _ = 1, 10 do
		smash(position, 8, 6, Vector3.zero, 0)
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
	if not result then
		return
	end
	if weapon.speed then -- knife flies there first
		task.wait((target - origin).Magnitude / weapon.speed)
	end
	local d = dummyOf(result.Instance)
	if d then
		if result.Instance.Parent then
			hit(d, result.Instance, dir, weapon.dmg, weapon.push)
		end
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
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for _, d in dummies do
		local ragdolled = d.model:GetAttribute("Ragdolled")
		if ragdolled then
			if not d.heldBy and d.state ~= "Dead" and now >= d.wakeAt then
				Ragdoll.set(d.model, false)
				setState(d, "Awake")
				d.nextWander = now + 2
			end
			continue
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
