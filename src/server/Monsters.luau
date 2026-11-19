-- Server-owned encounters. Reuses the game's weapon rays, blast path and player ragdoll callback.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Definitions = require(ReplicatedStorage.Shared.Mythology)
local Rig = require(ReplicatedStorage.Shared.MythRig)
local Ragdoll = require(ReplicatedStorage.Shared.Ragdoll)
local Monsters = {}
local actors = {}
local folder, events, knockPlayer
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
-- Blender cages (assets/myth): invisible blocking volumes in cage space (x, y, z = Roblox axes, the
-- cage's front at -z), how far the gate travels when the boss is let out, and where the pedestal is.
local CAGES = {
	Cyclops = { lift = Vector3.new(0, 19, 0), button = 20, sign = 16.5, solids = {
		{ "Wall", Vector3.new(4.2, 24, 3), Vector3.new(-11.9, 12, -9) }, { "Wall", Vector3.new(4.2, 24, 3), Vector3.new(11.9, 12, -9) },
		{ "Wall", Vector3.new(19.6, 3, 3), Vector3.new(0, 22.5, -9) },
		{ "Bar", Vector3.new(19.6, 21, 1.6), Vector3.new(0, 10.5, -9) },
		{ "Wall", Vector3.new(24, 24, 1.5), Vector3.new(0, 12, 10.25) },
		{ "Wall", Vector3.new(2, 24, 18), Vector3.new(11, 12, 1) }, { "Wall", Vector3.new(2, 24, 18), Vector3.new(-11, 12, 1) },
	} },
	Minotaur = { lift = Vector3.new(0, -15.5, 0), button = 19, sign = 16, solids = {
		{ "Floor", Vector3.new(29.8, 4.25, 25), Vector3.new(0, 2.125, 0) },
		{ "Wall", Vector3.new(1.2, 15, 21), Vector3.new(-10.5, 11.75, 0) }, { "Wall", Vector3.new(1.2, 15, 21), Vector3.new(10.5, 11.75, 0) },
		{ "Wall", Vector3.new(22.2, 15, 1.2), Vector3.new(0, 11.75, 10.5) },
		{ "Wall", Vector3.new(22.2, 1, 22.2), Vector3.new(0, 19.75, 0) },
		{ "Bar", Vector3.new(21, 15, 1.6), Vector3.new(0, 11.75, -10.6) },
	} },
	Talos = { lift = Vector3.new(0, -26, 0), button = 16, sign = 13.5, solids = {
		{ "Floor", Vector3.new(0.66, 17.2, 17.2), Vector3.new(0, 0.33, 0), true },
		{ "Bar", Vector3.new(16, 25, 1), Vector3.new(0, 12.5, -8.1) }, { "Bar", Vector3.new(16, 25, 1), Vector3.new(0, 12.5, 8.1) },
		{ "Bar", Vector3.new(1, 25, 16), Vector3.new(-8.1, 12.5, 0) }, { "Bar", Vector3.new(1, 25, 16), Vector3.new(8.1, 12.5, 0) },
	} },
}
-- Dungeons (design "Lochy Myth Yard"): each boss sits in a pit cut through the arena's grass rim down
-- to the bedrock (DEEP), walled RAMPART above the grass and crenellated, paved in the arena plaza's
-- stone rings, with a short ramp and a red arch toward the arena. Kept clear of the north launch ramp.
local PIT, DEEP, RAMPART, RAMP_HALF, RAMP_LONG = 22, 3, 6, 9, 6
local YARD = { z = -170, x = { Cyclops = -112, Minotaur = -56, Talos = 56 } }
local LOOK = {
	plaza = Color3.fromRGB(176, 170, 160), dark = Color3.fromRGB(150, 144, 136), path = Color3.fromRGB(160, 150, 136),
	marble = Color3.fromRGB(226, 222, 214), brick = Color3.fromRGB(170, 95, 80), gate = Color3.fromRGB(200, 50, 45),
	wall = Color3.fromRGB(110, 106, 114), steel = Color3.fromRGB(224, 160, 48), plank = Color3.fromRGB(150, 110, 70),
	crate = Color3.fromRGB(196, 150, 92), iron = Color3.fromRGB(58, 58, 66), flame = Color3.fromRGB(255, 150, 60),
}
local THEME = { -- a glowing ring in the paving (radius from, to)
	Cyclops = { ring = { 14, 17.5 }, glow = Color3.fromRGB(240, 122, 58) },
	Minotaur = {},
	Talos = { ring = { 9.5, 12 }, glow = Color3.fromRGB(57, 208, 230) },
}
local function slab(parent, name, size, at, color, material)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color, p.Material, p.Anchored = name, size, color, material, true
	p.CFrame = typeof(at) == "Vector3" and CFrame.new(at) or at
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function span(parent, name, x0, x1, y0, y1, z0, z1, color, material)
	return slab(parent, name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material)
end
-- Cuts holes ({ x0, x1, z0, z1 }) out of axis-aligned blocks (the arena's grass rim), keeping the rest.
local function carve(parts, holes)
	for _, part in parts do
		local lo, hi = part.Position - part.Size / 2, part.Position + part.Size / 2
		local cuts = {}
		for _, h in holes do
			if h[1] < hi.X and h[2] > lo.X and h[3] < hi.Z and h[4] > lo.Z then table.insert(cuts, h) end
		end
		if #cuts == 0 then continue end
		local zs = { lo.Z, hi.Z }
		for _, h in cuts do
			table.insert(zs, math.clamp(h[3], lo.Z, hi.Z)); table.insert(zs, math.clamp(h[4], lo.Z, hi.Z))
		end
		table.sort(zs)
		local function piece(xa, xb, za, zb)
			local p = part:Clone()
			p.Size = Vector3.new(xb - xa, part.Size.Y, zb - za)
			p.CFrame = CFrame.new((xa + xb) / 2, part.Position.Y, (za + zb) / 2)
			p.Parent = part.Parent
		end
		for k = 1, #zs - 1 do
			local za, zb = zs[k], zs[k + 1]
			if zb - za < 0.01 then continue end
			local row = {}
			for _, h in cuts do
				if h[3] < zb - 0.01 and h[4] > za + 0.01 then table.insert(row, h) end
			end
			table.sort(row, function(a, b) return a[1] < b[1] end)
			local x = lo.X
			for _, h in row do
				if h[1] > x + 0.01 then piece(x, h[1], za, zb) end
				x = math.max(x, h[2])
			end
			if x < hi.X - 0.01 then piece(x, hi.X, za, zb) end
		end
		part:Destroy()
	end
end
local function torch(parent, x, z, y)
	slab(parent, "Post", Vector3.new(2, 3.5, 2), Vector3.new(x, y + 1.75, z), LOOK.dark, Enum.Material.Slate)
	slab(parent, "Post", Vector3.new(2.6, 0.6, 2.6), Vector3.new(x, y + 3.8, z), LOOK.marble, Enum.Material.Marble)
	local flame = slab(parent, "Flame", Vector3.new(1, 1.2, 1), Vector3.new(x, y + 4.7, z), LOOK.flame, Enum.Material.Neon)
	flame.CanCollide, flame.CanQuery, flame.CastShadow = false, false, false
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range, light.Shadows = LOOK.flame, 1.4, 22, false
	light.Parent = flame
end
-- One boss's dungeon around base (the pit floor's centre). Returns the arch to hang its name on.
local function dungeon(ground, kind, base, floors)
	local model = Instance.new("Model"); model.Name = kind .. "Dungeon"; model.Parent = ground
	local b, c, low = base.X, base.Z, base.Y
	local x0, x1, z0, z1 = b - PIT, b + PIT, c - PIT, c + PIT -- the hole; z1 faces the arena
	local theme = THEME[kind]
	local n = 12
	local tile = (2 * PIT - 2) / n
	for i = 0, n - 1 do
		for k = 0, n - 1 do
			local px, pz = x0 + 1 + (i + 0.5) * tile, z0 + 1 + (k + 0.5) * tile
			local r = math.sqrt((px - b) ^ 2 + (pz - c) ^ 2)
			local color, material = (r // 4) % 2 == 0 and LOOK.plaza or LOOK.dark, Enum.Material.Cobblestone
			if theme.ring and r >= theme.ring[1] and r < theme.ring[2] then color, material = theme.glow, Enum.Material.Neon end
			table.insert(floors, slab(model, "Floor", Vector3.new(tile, 1, tile), Vector3.new(px, low - 0.5, pz), color, material))
		end
	end
	-- walls stand on the bedrock: slate under a brick band; the rampart ones carry merlons
	local function wall(xa, xb, za, zb, top)
		span(model, "Wall", xa, xb, low - 1, top - 1.5, za, zb, LOOK.wall, Enum.Material.Slate)
		span(model, "Wall", xa, xb, top - 1.5, top, za, zb, LOOK.brick, Enum.Material.Brick)
		if top <= 0 then return end
		local alongX = xb - xa > zb - za
		local from, to = alongX and xa or za, alongX and xb or zb
		for u = from + 3, to - 3, 4 do
			local size = alongX and Vector3.new(2, 1.5, zb - za) or Vector3.new(xb - xa, 1.5, 2)
			local at = alongX and Vector3.new(u + 1, top + 0.75, (za + zb) / 2) or Vector3.new((xa + xb) / 2, top + 0.75, u + 1)
			if u + 2 <= to - 2 then slab(model, "Merlon", size, at, LOOK.wall, Enum.Material.Slate) end
		end
	end
	wall(x0, x0 + 1, z0, z1, RAMPART); wall(x1 - 1, x1, z0, z1, RAMPART); wall(x0 + 1, x1 - 1, z0, z0 + 1, RAMPART)
	wall(x0 + 1, b - RAMP_HALF - 1, z1 - 1, z1, RAMPART); wall(b + RAMP_HALF + 1, x1 - 1, z1 - 1, z1, RAMPART)
	-- the ramp: a trench lined like the pit, a wedge rising toward the arena (+z) on a paved bed
	wall(b - RAMP_HALF - 1, b - RAMP_HALF, z1 - 1, z1 + RAMP_LONG, 0); wall(b + RAMP_HALF, b + RAMP_HALF + 1, z1 - 1, z1 + RAMP_LONG, 0)
	table.insert(floors, span(model, "Floor", b - RAMP_HALF, b + RAMP_HALF, low - 1, low, z1 - 1, z1 + RAMP_LONG, LOOK.dark, Enum.Material.Cobblestone))
	local ramp = Instance.new("WedgePart") -- low edge at its front (-z, the pit), high at the back
	ramp.Name, ramp.Size, ramp.CFrame, ramp.Anchored = "Ramp", Vector3.new(2 * RAMP_HALF, -low, RAMP_LONG), CFrame.new(b, low / 2, z1 + RAMP_LONG / 2), true
	ramp.Color, ramp.Material = LOOK.dark, Enum.Material.Slate
	ramp.TopSurface, ramp.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	ramp.Parent = model
	table.insert(floors, ramp)
	-- the red arch over the top of the ramp, like the arena's gate, and a torch on each corner
	local top = z1 + RAMP_LONG + 1
	for _, side in { -1, 1 } do
		slab(model, "Arch", Vector3.new(2, 16, 2), Vector3.new(b + side * (RAMP_HALF + 2), 8, top), LOOK.gate, Enum.Material.Wood)
	end
	local lintel = slab(model, "Arch", Vector3.new(2 * RAMP_HALF + 6, 3, 2.4), CFrame.new(b, 17.5, top) * CFrame.Angles(0, math.pi, 0), LOOK.gate, Enum.Material.Wood)
	for _, x in { x0 + 0.5, x1 - 0.5 } do
		for _, z in { z0 + 0.5, z1 - 0.5 } do torch(model, x, z, RAMPART) end
	end
	-- props: Cyclops's forge, Minotaur's maze corners, Talos's scaffolding
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			if kind == "Cyclops" then
				if sz > 0 then
					slab(model, "Anvil", Vector3.new(2, 2.4, 2), Vector3.new(b + sx * 17, low + 1.2, c + sz * 17), LOOK.iron, Enum.Material.Metal)
					slab(model, "Anvil", Vector3.new(4.4, 1.4, 2.2), Vector3.new(b + sx * 17, low + 3.1, c + sz * 17), LOOK.iron, Enum.Material.Metal)
				else
					slab(model, "Crate", Vector3.new(3, 3, 3), Vector3.new(b + sx * 18, low + 1.5, c + sz * 18), LOOK.crate, Enum.Material.WoodPlanks)
					slab(model, "Crate", Vector3.new(3, 3, 3), Vector3.new(b + sx * 18, low + 4.5, c + sz * 18), LOOK.crate, Enum.Material.WoodPlanks)
					slab(model, "Crate", Vector3.new(3, 3, 3), Vector3.new(b + sx * 14.5, low + 1.5, c + sz * 18), LOOK.crate, Enum.Material.WoodPlanks)
				end
			elseif kind == "Minotaur" then
				span(model, "Maze", math.min(b + sx * 11, b + sx * 18.25), math.max(b + sx * 11, b + sx * 18.25), low, low + 4.5, c + sz * 16 - 0.75, c + sz * 16 + 0.75, LOOK.plaza, Enum.Material.Cobblestone)
				span(model, "Maze", b + sx * 17.5 - 0.75, b + sx * 17.5 + 0.75, low, low + 4.5, math.min(c + sz * 9, c + sz * 15.25), math.max(c + sz * 9, c + sz * 15.25), LOOK.plaza, Enum.Material.Cobblestone)
				slab(model, "Post", Vector3.new(2, 1, 2), Vector3.new(b + sx * 17.5, low + 5, c + sz * 16), LOOK.marble, Enum.Material.Marble)
			else
				local cx, cz = b + sx * 17.5, c + sz * 17.5
				for _, px in { -2.2, 2.2 } do
					for _, pz in { -2.2, 2.2 } do
						slab(model, "Pole", Vector3.new(0.6, 12, 0.6), Vector3.new(cx + px, low + 6, cz + pz), LOOK.steel, Enum.Material.Metal)
					end
				end
				slab(model, "Deck", Vector3.new(5.6, 0.5, 5.6), Vector3.new(cx, low + 6, cz), LOOK.plank, Enum.Material.WoodPlanks)
				slab(model, "Crate", Vector3.new(3, 3, 3), Vector3.new(b + sx * 13, low + 1.5, cz), LOOK.crate, Enum.Material.WoodPlanks)
			end
		end
	end
	return lintel
end
-- In or out of a dungeon, a boss walks by the ramp: the pit's walls are too tall to climb.
local function inDungeon(p, b, c)
	local dx, dz = math.abs(p.X - b), p.Z - c
	return dx < PIT and dz > -PIT and dz < PIT or dx < RAMP_HALF + 1 and dz >= PIT and dz < PIT + RAMP_LONG
end
local function route(d, goal)
	local pit = d.cage:GetAttribute("Pit")
	if not pit then return goal end
	local b, c, at = pit.X, pit.Z, d.root.Position
	local here, there = inDungeon(at, b, c), inDungeon(goal, b, c)
	if here == there then return goal end
	local foot = Vector3.new(b, at.Y, c + PIT - 3)
	local head = Vector3.new(b, at.Y, c + PIT + RAMP_LONG + 4)
	if here then -- going out: line up under the ramp, then climb it
		return (math.abs(at.X - b) < 3 and at.Z > c + PIT - 6) and head or foot
	end
	-- coming home: to the top of the ramp, down it, then (inside) straight to the goal
	return (math.abs(at.X - b) < 3 and at.Z < head.Z + 2) and foot or head
end
local function groundAt(position, reach)
	local hit = workspace:Raycast(position + Vector3.yAxis * (reach or 6), Vector3.yAxis * -40, groundParams)
	return hit and hit.Position.Y
end
local function openGate(d, open)
	local gate = d.cage:FindFirstChild("Gate")
	if not gate then return end
	for _, p in gate:GetChildren() do
		local shut = p:GetAttribute("Shut")
		local goal = open and shut + d.cage:GetAttribute("GateLift") or shut
		TweenService:Create(p, TweenInfo.new(open and 1.6 or 2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = goal }):Play()
	end
end
local function setBars(cage, solid)
	for _, bar in cage:GetDescendants() do
		if bar:IsA("BasePart") and bar.Name == "Bar" then
			bar.CanCollide, bar.CanQuery = solid, solid
			if not bar:GetAttribute("Collider") then bar.Transparency = solid and 0 or 0.8 end
		end
	end
end
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
	setBars(d.cage, false)
	openGate(d, true)
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
local function plaque(on, message, color, font)
	local ui = Instance.new("SurfaceGui")
	ui.Face, ui.SizingMode, ui.PixelsPerStud = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 45
	ui.Parent = on
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	t.Font, t.TextScaled, t.TextColor3 = font or Enum.Font.GothamBold, true, color
	t.TextStrokeTransparency, t.TextStrokeColor3 = font and 0 or 1, Color3.fromRGB(20, 18, 26)
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
	setBars(cage, true)
	local ray = RaycastParams.new()
	-- a Blender cage's walls and closed gate stop the boss; the old bar cage is ignored as before
	local kit = cage:FindFirstChild("Kit")
	ray.FilterDescendantsInstances = kit and { model, kit, cage:FindFirstChild("Gate"), cage:FindFirstChild("Floors"), cage:FindFirstChild("Challenge"), cage:FindFirstChild("Sign") } or { model, cage }
	local d = { kind = kind, def = def, model = model, root = model.PrimaryPart, humanoid = model:FindFirstChildOfClass("Humanoid"), hp = def.hp,
		home = home, cage = cage, prompt = prompt, ray = ray, credit = {}, stunReady = 0, moving = 0, target = nil, lostAt = 0, nextAttack = 0 }
	actors[model] = d
	d.joints = {}
	for _, obj in model:GetDescendants() do if obj:IsA("Motor6D") then d.joints[obj.Name] = obj end end
	state(d, "Caged")
	openGate(d, false)
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
			if gap < distance and lineClear(d, d.root.Position + Vector3.yAxis * 6 * d.def.scale, r.Position) then best, distance = player, gap end
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
	-- follow the ground: off a plinth, up a step (never a climb taller than a step)
	local ground = groundAt(nextPosition - Vector3.yAxis * 6 * d.def.scale, 5)
	if ground then step += Vector3.yAxis * (ground + 6 * d.def.scale - d.root.Position.Y) end
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
		else state(d, "Return"); face(d, route(d, d.home)) end
		return
	end
	local dist = ((r.Position - d.root.Position) * XZ).Magnitude
	face(d, route(d, r.Position))
	if dist < (d.kind == "Minotaur" and 28 or d.kind == "Talos" and 26 or 16) and now >= d.nextAttack then
		local at = d.kind == "Talos" and r.Position or d.root.Position + flat(r.Position - d.root.Position) * (d.kind == "Cyclops" and 6 or 25)
		d.impact = Vector3.new(at.X, (groundAt(Vector3.new(at.X, d.root.Position.Y, at.Z), 2) or 0) + 0.08, at.Z)
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
	local floors, holes = {}, {}
	for _, b in YARD.x do
		table.insert(holes, { b - PIT, b + PIT, YARD.z - PIT, YARD.z + PIT })
		table.insert(holes, { b - RAMP_HALF - 1, b + RAMP_HALF + 1, YARD.z + PIT, YARD.z + PIT + RAMP_LONG })
	end
	-- the yard is the arena's grass rim north of it (Map.build): cut the pits through it, walk on it
	local rim = workspace:FindFirstChild("Rim")
	if rim then
		carve(rim:GetChildren(), holes)
		table.insert(floors, rim)
	end
	local entrance = block(ground, "EntranceSign", Vector3.new(19, 5, 0.8), Vector3.new(-84, 5, -88), Color3.fromRGB(28, 30, 33))
	entrance.CFrame *= CFrame.Angles(0, math.pi, 0)
	entrance.CanCollide = false
	plaque(entrance, "MYTH YARD\nCHOOSE A CHALLENGE  /  SHOOT THE WEAK POINT", Color3.fromRGB(240, 193, 82))
	local kitRoot = ReplicatedStorage:FindFirstChild("MythKit")
	for _, kind in { "Cyclops", "Minotaur", "Talos" } do
		local def = Definitions[kind]
		local spec = CAGES[kind]
		local kit = kitRoot and kitRoot:FindFirstChild(kind) and kitRoot[kind]:FindFirstChild("Cage")
		local base = Vector3.new(YARD.x[kind], -DEEP, YARD.z)
		local arch = dungeon(ground, kind, base, floors)
		-- the cage faces the entrance (+z); cage space is turned half round onto the yard
		local pivot = CFrame.new(base) * CFrame.Angles(0, math.pi, 0)
		local home = base + Vector3.yAxis * 6 * def.scale
		local cage = Instance.new("Model"); cage.Name = kind .. "Cage"; cage.Parent = ground
		cage:SetAttribute("Pit", base)
		local front = 16
		if kit then
			home = pivot * kit:GetAttribute("Stand") + Vector3.yAxis * 6 * def.scale
			front = spec.button
			cage:SetAttribute("GateLift", spec.lift)
			local look = Instance.new("Folder"); look.Name = "Kit"; look.Parent = cage
			local gate = Instance.new("Folder"); gate.Name = "Gate"; gate.Parent = cage
			local solid = Instance.new("Folder"); solid.Name = "Floors"; solid.Parent = cage
			for _, group in kit:GetChildren() do
				for _, src in group:GetChildren() do
					local c = src:Clone()
					c.CFrame = pivot * c:GetAttribute("Place")
					c.Anchored = true
					if group.Name == "Gate" then c:SetAttribute("Shut", c.CFrame) end
					c.Parent = group.Name == "Gate" and gate or look
				end
			end
			for _, v in spec.solids do
				local p = Instance.new("Part")
				p.Name, p.Size, p.Anchored, p.Transparency = v[1], v[2], true, 1
				p.CFrame = pivot * CFrame.new(v[3]) * (v[4] and CFrame.Angles(0, 0, math.pi / 2) or CFrame.identity)
				if v[4] then p.Shape = Enum.PartType.Cylinder end
				p.CanTouch, p.CastShadow = false, false
				p:SetAttribute("Collider", true)
				p.Parent = v[1] == "Floor" and solid or cage
				if v[1] == "Floor" then table.insert(floors, p) end
			end
		else
			for x = -10, 10, 4 do
				block(cage, "Bar", Vector3.new(0.5, 17, 0.5), base + Vector3.new(x, 8.5, 10), Color3.fromRGB(43, 47, 51))
				block(cage, "Bar", Vector3.new(0.5, 17, 0.5), base + Vector3.new(x, 8.5, -10), Color3.fromRGB(43, 47, 51))
			end
			for _, sign in { -1, 1 } do
				for z = -6, 6, 4 do block(cage, "Bar", Vector3.new(0.5, 17, 0.5), base + Vector3.new(sign * 10, 8.5, z), Color3.fromRGB(43, 47, 51)) end
			end
		end
		local button = block(cage, "Challenge", Vector3.new(3, 2.5, 2.5), base + Vector3.new(0, 1.25, front), def.accent)
		local p = Instance.new("ProximityPrompt")
		p.ActionText, p.ObjectText = "Release / Fight", def.name .. "  +" .. def.reward .. " XP"
		p.KeyboardKeyCode, p.HoldDuration, p.MaxActivationDistance = Enum.KeyCode.Y, 0.4, 12
		p.RequiresLineOfSight, p.Parent = false, button
		local board
		if kit then
			board = block(cage, "Sign", Vector3.new(9, 2.6, 0.4), base + Vector3.new(0, 4.6, spec.sign), Color3.fromRGB(28, 30, 33))
			board.CanCollide = false
		else
			board = block(cage, "Sign", Vector3.new(17, 3.5, 0.6), base + Vector3.new(0, 19, 10), Color3.fromRGB(28, 30, 33))
		end
		board.CFrame *= CFrame.Angles(0, math.pi, 0)
		plaque(board, def.name .. "\n" .. def.hint, def.accent)
		plaque(arch, def.name, LOOK.marble, Enum.Font.FredokaOne)
		Monsters.spawn(kind, home, cage)
	end
	groundParams.FilterDescendantsInstances = floors
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
