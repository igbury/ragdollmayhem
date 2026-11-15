-- WORK IN PROGRESS: City Square is still being built. It is hidden from the game (CITY_ENABLED =
-- false in init.server.luau, and left out of MAPS in client/Menu.luau) until it is finished.
--
-- City Square: a Times Square-style district far west of the arena. An avenue runs north to a
-- tower clad in screens and two cross streets cut it into three blocks. The north block's avenue
-- is half pedestrian plaza with red glowing steps; the middle block's east side is a park round a
-- fountain; the rest is canyons of buildings covered in billboards, with water tanks, vents and
-- roof signs on top. Sidewalks carry lamps, signals, trees, bus stops, hydrants and bins; the
-- road has taxis, cars, buses and roadworks. All of it breaks: the floor is Map tiles (one CUBE
-- deep on an unbreakable bedrock), everything standing is Map structures. Buildings are hollow
-- shells of whole 4-stud cubes and the billboards are neon cubes in their walls, so a blast
-- punches pixels out of an ad and cutting a ring through a tower drops everything above it.
local Map = require(script.Parent.Map)
local KINDS = Map.KINDS

local City = {}

local ORIGIN = Vector3.new(-600, 0, 0) -- the arena rim ends at -256 (the factory is at +600)
local CUBE = 4 -- Map's layout unit: floor depth and building brick
local TILE = 2 -- ponytail: same as the factory floor; the arena's CUBE / 3 would be 2.25x the parts
local X, Z = 80, 176 -- floor half extents
local AVE, WALK = 22, 32 -- avenue half width, sidewalk outer edge
local STREETS = { -62, 62 } -- z of the cross streets
local ROAD, CROSS = 10, 14 -- cross street: half width of its road, and of road + sidewalks
local TOWER = 12 -- half width of the tower at the north end of the avenue
local PARK_X, PARK = (WALK + X) / 2, STREETS[2] - CROSS -- park centre x, and its half length along z

City.SPAWN = CFrame.lookAt(ORIGIN + Vector3.new(0, 5, 150), ORIGIN + Vector3.new(0, 5, 0))
City.DUMMY_SPOTS = {}
for _, p in { { -10, 0 }, { 12, -40 }, { 8, -114 }, { -14, 40 }, { 20, 44 }, { -20, -28 }, { -16, -130 }, { 44, -66 }, { -40, 66 }, { 8, 124 }, { 50, 24 }, { 60, -24 } } do
	table.insert(City.DUMMY_SPOTS, ORIGIN + Vector3.new(p[1], 4, p[2]))
end

local ASPHALT = Color3.fromRGB(58, 58, 64)
local PAINT = Color3.fromRGB(232, 232, 226)
local YELLOW_LINE = Color3.fromRGB(240, 190, 40)
local SIDEWALK = Color3.fromRGB(156, 154, 156)
local SLAB = Color3.fromRGB(146, 144, 147) -- every other sidewalk slab
local CURB = Color3.fromRGB(112, 110, 114)
local MANHOLE = Color3.fromRGB(40, 40, 44)
local PLAZA = { Color3.fromRGB(96, 104, 128), Color3.fromRGB(84, 92, 116) }
local STONE = { Color3.fromRGB(176, 170, 160), Color3.fromRGB(150, 144, 136) }
local PATH = Color3.fromRGB(160, 150, 136)
local GRASS = { Color3.fromRGB(46, 140, 72), Color3.fromRGB(40, 126, 64) }
local POLE = Color3.fromRGB(46, 52, 50)
local LAMP = Color3.fromRGB(255, 226, 160)
local TAXI = Color3.fromRGB(250, 196, 30)
local TIRE = Color3.fromRGB(28, 28, 30)
local TINT = Color3.fromRGB(30, 38, 52)
local STEP_RED = Color3.fromRGB(220, 36, 48)
local LIT = Color3.fromRGB(255, 214, 150)
local WOOD = Color3.fromRGB(128, 82, 52)
local LEAF = Color3.fromRGB(30, 125, 55)
local DOOR = Color3.fromRGB(60, 40, 30)
local RED = Color3.fromRGB(200, 40, 40)
local BLUE = Color3.fromRGB(40, 80, 190)
local GREEN = Color3.fromRGB(30, 90, 60)
local ORANGE = Color3.fromRGB(255, 120, 20)
local VENT = Color3.fromRGB(150, 152, 158)
local NEON = {
	Color3.fromRGB(255, 40, 60), Color3.fromRGB(40, 120, 255), Color3.fromRGB(255, 50, 200), Color3.fromRGB(40, 230, 240),
	Color3.fromRGB(255, 220, 40), Color3.fromRGB(255, 130, 20), Color3.fromRGB(60, 230, 90), Color3.fromRGB(245, 245, 255),
	Color3.fromRGB(150, 60, 255),
}
local WALLS = {
	{ Color3.fromRGB(150, 84, 66), Enum.Material.Brick },
	{ Color3.fromRGB(196, 186, 168), Enum.Material.Concrete },
	{ Color3.fromRGB(70, 96, 128), Enum.Material.Glass },
	{ Color3.fromRGB(40, 42, 50), Enum.Material.Metal },
	{ Color3.fromRGB(120, 70, 60), Enum.Material.Brick },
	{ Color3.fromRGB(214, 190, 150), Enum.Material.Sandstone },
	{ Color3.fromRGB(226, 224, 218), Enum.Material.Marble },
}

local function streetDist(z: number): number
	return math.min(math.abs(z - STREETS[1]), math.abs(z - STREETS[2]))
end

-- What the floor tile centred at local (x, z) is, or nil where a building stands on the bedrock.
local function floorLook(x: number, z: number): (Color3?, Enum.Material?)
	local ax, dz = math.abs(x), streetDist(z)
	local park = x >= WALK and math.abs(z) < PARK
	if ax >= WALK and dz >= CROSS and not park or ax < TOWER and z < -Z + 2 * TOWER then
		return nil
	end
	if park then -- rings of stone round the fountain, paths out of it, grass
		local px = x - PARK_X
		local r = math.sqrt(px * px + z * z)
		if r < 14 then
			return STONE[(r // 4) % 2 + 1], Enum.Material.Cobblestone
		end
		if math.abs(px) < 4 or math.abs(z) < 4 then
			return PATH, Enum.Material.Cobblestone
		end
		return GRASS[(x // 8 + z // 8) % 2 + 1], Enum.Material.Grass
	end
	local slab = (x // 4 + z // 4) % 2 == 0 and SIDEWALK or SLAB
	if dz < CROSS then -- a cross street
		if ax >= WALK then
			if dz >= ROAD then
				return dz < ROAD + 2 and CURB or slab, Enum.Material.Pavement
			end
			return (dz < 2 and x // 8 % 2 == 0) and YELLOW_LINE or ASPHALT, Enum.Material.Asphalt
		end
		if ax >= AVE then -- the avenue's sidewalk carries on across it as a zebra
			if dz >= ROAD then
				return slab, Enum.Material.Pavement
			end
			return ((z + Z) // 2 % 2 == 0) and PAINT or ASPHALT, Enum.Material.Asphalt
		end
		return ASPHALT, Enum.Material.Asphalt
	end
	if ax >= AVE then
		return ax < AVE + 2 and CURB or slab, Enum.Material.Pavement
	end
	if dz < CROSS + 6 then -- zebra across the avenue
		return ((x + X) // 2 % 2 == 0) and PAINT or ASPHALT, Enum.Material.Asphalt
	end
	if z < STREETS[1] and x >= 2 then -- the pedestrian plaza, east half of the north block
		return PLAZA[(x // 4 + z // 4) % 2 + 1], Enum.Material.Concrete
	end
	if dz >= CROSS + 8 and dz < CROSS + 10 then -- stop line
		return PAINT, Enum.Material.Asphalt
	end
	if z > STREETS[1] and ax < 2 then
		return YELLOW_LINE, Enum.Material.Asphalt
	end
	if (x == -7 or x == -5) and (z + 21) % 48 < 4 then
		return MANHOLE, Enum.Material.DiamondPlate
	end
	if ax >= 10 and ax < 12 and z // 6 % 2 == 0 then -- lane dashes
		return PAINT, Enum.Material.Asphalt
	end
	return ASPHALT, Enum.Material.Asphalt
end

-- Billboard art, one colour per cube of a w x h screen (u across, v up) from three colours c.
local ADS = {
	function(u, v, w, h, c) return v < h / 2 and c[1] or c[2] end, -- two-tone
	function(u, v, w, h, c) return c[v % 3 + 1] end, -- bands
	function(u, v, w, h, c) -- logo on a background
		local d = Vector2.new(u - (w - 1) / 2, v - (h - 1) / 2).Magnitude
		return d < math.min(w, h) * 0.3 and c[2] or d < math.min(w, h) * 0.42 and c[3] or c[1]
	end,
	function(u, v, w, h, c) return (u + v) % 4 < 2 and c[1] or c[3] end, -- diagonal stripes
	function(u, v, w, h, c) return (u * 7 + v * 13) % 5 == 0 and c[3] or c[1] end, -- sparkle
	function(u, v, w, h, c) return u < w / 3 and c[2] or v == h // 2 and c[3] or c[1] end, -- panel + headline
}

local function screen(rng: Random, face, u0: number, u1: number, v0: number, v1: number)
	local c = {}
	while #c < 3 do
		local pick = NEON[rng:NextInteger(1, #NEON)]
		if not table.find(c, pick) then
			table.insert(c, pick)
		end
	end
	return { face = face, u0 = u0, u1 = u1, v0 = v0, v1 = v1, ad = ADS[rng:NextInteger(1, #ADS)], c = c }
end

-- A face of a building: the cube at grid (i, k) is on it when this returns its u (else nil).
local function faceX(col: number)
	return function(i, k)
		return i == col and k or nil
	end
end
local function faceZ(row: number)
	return function(i, k)
		return k == row and i or nil
	end
end

-- Street props, in studs: s(x, bottom, z, ...) places a whole cube of `size` (default 1).
local function studs(add)
	return function(x, y, z, color, material, size)
		add(x / CUBE, y / CUBE, z / CUBE, color, material, size or 1, true)
	end
end

-- Registers a building kind: a hollow nx * nz * ny shell of whole CUBEs with a roof and a parapet,
-- layer 0 sunk into the floor (its origin is the bottom of the floor). `shop` faces get a lit
-- storefront with doors at street level and an awning over it; screens are drawn over everything
-- else. `style` picks the windows, `sign` is a billboard standing on the parapet, and `seed`
-- scatters a water tank, vents and (on tall ones) an antenna over the roof.
local function building(name: string, nx: number, nz: number, ny: number, wall, style: number, seed: number, shop: { any }, screens: { any }, sign: any?)
	local roof = wall[1]:Lerp(Color3.new(0, 0, 0), 0.35)
	local trim = wall[1]:Lerp(Color3.new(1, 1, 1), 0.35)
	local awning = NEON[seed % #NEON + 1]
	KINDS[name] = function(add)
		for y = 0, ny do
			for i = 0, nx - 1 do
				for k = 0, nz - 1 do
					local edge = i == 0 or i == nx - 1 or k == 0 or k == nz - 1
					if not edge and y ~= ny - 1 then
						continue
					end
					local color, material = wall[1], wall[2]
					if y == ny then -- parapet
						color, material = trim, Enum.Material.Concrete
					elseif y == ny - 1 then
						color, material = edge and trim or roof, Enum.Material.Concrete
					else
						local drawn = false
						for _, s in screens do
							local u = s.face(i, k)
							if u and u >= s.u0 and u <= s.u1 and y >= s.v0 and y <= s.v1 then
								color, material = s.ad(u - s.u0, y - s.v0, s.u1 - s.u0 + 1, s.v1 - s.v0 + 1, s.c):Lerp(Color3.new(), 0.3), Enum.Material.Neon -- dimmed: full-bright neon blooms into a white blur
								drawn = true
								break
							end
						end
						local onShop = false
						for _, f in shop do
							onShop = onShop or f(i, k) ~= nil
						end
						local u = (i == 0 or i == nx - 1) and k or i
						local window = y >= 3 and y % 2 == 1 and u % 2 == 1
						if style == 1 then -- ribbons of glass
							window = y >= 3 and y % 2 == 1
						elseif style == 2 then -- tall windows between piers
							window = y >= 3 and y % 4 ~= 0 and u % 3 ~= 0
						end
						if drawn then
							-- screen pixel
						elseif onShop and y == 1 then
							color, material = LIT, Enum.Material.Glass
							if u % 4 == 1 then
								color, material = DOOR, Enum.Material.Wood
							end
						elseif onShop and y == 2 then
							color, material = awning, Enum.Material.SmoothPlastic -- neon here floods the whole street with bloom
						elseif window then
							local lit = (u * 5 + y * 3 + seed) % 7 < 2
							color, material = lit and LIT or TINT, lit and Enum.Material.SmoothPlastic or Enum.Material.Glass
						end
					end
					add(i + 0.5, y, k + 0.5, color, material, CUBE, true)
				end
			end
		end
		if sign then
			for k = 1, nz - 2 do
				for v = 1, sign.h do
					add(sign.col + 0.5, ny + v, k + 0.5, sign.ad(k - 1, v - 1, nz - 2, sign.h, sign.c):Lerp(Color3.new(), 0.3), Enum.Material.Neon, CUBE, true)
				end
			end
		end
		-- roof clutter, inside the parapet; the same every time the building is rebuilt
		local s, r, top = studs(add), Random.new(seed), ny * CUBE
		local tx, tz = r:NextInteger(2, math.max(2, nx // 2 - 1)) * CUBE, r:NextInteger(2, nz - 2) * CUBE
		s(tx, top, tz, POLE, Enum.Material.Metal, 2) -- water tank on its stand
		s(tx, top + 2, tz, WOOD, Enum.Material.WoodPlanks, 4)
		s(tx, top + 6, tz, POLE, Enum.Material.Metal, 2)
		for _ = 1, r:NextInteger(1, 3) do
			s(r:NextInteger(nx // 2 + 1, nx - 2) * CUBE, top, r:NextInteger(2, nz - 2) * CUBE, VENT, Enum.Material.Metal, 2)
		end
		if ny > 24 then
			for h = 0, 4 do
				s(nx // 2 * CUBE, top + h * 2, nz // 2 * CUBE, POLE, Enum.Material.Metal, 2)
			end
			s(nx // 2 * CUBE, top + 10, nz // 2 * CUBE, RED, Enum.Material.Neon)
		end
	end
end

function KINDS.CityLamp(add) -- arm toward +x
	local s = studs(add)
	for y = 0, 13 do
		s(0, y, 0, POLE, Enum.Material.Metal)
	end
	for x = 1, 3 do
		s(x, 13, 0, POLE, Enum.Material.Metal)
	end
	s(3, 12, 0, LAMP, Enum.Material.Neon)
end

function KINDS.CitySignal(add) -- arm toward +x, lights facing +z
	local s = studs(add)
	for y = 0, 15 do
		s(0, y, 0, POLE, Enum.Material.Metal)
	end
	for x = 1, 7 do
		s(x, 15, 0, POLE, Enum.Material.Metal)
	end
	for y, color in { [12] = Color3.fromRGB(60, 230, 90), [13] = Color3.fromRGB(255, 200, 40), [14] = Color3.fromRGB(255, 40, 40) } do
		s(7, y, 0, color, Enum.Material.Neon)
	end
end

-- A car: 4 wide, 10 long along z. `top` lists roof lights as { x, colour }.
local function car(name: string, color: Color3, top: { any }?)
	KINDS[name] = function(add)
		local s = studs(add)
		for _, x in { -1, 1 } do
			for _, z in { -4, -2, 0, 2, 4 } do
				s(x, 0, z, TIRE, math.abs(z) == 4 and Enum.Material.Rubber or Enum.Material.Metal, 2) -- wheels, chassis between
				s(x, 2, z, color, Enum.Material.SmoothPlastic, 2)
				if math.abs(z) < 4 then
					s(x, 4, z, TINT, Enum.Material.Glass, 2) -- cabin
				end
			end
		end
		for _, light in top or {} do
			s(light[1], 6, 0, light[2], Enum.Material.Neon)
		end
	end
end
car("Taxi", TAXI, { { 0, PAINT } })
car("CarRed", RED)
car("CarBlue", BLUE)
car("CarWhite", PAINT)
car("Police", Color3.fromRGB(30, 34, 48), { { -1, BLUE }, { 1, RED } })

function KINDS.Bus(add) -- 6 wide, 22 long along z
	local s = studs(add)
	for _, x in { -2, 0, 2 } do
		for z = -10, 10, 2 do
			local wheel = x ~= 0 and math.abs(z) == 6
			s(x, 0, z, TIRE, wheel and Enum.Material.Rubber or Enum.Material.Metal, 2)
			s(x, 6, z, PAINT, Enum.Material.SmoothPlastic, 2)
			if x ~= 0 or math.abs(z) == 10 then -- hollow inside
				s(x, 2, z, BLUE, Enum.Material.SmoothPlastic, 2)
				s(x, 4, z, TINT, Enum.Material.Glass, 2)
			end
		end
	end
end

function KINDS.CityTree(add)
	local s = studs(add)
	for y = 0, 4, 2 do
		s(0, y, 0, WOOD, Enum.Material.Wood, 2)
	end
	for y = 6, 8, 2 do
		for x = -2, 2, 2 do
			for z = -2, 2, 2 do
				s(x, y, z, LEAF, Enum.Material.Grass, 2)
			end
		end
	end
	s(0, 10, 0, LEAF, Enum.Material.Grass, 2)
end

function KINDS.Hydrant(add)
	local s = studs(add)
	for y = 0, 2 do
		s(0, y, 0, RED, Enum.Material.Metal)
	end
end

function KINDS.TrashCan(add)
	local s = studs(add)
	s(0, 0, 0, GREEN, Enum.Material.Metal, 2)
	s(0, 2, 0, POLE, Enum.Material.Metal)
end

function KINDS.Mailbox(add)
	local s = studs(add)
	s(0, 0, 0, BLUE, Enum.Material.Metal, 2)
	s(0, 2, 0, BLUE, Enum.Material.Metal, 2)
end

function KINDS.Cone(add)
	local s = studs(add)
	s(0, 0, 0, ORANGE, Enum.Material.SmoothPlastic)
	s(0, 1, 0, PAINT, Enum.Material.SmoothPlastic)
	s(0, 2, 0, ORANGE, Enum.Material.SmoothPlastic)
end

function KINDS.Barrier(add) -- a striped board on two feet, along x
	local s = studs(add)
	for x = -4, 4, 2 do
		if math.abs(x) == 4 then
			s(x, 0, 0, POLE, Enum.Material.Metal, 2)
		end
		s(x, 2, 0, x % 4 == 0 and ORANGE or PAINT, Enum.Material.SmoothPlastic, 2)
	end
end

function KINDS.BusStop(add) -- along z, glass back at -x, open toward +x
	local s = studs(add)
	for z = -4, 4, 2 do
		if math.abs(z) == 4 then
			s(-2, 0, z, POLE, Enum.Material.Metal, 2)
		else
			s(0, 0, z, WOOD, Enum.Material.WoodPlanks, 2) -- the seat
		end
		s(-2, 2, z, TINT, Enum.Material.Glass, 2)
		s(-2, 4, z, TINT, Enum.Material.Glass, 2)
		s(-2, 6, z, POLE, Enum.Material.Metal, 2)
		s(0, 6, z, POLE, Enum.Material.Metal, 2)
	end
	s(-2, 8, 0, BLUE, Enum.Material.Neon, 2)
end

function KINDS.HotDogCart(add)
	local s = studs(add)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			s(x, 0, z, (x + z) == 0 and PAINT or RED, Enum.Material.SmoothPlastic, 2)
		end
	end
	for y = 2, 5 do
		s(-1, y, -1, POLE, Enum.Material.Metal)
	end
	for x = -3, 1, 2 do -- umbrella
		for z = -3, 1, 2 do
			s(x, 6, z, (x + z) % 4 == 0 and RED or PAINT, Enum.Material.SmoothPlastic, 2)
		end
	end
end

function KINDS.Bollard(add)
	local s = studs(add)
	s(0, 0, 0, CURB, Enum.Material.Metal, 2)
	s(0, 2, 0, CURB, Enum.Material.Metal)
end

-- the red steps: rows of 2-stud cubes rising toward -z, lit from inside, glass on top
function KINDS.RedSteps(add)
	local s = studs(add)
	for step = 0, 6 do
		for x = -5, 5, 2 do
			for h = 0, step do
				s(x, h * 2, -step * 2, STEP_RED, h == step and Enum.Material.Glass or Enum.Material.Neon, 2)
			end
		end
	end
end

-- Unbreakable bedrock under the floor and a pavement rim round it, so the edge is not a cliff.
local function solid(size: Vector3, position: Vector3, color: Color3, material: Enum.Material, parent: Instance)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.Position = ORIGIN + position
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function City.build()
	local base = Instance.new("Model")
	base.Name = "CityBase"
	local RIM = 40
	solid(Vector3.new(2 * (X + RIM), 20, 2 * (Z + RIM)), Vector3.new(0, -CUBE - 10, 0), Color3.fromRGB(41, 38, 43), Enum.Material.Slate, base)
	for _, side in { -1, 1 } do
		solid(Vector3.new(2 * (X + RIM), CUBE, RIM), Vector3.new(0, -CUBE / 2, side * (Z + RIM / 2)), SIDEWALK, Enum.Material.Pavement, base)
		solid(Vector3.new(RIM, CUBE, 2 * Z), Vector3.new(side * (X + RIM / 2), -CUBE / 2, 0), SIDEWALK, Enum.Material.Pavement, base)
	end
	base.Parent = workspace

	for ix = 0, 2 * X / TILE - 1 do
		for iz = 0, 2 * Z / TILE - 1 do
			local x, z = -X + (ix + 0.5) * TILE, -Z + (iz + 0.5) * TILE
			local color, material = floorLook(x, z)
			if color then
				Map.tile(Vector3.new(TILE, CUBE, TILE), ORIGIN + Vector3.new(x, -CUBE / 2, z), color, material).CastShadow = false
			end
		end
		if ix % 8 == 0 then
			task.wait()
		end
	end

	local function at(kind: string, x: number, z: number, turns: number?, y: number?)
		Map.structure(kind, CFrame.new(ORIGIN + Vector3.new(x, y or 0, z)) * CFrame.Angles(0, (turns or 0) * math.pi / 2, 0))
	end

	-- buildings: each side of the avenue, three to a block; the east middle block is the park
	local rng = Random.new(42) -- fixed, so a rebuilt building comes back with the same ads
	local nx = (X - WALK) // CUBE
	local BLOCKS = { { -Z, { 9, 8, 8 } }, { STREETS[1] + CROSS, { 8, 8, 8 } }, { STREETS[2] + CROSS, { 8, 8, 9 } } }
	local count = 0
	for _, east in { false, true } do
		for block, spec in BLOCKS do
			local z0 = spec[1]
			for b, nz in spec[2] do
				if east and block == 2 then
					break
				end
				count += 1
				local name = "CityBuilding" .. count
				local corners = {} -- cube rows that face a cross street
				if b == 1 and block > 1 then
					table.insert(corners, 0)
				end
				if b == 3 and block < 3 then
					table.insert(corners, nz - 1)
				end
				local ny = rng:NextInteger(12, 24) + #corners * 8
				local col = east and 0 or nx - 1 -- the cube column facing the avenue
				local front = faceX(col)
				local screens = {}
				local v0 = rng:NextInteger(3, 5)
				local v1 = math.min(v0 + rng:NextInteger(4, 8), ny - 3)
				table.insert(screens, screen(rng, front, rng:NextInteger(0, 1), nz - 1 - rng:NextInteger(0, 1), v0, v1))
				if v1 + 6 < ny - 2 then -- a second one higher up
					local top = rng:NextInteger(v1 + 2, ny - 6)
					table.insert(screens, screen(rng, front, rng:NextInteger(1, 3), nz - 1 - rng:NextInteger(1, 3), top, top + rng:NextInteger(2, 4)))
				end
				local shop = { front }
				for _, row in corners do -- a tall screen down the cross street face too
					local side = faceZ(row)
					table.insert(screens, screen(rng, side, 1, nx - 2, 3, ny - 3))
					table.insert(shop, side)
				end
				local sign = nil
				if rng:NextNumber() < 0.5 then
					sign = screen(rng, front, 0, 0, 0, 0)
					sign.col, sign.h = col, rng:NextInteger(2, 3)
				end
				building(name, nx, nz, ny, WALLS[count % #WALLS + 1], count % 3, count, shop, screens, sign)
				at(name, east and WALK or -X, z0, 0, -CUBE)
				z0 += nz * CUBE
				task.wait()
			end
		end
	end

	-- the tower at the head of the avenue: screens stacked up its face and sides
	local tn, ty = 2 * TOWER // CUBE, 44
	local towerScreens = {}
	for v = 4, ty - 6, 7 do
		table.insert(towerScreens, screen(rng, faceZ(tn - 1), 0, tn - 1, v, v + 5))
		table.insert(towerScreens, screen(rng, faceX(0), 1, tn - 1, v, v + 4))
		table.insert(towerScreens, screen(rng, faceX(tn - 1), 1, tn - 1, v, v + 4))
	end
	building("CityTower", tn, tn, ty, WALLS[4], 1, 99, { faceZ(tn - 1) }, towerScreens)
	at("CityTower", -TOWER, -Z, 0, -CUBE)

	-- avenue sidewalks: a lamp every 32 studs, arm over the road, street furniture in between
	local CYCLE = { "CityTree", "TrashCan", false, "Hydrant", "CityTree", "Bench", false, "Mailbox", "CityTree", false, "BusStop", false, "CityTree" }
	local TURNS = { Bench = { 3, 1 }, BusStop = { 0, 2 } } -- west side, east side: backs to the buildings
	local n = 0
	for z = -168, 168, 8 do
		if streetDist(z) < CROSS + 6 then
			continue
		end
		if z % 32 == 0 then
			at("CityLamp", -AVE - 4, z)
			at("CityLamp", AVE + 4, z, 2)
			continue
		end
		for side = 1, 2 do
			n += 1
			local kind = CYCLE[n % #CYCLE + 1]
			if kind then
				at(kind, (side * 2 - 3) * (AVE + 6), z, TURNS[kind] and TURNS[kind][side])
			end
		end
	end
	-- each crossing: signals on its four corners, lamps down the cross street
	for _, s in STREETS do
		for _, z in { s - CROSS - 2, s + CROSS + 2 } do
			at("CitySignal", -AVE - 2, z)
			at("CitySignal", AVE + 2, z, 2)
		end
		for _, x in { -68, 44 } do
			at("CityLamp", x, s - ROAD - 2, 3)
			at("CityLamp", x + 24, s + ROAD + 2, 1)
		end
	end
	-- plaza: the red steps facing the square, bollards along its kerb, benches, trees, a cart
	at("RedSteps", 12, -124)
	for z = -86, -148, -6 do
		at("Bollard", 3, z)
	end
	at("Bench", 14, -92, 2)
	at("Bench", 14, -146, 2)
	at("CityTree", 18, -100)
	at("CityTree", 18, -112)
	at("HotDogCart", 9, -106)
	-- park: the fountain, benches facing it, a statue at the far end, trees in the corners
	at("Fountain", PARK_X, 0)
	at("Bench", PARK_X, -13, 2)
	at("Bench", PARK_X, 13)
	at("Bench", PARK_X - 13, 0, 3)
	at("Bench", PARK_X + 13, 0, 1)
	at("Statue", 72, 0, 3)
	at("HotDogCart", 38, 10)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			at("Tree", PARK_X + sx * 16, sz * 40)
			at("CityTree", PARK_X + sx * 12, sz * 22)
		end
	end
	-- roadworks on the avenue's south end
	at("Barrier", 12, 84)
	at("Barrier", 12, 100)
	at("Crates", 10, 91)
	at("Cone", 4, 92)
	at("Cone", 20, 92)
	-- traffic, stopped wherever
	for _, t in {
		{ "Taxi", -16, 96 }, { "CarRed", -6, 120 }, { "Taxi", 8, 30 }, { "CarBlue", 16, 112 }, { "Bus", -15, 20 },
		{ "Taxi", -6, -20 }, { "CarWhite", 16, -30 }, { "Police", 6, -36 }, { "Taxi", -16, -100 }, { "CarBlue", -6, -132 },
		{ "Taxi", 50, -57, 1 }, { "CarRed", -56, -67, 1 }, { "Bus", -58, 57, 1 }, { "Taxi", 52, 67, 1 }, { "CarWhite", -20, 64, 1 },
	} do
		at(t[1], t[2], t[3], t[4])
	end

	-- the name over the square
	local anchor = solid(Vector3.one, Vector3.new(0, 4 * ty + 14, -Z + TOWER), PAINT, Enum.Material.SmoothPlastic, base)
	anchor.Transparency = 1
	anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = false, false, false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(40, 8)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "CITY SQUARE"
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = anchor
end

return City
