-- Server-owned encounters. Reuses the game's weapon rays, blast path and player ragdoll callback.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Definitions = require(ReplicatedStorage.Shared.Mythology)
local Rig = require(ReplicatedStorage.Shared.MythRig)
local Ragdoll = require(ReplicatedStorage.Shared.Ragdoll)
local Monsters = {}
local actors = {}
local folder, events, knockPlayer
local XZ = Vector3.new(1, 0, 1)
local function flat(v)
	v *= XZ
	return v.Magnitude > 0.01 and v.Unit or Vector3.zAxis
end
local function state(d, name, duration)
	d.state, d.since, d.untilTime = name, workspace:GetServerTimeNow(), workspace:GetServerTimeNow() + (duration or 0)
	d.model:SetAttribute("MonsterState", name)
	d.model:SetAttribute("StateSince", d.since)
	d.model:SetAttribute("StateUntil", d.untilTime)
end
local function actorOf(part)
	local at = part
	while at and at.Parent ~= folder do at = at.Parent end
	return at and actors[at]
end
local function lineClear(d, from, to)
	local offset = to - from
	if offset.Magnitude < 0.01 then return true end
	local result = workspace:Raycast(from, offset, d.ray)
	local character = result and result.Instance:FindFirstAncestorOfClass("Model")
	return not result or (result.Position - to).Magnitude < 4
		or (character ~= nil and Players:GetPlayerFromCharacter(character) ~= nil)
end
local function playerRoot(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return h and h.Health > 0 and r, h
end
local function release(d)
	if d.state ~= "Caged" then return end
	d.prompt.Enabled = false
	for _, bar in d.cage:GetChildren() do
		if bar:IsA("BasePart") and bar.Name == "Bar" then bar.CanCollide, bar.CanQuery, bar.Transparency = false, false, 0.8 end
	end
	state(d, "Idle")
end
local function reward(d)
	local now = os.clock()
	for player, credit in d.credit do
		if player.Parent == Players and now - credit.at < 30 and credit.damage >= d.def.hp * 0.05 then
			local xp = (player:GetAttribute("MythXP") or 0) + d.def.reward
			local kills = (player:GetAttribute("MonsterKills") or 0) + 1
			player:SetAttribute("MythXP", xp)
			player:SetAttribute("MonsterKills", kills)
			events:FireClient(player, "Reward", d.def.name, d.def.reward, kills)
		end
	end
	table.clear(d.credit)
end
local function die(d, direction)
	if d.state == "Dead" then return end
	state(d, "Dead", 20)
	d.model:SetAttribute("HP", 0)
	d.humanoid.Health = 0
	d.root.Anchored = false
	Ragdoll.set(d.model, true)
	for _, p in d.model:GetDescendants() do
		if p:IsA("BasePart") and p:CanSetNetworkOwnership() then p:SetNetworkOwner(nil) end
	end
	d.root.AssemblyLinearVelocity = flat(direction) * 16 + Vector3.yAxis * 7
	reward(d)
	actors[d.model] = nil
	Debris:AddItem(d.model, 9)
	task.delay(20, function()
		if folder and folder.Parent then Monsters.spawn(d.kind, d.home, d.cage) end
	end)
end
function Monsters.damage(part, damage, direction, player)
	if not folder or not part then return false end
	local d = actorOf(part)
	if not d then return false end
	if d.state == "Dead" or damage <= 0 then return true end
	release(d)
	local weak = part.Name == d.def.weak or part:GetAttribute("WeakPoint") == true
	local multiplier = weak and 2.5 or d.state == "Recovery" and 1.5 or 1
	local actual = math.min(d.hp, math.clamp(damage, 0, 350) * multiplier)
	d.hp -= actual
	d.model:SetAttribute("HP", d.hp)
	d.humanoid.Health = d.hp
	d.model:SetAttribute("HurtAt", workspace:GetServerTimeNow())
	if player and player.Parent == Players then
		local credit = d.credit[player] or { damage = 0, at = 0 }
		credit.damage += actual; credit.at = os.clock(); d.credit[player] = credit
		events:FireClient(player, "Hit", part.Position, math.round(actual), weak)
	end
	if d.hp <= 0 then die(d, direction or Vector3.zAxis)
	elseif weak and os.clock() >= d.stunReady then
		d.stunReady = os.clock() + 3
		state(d, "Stunned", 1.05)
	end
	return true
end
function Monsters.blast(position, radius, damage, player)
	for _, d in actors do
		if (d.root.Position - position).Magnitude <= radius + 3 then
			Monsters.damage(d.root, damage, d.root.Position - position, player)
		end
	end
end
local function block(parent, name, size, position, color)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Position, p.Color, p.Anchored = name, size, position, color, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Studs, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Plastic
	p.Parent = parent
	return p
end
local function plaque(on, message, color)
	local ui = Instance.new("SurfaceGui")
	ui.Face, ui.SizingMode, ui.PixelsPerStud = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 45
	ui.Parent = on
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	t.Font, t.TextScaled, t.TextColor3 = Enum.Font.GothamBold, true, color
	t.TextWrapped, t.Text, t.Parent = true, message, ui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = t
end
function Monsters.spawn(kind, home, cage)
	local def = Definitions[kind]
	local model = Rig.build(kind)
	model:PivotTo(CFrame.new(home) * CFrame.Angles(0, math.pi, 0))
	model.Parent = folder
	Ragdoll.setup(model)
	local button = cage:FindFirstChild("Challenge")
	local prompt = button:FindFirstChildOfClass("ProximityPrompt")
	prompt.Enabled = true
	for _, p in cage:GetChildren() do
		if p:IsA("BasePart") and p.Name == "Bar" then p.CanCollide, p.CanQuery, p.Transparency = true, true, 0 end
	end
	local ray = RaycastParams.new()
	ray.FilterDescendantsInstances = { model, cage }
	local d = { kind = kind, def = def, model = model, root = model.PrimaryPart, humanoid = model:FindFirstChildOfClass("Humanoid"), hp = def.hp,
		home = home, cage = cage, prompt = prompt, ray = ray, credit = {}, stunReady = 0, moving = 0, target = nil, lostAt = 0, nextAttack = 0 }
	actors[model] = d
	d.joints = {}
	for _, obj in model:GetDescendants() do if obj:IsA("Motor6D") then d.joints[obj.Name] = obj end end
	state(d, "Caged")
	local connection = prompt.Triggered:Connect(function(player)
		local r = playerRoot(player)
		if r and (r.Position - button.Position).Magnitude <= 14 and player:GetAttribute("Map") == "ARENA" then release(d) end
	end)
	model.Destroying:Connect(function() actors[model] = nil; connection:Disconnect(); table.clear(d.credit) end)
	return model
end
local function findTarget(d)
	local best, distance = nil, 48
	for _, player in Players:GetPlayers() do
		local r = playerRoot(player)
		if r and player:GetAttribute("Map") == "ARENA" and (r.Position - d.home).Magnitude < 65 then
			local gap = (r.Position - d.root.Position).Magnitude
			if gap < distance and lineClear(d, d.root.Position, r.Position) then best, distance = player, gap end
		end
	end
	return best
end
local function face(d, position)
	local toward = (position - d.root.Position) * XZ
	if toward.Magnitude > 0.1 then d.root.CFrame = CFrame.lookAt(d.root.Position, d.root.Position + toward) end
end
local function move(d, direction, speed, dt)
	local step = flat(direction) * speed * dt
	local hit = workspace:Blockcast(d.root.CFrame, Vector3.new(4, 5, 3) * d.def.scale, step, d.ray)
	if hit then return false end
	local nextPosition = d.root.Position + step
	if ((nextPosition - d.home) * XZ).Magnitude > 60 then return false end
	d.root.CFrame += step
	return true
end
local function strike(d)
	local center = d.impact
	for _, player in Players:GetPlayers() do
		local r, h = playerRoot(player)
		if not r or player:GetAttribute("Map") ~= "ARENA" then continue end
		local horizontal = ((r.Position - center) * XZ).Magnitude
		local height = r.Position.Y - center.Y
		-- Jumping clears a cyclops shockwave; hammer and charge must be sidestepped.
		if horizontal <= d.def.radius and math.abs(height) < (d.kind == "Cyclops" and 5.5 or 14)
			and lineClear(d, center + Vector3.yAxis * 3, r.Position) then
			knockPlayer(player, h, flat(r.Position - center) * 42 + Vector3.yAxis * 24, d.def.damage, 0.8)
		end
	end
	events:FireAllClients("Impact", center, d.def.radius, d.def.accent)
end
local function think(d, now)
	if d.state == "Caged" or d.state == "Dead" then return end
	if d.state == "Windup" and now >= d.untilTime then
		if d.kind == "Minotaur" then
			d.chargeDirection = flat(d.impact - d.root.Position)
			d.chargeVictims = {}
			state(d, "Charge", 0.85)
		else
			strike(d)
			state(d, "Strike", 0.2)
		end
		return
	elseif (d.state == "Strike" or d.state == "Charge" or d.state == "Stunned") and now >= d.untilTime then
		state(d, "Recovery", d.def.recovery)
		return
	elseif d.state == "Recovery" then
		if now < d.untilTime then return end
		state(d, "Idle")
	elseif d.state == "Windup" or d.state == "Strike" or d.state == "Charge" or d.state == "Stunned" then return end
	d.target = findTarget(d)
	local r = d.target and playerRoot(d.target)
	if not r then
		if (d.root.Position - d.home).Magnitude < 1 then state(d, "Idle"); d.moving = 0
		else state(d, "Return"); face(d, d.home) end
		return
	end
	local dist = ((r.Position - d.root.Position) * XZ).Magnitude
	face(d, r.Position)
	if dist < (d.kind == "Minotaur" and 28 or d.kind == "Talos" and 26 or 16) and now >= d.nextAttack then
		local at = d.kind == "Talos" and r.Position or d.root.Position + flat(r.Position - d.root.Position) * (d.kind == "Cyclops" and 6 or 25)
		d.impact = Vector3.new(at.X, 0.08, at.Z)
		d.model:SetAttribute("ImpactAt", d.impact)
		d.model:SetAttribute("ChargeDirection", flat(r.Position - d.root.Position))
		d.nextAttack = now + d.def.windup + d.def.recovery + 1
		d.moving = 0
		state(d, "Windup", d.def.windup)
	else state(d, "Chase"); d.moving = 1 end
end
function Monsters.start(remotes, hurtPlayer)
	if folder then return end
	knockPlayer = hurtPlayer
	folder = Instance.new("Folder"); folder.Name = "Monsters"; folder.Parent = workspace
	events = Instance.new("RemoteEvent"); events.Name = "MythFx"; events.Parent = remotes
	local ground = Instance.new("Folder"); ground.Name = "MythYard"; ground.Parent = workspace
	block(ground, "Floor", Vector3.new(190, 4, 145), Vector3.new(0, -2, -152.5), Color3.fromRGB(99, 99, 91))
	for x = -90, 90, 10 do
		local stripe = block(ground, "Guide", Vector3.new(0.2, 0.1, 140), Vector3.new(x, 0.06, -152.5), Color3.fromRGB(116, 115, 104))
		stripe.CanCollide, stripe.CanQuery = false, false
	end
	local entrance = block(ground, "EntranceSign", Vector3.new(19, 5, 0.8), Vector3.new(0, 5, -87), Color3.fromRGB(28, 30, 33))
	entrance.CFrame *= CFrame.Angles(0, math.pi, 0)
	entrance.CanCollide = false
	plaque(entrance, "MYTH YARD\nCHOOSE A CHALLENGE  /  SHOOT THE WEAK POINT", Color3.fromRGB(240, 193, 82))
	for i, kind in { "Cyclops", "Minotaur", "Talos" } do
		local def = Definitions[kind]
		local home = Vector3.new((i - 2) * 56, 6 * def.scale, -170)
		local cage = Instance.new("Model"); cage.Name = kind .. "Cage"; cage.Parent = ground
		for x = -10, 10, 4 do
			block(cage, "Bar", Vector3.new(0.5, 17, 0.5), home * XZ + Vector3.new(x, 8.5, 10), Color3.fromRGB(43, 47, 51))
			block(cage, "Bar", Vector3.new(0.5, 17, 0.5), home * XZ + Vector3.new(x, 8.5, -10), Color3.fromRGB(43, 47, 51))
		end
		for _, sign in { -1, 1 } do
			for z = -6, 6, 4 do block(cage, "Bar", Vector3.new(0.5, 17, 0.5), home * XZ + Vector3.new(sign * 10, 8.5, z), Color3.fromRGB(43, 47, 51)) end
		end
		local button = block(cage, "Challenge", Vector3.new(3, 2.5, 2.5), home * XZ + Vector3.new(0, 1.25, 16), def.accent)
		local p = Instance.new("ProximityPrompt")
		p.ActionText, p.ObjectText = "Release / Fight", def.name .. "  +" .. def.reward .. " XP"
		p.KeyboardKeyCode, p.HoldDuration, p.MaxActivationDistance = Enum.KeyCode.Y, 0.4, 12
		p.RequiresLineOfSight, p.Parent = false, button
		local board = block(cage, "Sign", Vector3.new(17, 3.5, 0.6), home * XZ + Vector3.new(0, 19, 10), Color3.fromRGB(28, 30, 33))
		board.CFrame *= CFrame.Angles(0, math.pi, 0)
		plaque(board, def.name .. "\n" .. def.hint, def.accent)
		Monsters.spawn(kind, home, cage)
	end
	local accumulator, poseClock = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		debug.profilebegin("MythEncounters")
		accumulator += dt
		poseClock += dt
		local now = workspace:GetServerTimeNow()
		local tickBrain = accumulator >= 0.1
		local tickPose = poseClock >= 1 / 20
		if tickPose then poseClock %= 1 / 20 end
		if tickBrain then accumulator %= 0.1 end
		for _, d in actors do
			if not d.model.Parent then continue end
			if tickBrain then think(d, now) end
			if d.state == "Chase" or d.state == "Return" then
				d.moving = move(d, d.root.CFrame.LookVector, d.def.speed, math.min(dt, 0.1)) and 1 or 0
			elseif d.state == "Charge" then
				if not move(d, d.chargeDirection, 42, math.min(dt, 0.1)) then state(d, "Stunned", 1.2) end
				for _, player in Players:GetPlayers() do
					local r, h = playerRoot(player)
					if r and not d.chargeVictims[player] and (r.Position - d.root.Position).Magnitude < 8 then
						d.chargeVictims[player] = true
						knockPlayer(player, h, d.chargeDirection * 55 + Vector3.yAxis * 18, d.def.damage, 0.8)
					end
				end
			end
			if tickBrain then d.model:SetAttribute("Moving", d.moving) end
			if tickPose then
				local phase = math.clamp((now - d.since) / math.max(d.untilTime - d.since, 0.01), 0, 1)
				Rig.pose(d.joints, d.state, d.kind, now, d.moving, phase, math.clamp(1 - (now - (d.model:GetAttribute("HurtAt") or 0)) / 0.3, 0, 1), true)
			end
		end
		debug.profileend()
	end)
	Players.PlayerRemoving:Connect(function(player) for _, d in actors do d.credit[player] = nil end end)
end
return Monsters
