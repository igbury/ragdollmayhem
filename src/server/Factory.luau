-- Factory: an enclosed three-storey plant far from the arena, full of machines that hurt anything
-- with a Humanoid that touches them. Floors, decks and props break like the arena (Map tiles and
-- structures); walls, roof, ramps and the machines themselves do not.
-- Factory.build(hurt) wires it; hurt(model, damage, velocity) belongs to the server script.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Map = require(script.Parent.Map)

local Factory = {}

local ORIGIN = Vector3.new(600, 0, 0) -- the arena rim ends at 256, this spans 476..724
local W = 120 -- half width inside the walls
local H = 80 -- roof
local L1, L2 = 20, 40 -- deck heights
local RING = 16 -- catwalk width
local IN = W - RING -- inner edge of the catwalks
local FLOOR_TILE = 2 -- ponytail: 2x the arena tile, a 240-wide floor of arena tiles is 32k parts
local DECK_TILE = 2

local CONCRETE = { Color3.fromRGB(110, 110, 115), Color3.fromRGB(98, 98, 104) }
local STEEL = Color3.fromRGB(70, 74, 82)
local DARK = Color3.fromRGB(38, 40, 46)
local YELLOW = Color3.fromRGB(235, 185, 30)
local RED = Color3.fromRGB(210, 40, 35)
local BLUE = Color3.fromRGB(40, 90, 160)
local GREEN = Color3.fromRGB(60, 120, 70)
local RUST = Color3.fromRGB(140, 70, 40)
local LAVA = Color3.fromRGB(255, 110, 20)
local CHROME = Color3.fromRGB(190, 190, 195)
local CRATE = Color3.fromRGB(150, 110, 70)

local SPAWN = Vector3.new(-20, 0, -96)
Factory.SPAWN = CFrame.lookAt(ORIGIN + SPAWN + Vector3.new(0, 4, 0), ORIGIN + Vector3.new(-20, 4, 0))
Factory.DUMMY_SPOTS = {}
for _, p in {
	{ -60, 4, -20 }, { 20, 4, -30 }, { -20, 4, 30 }, { 80, 4, 20 }, { -66, 4, 65 }, { 30, 4, 70 },
	{ -80, 4, -90 }, { 90, 4, -60 }, { 0, 24, 112 }, { -60, 24, -112 }, { 112, 24, 0 }, { 0, 44, 0 },
} do
	table.insert(Factory.DUMMY_SPOTS, ORIGIN + Vector3.new(p[1], p[2], p[3]))
end

local folder = Instance.new("Folder")
folder.Name = "Factory"
local movers = {} -- function(t) called every frame
local hazards = {} -- { part, damage, cooldown, armed(t)?, push(position, t) -> Vector3, hits }

local function block(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = CFrame.new(ORIGIN) * cf
	p.Color = color
	-- everything is studded plastic bricks, no neon (lamps light the place through PointLights)
	p.Material = Enum.Material.Plastic
	p.Shape = shape or Enum.PartType.Block
	Map.studs(p)
	p.Parent = folder
	return p
end

local function at(x, y, z)
	return CFrame.new(x, y, z)
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's X axis vertical

local function lamp(x, y, z, color: Color3?, range: number?)
	local p = block(Vector3.new(4, 0.6, 4), at(x, y, z), color or Color3.fromRGB(255, 240, 210), Enum.Material.Neon)
	p.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = range or 60
	light.Brightness = 1.2
	light.Color = p.Color
	light.Parent = p
	return p
end

-- walkable slab from `bottom` to `top`, both points on its upper surface
local function ramp(bottom: Vector3, top: Vector3, width: number)
	block(Vector3.new(width, 2, (top - bottom).Magnitude + 1), CFrame.lookAt((bottom + top) / 2, top) * CFrame.new(0, -1, 0), YELLOW, Enum.Material.DiamondPlate)
end

local function hazard(part: BasePart, damage: number, cooldown: number, push, armed)
	table.insert(hazards, { part = part, damage = damage, cooldown = cooldown, push = push, armed = armed, hits = setmetatable({}, { __mode = "k" }) })
end

local function flat(v: Vector3): Vector3
	v *= Vector3.new(1, 0, 1)
	return v.Magnitude > 0.01 and v.Unit or Vector3.xAxis
end

local function structure(kind: string, x: number, y: number, z: number, turns: number?)
	Map.structure(kind, CFrame.new(ORIGIN + Vector3.new(x, y, z)) * CFrame.Angles(0, (turns or 0) * math.pi / 2, 0))
end

-- Machine layout (also paints the floor under them) ----------------------------------
local PRESSES = { { -90, 50 }, { -66, 50 }, { -42, 50 }, { -90, 80 }, { -66, 80 }, { -42, 80 } }
local SWEEPERS = { { 50, 0, 40, 22, 1.3 }, { -60, 0, -60, 22, -1.1 }, { 0, L2, 0, 11, 2 } } -- x, y, z, radius, speed
local GROUND_SAWS = { 12, -12 } -- z of each floor slot

-- Breakable floors -----------------------------------------------------------------------
local function floorColor(x: number, z: number): Color3
	for _, p in PRESSES do
		if math.abs(x - p[1]) < 7 and math.abs(z - p[2]) < 7 then
			return (x + z) // 2 % 2 == 0 and YELLOW or DARK
		end
	end
	for _, s in SWEEPERS do
		if s[2] == 0 and Vector2.new(x - s[1], z - s[3]).Magnitude < s[4] + 1 then
			return Color3.fromRGB(80, 70, 30)
		end
	end
	for _, sz in GROUND_SAWS do
		if math.abs(z - sz) < 1.5 and math.abs(x) < 46 then
			return YELLOW
		end
	end
	if Vector2.new(x - SPAWN.X, z - SPAWN.Z).Magnitude < 6 then
		return BLUE
	end
	if math.abs(x) < 1.5 or math.abs(z) < 1.5 then -- painted walkway lines
		return Color3.fromRGB(200, 200, 200)
	end
	return CONCRETE[(x // 8 + z // 8) % 2 + 1]
end

local function onL1(x, z)
	return math.abs(x) > IN or math.abs(z) > IN
end

local function onL2(x, z)
	return math.abs(z) > IN -- north and south decks
		or (math.abs(math.abs(x) - 40) < 5) -- the two long bridges
		or (math.abs(z) < 5 and math.abs(x) < 40) -- cross bridge
		or (math.abs(x) < 12 and math.abs(z) < 12) -- centre platform
end

local function deck(y: number, inside: (number, number) -> boolean)
	local s = DECK_TILE
	for x = -W + s / 2, W - s / 2, s do
		for z = -W + s / 2, W - s / 2, s do
			if not inside(x, z) then
				continue
			end
			local edge = not (inside(x + s, z) and inside(x - s, z) and inside(x, z + s) and inside(x, z - s))
			Map.tile(Vector3.new(s, 1, s), ORIGIN + Vector3.new(x, y - 0.5, z), edge and YELLOW or STEEL, Enum.Material.Plastic)
		end
		if x % 40 < s then
			task.wait() -- keep the server responsive while ~20k tiles go in
		end
	end
end

local function floors()
	block(Vector3.new(W * 2 + 8, 2, W * 2 + 8), at(0, -5, 0), Color3.fromRGB(41, 38, 43), Enum.Material.Slate) -- crater bottom
	local s = FLOOR_TILE
	for x = -W + s / 2, W - s / 2, s do
		for z = -W + s / 2, W - s / 2, s do
			Map.tile(Vector3.new(s, 4, s), ORIGIN + Vector3.new(x, -2, z), floorColor(x, z), Enum.Material.Plastic)
		end
		if x % 40 < s then
			task.wait()
		end
	end
	deck(L1, onL1)
	deck(L2, onL2)
end

-- Shell: walls, roof, ramps, lights, wall-mounted clutter (none of it breaks) --------------
local function shell()
	block(Vector3.new(W * 2 + 8, 2, W * 2 + 8), at(0, H + 1, 0), DARK, Enum.Material.CorrodedMetal)
	for _, s in { -1, 1 } do
		block(Vector3.new(W * 2 + 8, H, 4), at(0, H / 2, s * (W + 2)), STEEL, Enum.Material.CorrodedMetal)
		block(Vector3.new(4, H, W * 2), at(s * (W + 2), H / 2, 0), STEEL, Enum.Material.CorrodedMetal)
		block(Vector3.new(W * 2, 1.5, 0.4), at(0, 0.75, s * (W - 0.2)), YELLOW, Enum.Material.SmoothPlastic)
		block(Vector3.new(0.4, 1.5, W * 2), at(s * (W - 0.2), 0.75, 0), YELLOW, Enum.Material.SmoothPlastic)
		-- roof trusses and skylight strips
		for i = -3, 3 do
			block(Vector3.new(W * 2, 3, 1.5), at(0, H - 1.5, i * 30 + s * 15 / 2), DARK)
		end
		block(Vector3.new(W * 2, 0.4, 3), at(0, H - 0.2, s * 60), Color3.fromRGB(200, 230, 255), Enum.Material.Neon)
	end
	ramp(Vector3.new(-64, 0, 0), Vector3.new(-IN, L1, 0), 12) -- ground -> L1 west
	ramp(Vector3.new(113, L1, 60), Vector3.new(113, L2, IN), 10) -- L1 east -> L2 north
	ramp(Vector3.new(-113, L1, -60), Vector3.new(-113, L2, -IN), 10) -- L1 west -> L2 south

	for _, x in { -90, -30, 30, 90 } do
		for _, z in { -90, -30, 30, 90 } do
			lamp(x, H - 3.5, z)
		end
	end
	-- ceiling lights can't reach the ground floor (PointLight range caps at 60), so hang more
	-- under the L2 bridges
	for _, z in { -90, -60, -30, 30, 60, 90 } do
		lamp(-40, L2 - 1.3, z, nil, 55)
		lamp(40, L2 - 1.3, z, nil, 55)
	end
	for _, x in { -20, 20 } do
		lamp(x, L2 - 1.3, 0, nil, 55)
	end
	for _, v in { -100, -60, -20, 20, 60, 100 } do
		for _, s in { -1, 1 } do
			lamp(v, L1 - 1.3, s * (W - RING / 2), nil, 36)
			lamp(v, L2 - 1.3, s * (W - RING / 2), nil, 36)
			if math.abs(v) < 80 then
				lamp(s * (W - RING / 2), L1 - 1.3, v, nil, 36)
			end
		end
	end

	-- pipes along the north and south walls, risers on east and west, valve wheels, vents
	for _, y in { 10, 30, 52, 66 } do
		block(Vector3.new(W * 2, 2.4, 2.4), at(0, y, W - 1.6), RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
		block(Vector3.new(W * 2, 1.6, 1.6), at(0, y + 3, -W + 1.4), STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	for _, z in { -100, -70, -40, 40, 70, 100 } do
		for _, s in { -1, 1 } do
			block(Vector3.new(H, 2, 2), at(s * (W - 1.5), H / 2, z) * UPRIGHT, z > 0 and GREEN or RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
			block(Vector3.new(0.6, 4, 4), at(s * (W - 3), 8, z), RED, Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end
	for _, x in { -75, -25, 25, 75 } do
		block(Vector3.new(10, 6, 1), at(x, 58, -W + 0.6), DARK, Enum.Material.Metal)
		block(Vector3.new(14, 4, 0.4), at(x, 74, W - 0.3), YELLOW, Enum.Material.SmoothPlastic) -- hazard boards
	end
end

-- Breakable props ---------------------------------------------------------------------
-- Factory kinds go in through kind(), which builds every brick out of studded plastic.
local KINDS = {}

local function kind(name: string, build)
	Map.KINDS[name] = function(add)
		build(function(x, y, z, color, _, size)
			add(x, y, z, color, Enum.Material.Plastic, size)
		end)
	end
end

function KINDS.Column(add)
	for y = 0, 4 do
		add(0, y, 0, DARK, Enum.Material.Metal)
	end
end

local function container(color: Color3)
	return function(add)
		for x = -2, 2 do
			for y = 0, 1 do
				for _, z in { -0.5, 0.5 } do
					add(x, y, z, (x == -2 or x == 2) and DARK or color, Enum.Material.CorrodedMetal)
				end
			end
		end
	end
end
KINDS.ContainerRed = container(RED)
KINDS.ContainerBlue = container(BLUE)
KINDS.ContainerGreen = container(GREEN)

function KINDS.Tank(add)
	for y = 0, 3 do
		for x = -1, 1 do
			for z = -1, 1 do
				if x ~= 0 or z ~= 0 then
					add(x, y, z, y == 2 and YELLOW or CHROME, Enum.Material.Metal)
				end
			end
		end
	end
	add(0, 4, 0, CHROME, Enum.Material.Metal)
	add(0, 5, 0, RED, Enum.Material.Metal, 2)
end

function KINDS.Rack(add)
	for _, x in { -2.25, 2.25 } do
		for _, z in { -0.75, 0.75 } do
			for y = 0, 3.5, 0.5 do
				add(x, y, z, BLUE, Enum.Material.Metal, 2)
			end
		end
	end
	for _, y in { 1.5, 3.5 } do
		for x = -1.75, 1.75, 0.5 do
			for z = -0.75, 0.75, 0.5 do
				add(x, y, z, YELLOW, Enum.Material.Metal, 2)
			end
		end
	end
	for _, c in { { -1, 0 }, { 1, 0 }, { 0.5, 2 }, { -1, 4 } } do
		add(c[1], c[2], 0, CRATE, Enum.Material.WoodPlanks)
	end
end

function KINDS.Generator(add)
	for x = -1, 1 do
		for _, z in { -0.5, 0.5 } do
			add(x, 0, z, DARK, Enum.Material.Metal)
			add(x, 1, z, x == 0 and RED or YELLOW, Enum.Material.Metal)
		end
	end
	add(1, 2, 0.25, STEEL, Enum.Material.Metal, 2)
	add(1, 2.5, 0.25, STEEL, Enum.Material.Metal, 2)
	add(-0.75, 2, 0, GREEN, Enum.Material.Metal, 2)
end

function KINDS.Forklift(add)
	for _, z in { -1, 0, 1 } do
		add(0, 0, z, YELLOW, Enum.Material.Metal)
	end
	add(0, 1, 0.5, DARK, Enum.Material.Metal) -- seat
	for _, x in { -0.25, 0.25 } do
		for y = 1, 2.5, 0.5 do
			add(x, y, -0.25, DARK, Enum.Material.Metal, 2) -- cab posts
		end
		for y = 0, 3, 0.5 do
			add(x, y, -1.75, STEEL, Enum.Material.Metal, 2) -- mast
		end
		add(x, 0, -2.25, CHROME, Enum.Material.Metal, 2) -- forks
		add(x, 0, -2.75, CHROME, Enum.Material.Metal, 2)
	end
	add(0, 3, -0.25, DARK, Enum.Material.Metal) -- roof
end

function KINDS.Barrels(add)
	for i, c in { { 0, 0 }, { 0.5, 0 }, { 0, 0.5 }, { 0.5, 0.5 }, { 1.25, 0.25 }, { -0.5, 1.25 } } do
		local color = i % 2 == 0 and RED or BLUE
		add(c[1], 0, c[2], color, Enum.Material.Metal, 2)
		add(c[1], 0.5, c[2], color, Enum.Material.Metal, 2)
	end
	add(0.25, 1, 0.25, GREEN, Enum.Material.Metal, 2)
end

function KINDS.Lockers(add)
	for x = -1.5, 1.5 do
		for y = 0, 2 do
			add(x, y, 0, x % 2 == 0.5 and BLUE or Color3.fromRGB(150, 155, 165), Enum.Material.Metal)
		end
	end
end

function KINDS.PipeRun(add)
	for x = -2.5, 2.5 do
		add(x, 0.75, 0, RUST, Enum.Material.CorrodedMetal)
	end
	for _, x in { -2.5, 2.5 } do
		add(x, 0, 0, DARK, Enum.Material.Metal, 2)
		add(x, 0.5, 0, DARK, Enum.Material.Metal, 2)
	end
	add(0, 1.75, 0, RED, Enum.Material.Metal, 2) -- valve
end

KINDS.Boxes = Map.KINDS.Crates -- the arena's crates, rebuilt in plastic
for name, build in KINDS do
	kind(name, build)
end

local function props()
	for _, v in { -100, -60, -20, 20, 60, 100 } do
		structure("Column", v, 0, IN + 2)
		structure("Column", v, 0, -IN - 2)
		structure("Column", v, L1, IN + 2)
		structure("Column", v, L1, -IN - 2)
		structure("Column", IN + 2, 0, v)
		structure("Column", -IN - 2, 0, v)
	end
	structure("ContainerRed", -90, 0, 112)
	structure("ContainerBlue", -40, 0, 112)
	structure("ContainerGreen", 30, 0, 112)
	structure("ContainerBlue", 112, 0, -40, 1)
	structure("ContainerRed", 40, 0, -112)
	structure("Tank", 108, 0, -108)
	structure("Tank", -110, 0, -110)
	structure("Tank", 108, 0, 108)
	structure("Rack", -112, 0, -40, 1)
	structure("Rack", -112, 0, 40, 1)
	structure("Rack", -112, 0, 70, 1)
	structure("Rack", 112, L1, -20, 1)
	structure("Generator", 0, 0, -112)
	structure("Generator", 80, 0, -112)
	structure("Generator", -60, L1, 112)
	structure("Lockers", 112, 0, -80, 1)
	structure("Lockers", 112, 0, 30, 1)
	structure("Forklift", -20, 0, -60)
	structure("Forklift", 92, 0, 20, 1)
	structure("Barrels", -10, 0, 95)
	structure("Barrels", 30, 0, 95)
	structure("Barrels", 95, 0, -20)
	structure("Barrels", -95, 0, -40)
	structure("Barrels", 60, L2, 112)
	structure("Boxes", -10, 0, 70)
	structure("Boxes", 95, 0, -60)
	structure("Boxes", -30, 0, -30)
	structure("Boxes", -80, L2, -112)
	structure("PipeRun", 30, 0, -100)
	structure("PipeRun", -60, 0, 20, 1)
	structure("PipeRun", -112, L1, -20, 1)
end

-- Machines (solid, they keep working while the floor breaks around them) ----------------
local function presses()
	for i, pos in PRESSES do
		local x, z = pos[1], pos[2]
		for _, s in { -1, 1 } do
			block(Vector3.new(2, 22, 2), at(x + s * 7.5, 11, z), DARK)
		end
		block(Vector3.new(18, 3, 7), at(x, 23.5, z), RED, Enum.Material.Metal)
		local head = block(Vector3.new(12, 3, 12), at(x, 14, z), STEEL, Enum.Material.DiamondPlate)
		local stripe = block(Vector3.new(12.2, 0.6, 12.2), at(x, 14, z), RED, Enum.Material.Neon)
		stripe.CanCollide = false
		local rod = block(Vector3.new(2.4, 1, 2.4), at(x, 17, z), CHROME, Enum.Material.Metal)
		local offset = i * 0.7
		local function y(t)
			local p = (t + offset) % 3
			if p < 1.6 then
				return 15 -- waiting at the top
			elseif p < 1.75 then
				return 15 - (p - 1.6) / 0.15 * 13 -- slam
			elseif p < 2.3 then
				return 2
			end
			return 2 + (p - 2.3) / 0.7 * 13 -- slow rise
		end
		table.insert(movers, function(t)
			local h = y(t)
			head.CFrame = CFrame.new(ORIGIN + Vector3.new(x, h, z))
			stripe.CFrame = head.CFrame
			rod.Size = Vector3.new(2.4, 22 - h - 1.5, 2.4)
			rod.CFrame = CFrame.new(ORIGIN + Vector3.new(x, (22 + h + 1.5) / 2, z))
		end)
		hazard(head, 60, 1, function(position)
			return flat(position - head.Position) * 45 + Vector3.yAxis * 15
		end, function(t)
			local p = (t + offset) % 3
			return p >= 1.6 and p < 2
		end)
	end
end

local function conveyor(z: number, speed: number)
	local belt = block(Vector3.new(60, 1, 8), at(30, 0.5, z), DARK, Enum.Material.Rubber)
	belt.AssemblyLinearVelocity = Vector3.xAxis * speed -- anchored part with velocity = conveyor
	for _, s in { -1, 1 } do
		block(Vector3.new(60, 1.6, 0.8), at(30, 0.8, z + s * 4.4), YELLOW, Enum.Material.Metal)
	end
	for x = 4, 56, 8 do -- rollers under the belt edge, just for looks
		block(Vector3.new(1.2, 9.6, 1.2), at(x, 0.6, z) * CFrame.Angles(0, math.pi / 2, 0), CHROME, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	-- grinder at the end: housing open on the belt side, two spinning rollers inside
	local gx = 67
	block(Vector3.new(14, 1, 9), at(gx, 0.5, z), DARK, Enum.Material.Metal)
	block(Vector3.new(14, 12, 1), at(gx, 6, z - 5), RED)
	block(Vector3.new(14, 12, 1), at(gx, 6, z + 5), RED)
	block(Vector3.new(1, 12, 11), at(gx + 7.5, 6, z), RED)
	block(Vector3.new(15, 1, 11), at(gx + 0.5, 12.5, z), DARK)
	block(Vector3.new(6, 8, 6), at(gx + 2, 17, z), RUST, Enum.Material.CorrodedMetal) -- hopper
	local warn = lamp(gx - 7, 12.6, z, RED, 20)
	warn.Size = Vector3.new(1, 1, 9)
	local rollers = {}
	for i, dx in { -3, 0, 3 } do
		local r = block(Vector3.new(8.6, 3, 3), CFrame.identity, CHROME, Enum.Material.DiamondPlate, Enum.PartType.Cylinder)
		r.CanCollide = false
		rollers[i] = { part = r, dx = dx, dir = i % 2 == 1 and 1 or -1 }
	end
	table.insert(movers, function(t)
		for _, r in rollers do
			r.part.CFrame = CFrame.new(ORIGIN + Vector3.new(gx + r.dx, 2, z)) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(t * 14 * r.dir, 0, 0)
		end
	end)
	local zone = block(Vector3.new(13, 6, 8.5), at(gx, 3.5, z), RED)
	zone.Transparency = 1
	zone.CanCollide = false
	hazard(zone, 15, 0.25, function()
		return Vector3.new(-30, 70, math.random(-15, 15)) -- spat back out over the belt
	end)
end

local function sweeper(cx: number, y: number, cz: number, radius: number, speed: number)
	block(Vector3.new(8, 3, 3), at(cx, y + 4, cz) * UPRIGHT, DARK, Enum.Material.Metal, Enum.PartType.Cylinder)
	block(Vector3.new(1, 5, 5), at(cx, y + 8.5, cz) * UPRIGHT, RED, Enum.Material.Neon, Enum.PartType.Cylinder)
	local arms = {}
	for i = 1, 2 do
		local arm = block(Vector3.new(radius * 2, 1.6, 1.6), CFrame.identity, i == 1 and YELLOW or RED, Enum.Material.Metal)
		arm.CanCollide = false -- it hits through the hazard, not by shoving
		arms[i] = arm
		hazard(arm, 25, 1, function(position)
			local out = flat(position - (ORIGIN + Vector3.new(cx, 0, cz)))
			return Vector3.new(-out.Z, 0, out.X) * 60 * math.sign(speed) + out * 15 + Vector3.yAxis * 30
		end)
	end
	table.insert(movers, function(t)
		for i, arm in arms do
			arm.CFrame = CFrame.new(ORIGIN + Vector3.new(cx, y + 2.4, cz)) * CFrame.Angles(0, t * speed + i * math.pi / 2, 0)
		end
	end)
end

local function furnace()
	local x, z = 80, 80
	local pool = block(Vector3.new(28, 0.4, 28), at(x, 0.2, z), LAVA, Enum.Material.Neon)
	for _, s in { -1, 1 } do
		block(Vector3.new(30, 1.2, 1), at(x, 0.6, z + s * 14.5), DARK, Enum.Material.Basalt)
		block(Vector3.new(1, 1.2, 30), at(x + s * 14.5, 0.6, z), DARK, Enum.Material.Basalt)
		for _, s2 in { -1, 1 } do
			block(Vector3.new(2, 14, 2), at(x + s * 14, 7, z + s2 * 14), DARK) -- hood legs
		end
	end
	block(Vector3.new(30, 5, 30), at(x, 16.5, z), RUST, Enum.Material.CorrodedMetal) -- hood
	block(Vector3.new(6, H - 19, 6), at(x, (H + 19) / 2, z) * UPRIGHT, RUST, Enum.Material.CorrodedMetal, Enum.PartType.Cylinder)
	for _, c in { { -6, -6 }, { 6, 4 }, { -2, 7 } } do
		local fire = Instance.new("Fire")
		fire.Size = 14
		fire.Heat = 10
		local spot = block(Vector3.new(1, 1, 1), at(x + c[1], 0.5, z + c[2]), LAVA, Enum.Material.Neon)
		spot.Transparency = 1
		spot.CanCollide = false
		fire.Parent = spot
	end
	local light = Instance.new("PointLight")
	light.Color = LAVA
	light.Range = 40
	light.Brightness = 4
	light.Parent = pool
	local zone = block(Vector3.new(28, 4, 28), at(x, 2.2, z), LAVA)
	zone.Transparency = 1
	zone.CanCollide = false
	hazard(zone, 20, 0.4, function()
		return Vector3.new(math.random(-20, 20), 65, math.random(-20, 20))
	end)
end

-- a ram that shoots out of a wall along `dir` (unit, flat) and shoves you off the catwalk
local function piston(base: Vector3, dir: Vector3, offset: number)
	local look = CFrame.lookAt(base, base + dir)
	block(Vector3.new(9, 8, 1), look * CFrame.new(0, 0, 0.5), RED)
	local ram = block(Vector3.new(8, 6, 2), look, CHROME, Enum.Material.DiamondPlate)
	local warn = block(Vector3.new(8.2, 0.5, 2.2), look, YELLOW, Enum.Material.Neon)
	warn.CanCollide = false
	local function out(t) -- 0 = in the wall, 1 = at the catwalk edge
		local p = (t + offset) % 2.4
		if p < 1.3 then
			return 0
		elseif p < 1.45 then
			return (p - 1.3) / 0.15
		elseif p < 1.7 then
			return 1
		end
		return 1 - (p - 1.7) / 0.7
	end
	table.insert(movers, function(t)
		ram.CFrame = CFrame.new(ORIGIN) * look * CFrame.new(0, 0, -1 - out(t) * 14)
		warn.CFrame = ram.CFrame * CFrame.new(0, 3, 0)
	end)
	hazard(ram, 10, 0.8, function()
		return dir * 90 + Vector3.yAxis * 25
	end, function(t)
		local p = (t + offset) % 2.4
		return p >= 1.3 and p < 1.55
	end)
end

-- buzzsaw running back and forth along x in a floor slot at height y
local function saw(y: number, z: number, amplitude: number, phase: number)
	local blade = block(Vector3.new(0.6, 8, 8), CFrame.identity, CHROME, Enum.Material.Foil, Enum.PartType.Cylinder)
	blade.CanCollide = false
	local hub = block(Vector3.new(0.8, 2.4, 2.4), CFrame.identity, RED, Enum.Material.Neon, Enum.PartType.Cylinder)
	hub.CanCollide = false
	table.insert(movers, function(t)
		local x = math.sin(t * 0.8 + phase) * amplitude
		local cf = CFrame.new(ORIGIN + Vector3.new(x, y + 2, z)) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(t * 20, 0, 0)
		blade.CFrame = cf
		hub.CFrame = cf
	end)
	hazard(blade, 35, 0.5, function(_, t)
		return Vector3.xAxis * (math.cos(t * 0.8 + phase) >= 0 and 70 or -70) + Vector3.new(0, 35, 20)
	end)
end

-- pendulum hammer swinging across an L2 bridge
local function hammer(x: number, z: number, phase: number)
	local length = H - 2 - (L2 + 3)
	block(Vector3.new(12, 2, 2), at(x, H - 1, z), DARK)
	local arm = block(Vector3.new(0.8, length, 0.8), CFrame.identity, DARK, Enum.Material.Metal)
	arm.CanCollide = false
	local head = block(Vector3.new(4, 6, 9), CFrame.identity, RED, Enum.Material.Metal)
	head.CanCollide = false
	local band = block(Vector3.new(4.2, 1, 9.2), CFrame.identity, YELLOW, Enum.Material.Neon)
	band.CanCollide = false
	local pivot = CFrame.new(ORIGIN + Vector3.new(x, H - 2, z))
	table.insert(movers, function(t)
		local swing = pivot * CFrame.Angles(0, 0, math.sin(t * 1.4 + phase) * 1)
		arm.CFrame = swing * CFrame.new(0, -length / 2, 0)
		head.CFrame = swing * CFrame.new(0, -length, 0)
		band.CFrame = head.CFrame
	end)
	hazard(head, 30, 0.8, function(_, t)
		return Vector3.xAxis * (math.cos(t * 1.4 + phase) >= 0 and 90 or -90) + Vector3.yAxis * 30
	end)
end

-- overhead gantry crane rolling along x, its hook sweeping across the L2 decks
local function crane()
	for _, s in { -1, 1 } do
		block(Vector3.new(W * 2, 2, 2), at(0, H - 6, s * (W - 4)), YELLOW) -- rails on the walls
	end
	local beam = block(Vector3.new(4, 3, W * 2 - 6), CFrame.identity, YELLOW, Enum.Material.Metal)
	local trolley = block(Vector3.new(6, 3, 6), CFrame.identity, DARK, Enum.Material.Metal)
	local cable = block(Vector3.new(0.4, 1, 0.4), CFrame.identity, DARK, Enum.Material.Metal)
	cable.CanCollide = false
	local hook = block(Vector3.new(4, 4, 4), CFrame.identity, RED, Enum.Material.DiamondPlate)
	hook.CanCollide = false
	local top, low = H - 7.5, L2 + 4
	table.insert(movers, function(t)
		local x = math.sin(t * 0.25) * 100
		local z = math.sin(t * 0.6) * 90
		local y = low + (math.sin(t * 0.9) * 0.5 + 0.5) * 14 -- dips down to deck height and back
		beam.CFrame = CFrame.new(ORIGIN + Vector3.new(x, H - 6, 0))
		trolley.CFrame = CFrame.new(ORIGIN + Vector3.new(x, top - 1, z))
		cable.Size = Vector3.new(0.4, top - y, 0.4)
		cable.CFrame = CFrame.new(ORIGIN + Vector3.new(x, (top + y) / 2, z))
		hook.CFrame = CFrame.new(ORIGIN + Vector3.new(x, y, z)) * CFrame.Angles(0, t, 0)
	end)
	hazard(hook, 30, 1, function(position)
		return flat(position - hook.Position) * 70 + Vector3.yAxis * 35
	end)
end

function Factory.build(hurt: (Model, number, Vector3) -> ())
	shell()
	floors()
	props()
	presses()
	conveyor(-40, 14)
	conveyor(-80, 20)
	for _, s in SWEEPERS do
		sweeper(s[1], s[2], s[3], s[4], s[5])
	end
	furnace()
	for i, x in { -80, -40, 0, 40, 80 } do
		piston(Vector3.new(x, L1 + 3, W), -Vector3.zAxis, i * 0.45) -- north catwalk
	end
	for i, z in { 20, 50, 80 } do
		piston(Vector3.new(-W, L1 + 3, z), Vector3.xAxis, i * 0.6) -- west catwalk
	end
	for i, z in GROUND_SAWS do
		saw(0, z, 40, i * math.pi)
	end
	saw(L1, -W + RING / 2, 90, 0)
	saw(L1, -W + RING / 2, 90, math.pi)
	for i, pos in { { -40, -50 }, { -40, 50 }, { 40, -50 }, { 40, 50 } } do
		hammer(pos[1], pos[2], i * 1.3)
	end
	crane()
	folder.Parent = workspace

	-- only characters and dummies can be hurt, so only they are queried
	local include = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, move in movers do
			move(t)
		end
		table.clear(include)
		table.insert(include, workspace:FindFirstChild("Dummies"))
		for _, player in Players:GetPlayers() do
			table.insert(include, player.Character)
		end
		params.FilterDescendantsInstances = include
		for _, h in hazards do
			if h.armed and not h.armed(t) then
				continue
			end
			for _, part in workspace:GetPartsInPart(h.part, params) do
				local model = part:FindFirstAncestorWhichIsA("Model")
				local humanoid = model and model:FindFirstChildOfClass("Humanoid")
				if humanoid and (h.hits[model] or 0) < t then
					h.hits[model] = t + h.cooldown
					hurt(model, h.damage, h.push(part.Position, t))
				end
			end
		end
	end)
end

return Factory
