-- Port (design doc "Mapa Port / Doki — instrukcja budowy"): a container port far north of the arena.
-- Land in the south (gate, container yard, warehouse, quay with a ship-to-shore crane), a basin of
-- terrain water in the north closed by a breakwater, a cargo ship moored along the quay and a wooden
-- pier with a lighthouse. Everything players stand on or behind breaks like the arena: floors, the
-- ship's deck and the pier are Map tiles, containers, the warehouse, the ship's bridge, the lighthouse,
-- the gate and the walls are Map structures (a stack of containers is one structure, so cutting the
-- bottom one drops the rest). The crane, the hull, piles and bedrock do not break.
-- The crane and the hull are plain parts; when the place has ReplicatedStorage.PortKit (the Blender
-- kit, assets/port: build.py, export.py, install.luau) its meshes are shown instead and the parts
-- stay on, invisible, as the collision.
-- Local coordinates: x east, z north (toward the sea), studs, relative to ORIGIN.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = require(script.Parent.Map)
local KINDS = Map.KINDS

local Port = {}

local ORIGIN = Vector3.new(0, 0, 640) -- the arena rim ends at 256; Factory is at +600 x, City at -600 x
local CUBE = 4 -- Map's layout unit: floor depth and brick
local PIECE = Vector3.new(2, CUBE, 2) -- what a floor tile splits into where hit (as City and Factory)
local W = 160 -- half width
local SOUTH, QUAY, NORTH = -144, 24, 144 -- land from SOUTH to the quay edge, water from there to NORTH
local SEA, BED = -6, -26 -- water surface, sea bed
local DECK = 8 -- ship deck top
local HULL_W, HULL_E, HULL_S, HULL_N = -24, 120, 32, 72 -- ship's box (the bow sticks out east to 136)
local BOW = 136
local CRANE_X = 24
local RAILS = { -2, 18 } -- z of the crane rails (tile rows)

Port.SPAWN = CFrame.lookAt(ORIGIN + Vector3.new(0, 5, -128), ORIGIN + Vector3.new(0, 5, 0))
Port.DUMMY_SPOTS = {}
for _, p in {
	{ -108, 4, -74 }, { -60, 4, -46 }, { -12, 4, -74 }, { 40, 4, -46 }, -- yard aisles
	{ -60, 4, 6 }, { 100, 4, 6 }, -- quay
	{ 30, 12, 52 }, { 108, 12, 64 }, -- ship deck
	{ 100, 4, -80 }, { -140, 4, 80 }, -- warehouse, pier
	{ -36, 52, -88 }, { -132, 36, -60 }, -- container tops
} do
	table.insert(Port.DUMMY_SPOTS, ORIGIN + Vector3.new(p[1], p[2], p[3]))
end

local CONCRETE = { Color3.fromRGB(150, 148, 145), Color3.fromRGB(138, 136, 134) }
local YARD = Color3.fromRGB(126, 124, 122)
local ASPHALT = Color3.fromRGB(58, 58, 64)
local PAINT = Color3.fromRGB(232, 232, 226)
local YELLOW = Color3.fromRGB(235, 185, 30)
local BLACK = Color3.fromRGB(30, 30, 34)
local STEEL = Color3.fromRGB(70, 74, 82)
local SHED_FLOOR = Color3.fromRGB(160, 158, 150)
local WOOD = { Color3.fromRGB(128, 82, 52), Color3.fromRGB(112, 72, 46) }
local BEDROCK = Color3.fromRGB(60, 62, 66)
local ROCK = Color3.fromRGB(120, 122, 130)
local BLUE = Color3.fromHex("2E6FB0")
local WHITE = Color3.fromRGB(235, 235, 230)
local RED = Color3.fromRGB(200, 50, 45)
local HULL = Color3.fromRGB(28, 28, 32)
local HULL_RED = Color3.fromRGB(150, 40, 35)
local LAMP = Color3.fromHex("FFF6D0")
local GLASS = Color3.fromRGB(150, 210, 245)
local BRIDGE_GLASS = Color3.fromRGB(60, 105, 140)
local WALL = { Color3.fromRGB(176, 168, 150), Color3.fromRGB(160, 152, 136) }
local ROOF = Color3.fromRGB(90, 96, 104)
local BOX_COLORS = { "B8432F", "2F5FA8", "3C8A4A", "E07A2A", "E0B42A", "7A7E86" }

local folder = Instance.new("Folder") -- what does not break
folder.Name = "Port"
local standins: { BasePart }? = nil -- while set, part() also lists what it makes (crane, hull)

-- An unbreakable anchored part at `cf` (local space).
local function part(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(ORIGIN) * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	if standins then
		table.insert(standins, p)
	end
	return p
end

-- Clones the PortKit meshes of every piece whose name starts with `prefix`, at `pivot` (local space).
-- False when the place has no kit.
local function fromKit(prefix: string, pivot: CFrame): boolean
	local kit = ReplicatedStorage:FindFirstChild("PortKit")
	local placed = false
	for _, piece in kit and kit:GetChildren() or {} do
		if string.sub(piece.Name, 1, #prefix) == prefix then
			for _, mesh in piece:GetChildren() do
				local p = mesh:Clone() :: BasePart
				p.CFrame = CFrame.new(ORIGIN) * pivot * (p:GetAttribute("Place") or CFrame.identity)
				p.Parent = folder
				placed = true
			end
		end
	end
	return placed
end

-- With the meshes in, the stand-ins only collide: hidden, and the ones that never collided go.
local function hide(parts: { BasePart })
	for _, p in parts do
		if p.CanCollide then
			p.Transparency, p.CastShadow = 1, false
		else
			p:Destroy()
		end
	end
end

local function box(size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): BasePart
	return part(size, CFrame.new(position), color, material)
end

-- A square bar from `a` to `b`.
local function bar(a: Vector3, b: Vector3, thick: number, color: Color3, collide: boolean?): BasePart
	local p = part(Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, Enum.Material.Metal)
	p.CanCollide = collide ~= false
	return p
end

-- An upright cylinder standing on `bottom`.
local function post(bottom: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?): BasePart
	local p = part(Vector3.new(height, diameter, diameter), CFrame.new(bottom + Vector3.yAxis * height / 2) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function invisible(size: Vector3, position: Vector3)
	local p = box(size, position, BLACK)
	p.Transparency = 1
	p.CastShadow = false
end

-- A climbable truss from `bottom` up `height` studs (rounded to Roblox's 2-stud truss steps).
local function truss(bottom: Vector3, height: number)
	height = math.max(2, math.round(height / 2) * 2)
	local p = part(Vector3.new(2, height, 2), CFrame.new(bottom + Vector3.yAxis * height / 2), STEEL, Enum.Material.Metal, "TrussPart")
	p.CastShadow = false
end

local function at(kind: string, x: number, z: number, turns: number?, y: number?)
	Map.structure(kind, CFrame.new(ORIGIN + Vector3.new(x, y or 0, z)) * CFrame.Angles(0, (turns or 0) * math.pi / 2, 0))
end

-- STRUCTURES (cube-grid units, relative to the origin on the ground; see Map.KINDS)

-- One 40x16x16 container (10 x 4 x 4 cubes, hollow, 32x8x8 inside) at cube height y0, doors at +x.
local function container(add, y0: number, color: Color3, open: boolean)
	local dark = color:Lerp(Color3.new(), 0.18)
	for x = -4.5, 4.5 do
		for y = 0, 3 do
			for z = -1.5, 1.5 do
				local ex, ey, ez = math.abs(x) == 4.5, y == 0 or y == 3, math.abs(z) == 1.5
				local doorway = open and x == 4.5 and not ey and not ez
				if (ex or ey or ez) and not doorway then
					local frame = (ex and ez) or (ey and (ex or ez))
					add(x, y0 + y, z, (frame or (x + 4.5) % 2 == 1) and dark or color, Enum.Material.Metal)
				end
			end
		end
	end
end

-- A stack of containers is one structure: cut the bottom one and the rest has nothing to stand on.
local stackCount = 0
local function stack(rng: Random, height: number): string
	stackCount += 1
	local name = "PortStack" .. stackCount
	local looks = {}
	for i = 1, height do
		looks[i] = { Color3.fromHex(BOX_COLORS[rng:NextInteger(1, #BOX_COLORS)]), rng:NextNumber() < 0.33 }
	end
	KINDS[name] = function(add)
		for i, look in looks do
			container(add, (i - 1) * 4, look[1], look[2])
		end
	end
	return name
end

-- 80x32x80 shed: walls, roof, a 24x20 gate west and north, a mezzanine 16 up along the east wall.
function KINDS.PortWarehouse(add)
	for x = -9.5, 9.5 do
		for z = -9.5, 9.5 do
			local wall = math.abs(x) == 9.5 or math.abs(z) == 9.5
			for y = 0, 7 do
				local gate = y < 5 and ((x == -9.5 and math.abs(z) < 3) or (z == 9.5 and math.abs(x) < 3))
				if y == 7 then
					add(x, y, z, ROOF, Enum.Material.Metal)
				elseif wall and not gate then
					add(x, y, z, WALL[y % 2 + 1], Enum.Material.Concrete)
				end
			end
			if (x == 7.5 or x == 8.5) and not wall then
				add(x, 3, z, STEEL, Enum.Material.DiamondPlate)
			end
		end
	end
end

-- 12x56x12 hollow tower, red and white bands, an open lantern room (neon corners) under a roof.
function KINDS.PortLighthouse(add)
	for y = 0, 13 do
		for x = -1, 1 do
			for z = -1, 1 do
				local ring = x ~= 0 or z ~= 0
				local door = y <= 1 and x == 0 and z == -1
				if y <= 10 and ring and not door then
					add(x, y, z, (y // 2) % 2 == 0 and RED or WHITE, Enum.Material.SmoothPlastic)
				elseif (y == 11 or y == 12) and x ~= 0 and z ~= 0 then
					add(x, y, z, LAMP, Enum.Material.Neon)
				elseif y == 13 then
					add(x, y, z, RED, Enum.Material.SmoothPlastic)
				end
			end
		end
	end
end

-- The ship's bridge: a 20x40x40 white shell, a door east, a window band near the top, a roof hatch.
function KINDS.PortBridge(add)
	for x = -2, 2 do
		for z = -4.5, 4.5 do
			local wall = math.abs(x) == 2 or math.abs(z) == 4.5
			for y = 0, 9 do
				local door = y <= 1 and x == 2 and math.abs(z) < 1
				local hatch = y == 9 and x == 0 and z == 0.5
				if y == 9 and not hatch then
					add(x, y, z, WHITE, Enum.Material.SmoothPlastic)
				elseif y < 9 and wall and not door then
					local window = (y == 7 or y == 8) and not (math.abs(x) == 2 and math.abs(z) == 4.5)
					-- tinted glass, not Neon: a Neon band blooms into one white blot in daylight
					add(x, y, z, window and BRIDGE_GLASS or WHITE, Enum.Material.SmoothPlastic)
				end
			end
		end
	end
end

-- 12x12x12 guard hut: door west, a lit window east.
function KINDS.PortHut(add)
	for x = -1, 1 do
		for z = -1, 1 do
			for y = 0, 2 do
				local ring = x ~= 0 or z ~= 0
				if y == 2 then
					add(x, y, z, WHITE, Enum.Material.SmoothPlastic)
				elseif ring and not (x == -1 and z == 0) then
					local window = y == 1 and x == 1 and z == 0
					add(x, y, z, window and YELLOW or WALL[1], window and Enum.Material.Neon or Enum.Material.Concrete)
				end
			end
		end
	end
end

-- Gate: two 4x20 posts 32 apart and a striped bar 8 up between them.
function KINDS.PortGate(add)
	for y = 0, 4 do
		add(-3.5, y, 0, y % 2 == 0 and YELLOW or BLACK, Enum.Material.Concrete)
		add(3.5, y, 0, y % 2 == 0 and YELLOW or BLACK, Enum.Material.Concrete)
	end
	for x = -2.5, 2.5 do
		add(x, 2, 0, (x + 2.5) % 2 == 0 and RED or WHITE, Enum.Material.SmoothPlastic)
	end
end

-- FLOORS

local function landLook(x: number, z: number): (Color3, Enum.Material)
	if z < -108 then -- entrance: asphalt, a parking lot with lines every 12
		local lot = x > -80 and x < -40 and z > -140 and z < -116
		if lot and (x + 78) % 12 == 0 then
			return PAINT, Enum.Material.Asphalt
		end
		return ASPHALT, Enum.Material.Asphalt
	elseif z > -16 then -- quay: slabs, crane rails, a striped edge
		if z == QUAY - 2 then
			return (x + 158) % 8 == 0 and YELLOW or BLACK, Enum.Material.Concrete
		elseif z == RAILS[1] or z == RAILS[2] then
			return STEEL, Enum.Material.DiamondPlate
		end
		return CONCRETE[((x + 160) // 8 + (z + 144) // 8) % 2 + 1], Enum.Material.Concrete
	elseif x > 72 and x < 152 and z > -104 and z < -24 then
		return SHED_FLOOR, Enum.Material.Concrete
	elseif z == -74 or z == -46 then -- lane lines down the yard aisles
		return YELLOW, Enum.Material.Concrete
	end
	return YARD, Enum.Material.Concrete
end

local function floors()
	for x = -W + 2, W - 2, CUBE do
		for z = SOUTH + 2, QUAY - 2, CUBE do
			local color, material = landLook(x, z)
			-- nothing under a floor to shade, and thousands of shadow casters cost every frame
			Map.tile(Vector3.new(CUBE, CUBE, CUBE), ORIGIN + Vector3.new(x, -CUBE / 2, z), color, material, PIECE).CastShadow = false
		end
		if (x + W) % 32 < CUBE then
			task.wait()
		end
	end
	for x = -150, -130, CUBE do -- the pier
		for z = QUAY + 2, 134, CUBE do
			Map.tile(Vector3.new(CUBE, CUBE, CUBE), ORIGIN + Vector3.new(x, -CUBE / 2, z), WOOD[(x // CUBE) % 2 + 1], Enum.Material.WoodPlanks, PIECE).CastShadow = false
		end
	end
	task.wait()
	for x = HULL_W + 22, BOW - 2, CUBE do -- the deck, from the bridge to the tip of the bow
		for z = HULL_S + 4, HULL_N - 4, CUBE do
			-- in the bow only whole tiles inside the plates (a corner poking through the hull shows)
			local inBow = x < HULL_E or math.abs(z - 52) + 2 <= 20 * (BOW - x - 2) / (BOW - HULL_E)
			local hatch = x > 100 and x < 108 and z > 48 and z < 56
			if inBow and not hatch then
				Map.tile(Vector3.new(CUBE, CUBE, CUBE), ORIGIN + Vector3.new(x, DECK - CUBE / 2, z), STEEL:Lerp(BLACK, ((x + z) // 4) % 2 * 0.15), Enum.Material.DiamondPlate, PIECE).CastShadow = false
			end
		end
	end
end

-- WATER, BEDROCK, EDGES

local function ground()
	-- bedrock under the land floor, down to the sea bed: its north face is the quay wall
	box(Vector3.new(2 * W, -CUBE - BED, QUAY - SOUTH), Vector3.new(0, (BED - CUBE) / 2, (SOUTH + QUAY) / 2), BEDROCK, Enum.Material.Concrete)
	local terrain = workspace.Terrain
	local basin = Vector3.new(0, 0, (QUAY + NORTH) / 2)
	terrain:FillBlock(CFrame.new(ORIGIN + basin + Vector3.yAxis * (BED - 2)), Vector3.new(2 * W, 4, NORTH - QUAY), Enum.Material.Mud)
	terrain:FillBlock(CFrame.new(ORIGIN + basin + Vector3.yAxis * (BED + SEA) / 2), Vector3.new(2 * W, SEA - BED, NORTH - QUAY), Enum.Material.Water)
	-- the hold is dry: clear the water inside the hull
	terrain:FillBlock(CFrame.new(ORIGIN + Vector3.new((HULL_W + HULL_E) / 2 + 1, -8, (HULL_S + HULL_N) / 2)), Vector3.new(HULL_E - HULL_W - 2, 8, HULL_N - HULL_S - 4), Enum.Material.Air)
	terrain.WaterColor = Color3.fromHex("1F4F5C")
	terrain.WaterTransparency = 0.35
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = 0.6

	-- breakwater: an unbreakable bank to 4 over the water, broken rocks on top, a gap for ships
	for _, span in { { -W, 0 }, { 24, W } } do
		box(Vector3.new(span[2] - span[1], -2 - BED, 8), Vector3.new((span[1] + span[2]) / 2, (BED - 2) / 2, 140), ROCK, Enum.Material.Slate)
		for x = span[1] + 6, span[2] - 6, 12 do
			at("Rock", x, 140, 0, -2)
		end
	end
	-- walls round the land (they break) and invisible ones round everything (they do not)
	for x = -146, 134, 28 do
		at("Wall", x, SOUTH + 2)
	end
	for _, x in { -W + 2, W - 2 } do
		for z = -126, -14, 28 do -- starts clear of the south wall's corner cubes
			at("Wall", x, z, 1)
		end
	end
	invisible(Vector3.new(4, 120, NORTH - SOUTH + 8), Vector3.new(-W - 2, 30, 0))
	invisible(Vector3.new(4, 120, NORTH - SOUTH + 8), Vector3.new(W + 2, 30, 0))
	invisible(Vector3.new(2 * W, 120, 4), Vector3.new(0, 30, SOUTH - 2))
	invisible(Vector3.new(2 * W, 120, 4), Vector3.new(0, 30, NORTH + 2))
	-- ladders out of the water every 48 along the quay, the breakwater and the pier
	for _, x in { -120, -96, -48, 0, 48, 96, 144 } do
		truss(Vector3.new(x, BED, QUAY + 1), -BED)
	end
	for _, x in { -136, -88, -40, 56, 104, 152 } do
		truss(Vector3.new(x, BED, 135), -2 - BED)
	end
	for _, s in { { -127, 60 }, { -127, 108 }, { -153, 84 } } do
		truss(Vector3.new(s[1], BED, s[2]), -BED)
	end
end

-- QUAY

local function lamp(x: number, z: number)
	post(Vector3.new(x, 0, z), 16, 0.8, STEEL, Enum.Material.Metal)
	local head = box(Vector3.new(2, 0.6, 3), Vector3.new(x, 16.3, z + 1), STEEL, Enum.Material.Metal)
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range, light.Angle, light.Brightness = 24, 70, 2
	light.Color = Color3.fromHex("FFD9A0")
	light.Parent = head
	box(Vector3.new(1.6, 0.2, 2.6), Vector3.new(x, 15.9, z + 1), LAMP, Enum.Material.Neon)
end

local function quay()
	for x = -152, 152, 16 do -- bollards, clear of the crane and the gangway
		if math.abs(x - CRANE_X) > 20 and math.abs(x - 60) > 4 then
			post(Vector3.new(x, 0, QUAY - 3), 2.5, 2, BLACK, Enum.Material.Metal)
			post(Vector3.new(x, 2.5, QUAY - 3), 0.4, 2.2, YELLOW, Enum.Material.Metal)
		end
	end
	for x = -114, 150, 12 do -- tyre fenders on the quay face
		local tyre = part(Vector3.new(1.2, 3, 3), CFrame.new(x, -3, QUAY + 0.6) * CFrame.Angles(0, math.pi / 2, 0), BLACK, Enum.Material.Rubber)
		tyre.Shape = Enum.PartType.Cylinder
	end
	for x = -144, 144, 32 do
		lamp(x, -12)
	end
	at("Crates", -90, 4)
	at("Crates", 124, 6)
	at("Crates", 92, -84) -- in the shed
	at("Crates", 92, -44)
end

-- CRANE: portal on the rails, boom over the ship, a trolley and a spreader (PortKit's Port_Crane*
-- pieces, pivot between the rails under the portal's middle; these parts are their collision).

local function crane()
	local x = CRANE_X
	standins = {}
	for _, lx in { x - 14, x + 14 } do
		for _, lz in RAILS do
			box(Vector3.new(4, 38, 4), Vector3.new(lx, 19, lz), BLUE, Enum.Material.Metal)
		end
		box(Vector3.new(4, 4, 24), Vector3.new(lx, 40, 8), BLUE, Enum.Material.Metal)
	end
	for _, lz in RAILS do
		box(Vector3.new(24, 4, 4), Vector3.new(x, 40, lz), WHITE, Enum.Material.Metal)
	end
	box(Vector3.new(28, 12, 12), Vector3.new(x, 48, 8), WHITE, Enum.Material.Metal) -- machinery house
	-- boom, walkable on top; a hair over the beams so its underside does not share the house's plane
	box(Vector3.new(4, 4, 124), Vector3.new(x, 44.05, 26), BLUE, Enum.Material.Metal)
	box(Vector3.new(1, 1, 1), Vector3.new(x, 46.6, 87.5), RED, Enum.Material.Neon)
	local apex = Vector3.new(x, 66, 8)
	bar(Vector3.new(x - 12, 54, 8), apex, 2, BLUE)
	bar(Vector3.new(x + 12, 54, 8), apex, 2, BLUE)
	box(Vector3.new(3, 3, 3), apex, BLUE, Enum.Material.Metal)
	bar(apex, Vector3.new(x, 46, 87), 0.3, STEEL, false).CastShadow = false
	bar(apex, Vector3.new(x, 46, -35), 0.3, STEEL, false).CastShadow = false
	box(Vector3.new(8, 4, 8), Vector3.new(x, 40, 64), YELLOW, Enum.Material.Metal) -- trolley
	box(Vector3.new(6, 5, 6), Vector3.new(x, 35.5, 64), WHITE, Enum.Material.Metal) -- cab
	box(Vector3.new(4.6, 2, 0.2), Vector3.new(x, 36, 67.13), GLASS, Enum.Material.Glass).Transparency = 0.3
	box(Vector3.new(36, 1, 8), Vector3.new(x, DECK + 16.5, 64), YELLOW, Enum.Material.Metal) -- spreader, on a container, clear of the funnel
	for _, dx in { -3, 3 } do
		for _, dz in { -3, 3 } do
			bar(Vector3.new(x + dx, DECK + 17, 64 + dz), Vector3.new(x + dx, 38, 64 + dz), 0.25, STEEL, false).CastShadow = false
		end
	end
	local made = standins :: { BasePart }
	standins = nil
	if fromKit("Port_Crane", CFrame.new(x, 0, (RAILS[1] + RAILS[2]) / 2)) then
		hide(made)
	end
	for _, dz in { 40, 80 } do -- floodlights under the boom
		local fixture = box(Vector3.new(1.5, 0.6, 1.5), Vector3.new(x, 41.7, dz), LAMP, Enum.Material.Neon)
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Range, light.Angle, light.Brightness = 50, 50, 3
		light.Shadows = dz == 40
		light.Parent = fixture
	end
	truss(Vector3.new(x - 17, 0, RAILS[1]), 42) -- up the outside of a leg to the portal beam
end

-- SHIP: the hull is PortKit's Port_Hull (pivot at x 56, mid z); these plates are its collision, and
-- its look without the kit: red under the water line, a white stripe, black above.

local function hullSide(a: Vector2, b: Vector2, lift: number)
	local mid, len = (a + b) / 2, (b - a).Magnitude
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Y), Vector3.new(b.X, 0, b.Y))
	for _, band in { { -20 - lift, SEA, HULL_RED }, { SEA, SEA + 1, WHITE }, { SEA + 1, DECK + lift, HULL } } do
		part(Vector3.new(2, band[2] - band[1], len), cf + Vector3.yAxis * (band[1] + band[2]) / 2, band[3], Enum.Material.SmoothPlastic)
	end
end

local function ship()
	local mid = (HULL_S + HULL_N) / 2
	standins = {}
	hullSide(Vector2.new(HULL_W, HULL_S + 1), Vector2.new(HULL_E, HULL_S + 1), 0)
	hullSide(Vector2.new(HULL_W, HULL_N - 1), Vector2.new(HULL_E, HULL_N - 1), 0)
	hullSide(Vector2.new(HULL_W + 1, HULL_S + 2), Vector2.new(HULL_W + 1, HULL_N - 2), 0)
	hullSide(Vector2.new(HULL_E, HULL_S + 1), Vector2.new(BOW, mid), 0.04) -- bow plates reach a hair higher and
	hullSide(Vector2.new(HULL_E, HULL_N - 1), Vector2.new(BOW, mid), 0.08) -- lower: no shared top or bottom faces
	local made = standins :: { BasePart }
	standins = nil
	if fromKit("Port_Hull", CFrame.new((HULL_W + BOW) / 2, 0, mid)) then
		hide(made)
	end
	box(Vector3.new(HULL_E - HULL_W - 2, 2, HULL_N - HULL_S - 4), Vector3.new((HULL_W + HULL_E) / 2 + 1, -13, mid), STEEL, Enum.Material.DiamondPlate) -- hold floor
	box(Vector3.new(18, CUBE, HULL_N - HULL_S - 4), Vector3.new(-13, DECK - CUBE / 2, mid), STEEL, Enum.Material.DiamondPlate) -- deck under the bridge
	at("PortBridge", -14, mid, 0, DECK)
	truss(Vector3.new(-14, DECK, mid + 2), 40) -- inside the bridge, up to the roof hatch
	truss(Vector3.new(101, -12, 52), 20) -- out of the hold through the bow hatch
	for _, x in { 20, 70 } do -- out of the water up the hull (clear of the name, x 82..102)
		truss(Vector3.new(x, -18, HULL_S - 1), DECK + 18)
		truss(Vector3.new(x, -18, HULL_N + 1), DECK + 18)
	end
	-- funnel with a white band and smoke
	box(Vector3.new(8, 22, 12), Vector3.new(2, DECK + 11, 62), RED)
	box(Vector3.new(8, 4, 12), Vector3.new(2, DECK + 24, 62), WHITE)
	local top = box(Vector3.new(8, 6, 12), Vector3.new(2, DECK + 29, 62), RED)
	local vent = Instance.new("Attachment")
	vent.Position = Vector3.new(0, 3, 0)
	vent.Parent = top
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate, smoke.Lifetime, smoke.Speed = 6, NumberRange.new(5, 7), NumberRange.new(3, 5)
	smoke.Size = NumberSequence.new(4, 12)
	smoke.Transparency = NumberSequence.new(0.35, 1)
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 90, 95))
	smoke.Acceleration = Vector3.new(4, 1, 0)
	smoke.Parent = vent
	-- gangway from the quay to the deck
	local from, to = Vector3.new(60, 0.3, 14), Vector3.new(60, DECK + 0.3, HULL_S + 1)
	part(Vector3.new(4, 0.6, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), STEEL, Enum.Material.DiamondPlate)
	for _, dx in { -2.2, 2.2 } do
		bar(from + Vector3.new(dx, 3, 0), to + Vector3.new(dx, 3, 0), 0.3, WHITE)
	end
	-- moorings, bow and stern
	for _, m in { { -24, -16 }, { 120, 112 } } do -- { bollard x, hull x }
		bar(Vector3.new(m[1], 2.5, QUAY - 3), Vector3.new(m[2], DECK - 1, HULL_S), 0.4, Color3.fromRGB(200, 190, 160), false).CastShadow = false
	end
end

-- PIER, LIGHTHOUSE, BUOYS

local function pier()
	for _, x in { -149, -131 } do
		for z = QUAY + 4, 132, 8 do
			post(Vector3.new(x, BED, z), -CUBE - BED, 1.6, WOOD[2], Enum.Material.Wood)
		end
	end
	at("PortLighthouse", -140, 128)
	truss(Vector3.new(-140, 0, 128), 44)
	local lantern = box(Vector3.new(1, 1, 1), Vector3.new(-140, 50, 128), LAMP, Enum.Material.Neon)
	lantern.Transparency, lantern.CanCollide, lantern.CanQuery = 1, false, false
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 30, 3, LAMP
	light.Parent = lantern
	for _, b in { { 0, RED }, { 24, Color3.fromRGB(40, 190, 70) } } do
		post(Vector3.new(b[1], SEA - 1, 128), 3, 3, b[2])
		local top = box(Vector3.new(1.5, 1.5, 1.5), Vector3.new(b[1], SEA + 2.75, 128), b[2], Enum.Material.Neon)
		top.Shape = Enum.PartType.Ball
		local glow = Instance.new("PointLight")
		glow.Range, glow.Color = 10, b[2]
		glow.Parent = top
	end
end

-- YARD, SHED, GATE

local function yard()
	local rng = Random.new(7) -- fixed: the yard looks the same every server, and after a rebuild
	-- { row z, stack height per slot (x = -132, -84, -36, 12) }; the 12 slot of the -32 row sits under
	-- the crane's back-reach (boom at 42): 2 at most
	for _, row in { { -88, { 1, 2, 3, 2 } }, { -60, { 2, 3, 1, 2 } }, { -32, { 3, 2, 1, 2 } } } do
		local z = row[1]
		for i, h in row[2] do
			local x = -180 + i * 48
			at(stack(rng, h), x, z)
			if h == 3 then
				truss(Vector3.new(x - 21, 0, z), 48)
			end
			task.wait()
		end
	end
	for _, s in { { 28, 42, 2 }, { 76, 42, 1 }, { 28, 62, 1 }, { 76, 62, 2 } } do
		at(stack(rng, s[3]), s[1], s[2], 0, DECK)
	end
	at("PortWarehouse", 112, -64)
	truss(Vector3.new(139, 0, -64), 16) -- up to the mezzanine
	at("PortGate", 0, -112)
	at("PortHut", 20, -128)
end

function Port.build()
	ground()
	floors()
	quay()
	crane()
	ship()
	pier()
	yard()
	folder.Parent = workspace
end

return Port
