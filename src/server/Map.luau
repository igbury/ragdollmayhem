-- Destructible arena (Mayhem Park, see Map.build): a floor of anchored cubes over dark bedrock, plus structures built from
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
			pin.part:SetNetworkOwner(nil)
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
	-- floor = thin columns: small on top so craters come out round, full depth so they stay deep
	local count = math.round(HALF * 2 / TILE)
	for ix = 0, count - 1 do
		for iz = 0, count - 1 do
			local position = Vector3.new(-HALF + (ix + 0.5) * TILE, -CUBE / 2, -HALF + (iz + 0.5) * TILE)
			local color, material = floorLook(position.X, position.Z, ix, iz)
			-- nothing under the floor to shade, and 14k shadow casters cost the client every frame
			block(Vector3.new(TILE, CUBE, TILE), position, color, material, folder).CastShadow = false
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
