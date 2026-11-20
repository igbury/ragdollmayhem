-- Destructible arena (Mayhem Park, see Map.build): a floor of anchored cubes over dark bedrock, plus structures built from
-- cubes (pillars, trees, walls, towers, arches, crates, rocks); a hit knocks out only the bricks it reaches.
-- Broken floor cubes are hidden (not destroyed) and come back after REGEN seconds. Everything above the
-- bedrock breaks: the grass rim round the arena is floor tiles too, and the landmarks on it are structures.
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
-- the floor breaks 5x harder than structures: a hit's full width, but only this deep (5 hits go through)
local FLOOR_DIG = CUBE / 5
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
-- The grass round the arena (Map.build): floor tiles like the arena's, in a folder of their own that the
-- Myth Yard cuts its pits through (Monsters). Floor is whatever sits straight in `folder` or `rim`.
local rim = Instance.new("Folder")
rim.Name = "Rim"
rim.Parent = folder
local function isFloor(p: Instance): boolean
	return p.Parent == folder or p.Parent == rim
end
local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { folder }

-- Player-built blocks (the server's Toolbox "build"): blasts and hits break them like structure cubes,
-- brick by brick, and what breaks off never comes back. What is left stands only while it still
-- reaches something solid (dropUnbuilt).
local built: Instance? = nil
local builtParams = OverlapParams.new() -- built parts only: what a built part touches of its own kind
builtParams.FilterType = Enum.RaycastFilterType.Include
local worldParams = OverlapParams.new() -- everything else: the world a built part can rest on
worldParams.FilterType = Enum.RaycastFilterType.Exclude
function Map.breakable(f: Instance)
	built = f
	params.FilterDescendantsInstances = { folder, f }
	builtParams.FilterDescendantsInstances = { f }
	worldParams.FilterDescendantsInstances = { f }
end

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

-- Big blocks and floor tiles stay one part until a hit reaches them; then they split into their small
-- pieces in place (shatter), so the map has few parts but still breaks into small cubes. The "Piece"
-- attribute holds the size of the pieces a whole part splits into (an attribute, not a weak table:
-- Instance keys nothing else in Luau holds get collected).

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
		-- "Fixed": held up whatever it touches (a ledge bolted to the drop tower's column)
		grounded[b] = at[i].Y - b.Size.Y / 2 < 0.1 or b:GetAttribute("Fixed") or nil
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
--  * floor pieces in reach lose their top FLOOR_DIG (gone once nothing is left): the tile comes back
--    whole REGEN later, in place of its pieces; a tile wholly in reach (`inside`) is not split at all,
--    just dug as one. Its pieces ("Dug") are never split again, a later hit digs them in place.
--  * of the structure pieces in reach only MAX_FLYING per hit are made (and fly); the rest just go,
--    MAX_DEBRIS would sweep them at once anyway. Making them all stalled the server ~200 ms a blast.
-- `standing`: leave the floor whole.
-- A structure block is not cut into all its pieces: it is halved along its longest side, again and again,
-- only where the hit reaches, so a 90-stud wall turns into a few big blocks plus the bricks round the
-- hole (all of it at once would be tens of thousands of parts). The big blocks keep their "Piece" and
-- split the same way when a later hit reaches them.
local function shatter(hits: { BasePart }, standing: boolean?, inside: (BasePart) -> boolean, reach: (CFrame, Vector3, boolean) -> boolean): { BasePart }
	local out, plans, flying = {}, {}, 0
	for _, whole in hits do
		local piece, parent = whole:GetAttribute("Piece"), whole.Parent
		local floor = parent ~= nil and isFloor(whole)
		if not parent or (floor and standing) or not (piece or floor) then
			table.insert(out, whole)
			continue
		end
		if floor and whole:GetAttribute("Dug") then -- a piece of a tile already hit: dig it in place
			if reach(whole.CFrame, whole.Size, true) then
				local height = whole.Size.Y - FLOOR_DIG
				if height <= 0.05 then
					whole.Parent = nil -- the tile's own REGEN destroys it
				else
					whole.Size = Vector3.new(whole.Size.X, height, whole.Size.Z)
					whole.CFrame *= CFrame.new(0, -FLOOR_DIG / 2, 0)
				end
				table.insert(out, whole)
			end
			continue
		end
		local n = piece and Vector3.new(math.round(whole.Size.X / piece.X), math.round(whole.Size.Y / piece.Y), math.round(whole.Size.Z / piece.Z)) or Vector3.one
		local unit = whole.Size / n
		local cells = {} -- { cframe, hit, size, pieces in it }
		if floor and (not piece or inside(whole)) then
			if not reach(whole.CFrame, whole.Size, true) then
				continue
			end
			table.insert(cells, { whole.CFrame, true, whole.Size, Vector3.one })
		elseif floor then
			for x = 1, n.X do
				for y = 1, n.Y do
					for z = 1, n.Z do
						local cf = whole.CFrame * CFrame.new((Vector3.new(x, y, z) - (n + Vector3.one) / 2) * unit)
						table.insert(cells, { cf, reach(cf, unit, true), unit, Vector3.one })
					end
				end
			end
		elseif not reach(whole.CFrame, whole.Size, false) then
			continue -- its bounding box was in range, the block itself is not
		else
			local function split(cf: CFrame, count: Vector3)
				local size = count * unit
				local hit = reach(cf, size, false)
				if not hit or count.X * count.Y * count.Z == 1 then
					table.insert(cells, { cf, hit, size, count })
					flying += hit and 1 or 0
					return
				end
				local axis = if count.X >= count.Y and count.X >= count.Z then Vector3.xAxis elseif count.Y >= count.Z then Vector3.yAxis else Vector3.zAxis
				local along = count:Dot(axis)
				local a = math.floor(along / 2)
				local b = along - a
				local step = unit:Dot(axis)
				split(cf * CFrame.new(-axis * b * step / 2), count - axis * b)
				split(cf * CFrame.new(axis * a * step / 2), count - axis * a)
			end
			split(whole.CFrame, n)
		end
		table.insert(plans, { whole, parent, floor, cells })
	end
	local keep = math.min(1, MAX_FLYING / math.max(flying, 1))
	for _, plan in plans do
		local whole, parent, floor, cells = table.unpack(plan)
		local piece = whole:GetAttribute("Piece")
		local stay = {}
		for _, c in cells do
			local size = c[3]
			if c[2] and floor then
				size -= Vector3.new(0, FLOOR_DIG, 0)
				if size.Y <= 0.05 then
					continue
				end
			elseif c[2] and math.random() >= keep then
				continue
			end
			local p = whole:Clone() -- keeps colour, material, surfaces, shadow
			for _, child in p:GetChildren() do
				child:Destroy() -- a sign's text is the whole block's, not every piece's
			end
			local count = c[4]
			p:SetAttribute("Piece", if count.X * count.Y * count.Z > 1 then piece else nil)
			p:SetAttribute("Dug", floor or nil)
			p.Size = size
			p.CFrame = c[1] * CFrame.new(0, (size.Y - c[3].Y) / 2, 0) -- a dug floor piece keeps its bottom
			p.Parent = parent
			if c[2] then
				table.insert(out, p)
			end
			if floor or not c[2] then
				table.insert(stay, p) -- floor: all of it goes when the tile comes back
			end
		end
		whole.Parent = nil
		if floor then
			task.delay(REGEN, function()
				for _, p in stay do
					p:Destroy()
				end
				whole.Parent = parent
			end)
		elseif parent == built then
			whole:Destroy() -- its pieces that stay just stay: nothing settles built blocks
		else
			-- link only the pieces that stay: to each other and to what the block touched (relinking
			-- the whole structure is ~100 ms once it is full of small bricks)
			local origin = parent:GetAttribute("Origin") or CFrame.identity
			local around = neighbours[whole] or {}
			for _, p in stay do
				neighbours[p] = {}
				grounded[p] = origin:PointToObjectSpace(p.Position).Y - p.Size.Y / 2 < 0.1 or p:GetAttribute("Fixed") or nil
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

-- Kinds put back whole and at once instead of sliding in layer by layer: big pieces people stand on
-- (Map.build's landmarks), where a roof going see-through under someone would drop them through it.
local INSTANT = {}

-- `keep` (a repair): bricks in these slots are still standing, so they are put straight back and
-- only the rest slide in.
local function buildStructure(kind: string, origin: CFrame, layered: boolean?, keep: { [string]: boolean }?)
	local model = Instance.new("Model")
	model.Name = kind
	local bricks = {}
	layered = layered and not INSTANT[kind]
	-- add(x, y, z, color, material, size?): a cube of `size` (default CUBE) on the cube grid.
	-- add(cframe, size, color, material): a box of any Vector3 size, placed in origin space. Returns the part.
	KINDS[kind](function(x, y, z, color, material, size)
		local cube
		if typeof(x) == "CFrame" then
			local box: Vector3 = y
			cube = block(box, Vector3.zero, z, color, nil)
			cube.CFrame = origin * x
			local n = Vector3.new(math.max(1, math.round(box.X / BRICK)), math.max(1, math.round(box.Y / BRICK)), math.max(1, math.round(box.Z / BRICK)))
			if n.X * n.Y * n.Z > 1 then
				cube:SetAttribute("Piece", box / n)
			end
		else
			size = size or CUBE
			-- one part per block; a hit splits it into BRICK-sized bricks (shatter) so it still breaks small
			cube = block(Vector3.one * size, Vector3.zero, color, material, nil)
			cube.CFrame = origin * CFrame.new(x * CUBE, y * CUBE + size / 2, z * CUBE)
			local n = math.round(size / BRICK)
			if n > 1 then
				cube:SetAttribute("Piece", Vector3.one * (size / n))
			end
		end
		table.insert(bricks, cube)
		return cube
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
-- Only the newest MAX_GRAVES stand; the oldest goes when a new one is dug.
local MAX_GRAVES = 10
local graves: { Model } = {}
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
	table.insert(graves, model)
	while #graves > MAX_GRAVES do
		table.remove(graves, 1):Destroy()
	end
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
		if model == built then
			knock(cube, from, power) -- a built brick: no structure to settle or rebuild
			table.insert(knocked, cube)
		elseif model and not isFloor(cube) and model.Parent == folder then
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

-- Built parts near `position` that no longer reach anything anchored of the world, through built
-- parts touching each other, fall. Touching counts edges and corners too (a hair of padding).
-- ponytail: a search stops after MAX_SUPPORT_WALK parts and calls that build held up; raise it (or
-- cache support per build) if huge hanging builds should come down whole.
local MAX_SUPPORT_WALK = 1500
local TOUCH = Vector3.one * 0.2
local function resting(p: BasePart): boolean
	for _, o in workspace:GetPartBoundsInBox(p.CFrame, p.Size + TOUCH, worldParams) do
		if o.Anchored then -- the map, terrain, a structure (loose debris, bodies and hidden tiles are not)
			return true
		end
	end
	return false
end
local function dropUnbuilt(position: Vector3, radius: number)
	if not built then
		return
	end
	local held = {} -- [part] = whether it stands, once its group is known
	for _, seed in workspace:GetPartBoundsInRadius(position, radius + BRICK * 1.5, builtParams) do
		if held[seed] ~= nil then
			continue
		end
		local group, stack, seen, stands = { seed }, { seed }, { [seed] = true }, false
		while #stack > 0 do
			local p = table.remove(stack)
			if held[p] or resting(p) or #group > MAX_SUPPORT_WALK then
				stands = true
				break
			end
			for _, n in workspace:GetPartBoundsInBox(p.CFrame, p.Size + TOUCH, builtParams) do
				if not seen[n] then
					seen[n] = true
					table.insert(group, n)
					table.insert(stack, n)
				end
			end
		end
		for _, p in group do
			held[p] = stands
			if not stands then
				knock(p, p.Position, 0) -- just drops
			end
		end
	end
end
Map.dropUnbuilt = dropUnbuilt

-- Carve a crater. `inner` leaves an untouched island in the middle (ring crater). `standing`: only
-- break structures (walls, pillars), not the floor tiles in reach.
function Map.blast(position: Vector3, radius: number, power: number, inner: number?, standing: boolean?)
	local function inside(tile: BasePart): boolean
		local d, h = ((tile.Position - position) * Vector3.new(1, 0, 1)).Magnitude, tile.Size.X * 0.71
		return d + h <= radius and d - h >= (inner or 0)
	end
	local function reach(cf: CFrame, size: Vector3, floor: boolean): boolean
		if floor then
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
	for _, cube in hits do
		if not cube:GetAttribute("Dug") then -- the floor shatter dug (it is in reach)
			continue
		end
		local offset = (cube.Position - position) * Vector3.new(1, 0, 1)
		table.insert(broken, cube)
		if math.random() < chance then
			local out = offset.Magnitude > 0.1 and offset.Unit or Vector3.zero
			local velocity = (out * (0.3 + math.random() * 0.5) + Vector3.yAxis * (0.6 + math.random() * 0.6)) * power
			chunk(cube, TILE * (0.7 + math.random() * 0.6), velocity)
		end
	end
	dropUnbuilt(position, radius)
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
	for _, cube in hits do
		if not cube:GetAttribute("Dug") then
			continue
		end
		table.insert(broken, cube)
		if math.random() < chance then
			chunk(cube, TILE * (0.9 + math.random() * 0.5), velocity * (0.7 + math.random() * 0.6))
		end
	end
	dropUnbuilt(cf.Position, size.Magnitude / 2)
	breakSounds(broken, cf.Position)
end

-- Mayhem Park ---------------------------------------------------------------------------------
-- The destructible arena (2*HALF square, x east, -z north) is split into themed zones round a
-- stone plaza: a statue to the north, a little town (NE), a park (NW), a ragdoll bowling lane
-- (SW) and a building site (SE), joined by cobbled paths. Outside it, on the grass rim, the
-- landmarks: a launch ramp with a target to land on (N), a parkour canyon (E), a drop tower (W),
-- a trampoline field (S) and rooftops (NW). All of it breaks; only the bedrock under it does not. Plan: the "Ragdoll Mayhem — nowa mapa" design.
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

-- Movement pieces. Laid out for the client's moves: a jump clears about 6 studs up and 17 across at a
-- sprint, a mantle takes a ledge up to about 5 over the hips (so a 14-stud top from the ground, 12
-- more from a roof), a wall run goes 3.5 s at 32, and running from one wall to the one facing it
-- starts the clock again.
-- a block of flats: five storeys of brick round a hollow middle, the door on -X (the path), the windows
-- on that side only so the +X face (the alley to the houses) is one unbroken wall to run along; roof
-- at 24, one mantle up from a house roof
function KINDS.Apartment(add)
	for y = 0, 4 do
		for x = -1, 1 do
			for z = -3, 2 do
				local edge = x ~= 0 or z == -3 or z == 2
				local door = x == -1 and z == 0 and y <= 1
				local window = x == -1 and y % 2 == 1 and (z == -2 or z == 1)
				if edge and not door and not window then
					add(x, y, z, y == 4 and STONE or (x + z + y) % 3 == 0 and STONE or BRICK_RED, Enum.Material.Brick)
				end
			end
		end
	end
	for x = -1, 1 do
		for z = -3, 2 do
			add(x, 5, z, ROOF, Enum.Material.Slate)
		end
	end
end

-- a tall free-standing wall, 36 long and 20 high: one to run along, two side by side an alley
function KINDS.HighWall(add)
	for x = -4, 4 do
		for y = 0, 4 do
			add(x, y, 0, y == 4 and PLAZA_DARK or (x + y) % 2 == 0 and BRICK_RED or STONE, Enum.Material.Brick)
		end
	end
end

-- a pine: a short trunk under three narrowing layers of needles
function KINDS.Pine(add)
	local needles = Color3.fromRGB(26, 96, 56)
	add(0, 0, 0, WOOD, Enum.Material.Wood)
	for x = -1, 1 do
		for z = -1, 1 do
			add(x, 1, z, needles, Enum.Material.Grass)
			if x == 0 or z == 0 then
				add(x, 2, z, needles, Enum.Material.Grass)
			end
		end
	end
	add(0, 3, 0, needles, Enum.Material.Grass)
	add(0, 4, 0, needles, Enum.Material.Grass, 2)
end

-- four 8-stud blocks 12 apart, each 4 higher than the last (4 to 16): hop up them
function KINDS.Steps(add)
	for s = 0, 3 do
		for y = 0, s do
			for dx = -0.5, 0.5 do
				for dz = -0.5, 0.5 do
					add(s * 3 - 4.5 + dx, y, dz, y == s and PLAZA or PLAZA_DARK, Enum.Material.Slate)
				end
			end
		end
	end
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

-- The rim's districts (Map.build, districts): what the ground is round them. Rects are { x0, x1, z0, z1 }
-- on the 16-stud rim grid, tested against a tile's centre.
local LAVA = Color3.fromRGB(255, 100, 30)
local BASALT = Color3.fromRGB(58, 54, 60)
local ASH = Color3.fromRGB(92, 86, 84)
local CROP = Color3.fromRGB(118, 164, 62)
local VOLCANO = Vector3.new(176, 0, -176) -- the lava fields (NE): a moat of lava 32..48 out from it
local WATER = { { 144, 240, -64, 64 }, { -64, -32, 208, 240 } } -- the lake (E) and the park's pond (S)
local DRY = { 176, 208, -16, 16 } -- the lake's island
local function within(x: number, z: number, r): boolean
	return x > r[1] and x < r[2] and z > r[3] and z < r[4]
end
local function wet(x: number, z: number): boolean
	return (within(x, z, WATER[1]) or within(x, z, WATER[2])) and not within(x, z, DRY)
end
-- Colour and material of the rim tile centred at (x, z), and whether it is lava.
local function rimLook(x: number, z: number): (Color3, Enum.Material, boolean?)
	local volcano = math.max(math.abs(x - VOLCANO.X), math.abs(z - VOLCANO.Z))
	if volcano == 40 then
		return LAVA, Enum.Material.CrackedLava, true
	elseif volcano < 40 then
		return BASALT, Enum.Material.Basalt
	elseif volcano < 64 then
		return ASH, Enum.Material.Ground
	end
	if within(x, z, { 128, 256, -80, 80 }) then -- the lake's beach and island
		return SAND, Enum.Material.Sand
	end
	if x > 80 and z > 80 then -- downtown: streets every 64, pavement between
		local street = (x - 80) % 64 < 16 or (z - 80) % 64 < 16
		return if street then ASPHALT else PAVEMENT, if street then Enum.Material.Asphalt else Enum.Material.Pavement
	end
	if z > 160 and math.abs(x) < 80 then -- the park
		if (x > 0 and x < 16) or (z > 208 and z < 224) then
			return PATH, Enum.Material.Cobblestone
		end
		return PARK[((x + 256) // 16 + (z + 256) // 16) % 2 + 1], Enum.Material.Grass
	end
	if within(x, z, { -240, -160, 112, 192 }) then -- the farm's fields, in strips
		local dirt = (x + 256) // 16 % 2 == 0
		return if dirt then DIRT else CROP, if dirt then Enum.Material.Ground else Enum.Material.Grass
	end
	return GRASS[2], Enum.Material.Grass
end

-- What is not part of the map itself: the signs' anchors and the bowling pins.
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

-- A landmark: a structure (it breaks brick by brick, what nothing holds up falls, it mends itself) made of
-- boxes of any size, `boxes(add)` calling add(cframe, size, color, material) in `origin` space (world
-- space when left out). Put back whole and at once (INSTANT): people stand on these.
local function landmark(name: string, boxes: (any) -> (), origin: CFrame?)
	KINDS[name] = boxes
	INSTANT[name] = true
	buildStructure(name, origin or CFrame.identity)
end

-- A block with a flat roof cap and a band of windows per storey (rooftops, downtown): a landmark.
-- `extra(add)` adds more boxes to it (balconies, a spire).
local GLASS = Color3.fromRGB(54, 74, 102)
local function building(name: string, x0: number, x1: number, z0: number, z1: number, h: number, color: Color3, extra: ((any) -> ())?)
	local w, d = x1 - x0, z1 - z0
	local mid = Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2)
	landmark(name, function(add)
		add(CFrame.new(mid + Vector3.yAxis * (h - 1) / 2), Vector3.new(w, h - 1, d), color, Enum.Material.Concrete)
		add(CFrame.new(mid + Vector3.yAxis * (h - 0.5)), Vector3.new(w, 1, d), color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Concrete)
		-- a band of windows per 6-stud storey on every face, a hair proud of it (flush: the faces still run)
		for y = 4.5, h - 4, 6 do
			for _, face in { { Vector3.xAxis, d }, { -Vector3.xAxis, d }, { Vector3.zAxis, w }, { -Vector3.zAxis, w } } do
				local n, len = face[1], face[2]
				local out = mid + Vector3.new(n.X * (w / 2 + 0.1), y, n.Z * (d / 2 + 0.1))
				local size = n.X ~= 0 and Vector3.new(0.2, 2.6, len - 4) or Vector3.new(len - 4, 2.6, 0.2)
				add(CFrame.new(out), size, GLASS, Enum.Material.Glass).Reflectance = 0.15
			end
		end
		if extra then
			extra(add)
		end
	end)
end

-- A pad that throws whatever lands on it straight up. Dummies (server-owned) are thrown here;
-- a player's client owns its character, so it reads the "Bounce" attribute (the pad's pieces keep it)
-- and jumps itself. Square, so it breaks into bricks like everything else.
local function trampoline(name: string, position: Vector3, width: number, bounce: number)
	landmark(name, function(add)
		add(CFrame.new(position + Vector3.yAxis * 0.6), Vector3.new(width + 1.2, 1.2, width + 1.2), Color3.fromRGB(57, 208, 230), Enum.Material.Neon)
		local pad = add(CFrame.new(position + Vector3.yAxis * 0.7), Vector3.new(width, 1.4, width), Color3.fromRGB(43, 42, 51), Enum.Material.Rubber)
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
	-- side rails and a back stop, so a thrown body stays on the lane, and the board standing on the stop.
	-- All of it breaks (a landmark): the board is looked up whenever it is written, it may be a new one.
	local text, color = "RAGDOLL BOWLING\nthrow a dummy!", Color3.fromRGB(255, 214, 90)
	landmark("Bowling", function(add)
		for _, side in { -1, 1 } do
			add(CFrame.new(headX + 22, 0.6, laneZ + side * 5.5), Vector3.new(54, 1.2, 1), Color3.fromRGB(60, 58, 68), Enum.Material.Metal)
		end
		add(CFrame.new(headX - 9, 2.5, laneZ), Vector3.new(1, 5, 12), Color3.fromRGB(40, 38, 46), Enum.Material.Metal)
		local board = add(CFrame.new(headX - 9, 8, laneZ), Vector3.new(0.4, 6, 14), Color3.fromRGB(28, 26, 34), Enum.Material.SmoothPlastic)
		board.Name = "Scoreboard"
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Right -- +X: toward whoever throws
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = text
		label.Parent = gui
		gui.Parent = board
	end)
	local function show(t: string, c: Color3)
		text, color = t, c
		local lane = folder:FindFirstChild("Bowling")
		local board = lane and lane:FindFirstChild("Scoreboard")
		local gui = board and board:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text, label.TextColor3 = t, c
		end
	end

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
		show("RAGDOLL BOWLING\nthrow a dummy!", Color3.fromRGB(255, 214, 90))
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
					show("STRIKE!", Color3.fromRGB(255, 90, 70))
				else
					show(`{count} / {#pins}`, color)
				end
			end
			if resetAt and os.clock() >= resetAt then
				resetAt, shown = nil, 0
				reset()
			end
		end
	end)
end

-- A parked car facing `yaw`: body, glass cabin, wheels, lights. Its own origin, so its bricks line up with it.
local function car(name: string, x: number, z: number, yaw: number, color: Color3)
	landmark(name, function(add)
		add(CFrame.new(0, 1.7, 0), Vector3.new(4.4, 1.8, 9), color, Enum.Material.SmoothPlastic)
		add(CFrame.new(0, 3.3, 0.5), Vector3.new(4, 1.4, 5), GLASS, Enum.Material.Glass)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				add(CFrame.new(sx * 1.9, 0.8, sz * 2.9), Vector3.new(0.8, 1.6, 1.6), Color3.fromRGB(24, 24, 28), Enum.Material.Rubber)
			end
			add(CFrame.new(sx * 1.4, 1.9, -4.55), Vector3.new(0.9, 0.5, 0.1), Color3.fromRGB(255, 244, 200), Enum.Material.Neon)
		end
	end, CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0))
end

-- A landmark of plain boxes: { cframe, size, color, material } each, in world space.
local function boxes(name: string, list: { any })
	landmark(name, function(add)
		for _, b in list do
			add(b[1], b[2], b[3], b[4])
		end
	end)
end

-- Lava (rim tiles and the crater, the "Lava" attribute): every quarter second whoever stands on it, a
-- player or a dummy, is burned and thrown up through `hurt` (the server's hazard: Factory machines too).
local function lavaLoop(hurt: (Model, number, Vector3, string?) -> ())
	local down = RaycastParams.new()
	down.FilterType = Enum.RaycastFilterType.Include
	down.FilterDescendantsInstances = { folder }
	local burnt = setmetatable({}, { __mode = "k" }) -- [model] = os.clock() of its last burn
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local bodies = {}
			for _, player in Players:GetPlayers() do
				table.insert(bodies, player.Character)
			end
			local dummies = workspace:FindFirstChild("Dummies")
			for _, model in dummies and dummies:GetChildren() or {} do
				table.insert(bodies, model)
			end
			for _, model in bodies do
				local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and now - (burnt[model] or 0) > 0.8 then
					local under = workspace:Raycast(root.Position, Vector3.yAxis * -5, down)
					if under and under.Instance:GetAttribute("Lava") then
						burnt[model] = now
						hurt(model, 12, Vector3.new(math.random(-20, 20), 75, math.random(-20, 20)), "fire")
					end
				end
			end
		end
	end)
end

-- The rim round the arena, district by district (the ground under them: rimLook). `at` puts a cube-grid
-- structure on the ground at (x, z). Everything here is a structure or a landmark, so it all breaks.
local function districts(at: (string, number, number, number?) -> ())
	local SMOOTH, CONCRETE = Enum.Material.SmoothPlastic, Enum.Material.Concrete
	local function c(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end

	-- NE: lava fields. A stepped volcano with lava in its crater, in a square moat of lava (the rim
	-- tiles), crossed by two stone bridges; rocks round it.
	local v = VOLCANO
	landmark("Volcano", function(add)
		for i, half in { 28, 22, 17, 13 } do -- tiers 6 high: a jump and a mantle each
			add(CFrame.new(v + Vector3.yAxis * ((i - 1) * 6 + 3)), Vector3.new(half * 2, 6, half * 2), i % 2 == 0 and ASH or BASALT, Enum.Material.Basalt)
		end
		for _, side in { -1, 1 } do -- the crater's rim, 3 up round the pool
			add(CFrame.new(v + Vector3.new(side * 12, 25.5, 0)), Vector3.new(2, 3, 26), BASALT, Enum.Material.Basalt)
			add(CFrame.new(v + Vector3.new(0, 25.5, side * 12)), Vector3.new(22, 3, 2), BASALT, Enum.Material.Basalt)
		end
		local pool = add(CFrame.new(v + Vector3.yAxis * 24.5), Vector3.new(22, 1, 22), LAVA, Enum.Material.Neon)
		pool:SetAttribute("Lava", true)
		local smoke = Instance.new("Smoke")
		smoke.Color, smoke.Size, smoke.RiseVelocity, smoke.Opacity = Color3.fromRGB(60, 56, 56), 14, 6, 0.15
		smoke.Parent = pool
		local glow = Instance.new("PointLight")
		glow.Color, glow.Range, glow.Brightness = LAVA, 40, 3
		glow.Parent = pool
	end)
	boxes("LavaBridges", {
		{ c(v.X - 40, 0.5, v.Z), Vector3.new(24, 1, 6), ROCK, Enum.Material.Slate },
		{ c(v.X, 0.5, v.Z + 40), Vector3.new(6, 1, 24), ROCK, Enum.Material.Slate },
	})
	at("Rock", 118, -112)
	at("Rock", 236, -118)
	at("Rock", 236, -236)
	at("Rock", 116, -238)
	sign("LAVA FIELDS", v + Vector3.yAxis * 44, Color3.fromRGB(255, 130, 60))

	-- E: the lake (water down to the bedrock), an island with trees, a pier off the west shore, boats.
	for _, r in WATER do
		workspace.Terrain:FillBlock(CFrame.new((r[1] + r[2]) / 2, -CUBE / 2, (r[3] + r[4]) / 2), Vector3.new(r[2] - r[1], CUBE, r[4] - r[3]), Enum.Material.Water)
	end
	-- the island's own tiles stand in the water: clear it there again
	workspace.Terrain:FillBlock(CFrame.new((DRY[1] + DRY[2]) / 2, -CUBE / 2, (DRY[3] + DRY[4]) / 2), Vector3.new(DRY[2] - DRY[1], CUBE, DRY[4] - DRY[3]), Enum.Material.Air)
	at("Tree", 186, -6)
	at("Pine", 200, 8)
	landmark("Pier", function(add)
		add(c(158, 0.7, 40), Vector3.new(32, 0.6, 6), PLANK, Enum.Material.WoodPlanks)
		for _, x in { 146, 156, 166 } do
			for _, side in { -1, 1 } do
				add(c(x, -1.8, 40 + side * 2.4), Vector3.new(0.8, 4.4, 0.8), WOOD, Enum.Material.Wood) -- posts down to the bedrock
			end
		end
	end)
	for i, b in { { 206, 44, 0 }, { 168, -40, math.pi / 2 } } do
		landmark(`Boat{i}`, function(add)
			add(CFrame.new(0, 0.4, 0), Vector3.new(5, 1.6, 12), Color3.fromRGB(196, 72, 52), Enum.Material.WoodPlanks)
			add(CFrame.new(0, 1.4, 0), Vector3.new(4.6, 0.4, 1.4), PLANK, Enum.Material.WoodPlanks) -- a seat
		end, CFrame.new(b[1], 0, b[2]) * CFrame.Angles(0, b[3], 0))
	end
	sign("LAKE", Vector3.new(192, 30, 0), Color3.fromRGB(110, 190, 255))

	-- SE: downtown, a 3 x 3 grid of blocks between streets (the rim tiles), a tower in the middle one.
	local TOWN = { Color3.fromRGB(184, 176, 164), Color3.fromRGB(132, 140, 156), Color3.fromRGB(170, 120, 96), Color3.fromRGB(96, 104, 120), Color3.fromRGB(200, 184, 150) }
	building("Office1", 102, 138, 102, 138, 34, TOWN[1])
	building("Office2", 164, 182, 100, 140, 56, TOWN[2])
	building("Office3", 186, 204, 100, 124, 26, TOWN[3])
	building("Office4", 228, 252, 100, 140, 20, TOWN[4])
	building("Skyscraper", 168, 200, 168, 200, 90, TOWN[4], function(add)
		add(c(184, 100, 184), Vector3.new(20, 20, 20), TOWN[2], CONCRETE) -- a setback crown
		add(c(184, 118, 184), Vector3.new(1, 16, 1), Color3.fromRGB(200, 200, 210), Enum.Material.Metal) -- the mast
	end)
	building("Office5", 228, 252, 164, 204, 44, TOWN[5])
	building("Office6", 100, 140, 228, 252, 24, TOWN[3])
	building("Office7", 164, 204, 228, 252, 30, TOWN[1])
	building("Office8", 228, 252, 228, 252, 62, TOWN[2])
	at("Fountain", 120, 184) -- the plaza block
	at("Bench", 120, 168)
	at("Bench", 120, 200, 2)
	at("Tree", 102, 166)
	at("Tree", 138, 202)
	for i, k in { { 190, 134, 0, Color3.fromRGB(210, 50, 50) }, { 200, 134, 0, Color3.fromRGB(60, 110, 210) }, { 152, 120, 0, Color3.fromRGB(240, 200, 60) },
		{ 216, 176, 0, Color3.new(0.92, 0.92, 0.92) }, { 120, 152, math.pi / 2, Color3.fromRGB(60, 160, 90) }, { 184, 216, math.pi / 2, Color3.fromRGB(30, 30, 34) } } do
		car(`Car{i}`, k[1], k[2], k[3], k[4])
	end
	sign("DOWNTOWN", Vector3.new(184, 132, 184), Color3.fromRGB(255, 220, 140))

	-- S: the city park (its pond is in WATER), trees round it, a gazebo, benches, flower beds; a hedge maze
	-- beside the trampolines.
	for _, t in { { -72, 176 }, { -40, 184 }, { -76, 214 }, { -24, 248 }, { 30, 180 }, { 60, 196 }, { 72, 244 }, { 26, 246 }, { -56, 248 }, { 44, 214 } } do
		at(t[1] % 3 == 0 and "Pine" or "Tree", t[1], t[2])
	end
	landmark("Gazebo", function(add)
		add(c(52, 0.3, 230), Vector3.new(12, 0.6, 12), PLAZA, Enum.Material.Slate)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				add(c(52 + sx * 5, 4.3, 230 + sz * 5), Vector3.new(1, 7.4, 1), MARBLE, Enum.Material.Marble)
			end
		end
		add(c(52, 8.5, 230), Vector3.new(13, 1, 13), ROOF, Enum.Material.Slate)
		add(c(52, 9.5, 230), Vector3.new(8, 1, 8), ROOF, Enum.Material.Slate)
	end)
	at("Bench", 24, 200, 1)
	at("Bench", -8, 232, 3)
	at("Bench", 40, 210)
	local FLOWERS = { Color3.fromRGB(230, 60, 90), Color3.fromRGB(250, 200, 50), Color3.fromRGB(150, 80, 220) }
	local beds = {}
	for i, f in { { -8, 192 }, { 24, 232 }, { -16, 204 }, { 36, 192 } } do
		table.insert(beds, { c(f[1], 0.5, f[2]), Vector3.new(6, 1, 3), DIRT, Enum.Material.Ground })
		table.insert(beds, { c(f[1], 1.2, f[2]), Vector3.new(5, 0.4, 2), FLOWERS[i % 3 + 1], SMOOTH })
	end
	boxes("FlowerBeds", beds)
	sign("CITY PARK", Vector3.new(8, 28, 216), Color3.fromRGB(140, 235, 150))
	local hedge = Color3.fromRGB(44, 112, 52)
	local maze = {}
	for _, w in { -- { x0, x1, z0, z1 } 6 high; in at the north (arena) side, out at the east
		{ -80, -78, 96, 160 }, { -80, -58, 96, 98 }, { -46, -44, 96, 148 }, { -80, -44, 158, 160 },
		{ -72, -44, 110, 112 }, { -80, -54, 124, 126 }, { -70, -44, 138, 140 }, { -62, -60, 140, 158 }, { -56, -54, 112, 124 },
	} do
		table.insert(maze, { c((w[1] + w[2]) / 2, 3, (w[3] + w[4]) / 2), Vector3.new(w[2] - w[1], 6, w[4] - w[3]), hedge, Enum.Material.Grass })
	end
	boxes("HedgeMaze", maze)
	sign("HEDGE MAZE", Vector3.new(-62, 16, 128), Color3.fromRGB(120, 210, 120))

	-- SW: the farm. A red barn with a stepped roof, a silo, a windmill, a fenced field (the strip
	-- tiles), hay bales.
	local BARN = Color3.fromRGB(168, 46, 40)
	landmark("Barn", function(add)
		add(c(-126, 6, 134), Vector3.new(28, 12, 28), BARN, Enum.Material.WoodPlanks)
		for i, d in { 30, 22, 14, 6 } do
			add(c(-126, 12 + i * 2 - 1, 134), Vector3.new(30, 2, d), Color3.fromRGB(88, 60, 50), Enum.Material.WoodPlanks)
		end
		add(c(-111.9, 4.5, 134), Vector3.new(0.2, 9, 10), Color3.fromRGB(64, 36, 30), Enum.Material.WoodPlanks) -- the doors
		add(c(-111.8, 4.5, 134), Vector3.new(0.2, 9, 0.6), Color3.new(0.95, 0.95, 0.95), SMOOTH)
	end)
	boxes("Silo", {
		{ c(-104, 13, 116), Vector3.new(8, 26, 8), Color3.fromRGB(190, 192, 198), Enum.Material.Metal },
		{ c(-104, 27, 116), Vector3.new(9, 2, 9), Color3.fromRGB(120, 124, 132), Enum.Material.Metal },
		{ c(-104, 29, 116), Vector3.new(5, 2, 5), Color3.fromRGB(120, 124, 132), Enum.Material.Metal },
	})
	boxes("HayBales", {
		{ c(-104, 1.5, 150), Vector3.new(6, 3, 4), Color3.fromRGB(222, 190, 96), Enum.Material.Fabric },
		{ c(-104, 4.5, 150), Vector3.new(6, 3, 4), Color3.fromRGB(222, 190, 96), Enum.Material.Fabric },
		{ c(-104, 1.5, 155), Vector3.new(6, 3, 4), Color3.fromRGB(212, 180, 86), Enum.Material.Fabric },
	})
	local fence = {}
	local function rail(x0: number, x1: number, z0: number, z1: number)
		for _, y in { 1.2, 2.4 } do
			table.insert(fence, { c((x0 + x1) / 2, y, (z0 + z1) / 2), Vector3.new(math.max(x1 - x0, 0.4), 0.4, math.max(z1 - z0, 0.4)), WOOD, Enum.Material.Wood })
		end
		local n = math.max(x1 - x0, z1 - z0) // 16
		for k = 0, n do
			local t = k / math.max(n, 1)
			table.insert(fence, { c(x0 + (x1 - x0) * t, 1.5, z0 + (z1 - z0) * t), Vector3.new(0.6, 3, 0.6), WOOD, Enum.Material.Wood })
		end
	end
	rail(-240, -160, 112, 112)
	rail(-240, -160, 192, 192)
	rail(-240, -240, 112, 192)
	rail(-160, -160, 112, 144) -- the gate: open between z 144 and 160
	rail(-160, -160, 160, 192)
	boxes("Fence", fence)
	landmark("Windmill", function(add)
		add(c(-200, 15, 224), Vector3.new(8, 30, 8), Color3.fromRGB(226, 218, 200), Enum.Material.WoodPlanks)
		add(c(-200, 31, 224), Vector3.new(10, 2, 10), Color3.fromRGB(88, 60, 50), Enum.Material.WoodPlanks)
		add(c(-200, 26, 219), Vector3.new(2, 2, 2), WOOD, Enum.Material.Wood) -- the hub, on the north face
		add(c(-200, 26, 217.7), Vector3.new(1.6, 26, 0.6), Color3.new(0.95, 0.95, 0.95), Enum.Material.WoodPlanks)
		add(c(-200, 26, 217.7), Vector3.new(26, 1.6, 0.6), Color3.new(0.95, 0.95, 0.95), Enum.Material.WoodPlanks)
	end)
	sign("FARM", Vector3.new(-170, 30, 150), Color3.fromRGB(255, 200, 120))

	-- W: the forest, trees and pines on a jittered grid round a log cabin with a campfire; rocks.
	local rng = Random.new(19)
	for gx = -244, -180, 16 do
		for gz = -80, 80, 16 do
			local x, z = gx + rng:NextInteger(-2, 2), gz + rng:NextInteger(-2, 2)
			if rng:NextNumber() < 0.3 or (x > -240 and x < -196 and z > 22 and z < 66) then
				continue -- a clearing, and the cabin's
			end
			at(rng:NextNumber() < 0.5 and "Pine" or "Tree", x, z)
		end
	end
	for _, t in { { -110, -60 }, { -118, 50 }, { -100, 72 } } do -- a few between the arena and the drop tower
		at("Tree", t[1], t[2])
	end
	landmark("Cabin", function(add)
		local logs = Color3.fromRGB(110, 72, 46)
		add(c(-222, 4, 38), Vector3.new(20, 8, 16), logs, Enum.Material.Wood)
		for i, d in { 18, 13, 8, 3 } do
			add(c(-222, 8 + i * 1.5 - 0.75, 38), Vector3.new(22, 1.5, d), Color3.fromRGB(70, 46, 34), Enum.Material.WoodPlanks)
		end
		add(c(-211.9, 3.5, 38), Vector3.new(0.2, 7, 4), Color3.fromRGB(56, 36, 26), Enum.Material.WoodPlanks) -- the door
	end)
	landmark("Campfire", function(add)
		add(c(-204, 0.4, 52), Vector3.new(5, 0.8, 1), WOOD, Enum.Material.Wood)
		local log = add(c(-204, 0.4, 52), Vector3.new(1, 0.8, 5), WOOD, Enum.Material.Wood)
		local fire = Instance.new("Fire")
		fire.Size, fire.Heat = 5, 8
		fire.Parent = log
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = Color3.fromRGB(255, 160, 80), 22, 2
		light.Parent = log
	end)
	at("Rock", -190, -64)
	at("Rock", -244, 76)
	sign("FOREST", Vector3.new(-212, 32, -16), Color3.fromRGB(120, 200, 110))

	-- N, past the Myth Yard pits: the ruins of two temples, columns standing, broken and fallen.
	local function ruin(name: string, x0: number, x1: number, z0: number, z1: number, heights: { number })
		landmark(name, function(add)
			add(c((x0 + x1) / 2, 1, (z0 + z1) / 2), Vector3.new(x1 - x0, 2, z1 - z0), MARBLE, Enum.Material.Marble)
			local n = #heights
			for i, h in heights do
				local x = x0 + 4 + (x1 - x0 - 8) * (i - 1) / math.max(n - 1, 1)
				for _, z in { z0 + 4, z1 - 4 } do
					local hh = if z == z0 + 4 then h else heights[n - i + 1]
					if hh > 0 then
						add(c(x, 2 + hh / 2, z), Vector3.new(2.6, hh, 2.6), MARBLE, Enum.Material.Marble)
					end
				end
			end
			-- a lintel left on the first two columns of the front row, if they both still stand full height
			if heights[1] >= 16 and heights[2] >= 16 then
				local xa, xb = x0 + 4, x0 + 4 + (x1 - x0 - 8) / math.max(n - 1, 1)
				add(c((xa + xb) / 2, 19, z0 + 4), Vector3.new(xb - xa + 2.6, 2, 3), MARBLE, Enum.Material.Marble)
			end
			add(c((x0 + x1) / 2 + 6, 3.3, (z0 + z1) / 2), Vector3.new(14, 2.6, 2.6), MARBLE, Enum.Material.Marble) -- a fallen column
		end)
	end
	ruin("TempleWest", -120, -60, -246, -216, { 16, 16, 9, 16, 4, 16 })
	ruin("TempleEast", 34, 86, -246, -218, { 16, 6, 16, 11, 16 })
	sign("RUINS", Vector3.new(-90, 32, -231), Color3.fromRGB(240, 220, 170))

	-- NW, behind the rooftops: a water tower on four legs (shoot a leg out and it comes down) and cars.
	landmark("WaterTower", function(add)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				add(c(-215 + sx * 5, 12, -226 + sz * 5), Vector3.new(1.6, 24, 1.6), Color3.fromRGB(110, 70, 50), Enum.Material.Metal)
			end
		end
		add(c(-215, 29, -226), Vector3.new(14, 10, 14), Color3.fromRGB(150, 160, 170), Enum.Material.Metal)
		add(c(-215, 35, -226), Vector3.new(10, 2, 10), Color3.fromRGB(110, 118, 128), Enum.Material.Metal)
	end)
	car("Car7", -180, -230, 0.4, Color3.fromRGB(240, 140, 40))
	car("Car8", -172, -214, -0.3, Color3.fromRGB(80, 80, 90))
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

-- `hurt(model, damage, velocity, kind?)`: the server's hazard (lava burns players and dummies through it).
function Map.build(hurt: (Model, number, Vector3, string?) -> ())
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
	-- the grass round the arena out to the edge of the 512 baseplate: floor tiles like the arena's (into
	-- `rim`), 16 studs and 2-stud columns where hit; 4 studs where they make up the bullseye north of the
	-- launch ramp, its rings drawn in tile colours (a ring lying on the grass would hang over a crater)
	local bull = Vector3.new(0, 0, -222)
	local rings = { { 3, Color3.fromRGB(255, 220, 60), Enum.Material.Neon }, { 7, Color3.new(1, 1, 1) }, { 12, Color3.fromRGB(226, 70, 60) },
		{ 17, Color3.new(1, 1, 1) }, { 22, Color3.fromRGB(226, 70, 60) } }
	local function rimTile(x: number, z: number, size: number)
		local position = Vector3.new(x + size / 2, -CUBE / 2, z + size / 2)
		local color, material, lava = rimLook(position.X, position.Z)
		local d = ((position - bull) * Vector3.new(1, 0, 1)).Magnitude
		for _, ring in rings do
			if size < 16 and d < ring[1] then
				color, material = ring[2], ring[3] or Enum.Material.SmoothPlastic
				break
			end
		end
		local p = block(Vector3.new(size, CUBE, size), position, color, material, rim)
		p:SetAttribute("Piece", size >= 16 and Vector3.new(TILE * 2, CUBE, TILE * 2) or column)
		p:SetAttribute("Lava", lava) -- standing on it burns (lavaLoop); its pieces keep it
		p.CastShadow = false
	end
	for x = -256, 240, 16 do
		for z = -256, 240, 16 do
			if math.abs(x + 8) < HALF and math.abs(z + 8) < HALF then
				continue -- the arena's own floor
			end
			if wet(x + 8, z + 8) then
				continue -- the lake and the pond: water down to the bedrock (districts fills it)
			end
			if ((Vector3.new(x + 8, 0, z + 8) - bull) * Vector3.new(1, 0, 1)).Magnitude < 34 then
				for sx = 0, 12, 4 do
					for sz = 0, 12, 4 do
						rimTile(x + sx, z + sz, 4)
					end
				end
			else
				rimTile(x, z, 16)
			end
		end
	end

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
	-- movement: flats at the town's west end (an alley to the houses, a step up from their roofs), a
	-- walled alley in the southwest, steps up east of the plaza toward the scaffold's top deck
	at("Apartment", 14, -64)
	at("HighWall", -48, 6)
	at("HighWall", -48, 18)
	at("Steps", 46, 14) -- x 24..68, clear of the pillar and the east arch; top 16, 9 short of the scaffold's 26 deck

	-- the landmarks on the rim: structures too (landmark), they break like the rest ------------------
	-- N: launch ramp, 30 up over 70, its top facing the target further north. The plate is a structure of
	-- its own laid along its slope (origin on its underside), so its bricks line up with it.
	local rise, run = 30, 70
	local tilt = math.atan2(rise, run)
	landmark("LaunchRamp", function(add)
		add(CFrame.new(0, 1, 0), Vector3.new(30, 2, math.sqrt(rise * rise + run * run)), Color3.fromRGB(240, 122, 58), Enum.Material.DiamondPlate)
	end, CFrame.new(0, rise / 2, -110 - run / 2) * CFrame.Angles(tilt, 0, 0) * CFrame.new(0, -1, 0))
	landmark("RampLegs", function(add)
		for _, x in { -12, 12 } do
			add(CFrame.new(x, (rise - 2) / 2, -110 - run + 2), Vector3.new(3, rise - 2, 3), Color3.fromRGB(110, 60, 30), Enum.Material.Metal)
		end
	end)
	sign("LAUNCH RAMP", Vector3.new(0, 40, -150), Color3.fromRGB(255, 160, 90))
	sign("BULLSEYE", Vector3.new(0, 14, -222), Color3.fromRGB(255, 120, 100))
	-- E: parkour canyon, two walls 20 apart (replaces the old test wall)
	landmark("Canyon", function(add)
		for _, x in { 100, 124 } do
			for i = 0, 7 do
				add(CFrame.new(x, 24, -70 + i * 20), Vector3.new(4, 48, 20), i % 2 == 0 and Color3.fromRGB(70, 80, 106) or Color3.fromRGB(92, 102, 134), Enum.Material.Concrete)
			end
		end
	end)
	sign("PARKOUR CANYON", Vector3.new(112, 54, 0), Color3.fromRGB(140, 170, 255))
	-- W: drop tower, ledges spiralling up to a platform 80 up. The ledges stand clear of the column, so
	-- they are "Fixed": shot to bits, but never dropped for touching nothing.
	local tower = Vector3.new(-150, 0, 0)
	landmark("DropTower", function(add)
		add(CFrame.new(tower + Vector3.yAxis * 40), Vector3.new(12, 80, 12), Color3.fromRGB(122, 127, 140), Enum.Material.Concrete)
		for i = 1, 15 do
			local angle = i * math.pi / 4
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 12
			local ledge = add(CFrame.new(tower + offset + Vector3.yAxis * (i * 5)), Vector3.new(6, 1.2, 6), i % 2 == 0 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(230, 120, 50), Enum.Material.Metal)
			ledge:SetAttribute("Fixed", true)
		end
		add(CFrame.new(tower + Vector3.yAxis * 81), Vector3.new(16, 2, 16), Color3.fromRGB(60, 62, 72), Enum.Material.DiamondPlate)
	end)
	sign("DROP TOWER", tower + Vector3.yAxis * 92, Color3.fromRGB(255, 200, 80))
	-- NW: rooftops, west of the Myth Yard pits (they reach x = -134). Roofs stepping up westward 6 at
	-- a time (a jump and a mantle each, 8 apart); two long blocks with a 10-stud alley between them to
	-- run wall to wall; a tower behind them, 50 up, climbed by balconies 6 apart, to jump off.
	local CONCRETE = { Color3.fromRGB(176, 166, 150), Color3.fromRGB(150, 118, 102), Color3.fromRGB(120, 128, 142), Color3.fromRGB(196, 152, 112) }
	for i, h in { 10, 16, 22, 28 } do -- 18 x 18, west from x = -143
		local x1 = -143 - (i - 1) * 26
		building(`Roof{i}`, x1 - 18, x1, -124, -106, h, CONCRETE[i])
	end
	landmark("Dumpster", function(add) -- to vault onto the first roof
		add(CFrame.new(-140, 2, -115), Vector3.new(4, 4, 8), Color3.fromRGB(52, 110, 74), Enum.Material.Metal)
	end)
	building("AlleyNorth", -240, -150, -146, -134, 26, Color3.fromRGB(140, 96, 84)) -- the alley, z -156..-146
	building("AlleySouth", -240, -150, -168, -156, 26, Color3.fromRGB(128, 120, 112))
	building("RoofTower", -205, -185, -195, -175, 50, Color3.fromRGB(112, 118, 134), function(add)
		for i, top in { 32, 38, 44 } do -- balconies on its alley side, zigzag
			add(CFrame.new(i % 2 == 1 and -199 or -191, top - 0.5, -173.5), Vector3.new(6, 1, 3), Color3.fromRGB(60, 62, 72), Enum.Material.DiamondPlate)
		end
	end)
	sign("ROOFTOPS", Vector3.new(-192, 62, -150), Color3.fromRGB(255, 170, 120))
	-- the rest of the rim: lava fields, the lake, downtown, the park and the maze, the farm, the forest, ruins
	districts(at)
	lavaLoop(hurt)
	-- S: trampoline field
	for i, x in { -26, 0, 26 } do
		for j, z in { 122, 152 } do
			trampoline(`Trampoline{i}{j}`, Vector3.new(x, 0, z), 14, 115)
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
