-- Destructible arena: a floor of anchored cubes over dark bedrock, plus structures built from
-- cubes (pillars, trees, walls, towers, arches, crates, rocks) that collapse when hit.
-- Broken floor cubes are hidden (not destroyed) and come back after REGEN seconds.
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")

local Map = {}

local CUBE = 4 -- layout unit and floor depth
local TILE = CUBE / 3 -- floor columns and flying debris
local BRICK = CUBE / 2 -- structure cubes; ponytail: not TILE, a tower would be ~1300 loose parts when it falls
local HALF = 80 -- arena is 2*HALF studs wide
local REGEN = 25
local LOOSE_LIFE = 6 -- fallen structure bricks are swept after this, the structure returns at REGEN
local MAX_LOOSE = 110 -- bricks kept per falling structure, the rest vanish in the dust
local MAX_CHUNKS = 140 -- flying cubes per blast
local MAX_DEBRIS = 250 -- loose cubes alive at once across all blasts, extra ones just aren't spawned
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

local live = 0
local function track(p: BasePart)
	live += 1
	p.Destroying:Once(function()
		live -= 1
	end)
end

local function chunk(source: BasePart, size: number, velocity: Vector3)
	if live >= MAX_DEBRIS then
		return
	end
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

local function hide(cubes: { BasePart })
	setHidden(cubes, true)
	task.delay(REGEN, setHidden, cubes, false)
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

local function buildStructure(kind: string, origin: CFrame)
	local model = Instance.new("Model")
	model.Name = kind
	KINDS[kind](function(x, y, z, color, material, size)
		size = size or CUBE
		-- every block is built out of small bricks so it shatters instead of tumbling whole
		local n = math.round(size / BRICK)
		local brick = size / n
		for bx = 1, n do
			for by = 1, n do
				for bz = 1, n do
					local offset = Vector3.new(bx, by, bz) * brick - Vector3.one * (size + brick) / 2
					local cube = block(Vector3.one * brick, Vector3.zero, color, material, model)
					cube.CFrame = origin * CFrame.new(x * CUBE, y * CUBE + size / 2, z * CUBE) * CFrame.new(offset)
				end
			end
		end
	end)
	model:SetAttribute("Origin", origin)
	model.Parent = folder
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
	model.Parent = folder
	return model
end

-- A breakable floor/deck tile: blasts hide it, it comes back after REGEN.
function Map.tile(size: Vector3, position: Vector3, color: Color3, material: Enum.Material)
	return block(size, position, color, material, folder)
end

local function collapse(model: Model, from: Vector3, power: number)
	-- model is nil for a brick this same blast already thinned out of its structure
	if not model or model:GetAttribute("Fallen") then
		return
	end
	model:SetAttribute("Fallen", true)
	local bricks = model:GetChildren()
	local keep = math.max(0, math.min(MAX_LOOSE, MAX_DEBRIS - live)) / #bricks
	for _, cube in bricks do
		if math.random() > keep then
			cube:Destroy()
			continue
		end
		track(cube)
		cube.CollisionGroup = "Debris"
		cube.Anchored = false
		-- cubes next to the blast get thrown, the rest just lose their footing
		local offset = cube.Position - from
		cube.AssemblyLinearVelocity = offset.Unit * power * math.clamp(1.2 - offset.Magnitude / 24, 0.1, 1)
		cube.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
	end
	task.delay(LOOSE_LIFE, model.ClearAllChildren, model)
	task.delay(REGEN, function()
		model:Destroy()
		if model:GetAttribute("Origin") then -- a grave (Map.grave) stays broken
			buildStructure(model.Name, model:GetAttribute("Origin"))
		end
	end)
end

-- Carve a crater. `inner` leaves an untouched island in the middle (ring crater).
function Map.blast(position: Vector3, radius: number, power: number, inner: number?)
	local hits = workspace:GetPartBoundsInRadius(position, radius, params)
	local chance = math.min(1, MAX_CHUNKS / math.max(#hits, 1))
	local broken = {}
	for _, cube in hits do
		if cube.Parent ~= folder then
			collapse(cube.Parent, position, power)
			continue
		end
		local offset = (cube.Position - position) * Vector3.new(1, 0, 1)
		if offset.Magnitude > radius or offset.Magnitude < (inner or 0) then
			continue
		end
		table.insert(broken, cube)
		if math.random() < chance then
			local out = offset.Magnitude > 0.1 and offset.Unit or Vector3.zero
			local velocity = (out * (0.3 + math.random() * 0.5) + Vector3.yAxis * (0.6 + math.random() * 0.6)) * power
			chunk(cube, TILE * (0.7 + math.random() * 0.6), velocity)
		end
	end
	hide(broken)
end

-- Rip a rectangular slab out of the floor and throw it up as cubes.
function Map.flip(cf: CFrame, size: Vector3, velocity: Vector3)
	local hits = workspace:GetPartBoundsInBox(cf, size, params)
	local chance = math.min(1, MAX_CHUNKS * 1.5 / math.max(#hits, 1))
	local broken = {}
	for _, cube in hits do
		if cube.Parent ~= folder then
			collapse(cube.Parent, cf.Position, velocity.Magnitude)
			continue
		end
		table.insert(broken, cube)
		if math.random() < chance then
			chunk(cube, TILE * (0.9 + math.random() * 0.5), velocity * (0.7 + math.random() * 0.6))
		end
	end
	hide(broken)
end

function Map.build()
	local bedrock = workspace:FindFirstChild("Baseplate") :: BasePart?
	if bedrock then -- crater floor: sits one cube below the grass
		bedrock.Position = Vector3.new(0, -CUBE - bedrock.Size.Y / 2, 0)
		bedrock.Color = Color3.fromRGB(41, 38, 43)
	end
	-- floor = thin columns: small on top so craters come out round, full depth so they stay deep
	local count = math.round(HALF * 2 / TILE)
	for ix = 0, count - 1 do
		for iz = 0, count - 1 do
			local position = Vector3.new(-HALF + (ix + 0.5) * TILE, -CUBE / 2, -HALF + (iz + 0.5) * TILE)
			local color = GRASS[(ix // 6 + iz // 6) % 2 + 1]
			-- nothing under the floor to shade, and 14k shadow casters cost the client every frame
			block(Vector3.new(TILE, CUBE, TILE), position, color, Enum.Material.Grass, folder).CastShadow = false
		end
	end
	-- solid grass around the arena, out to the edge of the 512 baseplate
	local rim = Instance.new("Model")
	rim.Name = "Rim"
	local far = (256 + HALF) / 2
	local wide = 256 - HALF
	for _, side in { -1, 1 } do
		block(Vector3.new(512, CUBE, wide), Vector3.new(0, -CUBE / 2, side * far), GRASS[1], Enum.Material.Grass, rim)
		block(Vector3.new(wide, CUBE, HALF * 2), Vector3.new(side * far, -CUBE / 2, 0), GRASS[1], Enum.Material.Grass, rim)
	end
	rim.Parent = workspace
	-- big wall for testing wall runs: just outside the arena on the east side, outside the
	-- destructible folder so blasts leave it alone
	local testWall = Instance.new("Part")
	testWall.Name = "TestWall"
	testWall.Anchored = true
	testWall.Size = Vector3.new(4, 48, 160)
	testWall.Position = Vector3.new(HALF + 24, 24, 0)
	testWall.Color = Color3.fromRGB(70, 78, 105)
	testWall.Material = Enum.Material.SmoothPlastic
	testWall.Parent = workspace
	-- rings of structures around the middle; snapped to the cube grid and turned in 90-degree
	-- steps so everything sits on whole cubes
	local function ring(kind: string, count: number, radius: number, phase: number)
		for i = 1, count do
			local angle = (i + phase) / count * math.pi * 2
			local x = math.round(math.cos(angle) * radius / CUBE) * CUBE
			local z = math.round(math.sin(angle) * radius / CUBE) * CUBE
			buildStructure(kind, CFrame.new(x, 0, z) * CFrame.Angles(0, math.round(angle / (math.pi / 2)) * math.pi / 2, 0))
		end
	end
	ring("Crates", 6, 14, 0.5)
	ring("Rock", 5, 34, 0.2)
	ring("Wall", 6, 42, 0.5)
	ring("Pillar", 6, 56, 0)
	ring("Arch", 4, 50, 0.5)
	ring("Tree", 12, 68, 0.25)
	ring("Tower", 4, 72, 0.5)
	folder.Parent = workspace
end

return Map
