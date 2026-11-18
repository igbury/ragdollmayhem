-- Destructible arena (Mayhem Park, see Map.build): a floor of anchored cubes over dark bedrock, plus structures built from
-- cubes (pillars, trees, walls, towers, arches, crates, rocks); a hit knocks out only the bricks it reaches.
-- Broken floor cubes are hidden (not destroyed) and come back after REGEN seconds.
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")
local Sfx = require(game:GetService("ReplicatedStorage").Shared.Sfx)

local Map = {}

local CUBE = 4 -- layout unit and floor depth
-- Both are only what a hit splits a block into (shatter): the map itself is whole CUBE blocks. ponytail: built
-- whole at these sizes it would be ~200k parts; split only where hit, a big blast makes a few thousand.
local TILE = CUBE / 4 -- floor columns and flying debris
local BRICK = CUBE / 4 -- structure bricks
local HALF = 80 -- arena is 2*HALF studs wide
local REGEN = 25
local LOOSE_LIFE = 6 -- knocked-out structure bricks are swept after this
local REBUILD_AT = 0.1 -- a structure comes back (REGEN later) only once 90% of its bricks are gone
local IDLE_REPAIR = 45 -- or, damaged at all, once nothing has hit it for this long: the missing bricks slide back
local LAYER_DELAY = 0.15 -- rebuilt structures rise one brick layer at a time
local WAVE = 0.04 -- s per stud along a layer: its bricks slide in one after another, as a wave
local SLIDE = 8 -- studs a rebuilt brick slides in from
local MAX_CHUNKS = 140 -- flying cubes per blast
local MAX_DEBRIS = 250 -- loose cubes alive at once across all blasts, past it the oldest are removed
local MAX_FLYING = 160 -- loose bricks one hit throws out of split blocks (shatter)
local GRASS = { Color3.fromRGB(40, 170, 80), Color3.fromRGB(34, 150, 70) }
local DIRT = Color3.fromRGB(120, 85, 60)
local STONE = Color3.fromRGB(190, 182, 170)
local WOOD = Color3.fromRGB(128, 82, 52)
local LEAF = Color3.fromRGB(30, 125, 55)
local BRICK_RED = Color3.fromRGB(170, 95, 80)
local CRATE = Color3.fromRGB(196, 150, 92)
local ROCK = Color3.fromRGB(120, 122, 130)
local GATE = Color3.fromRGB(200, 50, 45)

-- Loose cubes pass through each other: a pile of hundreds colliding pairwise drops physics to
-- ~10 fps, and nobody can tell in the chaos. They still hit the floor, players and dummies.
PhysicsService:RegisterCollisionGroup("Debris")
PhysicsService:CollisionGroupSetCollidable("Debris", "Debris", false)

local folder = Instance.new("Folder")
folder.Name = "Map"
Map.folder = folder
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { folder }

-- Plastic parts get the classic brick look: studs on top, weld on every other face.
local function studs(p: BasePart)
	if p.Material ~= Enum.Material.Plastic then
		return
	end
	p.TopSurface = Enum.SurfaceType.Studs
	for _, face in { "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" } do
		p[face] = Enum.SurfaceType.Weld
	end
end
Map.studs = studs

local function block(size: Vector3, position: Vector3, color: Color3, material: Enum.Material, parent: Instance)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	studs(p)
	p.Parent = parent
	return p
end

local loose = {} -- live loose cubes, oldest first
local function track(p: BasePart)
	table.insert(loose, p)
	p.Destroying:Once(function()
		local i = table.find(loose, p)
		if i then
			table.remove(loose, i)
		end
	end)
	if #loose > MAX_DEBRIS then
		table.remove(loose, 1):Destroy() -- newest always shows, the oldest makes room
	end
end

local function chunk(source: BasePart, size: number, velocity: Vector3)
	local p = Instance.new("Part")
	p.Size = Vector3.one * size
	p.Color = math.random() < 0.3 and DIRT or source.Color
	p.Material = source.Material
	studs(p)
	p.CFrame = source.CFrame + Vector3.new(0, CUBE / 2, 0)
	p.CollisionGroup = "Debris"
	track(p)
	p.Parent = workspace
	p.AssemblyLinearVelocity = velocity
	p.AssemblyAngularVelocity = Vector3.new(math.random(-12, 12), math.random(-12, 12), math.random(-12, 12))
	task.delay(4.5, function()
		TweenService:Create(p, TweenInfo.new(0.5), { Size = Vector3.one * 0.1 }):Play()
	end)
	Debris:AddItem(p, 5)
end

local function setHidden(cubes: { BasePart }, hidden: boolean)
	for _, cube in cubes do
		cube.Transparency = hidden and 1 or 0
		cube.CanCollide = not hidden
		cube.CanQuery = not hidden -- also keeps hidden ones out of later blasts
	end
end

-- Big blocks and floor tiles stay one part until a hit reaches them; then they split into their small
-- pieces in place (shatter), so the map has few parts but still breaks into small cubes. The "Piece"
-- attribute holds the size of the pieces a whole part splits into (an attribute, not a weak table:
-- Instance keys nothing else in Luau holds get collected).

local function hide(cubes: { BasePart })
	setHidden(cubes, true)
	task.delay(REGEN, setHidden, cubes, false)
end

-- Total size of what is left of a structure (split pieces count by volume, like the block they came from).
local function bulk(parts: { Instance }): number
	local v = 0
	for _, b in parts do
		if b:IsA("BasePart") then
			v += b.Size.X * b.Size.Y * b.Size.Z
		end
	end
	return v
end

-- Each kind lists its cubes through add(x, y, z, color, material, size?), in cube-grid units
-- relative to the structure's origin on the ground. Other maps (Factory) add their own kinds.
local KINDS = {}
Map.KINDS = KINDS

function KINDS.Pillar(add)
	for y = 0, 6 do
		for x = 0, 1 do
			for z = 0, 1 do
				add(x - 0.5, y, z - 0.5, STONE, Enum.Material.Slate)
			end
		end
	end
end

function KINDS.Tree(add)
	for y = 0, 2 do
		add(0, y, 0, WOOD, Enum.Material.Wood)
	end
	for y = 3, 4 do
		for x = -1, 1 do
			for z = -1, 1 do
				add(x, y, z, LEAF, Enum.Material.Grass)
			end
		end
	end
	add(0, 5, 0, LEAF, Enum.Material.Grass)
end

function KINDS.Wall(add)
	for x = -3, 3 do
		for y = 0, 2 do
			add(x, y, 0, (x + y) % 2 == 0 and BRICK_RED or STONE, Enum.Material.Brick)
		end
	end
end

function KINDS.Tower(add) -- hollow, so it caves in on itself
	for y = 0, 5 do
		for x = -1, 1 do
			for z = -1, 1 do
				if x ~= 0 or z ~= 0 then
					add(x, y, z, y % 2 == 0 and STONE or ROCK, Enum.Material.Cobblestone)
				end
			end
		end
	end
end

function KINDS.Arch(add)
	for y = 0, 3 do
		add(-2, y, 0, GATE, Enum.Material.Wood)
		add(2, y, 0, GATE, Enum.Material.Wood)
	end
	for x = -3, 3 do
		add(x, 4, 0, GATE, Enum.Material.Wood)
	end
end

function KINDS.Crates(add)
	for _, c in { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 0.5, 1, 0.5 }, { -1, 0, 0.5 } } do
		add(c[1], c[2], c[3], CRATE, Enum.Material.WoodPlanks)
	end
end

function KINDS.Rock(add)
	add(0, 0.25, 0, ROCK, Enum.Material.Slate, 6)
	add(1, 0, 0.75, ROCK, Enum.Material.Slate)
	add(-0.75, 0, -1, ROCK, Enum.Material.Slate)
	add(0.25, 1.4, 0, ROCK, Enum.Material.Slate, 3)
end

-- Which bricks touch face to face, and which stand on the ground: a brick with no path of touching
-- bricks down to the ground falls (settle). Positions are in `origin` space; structures only turn
-- in quarter turns, so brick sizes line up with its axes.
-- Pairs are found through a grid of cells as big as the biggest brick, so only bricks in
-- neighbouring cells get compared.
local neighbours = setmetatable({}, { __mode = "k" }) -- [brick] = { touching bricks }
local grounded = setmetatable({}, { __mode = "k" }) -- [brick] = true when it stands on the ground
-- Joins a and b if they share a face; `d` is a - b in origin space.
local function pair(a: BasePart, b: BasePart, d: Vector3)
	local h = (a.Size + b.Size) / 2
	local x, y, z = math.abs(d.X), math.abs(d.Y), math.abs(d.Z)
	if x <= h.X + 0.05 and y <= h.Y + 0.05 and z <= h.Z + 0.05 then
		-- overlapping on two axes = sharing a face, not just an edge or a corner
		local shared = (x < h.X - 0.05 and 1 or 0) + (y < h.Y - 0.05 and 1 or 0) + (z < h.Z - 0.05 and 1 or 0)
		if shared >= 2 then
			table.insert(neighbours[a], b)
			table.insert(neighbours[b], a)
		end
	end
end

local function link(bricks: { BasePart }, origin: CFrame)
	local at, cellSize = {}, 0
	for i, b in bricks do
		at[i] = origin:PointToObjectSpace(b.Position)
		neighbours[b] = {}
		grounded[b] = at[i].Y - b.Size.Y / 2 < 0.1 or nil
		cellSize = math.max(cellSize, b.Size.X, b.Size.Y, b.Size.Z)
	end
	local cells, cellOf = {}, {}
	for i in bricks do
		local c = at[i] / cellSize
		cellOf[i] = { math.floor(c.X), math.floor(c.Y), math.floor(c.Z) }
		local key = table.concat(cellOf[i], ",")
		cells[key] = cells[key] or {}
		table.insert(cells[key], i)
	end
	for i, a in bricks do
		local cx, cy, cz = table.unpack(cellOf[i])
		for dx = -1, 1 do
			for dy = -1, 1 do
				for dz = -1, 1 do
					for _, j in cells[`{cx + dx},{cy + dy},{cz + dz}`] or {} do
						if j <= i then
							continue
						end
						pair(a, bricks[j], at[i] - at[j])
					end
				end
			end
		end
	end
end

-- A brick's place in its structure (origin space, to a tenth of a stud): finds the same brick again.
local function slot(origin: CFrame, position: Vector3): string
	local at = origin:PointToObjectSpace(position)
	return `{math.round(at.X * 10)},{math.round(at.Y * 10)},{math.round(at.Z * 10)}`
end

-- Split every whole block/tile among `hits` into its pieces and return what the hit breaks: the
-- untouched parts of `hits` plus the pieces in reach. Only the pieces that stay or fly are made:
--  * `reach(cf, size, floor)`: a piece there is broken by the hit.
--  * floor pieces in reach are never made: the tile comes back whole REGEN later, in place of what
--    is left round the hole; a tile wholly in reach (`inside`) is not split at all, just hidden.
--  * of the structure pieces in reach only MAX_FLYING per hit are made (and fly); the rest just go,
--    MAX_DEBRIS would sweep them at once anyway. Making them all stalled the server ~200 ms a blast.
-- `standing`: leave the floor whole.
local function shatter(hits: { BasePart }, standing: boolean?, inside: (BasePart) -> boolean, reach: (CFrame, Vector3, boolean) -> boolean): { BasePart }
	local out, plans, flying = {}, {}, 0
	for _, whole in hits do
		local piece, parent = whole:GetAttribute("Piece"), whole.Parent
		local floor = parent == folder
		if not piece or not parent or (floor and (standing or inside(whole))) then
			table.insert(out, whole)
			continue
		end
		local n = Vector3.new(math.round(whole.Size.X / piece.X), math.round(whole.Size.Y / piece.Y), math.round(whole.Size.Z / piece.Z))
		local size = whole.Size / n
		local cells = {}
		for x = 1, n.X do
			for y = 1, n.Y do
				for z = 1, n.Z do
					local cf = whole.CFrame * CFrame.new((Vector3.new(x, y, z) - (n + Vector3.one) / 2) * size)
					local hit = reach(cf, size, floor)
					table.insert(cells, { cf, hit })
					if hit and not floor then
						flying += 1
					end
				end
			end
		end
		table.insert(plans, { whole, parent, floor, size, cells })
	end
	local keep = math.min(1, MAX_FLYING / math.max(flying, 1))
	for _, plan in plans do
		local whole, parent, floor, size, cells = table.unpack(plan)
		local stay = {}
		for _, c in cells do
			if c[2] and (floor or math.random() >= keep) then
				continue
			end
			local p = whole:Clone() -- keeps colour, material, surfaces, shadow
			p:SetAttribute("Piece", nil)
			p.Size = size
			p.CFrame = c[1]
			p.Parent = parent
			table.insert(c[2] and out or stay, p)
		end
		whole.Parent = nil
		if floor then
			task.delay(REGEN, function()
				for _, p in stay do
					p:Destroy()
				end
				whole.Parent = folder
			end)
		else
			-- link only the pieces that stay: to each other and to what the block touched (relinking
			-- the whole structure is ~100 ms once it is full of small bricks)
			local origin = parent:GetAttribute("Origin") or CFrame.identity
			local around = neighbours[whole] or {}
			for _, p in stay do
				neighbours[p] = {}
				grounded[p] = origin:PointToObjectSpace(p.Position).Y - p.Size.Y / 2 < 0.1 or nil
			end
			for i, p in stay do
				for j = i + 1, #stay do
					pair(p, stay[j], origin:VectorToObjectSpace(p.Position - stay[j].Position))
				end
				for _, nb in around do
					if nb.Parent == parent then
						pair(p, nb, origin:VectorToObjectSpace(p.Position - nb.Position))
					end
				end
			end
			whole:Destroy()
		end
	end
	return out
end

-- `keep` (a repair): bricks in these slots are still standing, so they are put straight back and
-- only the rest slide in.
local function buildStructure(kind: string, origin: CFrame, layered: boolean?, keep: { [string]: boolean }?)
	local model = Instance.new("Model")
	model.Name = kind
	local bricks = {}
	KINDS[kind](function(x, y, z, color, material, size)
		size = size or CUBE
		-- one part per block; a hit splits it into BRICK-sized bricks (shatter) so it still breaks small
		local cube = block(Vector3.one * size, Vector3.zero, color, material, nil)
		cube.CFrame = origin * CFrame.new(x * CUBE, y * CUBE + size / 2, z * CUBE)
		local n = math.round(size / BRICK)
		if n > 1 then
			cube:SetAttribute("Piece", Vector3.one * (size / n))
		end
		table.insert(bricks, cube)
	end)
	model:SetAttribute("Origin", origin)
	model:SetAttribute("Total", bulk(bricks))
	link(bricks, origin)
	model.Parent = folder
	if not layered then
		for _, cube in bricks do
			cube.Parent = model
		end
		return
	end
	-- rebuild from the ground up: each layer slides in from the side, as a wave along the structure
	model:SetAttribute("Rebuilding", true)
	if keep then
		local missing = {}
		for _, cube in bricks do
			if keep[slot(origin, cube.Position)] then
				cube.Parent = model
			else
				table.insert(missing, cube)
			end
		end
		bricks = missing
	end
	local layers, lowX = {}, math.huge
	for _, cube in bricks do
		local at = origin:PointToObjectSpace(cube.Position)
		lowX = math.min(lowX, at.X)
		table.insert(layers, math.round(at.Y * 10))
	end
	local ys = {}
	for _, y in layers do
		ys[y] = true
	end
	local order = {}
	for y in ys do
		table.insert(order, y)
	end
	table.sort(order)
	local rank = {}
	for i, y in order do
		rank[y] = i - 1
	end
	local last = 0
	for i, cube in bricks do
		local target = cube.CFrame
		local delay = rank[layers[i]] * LAYER_DELAY + (origin:PointToObjectSpace(cube.Position).X - lowX) * WAVE
		last = math.max(last, delay)
		cube.CFrame = target - origin.RightVector * SLIDE
		cube.Transparency = 1
		cube.CanCollide, cube.CanQuery = false, false -- not hit or in the way while still sliding
		cube.Parent = model
		local tween = TweenService:Create(cube, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay), { CFrame = target, Transparency = 0 })
		tween.Completed:Once(function()
			cube.CanCollide, cube.CanQuery = true, true
		end)
		tween:Play()
	end
	task.delay(last + 0.4, model.SetAttribute, model, "Rebuilding", nil)
end
Map.structure = buildStructure

-- A grave a dummy dug: a mound and a headstone with the name on it, at `origin` (on the ground,
-- the stone at its -Z end). Built of small bricks so a hit shatters it like the rest of the map;
-- once broken it does not come back.
function Map.grave(origin: CFrame, name: string)
	local model = Instance.new("Model")
	model.Name = "Grave"
	local function slab(size: Vector3, at: Vector3, color: Color3, material: Enum.Material)
		local n = Vector3.new(math.max(1, math.round(size.X / 0.6)), math.max(1, math.round(size.Y / 0.6)), math.max(1, math.round(size.Z / 0.6)))
		local brick = size / n
		for x = 1, n.X do
			for y = 1, n.Y do
				for z = 1, n.Z do
					local cube = block(brick, Vector3.zero, color, material, model)
					cube.CFrame = origin * CFrame.new(at + (Vector3.new(x, y, z) - (n + Vector3.one) / 2) * brick)
				end
			end
		end
	end
	slab(Vector3.new(2.4, 0.6, 4.2), Vector3.new(0, 0.3, 0.6), DIRT, Enum.Material.Ground)
	slab(Vector3.new(2.4, 3, 0.6), Vector3.new(0, 1.5, -1.8), STONE, Enum.Material.Slate)
	local plate = block(Vector3.new(2.2, 1.6, 0.05), Vector3.zero, STONE, Enum.Material.Slate, model)
	plate.CFrame = origin * CFrame.new(0, 1.9, -1.8 + 0.33)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- toward the mound
	gui.PixelsPerStud = 60
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Garamond
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(60, 56, 52)
	text.Text = "R.I.P.\n" .. name
	text.Parent = gui
	gui.Parent = plate
	model:SetAttribute("Total", bulk(model:GetChildren()))
	link(model:GetChildren(), origin)
	model.Parent = folder
	return model
end

-- A breakable floor/deck tile: blasts hide it, it comes back after REGEN.
-- `piece`: split into columns this size when hit (a big tile that still breaks small).
function Map.tile(size: Vector3, position: Vector3, color: Color3, material: Enum.Material, piece: Vector3?)
	local p = block(size, position, color, material, folder)
	p:SetAttribute("Piece", piece)
	return p
end

-- Knock one brick out of its structure: only what the hit reaches breaks off.
local function knock(cube: BasePart, from: Vector3, power: number)
	local offset = cube.Position - from
	cube.Parent = workspace -- out of the structure (and out of later blasts)
	cube.CollisionGroup = "Debris"
	cube.Anchored = false
	track(cube)
	local out = offset.Magnitude > 0.1 and offset.Unit or Vector3.yAxis
	cube.AssemblyLinearVelocity = out * power * math.clamp(1.2 - offset.Magnitude / 24, 0.2, 1)
	cube.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
	Debris:AddItem(cube, LOOSE_LIFE)
end

-- Once 90% of a structure is gone the rest falls and it rebuilds REGEN later, bottom up.
local function damaged(model: Model)
	if model.Parent ~= folder or model:GetAttribute("Rebuilding") then
		return
	end
	local left = model:GetChildren()
	if bulk(left) > (model:GetAttribute("Total") or 0) * REBUILD_AT then
		return
	end
	model.Parent = nil
	for _, cube in left do
		if cube:IsA("BasePart") then
			knock(cube, cube.Position + Vector3.yAxis, 5)
		end
	end
	task.delay(REGEN, function()
		model:Destroy()
		if model:GetAttribute("Origin") then -- a grave (Map.grave) stays broken
			buildStructure(model.Name, model:GetAttribute("Origin"), true)
		end
	end)
end

-- Gravity: bricks no longer joined to the ground through touching bricks drop, and count as destroyed.
local function settle(model: Model)
	local held, stack = {}, {}
	for _, b in model:GetChildren() do
		if grounded[b] then
			held[b] = true
			table.insert(stack, b)
		end
	end
	while #stack > 0 do
		for _, n in neighbours[table.remove(stack)] or {} do
			if not held[n] and n.Parent == model then
				held[n] = true
				table.insert(stack, n)
			end
		end
	end
	for _, b in model:GetChildren() do
		if not held[b] and b:IsA("BasePart") then
			knock(b, b.Position, 0)
		end
	end
end

-- Break sound by material; anything not listed (slate, cobble, marble, concrete, grass...) sounds like stone.
local BREAK_SOUND = {
	[Enum.Material.Brick] = Sfx.BRICK,
	[Enum.Material.Wood] = Sfx.WOOD,
	[Enum.Material.WoodPlanks] = Sfx.WOOD,
	[Enum.Material.Metal] = Sfx.METAL,
	[Enum.Material.DiamondPlate] = Sfx.METAL,
	[Enum.Material.CorrodedMetal] = Sfx.METAL,
	[Enum.Material.Foil] = Sfx.METAL,
}

-- One sound per material among the broken cubes, at the hit.
local function breakSounds(cubes: { BasePart }, at: Vector3)
	local played = {}
	for _, cube in cubes do
		local id = BREAK_SOUND[cube.Material] or Sfx.STONE
		if not played[id] then
			played[id] = true
			Sfx.play(id, at)
		end
	end
end

-- Put back what is missing from a structure that is still standing (the bricks left stay as they are).
local function repair(model: Model)
	local origin = model:GetAttribute("Origin")
	local keep = {}
	for _, b in model:GetChildren() do
		if b:IsA("BasePart") then
			keep[slot(origin, b.Position)] = true
		end
	end
	buildStructure(model.Name, origin, true, keep)
	model:Destroy() -- same frame as the new one appears: the bricks that stayed never blink
end

-- Each hit restarts the structure's clock; IDLE_REPAIR after the last one it mends itself.
local lastHit = setmetatable({}, { __mode = "k" }) -- [model] = os.clock() of its latest hit
local function idleCheck(model: Model, stamp: number)
	if lastHit[model] ~= stamp or model.Parent ~= folder or not model:GetAttribute("Origin") then
		return -- hit again since, fell down whole (it rebuilds on its own), or a grave (stays broken)
	end
	if model:GetAttribute("Rebuilding") then
		task.delay(1, idleCheck, model, stamp)
		return
	end
	if bulk(model:GetChildren()) < (model:GetAttribute("Total") or 0) - 1 then
		repair(model)
	end
end

-- Structure bricks among `hits` break off, what they held up falls, then each structure hit is checked for a rebuild.
-- Returns the bricks knocked out.
local function hitStructures(hits: { BasePart }, from: Vector3, power: number): { BasePart }
	local models, knocked = {}, {}
	for _, cube in hits do
		local model = cube.Parent
		if model ~= folder and model and model.Parent == folder then
			models[model] = true
			knock(cube, from, power)
			table.insert(knocked, cube)
		end
	end
	local now = os.clock()
	for model in models do
		settle(model)
		damaged(model)
		lastHit[model] = now
		task.delay(IDLE_REPAIR, idleCheck, model, now)
	end
	return knocked
end

-- Carve a crater. `inner` leaves an untouched island in the middle (ring crater). `standing`: only
-- break structures (walls, pillars), not the floor tiles in reach.
function Map.blast(position: Vector3, radius: number, power: number, inner: number?, standing: boolean?)
	local function inside(tile: BasePart): boolean
		local d, h = ((tile.Position - position) * Vector3.new(1, 0, 1)).Magnitude, tile.Size.X * 0.71
		return d + h <= radius and d - h >= (inner or 0)
	end
	local function reach(cf: CFrame, size: Vector3, floor: boolean): boolean
		if floor then -- the same test the floor loop below makes
			local d = ((cf.Position - position) * Vector3.new(1, 0, 1)).Magnitude
			return d <= radius and d >= (inner or 0)
		end
		local at = cf:PointToObjectSpace(position) -- nearest point of the piece to the centre
		local h = size / 2
		local near = Vector3.new(math.clamp(at.X, -h.X, h.X), math.clamp(at.Y, -h.Y, h.Y), math.clamp(at.Z, -h.Z, h.Z))
		return (at - near).Magnitude <= radius
	end
	local hits = shatter(workspace:GetPartBoundsInRadius(position, radius, params), standing, inside, reach)
	local broken = hitStructures(hits, position, power)
	local chance = math.min(1, MAX_CHUNKS / math.max(#hits, 1))
	local floor = {}
	for _, cube in hits do
		if cube.Parent ~= folder or standing then
			continue
		end
		local offset = (cube.Position - position) * Vector3.new(1, 0, 1)
		if offset.Magnitude > radius or offset.Magnitude < (inner or 0) then
			continue
		end
		table.insert(floor, cube)
		table.insert(broken, cube)
		if math.random() < chance then
			local out = offset.Magnitude > 0.1 and offset.Unit or Vector3.zero
			local velocity = (out * (0.3 + math.random() * 0.5) + Vector3.yAxis * (0.6 + math.random() * 0.6)) * power
			chunk(cube, TILE * (0.7 + math.random() * 0.6), velocity)
		end
	end
	hide(floor)
	breakSounds(broken, position)
end

-- Rip a rectangular slab out of the floor and throw it up as cubes.
function Map.flip(cf: CFrame, size: Vector3, velocity: Vector3)
	local function inside(tile: BasePart): boolean
		local at, h = cf:PointToObjectSpace(tile.Position), tile.Size.X * 0.71
		return math.abs(at.X) + h <= size.X / 2 and math.abs(at.Z) + h <= size.Z / 2
	end
	local function reach(piece: CFrame, extent: Vector3, _floor: boolean): boolean
		local at, h = cf:PointToObjectSpace(piece.Position), extent * 0.87 -- roughly: its box overlaps the slab
		return math.abs(at.X) <= size.X / 2 + h.X and math.abs(at.Y) <= size.Y / 2 + h.Y and math.abs(at.Z) <= size.Z / 2 + h.Z
	end
	local hits = shatter(workspace:GetPartBoundsInBox(cf, size, params), nil, inside, reach)
	local broken = hitStructures(hits, cf.Position, velocity.Magnitude)
	local chance = math.min(1, MAX_CHUNKS * 1.5 / math.max(#hits, 1))
	local floor = {}
	for _, cube in hits do
		if cube.Parent ~= folder then
			continue
		end
		table.insert(floor, cube)
		table.insert(broken, cube)
		if math.random() < chance then
			chunk(cube, TILE * (0.9 + math.random() * 0.5), velocity * (0.7 + math.random() * 0.6))
		end
	end
	hide(floor)
	breakSounds(broken, cf.Position)
end

-- Mayhem Park ---------------------------------------------------------------------------------
-- The destructible arena (2*HALF square, x east, -z north) is split into themed zones round a
-- stone plaza: a statue to the north, a little town (NE), a park (NW), a ragdoll bowling lane
-- (SW) and a building site (SE), joined by cobbled paths. Outside it, on the solid rim, the
-- landmarks nothing can break: a launch ramp with a target to land on (N), a parkour canyon
-- (E), a drop tower (W) and a trampoline field (S). Plan: the "Ragdoll Mayhem — nowa mapa" design.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local PLAZA = Color3.fromRGB(176, 170, 160)
local PLAZA_DARK = Color3.fromRGB(150, 144, 136)
local PATH = Color3.fromRGB(160, 150, 136)
local ASPHALT = Color3.fromRGB(78, 77, 86)
local PAVEMENT = Color3.fromRGB(132, 130, 138)
local PARK = { Color3.fromRGB(46, 140, 72), Color3.fromRGB(40, 126, 64) }
local LANE = Color3.fromRGB(206, 160, 100)
local SAND = Color3.fromRGB(200, 164, 110)
local MARBLE = Color3.fromRGB(226, 222, 214)
local WATER = Color3.fromRGB(70, 150, 220)
local ROOF = Color3.fromRGB(70, 60, 74)
local STEEL = Color3.fromRGB(224, 160, 48)
local PLANK = Color3.fromRGB(150, 110, 70)

-- the statue on its plinth, facing +Z (the plaza): a stone dummy, fists on its hips
function KINDS.Statue(add)
	for x = -1, 1 do
		for z = -1, 1 do
			add(x, 0, z, PLAZA_DARK, Enum.Material.Slate) -- plinth
		end
	end
	for y = 1, 2 do -- legs
		add(-0.5, y, 0, MARBLE, Enum.Material.Marble)
		add(0.5, y, 0, MARBLE, Enum.Material.Marble)
	end
	for y = 3, 4 do -- body
		add(-0.5, y, 0, MARBLE, Enum.Material.Marble)
		add(0.5, y, 0, MARBLE, Enum.Material.Marble)
	end
	add(-1.5, 4, 0, MARBLE, Enum.Material.Marble) -- arms out at the elbows
	add(1.5, 4, 0, MARBLE, Enum.Material.Marble)
	add(-1.5, 3, 0, MARBLE, Enum.Material.Marble)
	add(1.5, 3, 0, MARBLE, Enum.Material.Marble)
	add(0, 5, 0, MARBLE, Enum.Material.Marble) -- head
end

-- a brick house with a flat roof, the door on its +X side
function KINDS.House(add)
	for y = 0, 1 do
		for x = -2, 2 do
			for z = -2, 1 do
				local edge = x == -2 or x == 2 or z == -2 or z == 1
				local door = x == 2 and z == 0 -- 4 wide, 8 high
				local window = y == 1 and (z == -2 or z == 1) and x == 0
				if edge and not door and not window then
					add(x, y, z, (x + z + y) % 3 == 0 and STONE or BRICK_RED, Enum.Material.Brick)
				end
			end
		end
	end
	for x = -2, 2 do
		for z = -2, 1 do
			add(x, 2, z, ROOF, Enum.Material.Slate)
		end
	end
end

-- a round basin of marble with water standing in it and a column in the middle
function KINDS.Fountain(add)
	for x = -4, 4 do
		for z = -4, 4 do
			if math.max(math.abs(x), math.abs(z)) == 4 then
				add(x * 0.5, 0, z * 0.5, MARBLE, Enum.Material.Marble, 2)
			elseif math.abs(x) > 0 or math.abs(z) > 0 then
				add(x * 0.5, -0.1, z * 0.5, WATER, Enum.Material.Glass, 2)
			end
		end
	end
	for y = 0, 2 do
		add(0, y, 0, MARBLE, Enum.Material.Marble)
	end
end

function KINDS.Bench(add)
	for x = -1, 1 do
		add(x * 0.5, 0.5, 0, WOOD, Enum.Material.WoodPlanks, 2)
		add(x * 0.5, 1, 0.5, WOOD, Enum.Material.WoodPlanks, 2) -- the back
	end
	add(-0.5, 0, 0, ROCK, Enum.Material.Metal, 2)
	add(0.5, 0, 0, ROCK, Enum.Material.Metal, 2)
end

-- scaffolding: four poles and two plank decks (12 and 24 studs up), crates stacked into steps
function KINDS.Scaffold(add)
	for k = 0, 13 do
		for _, c in { { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } } do
			add(c[1], k * 0.5, c[2], STEEL, Enum.Material.Metal, 2)
		end
	end
	for _, y in { 3, 6 } do
		for x = -3, 3 do
			for z = -3, 3 do
				if math.abs(x) < 3 or math.abs(z) < 3 then
					add(x * 0.5, y, z * 0.5, PLANK, Enum.Material.WoodPlanks, 2)
				end
			end
		end
	end
	for step = 0, 2 do -- the way up: one crate, two, three
		for h = 0, step do
			add(-4.5 + step, h, 0, CRATE, Enum.Material.WoodPlanks)
		end
	end
end

-- a short stone post (the plaza ring)
function KINDS.Post(add)
	for y = 0, 2 do
		add(0, y * 0.5, 0, PLAZA_DARK, Enum.Material.Slate, 2)
	end
	add(0, 1.5, 0, MARBLE, Enum.Material.Marble, 2)
end

-- What the floor tile at (x, z) is made of.
local function floorLook(x: number, z: number, ix: number, iz: number): (Color3, Enum.Material)
	local r = math.sqrt(x * x + z * z)
	if r < 20 then -- plaza: rings of stone
		return (r // 4) % 2 == 0 and PLAZA or PLAZA_DARK, Enum.Material.Cobblestone
	end
	if math.abs(x) < 3 or math.abs(z) < 3 then -- the four paths out of it
		return PATH, Enum.Material.Cobblestone
	end
	if x > 0 and z < 0 then -- town: a street between two rows of houses, pavement round them
		return math.abs(x - 52) < 4 and ASPHALT or PAVEMENT, math.abs(x - 52) < 4 and Enum.Material.Asphalt or Enum.Material.Pavement
	end
	if x < 0 and z > 0 and math.abs(z - 52) < 5 and x < -24 then -- the bowling lane
		return LANE, Enum.Material.WoodPlanks
	end
	if x > 0 and z > 0 then -- building site
		return SAND, Enum.Material.Sand
	end
	if x < 0 and z < 0 then -- park
		return PARK[(ix // 6 + iz // 6) % 2 + 1], Enum.Material.Grass
	end
	return GRASS[(ix // 6 + iz // 6) % 2 + 1], Enum.Material.Grass
end

-- Unbreakable pieces outside the arena (and the bowling lane's rails): plain anchored parts.
local landmarks = Instance.new("Folder")
landmarks.Name = "Landmarks"
local function solid(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = landmarks
	return p
end

-- A zone name floating over it, readable from across the arena.
local function sign(text: string, position: Vector3, color: Color3)
	local anchor = solid(Vector3.one, CFrame.new(position), color)
	anchor.Transparency = 1
	anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(18, 4)
	gui.MaxDistance = 170
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(20, 18, 26)
	label.Parent = gui
	gui.Parent = anchor
end

-- A pad that throws whatever lands on it straight up. Dummies (server-owned) are thrown here;
-- a player's client owns its character, so it reads the "Bounce" attribute and jumps itself.
local function trampoline(position: Vector3, diameter: number, bounce: number)
	local flat = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder lies along X: stand it on its end
	solid(Vector3.new(1.2, diameter + 1.2, diameter + 1.2), CFrame.new(position + Vector3.yAxis * 0.6) * flat, Color3.fromRGB(57, 208, 230), Enum.Material.Neon, Enum.PartType.Cylinder)
	local pad = solid(Vector3.new(1.4, diameter, diameter), CFrame.new(position + Vector3.yAxis * 0.7) * flat, Color3.fromRGB(43, 42, 51), Enum.Material.Rubber, Enum.PartType.Cylinder)
	pad.Name = "Trampoline"
	pad:SetAttribute("Bounce", bounce)
	local recent = setmetatable({}, { __mode = "k" })
	pad.Touched:Connect(function(other)
		local model = other:FindFirstAncestorOfClass("Model")
		if not model or Players:GetPlayerFromCharacter(model) or recent[model] and os.clock() - recent[model] < 0.4 then
			return
		end
		if model:FindFirstChildOfClass("Humanoid") then
			recent[model] = os.clock()
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and not part.Anchored then
					local v = part.AssemblyLinearVelocity
					part.AssemblyLinearVelocity = Vector3.new(v.X * 0.6, bounce, v.Z * 0.6)
				end
			end
		elseif not other.Anchored then -- a cut-off limb, a crate brick
			local v = other.AssemblyLinearVelocity
			other.AssemblyLinearVelocity = Vector3.new(v.X, bounce * 0.8, v.Z)
		end
	end)
end

-- Ragdoll bowling: ten real pins at the far end of the lane. A board counts them down; they
-- stand again a few seconds after the last one falls.
local PIN_RESET = 6
local function bowling(laneZ: number, headX: number)
	local pins = {}
	local stand = CFrame.Angles(0, 0, math.pi / 2)
	for row = 0, 3 do
		for i = 0, row do
			local home = CFrame.new(headX - row * 2.2, 2.3, laneZ + (i - row / 2) * 2.4) * stand
			local pin = Instance.new("Part")
			pin.Name = "Pin"
			pin.Shape = Enum.PartType.Cylinder
			pin.Size = Vector3.new(4.4, 1.5, 1.5)
			pin.Color = Color3.fromRGB(245, 242, 236)
			pin.Material = Enum.Material.SmoothPlastic
			pin.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.4, 0.3)
			pin.CFrame = home
			local stripe = Instance.new("Part")
			stripe.Shape = Enum.PartType.Cylinder
			stripe.Size = Vector3.new(0.5, 1.55, 1.55)
			stripe.Color = Color3.fromRGB(214, 48, 49)
			stripe.Material = Enum.Material.SmoothPlastic
			stripe.Massless, stripe.CanCollide, stripe.CanQuery = true, false, false
			stripe.CFrame = home * CFrame.new(1.2, 0, 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = pin, stripe
			weld.Parent = stripe
			stripe.Parent = pin
			pin.Parent = landmarks
			table.insert(pins, { part = pin, home = home })
		end
	end
	-- side rails and a back stop, so a thrown body stays on the lane
	for _, side in { -1, 1 } do
		solid(Vector3.new(54, 1.2, 1), CFrame.new(headX + 22, 0.6, laneZ + side * 5.5), Color3.fromRGB(60, 58, 68), Enum.Material.Metal)
	end
	solid(Vector3.new(1, 5, 12), CFrame.new(headX - 9, 2.5, laneZ), Color3.fromRGB(40, 38, 46), Enum.Material.Metal)
	local board = solid(Vector3.new(0.4, 6, 14), CFrame.new(headX - 9, 9, laneZ), Color3.fromRGB(28, 26, 34), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right -- +X: toward whoever throws
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 90)
	label.Text = "RAGDOLL BOWLING\nthrow a dummy!"
	label.Parent = gui
	gui.Parent = board

	local function down(pin): boolean
		return pin.part.CFrame.RightVector.Y < 0.75 or (pin.part.Position - pin.home.Position).Magnitude > 2.5
	end
	local function reset()
		for _, pin in pins do
			pin.part.Anchored = true
			pin.part.CFrame = pin.home
			pin.part.AssemblyLinearVelocity = Vector3.zero
			pin.part.AssemblyAngularVelocity = Vector3.zero
			pin.part.Anchored = false
			if pin.part:IsDescendantOf(workspace) then pin.part:SetNetworkOwner(nil) end
		end
		label.Text = "RAGDOLL BOWLING\nthrow a dummy!"
		label.TextColor3 = Color3.fromRGB(255, 214, 90)
	end
	task.spawn(function()
		reset()
		local resetAt, shown = nil, 0
		while true do
			task.wait(0.25)
			local count = 0
			for _, pin in pins do
				if down(pin) then
					count += 1
				end
			end
			if count > shown then
				shown = count
				resetAt = os.clock() + PIN_RESET
				if count == #pins then
					label.Text = "STRIKE!"
					label.TextColor3 = Color3.fromRGB(255, 90, 70)
				else
					label.Text = `{count} / {#pins}`
				end
			end
			if resetAt and os.clock() >= resetAt then
				resetAt, shown = nil, 0
				reset()
			end
		end
	end)
end

local function lighting()
	Lighting.ClockTime = 16.6 -- golden hour: long shadows, warm light, every frame a thumbnail
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 2.6
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 108, 122)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	local function add(class: string, props: { [string]: any })
		local effect = Lighting:FindFirstChild("Map" .. class) or Instance.new(class)
		effect.Name = "Map" .. class
		for k, v in props do
			(effect :: any)[k] = v
		end
		effect.Parent = Lighting
	end
	add("Atmosphere", { Density = 0.28, Offset = 0.12, Color = Color3.fromRGB(255, 214, 170), Decay = Color3.fromRGB(120, 92, 112), Glare = 0.35, Haze = 1.4 })
	add("BloomEffect", { Intensity = 0.55, Size = 24, Threshold = 1.5 })
	add("SunRaysEffect", { Intensity = 0.06, Spread = 0.55 })
	add("ColorCorrectionEffect", { Saturation = 0.15, Contrast = 0.08, TintColor = Color3.fromRGB(255, 248, 240) })
end

function Map.build()
	lighting()
	local bedrock = workspace:FindFirstChild("Baseplate") :: BasePart?
	if bedrock then -- crater floor: sits one cube below the grass
		bedrock.Position = Vector3.new(0, -CUBE - bedrock.Size.Y / 2, 0)
		bedrock.Color = Color3.fromRGB(41, 38, 43)
	end
	-- floor = CUBE tiles (1.6k parts) that split into thin TILE columns where hit, so craters still
	-- come out round, full depth so they stay deep
	local count = math.round(HALF * 2 / CUBE)
	local column = Vector3.new(TILE, CUBE, TILE)
	for ix = 0, count - 1 do
		for iz = 0, count - 1 do
			local position = Vector3.new(-HALF + (ix + 0.5) * CUBE, -CUBE / 2, -HALF + (iz + 0.5) * CUBE)
			local color, material = floorLook(position.X, position.Z, ix * 3, iz * 3)
			-- nothing under the floor to shade, and thousands of shadow casters cost the client every frame
			Map.tile(Vector3.new(CUBE, CUBE, CUBE), position, color, material, column).CastShadow = false
		end
	end
	-- solid grass around the arena, out to the edge of the 512 baseplate
	local rim = Instance.new("Model")
	rim.Name = "Rim"
	local far = (256 + HALF) / 2
	local wide = 256 - HALF
	for _, side in { -1, 1 } do
		block(Vector3.new(512, CUBE, wide), Vector3.new(0, -CUBE / 2, side * far), GRASS[2], Enum.Material.Grass, rim)
		block(Vector3.new(wide, CUBE, HALF * 2), Vector3.new(side * far, -CUBE / 2, 0), GRASS[2], Enum.Material.Grass, rim)
	end
	rim.Parent = workspace

	local function at(kind: string, x: number, z: number, turns: number?)
		buildStructure(kind, CFrame.new(x, 0, z) * CFrame.Angles(0, (turns or 0) * math.pi / 2, 0))
	end
	-- plaza: a ring of posts, the statue looking down the north path
	for i = 1, 8 do
		local angle = (i + 0.5) / 8 * math.pi * 2
		at("Post", math.round(math.cos(angle) * 20 / 2) * 2, math.round(math.sin(angle) * 20 / 2) * 2)
	end
	at("Statue", 0, -40)
	-- town (NE): two rows of houses either side of the street at x = 52, doors onto it
	for _, z in { -36, -64 } do
		at("House", 38, z)
		at("House", 66, z, 2)
	end
	at("Crates", 52, -24)
	-- park (NW): the fountain, benches round it, trees
	at("Fountain", -48, -48)
	at("Bench", -48, -34, 2)
	at("Bench", -34, -48, 1)
	at("Bench", -62, -48, 3)
	for _, t in { { -32, -32 }, { -68, -28 }, { -28, -70 }, { -70, -70 }, { -52, -72 }, { -72, -52 }, { -36, -66 } } do
		at("Tree", t[1], t[2])
	end
	-- bowling (SW): the lane runs along z = 52, pins at its west end; cover beside it
	bowling(52, -70)
	at("Wall", -52, 32)
	at("Rock", -36, 70)
	at("Tree", -72, 30)
	-- building site (SE): two scaffolds, crate stacks, rocks
	at("Scaffold", 44, 56)
	at("Scaffold", 66, 34, 1)
	at("Crates", 30, 40)
	at("Crates", 70, 70)
	at("Tower", 30, 70)
	at("Rock", 56, 28)
	-- cover along the paths, between the zones
	at("Pillar", 24, 24)
	at("Pillar", -24, 24)
	at("Pillar", 24, -24)
	at("Pillar", -24, -24)
	at("Arch", 0, 72)
	at("Arch", 72, 0, 1)
	at("Arch", -72, 0, 1)

	-- the landmarks on the rim -------------------------------------------------------------
	-- N: launch ramp, 30 up over 70, its top facing the target further north
	local rise, run = 30, 70
	local tilt = math.atan2(rise, run)
	solid(Vector3.new(30, 2, math.sqrt(rise * rise + run * run)), CFrame.new(0, rise / 2, -110 - run / 2) * CFrame.Angles(tilt, 0, 0), Color3.fromRGB(240, 122, 58), Enum.Material.DiamondPlate)
	for _, x in { -12, 12 } do
		solid(Vector3.new(3, rise - 2, 3), CFrame.new(x, (rise - 2) / 2, -110 - run + 2), Color3.fromRGB(110, 60, 30), Enum.Material.Metal)
	end
	local flat = CFrame.Angles(0, 0, math.pi / 2)
	for i, ring in { { 44, Color3.fromRGB(226, 70, 60) }, { 34, Color3.new(1, 1, 1) }, { 24, Color3.fromRGB(226, 70, 60) }, { 14, Color3.new(1, 1, 1) }, { 6, Color3.fromRGB(255, 220, 60) } } do
		solid(Vector3.new(0.2, ring[1], ring[1]), CFrame.new(0, 0.1 + i * 0.02, -222) * flat, ring[2], i == 5 and Enum.Material.Neon or Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	sign("LAUNCH RAMP", Vector3.new(0, 40, -150), Color3.fromRGB(255, 160, 90))
	sign("BULLSEYE", Vector3.new(0, 14, -222), Color3.fromRGB(255, 120, 100))
	-- E: parkour canyon, two walls 20 apart (replaces the old test wall)
	for _, x in { 100, 124 } do
		for i = 0, 7 do
			solid(Vector3.new(4, 48, 20), CFrame.new(x, 24, -70 + i * 20), i % 2 == 0 and Color3.fromRGB(70, 80, 106) or Color3.fromRGB(92, 102, 134), Enum.Material.Concrete)
		end
	end
	sign("PARKOUR CANYON", Vector3.new(112, 54, 0), Color3.fromRGB(140, 170, 255))
	-- W: drop tower, ledges spiralling up to a platform 80 up
	local tower = Vector3.new(-150, 0, 0)
	solid(Vector3.new(12, 80, 12), CFrame.new(tower + Vector3.yAxis * 40), Color3.fromRGB(122, 127, 140), Enum.Material.Concrete)
	for i = 1, 15 do
		local angle = i * math.pi / 4
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 12
		solid(Vector3.new(6, 1.2, 6), CFrame.new(tower + offset + Vector3.yAxis * (i * 5)), i % 2 == 0 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(230, 120, 50), Enum.Material.Metal)
	end
	solid(Vector3.new(16, 2, 16), CFrame.new(tower + Vector3.yAxis * 81), Color3.fromRGB(60, 62, 72), Enum.Material.DiamondPlate)
	sign("DROP TOWER", tower + Vector3.yAxis * 92, Color3.fromRGB(255, 200, 80))
	-- S: trampoline field
	for _, x in { -26, 0, 26 } do
		for _, z in { 122, 152 } do
			trampoline(Vector3.new(x, 0, z), 14, 115)
		end
	end
	sign("TRAMPOLINES", Vector3.new(0, 26, 137), Color3.fromRGB(90, 230, 245))
	-- zone names inside the arena
	sign("TOWN", Vector3.new(52, 22, -50), Color3.fromRGB(255, 150, 120))
	sign("PARK", Vector3.new(-48, 22, -48), Color3.fromRGB(130, 230, 140))
	sign("BOWLING", Vector3.new(-48, 18, 52), Color3.fromRGB(255, 214, 90))
	sign("BUILDING SITE", Vector3.new(52, 34, 52), Color3.fromRGB(255, 190, 70))
	landmarks.Parent = workspace
	folder.Parent = workspace
end

return Map
