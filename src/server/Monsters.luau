-- Server-owned bosses. They never fight players and cannot be killed: let out of their cage they roam the
-- whole arena map hunting every dummy (init.server.luau hands over `prey`), crush and eat them, and
-- smash the structures in their way. Only their pedestal puts them back in the cage.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Definitions = require(ReplicatedStorage.Shared.Mythology)
local Rig = require(ReplicatedStorage.Shared.MythRig)
local Ragdoll = require(ReplicatedStorage.Shared.Ragdoll)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local Map = require(script.Parent.Map)
local Funnels = require(script.Parent.Funnels)
local Monsters = {}
-- a boss's voice: the zombie clips, pitched down to its size
local function voice(d, id, volume)
	Sfx.play({ id, 0.6 / math.max(d.def.scale or 1, 1) ^ 0.3, volume or 1 }, d.root.Position)
end
local actors = {}
local folder, events, prey
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
-- Each boss stands chained in the bottom of its pit, in full view (design "Mayhem Park 2.0": no cages).
-- A chain runs from each wrist shackle back to a plate on the pit's side wall and from each ankle to a ring
-- in the floor (lair space, x on the shackle's side; y above the ground, or `floor`: lying on the pit's floor). The
-- pedestal snaps them and lets it out; putting it back chains it again. Links and plates are Blender meshes
-- (assets/myth: MythKit.Chain), blocks without the kit.
local CHAINS = {
	Wrist = { anchor = Vector3.new(20.7, 2, -15), sag = 2.2 },
	Ankle = { anchor = Vector3.new(13, 0, -10), floor = true, sag = 0.8 },
}
local LINK_SCALE = 1.25
local LINK_PITCH = 1.9 * LINK_SCALE -- a link 3.7 studs long; the next one hangs 2.4 on
-- Dungeons: each boss sits in a pit cut through the rim's ground down to the bedrock (DEEP), walled
-- RAMPART above it and crenellated, paved in the arena plaza's stone rings, with a short ramp out and a
-- gate over its top. Every one is in its own lair (Map.LAIRS, design "Mayhem Park 2.0"): the Cyclops at a
-- forge under the volcano, the Minotaur in the hedge labyrinth, Talos on the lake's island. A lair's frame
-- is the pit's centre on the ground; in lair space the ramp leads out toward +z.
local ROAR = 1.8 -- seconds it roars when let out, before it goes hunting
local PIT, DEEP, RAMPART, RAMP_HALF, RAMP_LONG = 22, 3, 6, 9, 6
local LAIRS = Map.LAIRS
-- Round each lair (lair space): a pylon either side of the way out, wide of the ramp so a 36-stud boss
-- walks out between them with its arms swinging (x, z: MythKit.<Kind>.Lair.Pylon, a post without it); what
-- stands outside (ArenaKit models via Map.structure; turns of 90 degrees, 2 = facing +z); where its name
-- board is (x, z; facing +z). No gate over the ramp: the bosses are taller than any arch.
local LAIR_LOOK = {
	Cyclops = { pylon = { 21.5, 26 }, sign = { 20, 34 }, props = { { "Forge", -22, 38, 3 }, { "Anvil", -12, 39, 2 } } },
	-- the board out at the labyrinth's way in, the bull in its dead-end corner by the pit; the pylons just
	-- clear the labyrinth's side hedges
	Minotaur = { pylon = { 21.5, 26 }, sign = { 17, 57 }, props = { { "BullStatue", -19, 33, 3 } } },
	-- all of it on the island (lair x and z within 32 and 40)
	Talos = { pylon = { 21.5, 25.5 }, sign = { 20, 34 }, props = {
		{ "Brazier", -29, 16 }, { "Brazier", 29, 16 }, { "TalosHead", -26.5, 34, 2 },
	} },
}
local LOOK = {
	plaza = Color3.fromRGB(176, 170, 160), dark = Color3.fromRGB(150, 144, 136), path = Color3.fromRGB(160, 150, 136),
	marble = Color3.fromRGB(226, 222, 214), brick = Color3.fromRGB(170, 95, 80), gate = Color3.fromRGB(200, 50, 45),
	wall = Color3.fromRGB(110, 106, 114), steel = Color3.fromRGB(224, 160, 48), plank = Color3.fromRGB(150, 110, 70),
	crate = Color3.fromRGB(196, 150, 92), iron = Color3.fromRGB(58, 58, 66), flame = Color3.fromRGB(255, 150, 60),
}
local THEME = { -- a coloured ring in the paving (radius from, to)
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
	local flame = slab(parent, "Flame", Vector3.new(1, 1.2, 1), Vector3.new(x, y + 4.7, z), LOOK.flame, Enum.Material.SmoothPlastic)
	flame.CanCollide, flame.CanQuery, flame.CastShadow = false, false, false
	local light = Instance.new("PointLight") -- a soft glow, not a floodlight
	light.Color, light.Brightness, light.Range, light.Shadows = LOOK.flame, 0.6, 14, false
	light.Parent = flame
end
-- One boss's dungeon in its lair (frame: the pit's centre on the ground, the ramp out toward its +z). Built
-- round the origin, then moved onto the frame.
local function dungeon(ground, kind, frame, floors)
	local model = Instance.new("Model"); model.Name = kind .. "Dungeon"; model.Parent = ground
	local b, c, low = 0, 0, -DEEP
	local x0, x1, z0, z1 = b - PIT, b + PIT, c - PIT, c + PIT -- the hole; z1 faces the arena
	local theme = THEME[kind]
	local n = 12
	local tile = (2 * PIT - 2) / n
	for i = 0, n - 1 do
		for k = 0, n - 1 do
			local px, pz = x0 + 1 + (i + 0.5) * tile, z0 + 1 + (k + 0.5) * tile
			local r = math.sqrt((px - b) ^ 2 + (pz - c) ^ 2)
			local color, material = (r // 4) % 2 == 0 and LOOK.plaza or LOOK.dark, Enum.Material.Cobblestone
			if theme.ring and r >= theme.ring[1] and r < theme.ring[2] then color, material = theme.glow, Enum.Material.Slate end
			-- a hair below the pit's bottom: the cage kits lay their own sand / paving right at `low`,
			-- and two faces at one height flicker (z-fighting)
			table.insert(floors, slab(model, "Floor", Vector3.new(tile, 1, tile), Vector3.new(px, low - 0.55, pz), color, material))
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
	table.insert(floors, span(model, "Floor", b - RAMP_HALF, b + RAMP_HALF, low - 1.05, low - 0.05, z1 - 1, z1 + RAMP_LONG, LOOK.dark, Enum.Material.Cobblestone)) -- under the kit's sand (see the paving)
	local ramp = Instance.new("WedgePart") -- low edge at its front (-z, the pit), high at the back
	ramp.Name, ramp.Size, ramp.CFrame, ramp.Anchored = "Ramp", Vector3.new(2 * RAMP_HALF, -low, RAMP_LONG), CFrame.new(b, low / 2, z1 + RAMP_LONG / 2), true
	ramp.Color, ramp.Material = LOOK.dark, Enum.Material.Slate
	ramp.TopSurface, ramp.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	ramp.Parent = model
	table.insert(floors, ramp)
	-- a torch on each corner
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
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then part.CFrame = frame * part.CFrame end
	end
end
-- In or out of a dungeon, a boss walks by the ramp: the pit's walls are too tall to climb.
local function inDungeon(p, frame)
	local q = frame:PointToObjectSpace(p)
	local dx, dz = math.abs(q.X), q.Z
	-- the ramp, and the lane on out past the pylons
	return dx < PIT and dz > -PIT and dz < PIT or dx < RAMP_HALF + 1 and dz >= PIT and dz < PIT + RAMP_LONG + 6
end
local function route(d, goal)
	local frame = d.cage:GetAttribute("Lair")
	if not frame then return goal end
	local at = d.root.Position
	local here, there = inDungeon(at, frame), inDungeon(goal, frame)
	if here == there then return goal end
	local q = frame:PointToObjectSpace(at) -- the boss in lair space
	local function out(z) -- on the ramp's line at its own height
		local w = frame:PointToWorldSpace(Vector3.new(0, 0, z))
		return Vector3.new(w.X, at.Y, w.Z)
	end
	-- the head of the ramp: far enough out that it turns off clear of the pylons (LAIR_LOOK)
	local foot, head = out(PIT - 3), out(PIT + RAMP_LONG + 7)
	if here then -- going out: line up under the ramp, then climb it
		return (math.abs(q.X) < 3 and q.Z > PIT - 6) and head or foot
	end
	-- coming home: to the top of the ramp, down it, then (inside) straight to the goal
	return (math.abs(q.X) < 3 and q.Z < PIT + RAMP_LONG + 9) and foot or head
end
local function groundAt(position, reach)
	local hit = workspace:Raycast(position + Vector3.yAxis * (reach or 6), Vector3.yAxis * -40, groundParams)
	return hit and hit.Position.Y
end
-- A kit piece (a folder of MeshParts, each with its "Place" in the piece's space) at `cf`, `k` times its size.
local function placeKit(src, cf, k, parent)
	local parts = {}
	for _, s in src:GetChildren() do
		if not s:IsA("BasePart") then continue end
		local c = s:Clone()
		local place = s:GetAttribute("Place")
		c.Size = s.Size * k
		c.CFrame = cf * CFrame.new(place.Position * k) * place.Rotation
		c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch = true, false, false, false
		c.Parent = parent
		table.insert(parts, c)
	end
	return parts
end
local IRON = Color3.fromRGB(60, 62, 70)
-- One chain hanging from a to b, `sag` studs low in the middle: links along the curve, every other one
-- turned a quarter about its length. Each link is a Model whose parts are welded to its first one.
local function hang(parent, a, b, sag, link)
	local function at(t) return a:Lerp(b, t) - Vector3.yAxis * sag * 4 * t * (1 - t) end
	local points, lengths, total = { a }, { 0 }, 0
	for i = 1, 24 do
		local p = at(i / 24)
		total += (p - points[i]).Magnitude
		points[i + 1], lengths[i + 1] = p, total
	end
	local count = math.max(1, math.ceil(total / LINK_PITCH))
	local k = 1
	for n = 0, count - 1 do
		local s = (n + 0.5) * total / count
		while k < 24 and lengths[k + 1] < s do k += 1 end
		local p0, p1 = points[k], points[k + 1]
		local along = (p1 - p0).Unit
		local side = along:Cross(Vector3.yAxis)
		if side.Magnitude < 0.05 then side = Vector3.xAxis end
		local cf = CFrame.fromMatrix(p0:Lerp(p1, (s - lengths[k]) / math.max(lengths[k + 1] - lengths[k], 1e-3)), side.Unit, along)
			* CFrame.Angles(0, n % 2 * math.pi / 2, 0)
		local model = Instance.new("Model"); model.Name = "Link"; model.Parent = parent
		local parts = link and placeKit(link, cf, LINK_SCALE, model) or { slab(model, "Link", Vector3.new(1.4, 2.9, 0.55) * LINK_SCALE, cf, IRON, Enum.Material.Metal) }
		for i = 2, #parts do
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1, w.Parent = parts[1], parts[i], parts[i]
		end
		parts[1].CanQuery, parts[1].CastShadow = false, true
		model.PrimaryPart = parts[1]
	end
end
-- Chains the boss in its pit: from every shackle ring (MythRig "ChainRing" attachments, posed) to its plate.
local function chainUp(d)
	local old = d.cage:FindFirstChild("Chains")
	if old then old:Destroy() end
	local chains = Instance.new("Folder"); chains.Name = "Chains"; chains.Parent = d.cage
	local frame = d.cage:GetAttribute("Lair")
	for _, ring in d.model:GetDescendants() do
		if not (ring:IsA("Attachment") and ring.Name == "ChainRing") then continue end
		local spec = CHAINS[ring:GetAttribute("Ring")]
		local from = ring.WorldPosition
		local side = frame:PointToObjectSpace(from).X >= 0 and 1 or -1
		local plate = d.plates[ring:GetAttribute("Ring") .. side]
		hang(chains, from, plate.Position, spec.sag, d.chainKit and d.chainKit:FindFirstChild("Link"))
	end
end
-- The pedestal snaps them: every link drops off and is gone a few seconds later.
local function unchain(d)
	local chains = d.cage:FindFirstChild("Chains")
	if not chains then return end
	chains.Name = "Snapped"
	local center = d.root.Position
	for _, link in chains:GetChildren() do
		local main = link.PrimaryPart
		for _, p in link:GetDescendants() do
			if p:IsA("BasePart") then p.Anchored = false end
		end
		main.CanCollide = true
		local out = (main.Position - center) * Vector3.new(1, 0, 1)
		main.AssemblyLinearVelocity = (out.Magnitude > 0.1 and out.Unit or Vector3.zero) * math.random(8, 16) + Vector3.yAxis * math.random(6, 14)
		main.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
	end
	Sfx.play({ Sfx.BULLET_HIT_METAL, 0.5, 1 }, center)
	Sfx.play({ Sfx.FACTORY_PRESS_SLAM, 0.8, 0.8 }, center)
	Debris:AddItem(chains, 4)
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
local function playerRoot(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return h and h.Health > 0 and r, h
end
local function release(d)
	if d.state ~= "Caged" then return end
	d.prompt.ActionText = "Recall"
	unchain(d)
	voice(d, Sfx.ZOMBIE_ATTACK)
	state(d, "Roar", ROAR) -- MythRig poses it; client/MythPresentation announces it
	d.moving = 0
	if events then events:FireAllClients("loose", d.kind, d.root.Position) end
end
local drop
-- Chains it once its pose has settled (the server poses it at 20 Hz), unless it got out again meanwhile.
local function chainSoon(d)
	task.delay(0.25, function()
		if d.state == "Caged" and d.model.Parent then chainUp(d) end
	end)
end
-- The pedestal again: whatever it is doing, it is back in the bottom of its pit, chained.
local function recall(d)
	if d.state == "Caged" then return end
	drop(d)
	d.moving, d.goal, d.skip = 0, nil, {}
	d.model:PivotTo(CFrame.new(d.home) * d.turn)
	d.prompt.ActionText = "Release"
	state(d, "Caged")
	chainSoon(d)
end
-- A weapon hit on a boss: it flinches and lets itself out, nothing more. True when `part` is a boss's,
-- so the shot stops there.
function Monsters.damage(part, damage, _direction, player)
	if not folder or not part then return false end
	local d = actorOf(part)
	if not d then return false end
	if damage <= 0 then return true end
	if typeof(player) == "Instance" and player:IsA("Player") then
		Funnels.first(player, "BossEncountered")
		Funnels.first(player, "BossHit")
	end
	release(d)
	d.model:SetAttribute("HurtAt", workspace:GetServerTimeNow())
	if os.clock() >= (d.hurtVoiceAt or 0) then -- a grunt, not one per pellet
		d.hurtVoiceAt = os.clock() + 0.6
		voice(d, Sfx.ZOMBIE_HURT, 0.9)
	end
	return true
end
function Monsters.isMonster(part)
	return folder ~= nil and part ~= nil and actorOf(part) ~= nil
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
function Monsters.spawn(kind, home, cage, plates, chainKit)
	local def = Definitions[kind]
	local model = Rig.build(kind)
	-- on its stand it looks out of its lair, up the ramp (lair +z)
	local turn = cage:GetAttribute("Lair").Rotation * CFrame.Angles(0, math.pi, 0)
	model:PivotTo(CFrame.new(home) * turn)
	model.Parent = folder
	Ragdoll.setup(model)
	local button = cage:FindFirstChild("Challenge")
	local prompt = button:FindFirstChildOfClass("ProximityPrompt")
	prompt.Enabled = true
	local ray = RaycastParams.new()
	-- its own lair's bits (pedestal, board, chains, pylons) and the dummies never block it: it walks
	-- through them to its meal
	local dummies = workspace:FindFirstChild("Dummies")
	ray.FilterDescendantsInstances = { model, cage, dummies }
	local d = { kind = kind, def = def, model = model, root = model.PrimaryPart, plates = plates, chainKit = chainKit,
		home = home, turn = turn, cage = cage, prompt = prompt, ray = ray, moving = 0, nextAttack = 0, nextBite = 0, skip = {} }
	actors[model] = d
	d.joints = {}
	for _, obj in model:GetDescendants() do if obj:IsA("Motor6D") then d.joints[obj.Name] = obj end end
	state(d, "Caged")
	chainSoon(d)
	local connection = prompt.Triggered:Connect(function(player)
		local r = playerRoot(player)
		if r and (r.Position - button.Position).Magnitude <= 14 and player:GetAttribute("Map") == "ARENA" then
			Funnels.first(player, "BossEncountered")
			if d.state == "Caged" then release(d) else recall(d) end
		end
	end)
	model.Destroying:Connect(function() actors[model] = nil; connection:Disconnect() end)
	return model
end
-- The nearest dummy anywhere on the arena map (over its ground, not one it gave up on): (model, torso).
local function findTarget(d)
	local best, torso, distance = nil, nil, math.huge
	local now = os.clock()
	prey.each(function(model, part)
		if (d.skip[model] or 0) > now then return end
		local gap = (part.Position - d.root.Position).Magnitude
		if gap < distance and groundAt(part.Position, 2) then best, torso, distance = model, part, gap end
	end)
	return best, torso
end
-- No dummy left: a random spot on the arena ground, never in another boss's pit.
local function wanderGoal(d)
	for _ = 1, 6 do
		local spot = Vector3.new(math.random(-240, 240), 0, math.random(-240, 240))
		local y = groundAt(spot + Vector3.yAxis * 30, 0)
		local pit = false
		for kind, frame in LAIRS do
			if kind ~= d.kind and inDungeon(spot, frame) then pit = true end
		end
		if y and not pit then return Vector3.new(spot.X, y, spot.Z) end
	end
	return nil
end
local function face(d, position)
	local toward = (position - d.root.Position) * XZ
	if toward.Magnitude > 0.1 then d.root.CFrame = CFrame.lookAt(d.root.Position, d.root.Position + toward) end
end
-- Walls in its way get knocked down (structures only: the floor and the unbreakable stay).
local function smash(d, at)
	if os.clock() < (d.nextSmash or 0) then return end
	d.nextSmash = os.clock() + 0.4
	Map.blast(at, 4 * d.def.scale, 70, nil, true)
end
local function move(d, direction, speed, dt)
	local step = flat(direction) * speed * dt
	-- its body from knee height (a hedge stops it, a ramp or a kerb does not) up to the shoulders
	local hit = workspace:Blockcast(d.root.CFrame * CFrame.new(0, -1.25 * d.def.scale, 0), Vector3.new(4, 7.5, 3) * d.def.scale, step, d.ray)
	if hit and hit.Instance.Anchored then -- loose bricks it just wades through
		smash(d, hit.Position)
		return false
	end
	local nextPosition = d.root.Position + step
	-- follow the ground: off a plinth, up a step (never a climb taller than a step), never off an edge
	local ground = groundAt(nextPosition - Vector3.yAxis * 6 * d.def.scale, 5)
	if not ground then return false end
	step += Vector3.yAxis * (ground + 6 * d.def.scale - d.root.Position.Y)
	d.root.CFrame += step
	return true
end
local CRUSH = 6 -- blow power on a dummy (init.server hit()): enough to break the bone it lands on
local function strike(d)
	local center = d.impact
	Sfx.play({ Sfx.SLEDGEHAMMER_SLAM, 0.7, 1 }, center)
	Map.blast(center, d.def.radius * 0.5, 70, nil, true)
	prey.each(function(model, torso)
		if ((torso.Position - center) * XZ).Magnitude <= d.def.radius and math.abs(torso.Position.Y - center.Y) < 14 then
			prey.crush(model, center, CRUSH)
		end
	end)
	events:FireAllClients("Impact", center, d.def.radius, d.def.accent)
end
-- The dummy in its hands: lifted to the mouth (welded to the boss), bitten limb by limb, then gone.
local EAT_TIME, BITE_EVERY = 3.2, 0.7
function drop(d)
	if d.weld then d.weld:Destroy() end
	d.meal, d.weld = nil, nil
end
local function startEating(d, model, torso)
	if not prey.grab(model) then return false end
	torso.CFrame = d.root.CFrame * CFrame.new(0, 4.6 * d.def.scale, -3.4 * d.def.scale) * CFrame.Angles(math.pi / 2, 0, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Name, weld.Part0, weld.Part1, weld.Parent = "BossBite", d.root, torso, torso
	d.meal, d.weld, d.nextBite = model, weld, os.clock() + 0.5
	d.moving = 0
	state(d, "Eat", EAT_TIME)
	voice(d, Sfx.ZOMBIE_ATTACK)
	return true
end
local function chew(d, now)
	local model = d.meal
	if not (model and model.Parent and d.weld and d.weld.Parent) or prey.held(model) then
		drop(d) -- a player took it off it, or it is gone
		state(d, "Idle")
		return
	end
	if now >= d.untilTime then
		drop(d)
		prey.eat(model)
		voice(d, Sfx.ZOMBIE_DEATH, 0.7) -- a satisfied belch
		state(d, "Recovery", d.def.recovery)
	elseif os.clock() >= d.nextBite then
		d.nextBite = os.clock() + BITE_EVERY
		prey.bite(model, d.root.Position + Vector3.yAxis * 5 * d.def.scale)
	end
end
local function think(d, now)
	if d.state == "Caged" then return end
	if d.state == "Eat" then chew(d, now); return end
	if d.state == "Roar" then
		if now < d.untilTime then return end
		state(d, "Idle")
	end
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
	elseif (d.state == "Strike" or d.state == "Charge") and now >= d.untilTime then
		state(d, "Recovery", d.def.recovery)
		return
	elseif d.state == "Recovery" then
		if now < d.untilTime then return end
		state(d, "Idle")
	elseif d.state == "Windup" or d.state == "Strike" or d.state == "Charge" then return end
	-- stuck on something it cannot break: give up on that dummy (or spot) for a while
	if d.moving == 0 and (d.state == "Chase" or d.state == "Return") then
		d.stuck = (d.stuck or 0) + 1
		if d.stuck >= 30 then -- 3 s
			if d.chasing then d.skip[d.chasing] = os.clock() + 12 end
			d.goal, d.stuck = nil, 0
		end
	else d.stuck = 0 end
	local target, r = findTarget(d)
	d.chasing = target
	if not r then
		if not d.goal or ((d.goal - d.root.Position) * XZ).Magnitude < 4 then d.goal = wanderGoal(d) end
		if d.goal then state(d, "Return"); face(d, route(d, d.goal)) else state(d, "Idle"); d.moving = 0 end
		return
	end
	local dist = ((r.Position - d.root.Position) * XZ).Magnitude
	face(d, route(d, r.Position))
	if dist < 7 * d.def.scale + 3 and startEating(d, target, r) then return end
	-- one on its feet gets the attack first; one already down it just walks over to and eats
	if not target:GetAttribute("Ragdolled") and dist < d.def.reach and now >= d.nextAttack then
		local at = d.def.lunge and d.root.Position + flat(r.Position - d.root.Position) * d.def.lunge or r.Position
		d.impact = Vector3.new(at.X, (groundAt(Vector3.new(at.X, d.root.Position.Y, at.Z), 2) or 0) + 0.08, at.Z)
		d.model:SetAttribute("ImpactAt", d.impact)
		d.model:SetAttribute("ChargeDirection", flat(r.Position - d.root.Position))
		d.nextAttack = now + d.def.windup + d.def.recovery + 1
		d.moving = 0
		state(d, "Windup", d.def.windup)
		voice(d, Sfx.ZOMBIE_ATTACK)
	else state(d, "Chase"); d.moving = 1 end
end
-- `api` (init.server.luau) works on the dummies: each(fn(model, torso)), crush(model, from, power),
-- grab(model) -> ok, held(model), bite(model, from), eat(model).
function Monsters.start(remotes, api)
	if folder then return end
	prey = api
	folder = Instance.new("Folder"); folder.Name = "Monsters"; folder.Parent = workspace
	events = Instance.new("RemoteEvent"); events.Name = "MythFx"; events.Parent = remotes
	local ground = Instance.new("Folder"); ground.Name = "MythYard"; ground.Parent = workspace
	-- Studio only, for tests: ServerStorage.MythTest:Invoke(kind, "release" | "recall") does what the pedestal does
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction"); hook.Name = "MythTest"; hook.Parent = game:GetService("ServerStorage")
		hook.OnInvoke = function(kind, action)
			for _, d in actors do
				if d.kind == kind then
					if action == "release" then release(d) else recall(d) end
					return d.state
				end
			end
			return nil
		end
	end
	local floors, holes = {}, {}
	-- a lair-space rectangle as the world box round it (the lairs turn by quarter turns: still a rectangle)
	local function hole(frame, x0, x1, z0, z1)
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, corner in { Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z0), Vector3.new(x0, 0, z1), Vector3.new(x1, 0, z1) } do
			local w = frame:PointToWorldSpace(corner)
			lo, hi = lo:Min(w), hi:Max(w)
		end
		local function r(v) return math.round(v * 1000) / 1000 end
		table.insert(holes, { r(lo.X), r(hi.X), r(lo.Z), r(hi.Z) })
	end
	for _, frame in LAIRS do
		hole(frame, -PIT, PIT, -PIT, PIT)
		hole(frame, -RAMP_HALF - 1, RAMP_HALF + 1, PIT, PIT + RAMP_LONG)
	end
	-- the lairs are out on the rim round the arena (Map.build): cut the pits through it, walk on it
	local map = workspace:FindFirstChild("Map")
	local rim = map and map:FindFirstChild("Rim") -- breakable floor tiles (Map.build)
	if rim then
		carve(rim:GetChildren(), holes)
		table.insert(floors, rim)
	end
	local kitRoot = ReplicatedStorage:FindFirstChild("MythKit")
	local chainKit = kitRoot and kitRoot:FindFirstChild("Chain") and kitRoot.Chain:FindFirstChild("Parts")
	-- the lairs' props (Blender, assets/arena) when the arena kit is in
	local themed = ReplicatedStorage:FindFirstChild("ArenaKit") ~= nil
	for _, kind in { "Cyclops", "Minotaur", "Talos" } do
		local def = Definitions[kind]
		local frame = LAIRS[kind]
		local lair = LAIR_LOOK[kind]
		dungeon(ground, kind, frame, floors)
		local bottom = frame * CFrame.new(0, -DEEP, 0) -- the pit's floor, in lair space
		-- it stands in the middle of the pit's floor, looking up the ramp
		local home = bottom.Position + Vector3.yAxis * 6 * def.scale
		local cage = Instance.new("Model"); cage.Name = kind .. "Cage"; cage.Parent = ground
		cage:SetAttribute("Lair", frame)
		if themed then
			for _, prop in lair.props do
				Map.structure(prop[1], frame * CFrame.new(prop[2], 0, prop[3]) * CFrame.Angles(0, (prop[4] or 0) * math.pi / 2, 0))
			end
		end
		-- the pylons either side of the way out, facing out of the lair. Players bump into them; a boss's
		-- spatial queries do not see them (it never gets stuck on one: the way out passes between them).
		local pylonKit = kitRoot and kitRoot:FindFirstChild(kind) and kitRoot[kind]:FindFirstChild("Lair")
		pylonKit = pylonKit and pylonKit:FindFirstChild("Pylon")
		for _, side in { -1, 1 } do
			local cf = frame * CFrame.new(side * lair.pylon[1], 0, lair.pylon[2]) * CFrame.Angles(0, math.pi, 0)
			if pylonKit then
				placeKit(pylonKit, cf, 1, cage)
				local solid = slab(cage, "Pylon", Vector3.new(4.6, 26, 4.6), cf * CFrame.new(0, 13, 0), LOOK.wall, Enum.Material.Slate)
				solid.Transparency, solid.CanQuery, solid.CanTouch, solid.CastShadow = 1, false, false, false
			else
				for _, part in {
					slab(cage, "Pylon", Vector3.new(4, 22, 4), cf * CFrame.new(0, 11, 0), LOOK.wall, Enum.Material.Slate),
					slab(cage, "Pylon", Vector3.new(5.2, 1.2, 5.2), cf * CFrame.new(0, 22.6, 0), LOOK.marble, Enum.Material.Marble),
				} do part.CanQuery = false end
				local flame = slab(cage, "Flame", Vector3.new(2, 2.4, 2), cf * CFrame.new(0, 24.4, 0), LOOK.flame, Enum.Material.Neon)
				flame.CanCollide, flame.CanQuery, flame.CastShadow = false, false, false
			end
		end
		-- the chains' plates: on the side walls behind it for the wrists, in the floor for the ankles
		local plates = {}
		for name, spec in CHAINS do
			for _, side in { -1, 1 } do
				local c = spec.anchor
				local cf = if spec.floor
					then frame * CFrame.new(side * c.X, -DEEP - 0.05 + 0.32, c.Z) * CFrame.Angles(math.pi / 2, 0, 0)
					else frame * CFrame.new(side * c.X, c.Y, c.Z) * CFrame.Angles(0, side * math.pi / 2, 0)
				local anchor = chainKit and chainKit:FindFirstChild("Anchor")
				if anchor then placeKit(anchor, cf, 1, cage) else slab(cage, "Anchor", Vector3.new(3.2, 3.2, 0.6), cf, IRON, Enum.Material.Metal) end
				plates[name .. side] = cf * CFrame.new(0, -0.55, -1.15) -- the ring bolt
			end
		end
		-- its name board beside the way in, facing whoever comes up to it
		local entrance = block(ground, "EntranceSign", Vector3.new(14, 4.5, 0.8), Vector3.zero, Color3.fromRGB(28, 30, 33))
		entrance.CFrame = frame * CFrame.new(lair.sign[1], 5, lair.sign[2]) * CFrame.Angles(0, math.pi, 0)
		entrance.CanCollide = false
		plaque(entrance, def.name .. "\nLET ONE OUT  /  FEED IT DUMMIES", def.accent)
		-- the pedestal at the foot of the ramp, a small board on the boss's side of it
		local button = block(cage, "Challenge", Vector3.new(3, 2.5, 2.5), Vector3.zero, def.accent)
		button.CFrame = bottom * CFrame.new(0, 1.25, 18)
		local p = Instance.new("ProximityPrompt")
		p.ActionText, p.ObjectText = "Release", def.name
		p.KeyboardKeyCode, p.HoldDuration, p.MaxActivationDistance = Enum.KeyCode.Y, 0.4, 12
		p.RequiresLineOfSight, p.Parent = false, button
		local board = block(cage, "Sign", Vector3.new(9, 2.6, 0.4), Vector3.zero, Color3.fromRGB(28, 30, 33))
		board.CFrame = bottom * CFrame.new(0, 4.6, 15.5) * CFrame.Angles(0, math.pi, 0)
		board.CanCollide = false
		plaque(board, def.name .. "\n" .. def.hint, def.accent)
		Monsters.spawn(kind, home, cage, plates, chainKit)
	end
	if map then table.insert(floors, map) end -- out of the yard it walks the whole arena map
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
				if not move(d, d.chargeDirection, 42, math.min(dt, 0.1)) then state(d, "Recovery", d.def.recovery) end
				prey.each(function(model, torso)
					if not d.chargeVictims[model] and (torso.Position - d.root.Position).Magnitude < 8 * d.def.scale then
						d.chargeVictims[model] = true
						prey.crush(model, d.root.Position - d.chargeDirection * 3, CRUSH)
					end
				end)
			end
			if tickBrain then d.model:SetAttribute("Moving", d.moving) end
			if tickPose then
				local phase = math.clamp((now - d.since) / math.max(d.untilTime - d.since, 0.01), 0, 1)
				Rig.pose(d.joints, d.state, d.kind, now, d.moving, phase, math.clamp(1 - (now - (d.model:GetAttribute("HurtAt") or 0)) / 0.3, 0, 1), true)
			end
		end
		debug.profileend()
	end)
end
return Monsters
