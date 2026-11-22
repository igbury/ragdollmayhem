-- Uniforms built out of parts welded onto a dummy's body (no catalog clothes, no uploads).
--  * Soldier (4 stars): covered helmet with goggles, ear protectors and a night-vision mount; a plate
--    carrier with webbing, magazine pouches, radio and antenna, a grenade; a pack with a bedroll;
--    belt, holster, cargo pockets, elbow and knee pads, gloves and boots.
--  * Heavy (5 stars): full plate. Closed helmet with a visor, jaw guard and breathing filters;
--    chest, back and belly plates, a power pack, layered pauldrons, gauntlets, tassets, thigh plates,
--    knee cops, shin guards and armoured boots.
--  * Worker and Zombie (Toolbox): Blender kit only, no plain-parts version (assets/army/build.py).
-- Body colours come with the kind (main script KINDS); the armour stat too. Looks only: every piece
-- is massless and never collides. Offsets are fractions of the part they sit on, so any body fits.
local Outfits = {}

local OLIVE = Color3.fromRGB(84, 96, 58)
local OLIVE_DARK = Color3.fromRGB(60, 68, 42)
local TAN = Color3.fromRGB(156, 138, 100)
local KHAKI = Color3.fromRGB(122, 112, 82)
local STRAP = Color3.fromRGB(36, 34, 30)
local BLACK = Color3.fromRGB(22, 22, 24)
local LENS = Color3.fromRGB(70, 125, 155)
local CHARCOAL = Color3.fromRGB(40, 42, 48)
local PLATE = Color3.fromRGB(64, 68, 76)
local PLATE_LIGHT = Color3.fromRGB(92, 96, 106)
local EDGE = Color3.fromRGB(20, 21, 25)
local VISOR = Color3.fromRGB(26, 74, 92)
local GLOW = Color3.fromRGB(255, 120, 40)

-- One welded piece on `body`, at `at` in that part's space. `shape`: nil (block), "Ball" / "Cyl"
-- (a built-in SpecialMesh sphere / upright cylinder, any proportions), "Wedge" (a WedgePart).
local function piece(body: BasePart?, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, shape: string?)
	if not body then
		return nil
	end
	local p = Instance.new(shape == "Wedge" and "WedgePart" or "Part") :: BasePart
	p.Name = "Armor"
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CastShadow = false
	if shape == "Ball" or shape == "Cyl" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = shape == "Ball" and Enum.MeshType.Sphere or Enum.MeshType.Cylinder
		m.Parent = p
	end
	p.CFrame = body.CFrame * at
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1, weld.Parent = body, p, p
	p.Parent = body -- with its limb: a cut-off arm takes its guard along
	return p
end

-- A body part and a function placing pieces on it in fractions of its size: put(size, x, y, z, ...)
-- puts a piece of `size` (studs) with its centre at (x, y, z) * the part's size (from its centre).
local function on(model: Model, name: string)
	local body = model:FindFirstChild(name) :: BasePart?
	local s = body and body.Size or Vector3.one
	return function(size: Vector3, x: number, y: number, z: number, color: Color3, material: Enum.Material?, shape: string?, turn: CFrame?)
		return piece(body, size, CFrame.new(x * s.X, y * s.Y, z * s.Z) * (turn or CFrame.identity), color, material, shape)
	end, s
end

local function paint(model: Model, names: { string }, color: Color3)
	for _, name in names do
		local p = model:FindFirstChild(name) :: BasePart?
		if p then
			p.Color = color
		end
	end
end

local SIDEWAYS = CFrame.Angles(0, 0, math.rad(90)) -- an upright cylinder laid along X
local FORWARD = CFrame.Angles(math.rad(90), 0, 0) -- along Z (facing front / back)
local FABRIC = Enum.Material.Fabric
local METAL = Enum.Material.Metal

function Outfits.Soldier(model: Model)
	paint(model, { "LeftHand", "RightHand" }, BLACK) -- gloves
	paint(model, { "LeftFoot", "RightFoot" }, STRAP) -- boots

	-- helmet: covered shell, band, rails, night-vision mount, goggles on the front, ear protectors, chin strap
	local head, h = on(model, "Head")
	head(Vector3.new(h.X * 1.18, h.Y * 0.86, h.Z * 1.22), 0, 0.17, 0.02, OLIVE, FABRIC, "Ball")
	head(Vector3.new(h.X * 1.16, 0.12, h.Z * 1.2), 0, 0.1, 0.02, OLIVE_DARK, FABRIC, "Cyl")
	for _, x in { -1, 1 } do
		head(Vector3.new(0.06, 0.12, h.Z * 0.5), x * 0.585, 0.16, 0, BLACK, METAL)
		head(Vector3.new(0.36, 0.16, 0.36), x * 0.52, -0.06, 0.03, OLIVE_DARK, nil, "Cyl", SIDEWAYS) -- ear protector
		head(Vector3.new(0.05, h.Y * 0.5, 0.05), x * 0.42, -0.28, -0.08, STRAP) -- chin strap
	end
	head(Vector3.new(0.26, 0.2, 0.1), 0, 0.42, -0.58, BLACK, METAL) -- NVG mount
	head(Vector3.new(0.08, 0.16, 0.12), 0, 0.3, -0.6, BLACK, METAL)
	head(Vector3.new(h.X * 1.16, 0.1, h.Z * 1.2), 0, 0.3, 0.02, BLACK, nil, "Cyl") -- goggle strap
	head(Vector3.new(0.82, 0.22, 0.12), 0, 0.31, -0.55, BLACK)
	for _, x in { -0.19, 0.19 } do
		head(Vector3.new(0.28, 0.07, 0.24), x, 0.31, -0.6, LENS, Enum.Material.Glass, "Cyl", FORWARD)
	end

	-- plate carrier: front and back plates, cummerbund, shoulder straps, webbing rows, collar
	local chest, t = on(model, "UpperTorso")
	chest(Vector3.new(t.X * 0.76, t.Y * 0.66, 0.26), 0, -0.06, -0.55, OLIVE_DARK, FABRIC)
	chest(Vector3.new(t.X * 0.76, t.Y * 0.66, 0.26), 0, -0.06, 0.55, OLIVE_DARK, FABRIC)
	chest(Vector3.new(t.X * 1.06, t.Y * 0.3, t.Z * 1.12), 0, -0.26, 0, OLIVE_DARK, FABRIC)
	for _, x in { -0.24, 0.24 } do
		chest(Vector3.new(0.3, 0.12, t.Z * 1.14), x, 0.33, 0, OLIVE_DARK, FABRIC)
	end
	for _, y in { -0.02, -0.12, -0.22 } do
		chest(Vector3.new(t.X * 0.72, 0.04, 0.04), 0, y, -0.68, STRAP)
	end
	chest(Vector3.new(t.X * 0.6, 0.16, t.Z * 1.0), 0, 0.47, 0, OLIVE, FABRIC) -- collar
	-- three magazine pouches with flaps, an admin pouch with a patch, radio and antenna, a grenade
	for _, x in { -0.21, 0, 0.21 } do
		chest(Vector3.new(0.3, 0.4, 0.2), x, -0.3, -0.7, TAN, FABRIC)
		chest(Vector3.new(0.32, 0.09, 0.22), x, -0.2, -0.71, KHAKI, FABRIC)
	end
	chest(Vector3.new(t.X * 0.36, 0.3, 0.12), 0, 0.13, -0.64, OLIVE, FABRIC)
	chest(Vector3.new(0.36, 0.2, 0.02), 0, 0.14, -0.7, KHAKI)
	chest(Vector3.new(0.36, 0.06, 0.025), 0, 0.17, -0.705, OLIVE_DARK)
	chest(Vector3.new(0.22, 0.5, 0.2), 0.36, 0.05, -0.6, BLACK)
	chest(Vector3.new(0.04, 1.1, 0.04), 0.39, 0.42, -0.55, BLACK, nil, "Cyl")
	chest(Vector3.new(0.3, 0.3, 0.3), -0.36, -0.14, -0.66, OLIVE_DARK, METAL, "Ball")
	-- the pack: body, lid, side pockets, straps over it, a rolled mat on top
	chest(Vector3.new(t.X * 0.66, t.Y * 0.62, 0.5), 0, -0.04, 0.83, OLIVE, FABRIC)
	chest(Vector3.new(t.X * 0.68, 0.24, 0.56), 0, 0.27, 0.84, OLIVE_DARK, FABRIC)
	for _, x in { -1, 1 } do
		chest(Vector3.new(0.2, t.Y * 0.32, 0.4), x * 0.4, -0.1, 0.83, OLIVE_DARK, FABRIC)
		chest(Vector3.new(0.08, t.Y * 0.62, 0.04), x * 0.16, -0.04, 1.06, STRAP)
	end
	chest(Vector3.new(0.34, t.X * 0.74, 0.34), 0, 0.42, 0.86, TAN, FABRIC, "Cyl", SIDEWAYS)

	-- arms: unit patches, elbow pads
	for _, side in { "Left", "Right" } do
		local sign = side == "Left" and -1 or 1
		local upper = on(model, side .. "UpperArm")
		upper(Vector3.new(0.03, 0.3, 0.3), sign * 0.52, 0.15, 0, KHAKI)
		upper(Vector3.new(0.035, 0.1, 0.3), sign * 0.53, 0.15, 0, OLIVE_DARK)
		local lower, la = on(model, side .. "LowerArm")
		lower(Vector3.new(la.X * 0.9, 0.34, 0.24), 0, 0.36, 0.42, BLACK, nil, "Ball")
		lower(Vector3.new(la.X * 1.04, 0.1, la.Z * 1.04), 0, -0.42, 0, OLIVE_DARK, FABRIC, "Cyl") -- cuff
	end

	-- belt: buckle, holster with a grip in it, a dump pouch
	local hips, l = on(model, "LowerTorso")
	hips(Vector3.new(l.X * 1.06, 0.22, l.Z * 1.1), 0, 0.2, 0, BLACK)
	hips(Vector3.new(0.28, 0.2, 0.06), 0, 0.2, -0.58, TAN, METAL)
	hips(Vector3.new(0.24, 0.6, 0.34), 0.56, -0.2, 0, BLACK)
	hips(Vector3.new(0.14, 0.24, 0.2), 0.56, 0.25, -0.05, CHARCOAL, METAL)
	hips(Vector3.new(0.34, 0.4, 0.34), -0.52, -0.1, 0.3, OLIVE_DARK, FABRIC)

	-- legs: cargo pockets, knee pads with straps, boot cuffs
	for _, side in { "Left", "Right" } do
		local sign = side == "Left" and -1 or 1
		local thigh = on(model, side .. "UpperLeg")
		thigh(Vector3.new(0.12, 0.46, 0.44), sign * 0.56, -0.08, 0, OLIVE, FABRIC)
		thigh(Vector3.new(0.13, 0.08, 0.46), sign * 0.56, 0.08, 0, OLIVE_DARK, FABRIC)
		local shin, ll = on(model, side .. "LowerLeg")
		shin(Vector3.new(ll.X * 0.86, 0.42, 0.24), 0, 0.33, -0.5, BLACK, nil, "Ball")
		shin(Vector3.new(ll.X * 1.06, 0.08, ll.Z * 1.06), 0, 0.33, 0, STRAP, nil, "Cyl")
		shin(Vector3.new(ll.X * 1.1, 0.24, ll.Z * 1.08), 0, -0.4, 0, STRAP, nil, "Cyl")
	end
end

function Outfits.Heavy(model: Model)
	paint(model, { "LeftHand", "RightHand", "LeftFoot", "RightFoot" }, EDGE)

	-- helmet: shell, crest, side bolts, visor in a frame, jaw guard with two breathing filters
	local head, h = on(model, "Head")
	head(Vector3.new(h.X * 1.26, h.Y * 0.96, h.Z * 1.3), 0, 0.15, 0.03, CHARCOAL, METAL, "Ball")
	head(Vector3.new(0.16, 0.12, h.Z * 1.08), 0, 0.6, 0.03, PLATE_LIGHT, METAL)
	for _, x in { -1, 1 } do
		head(Vector3.new(0.14, 0.14, 0.14), x * 0.62, 0.08, 0.02, PLATE_LIGHT, METAL, "Ball")
		head(Vector3.new(0.1, h.Y * 0.62, h.Z * 0.7), x * 0.6, -0.12, 0.06, PLATE, METAL) -- cheek plate
	end
	head(Vector3.new(h.X * 0.96, 0.42, 0.1), 0, 0.04, -0.6, EDGE, METAL)
	head(Vector3.new(h.X * 0.86, 0.3, 0.1), 0, 0.04, -0.63, VISOR, Enum.Material.Glass)
	head(Vector3.new(h.X * 0.84, h.Y * 0.36, 0.24), 0, -0.3, -0.5, PLATE, METAL)
	for _, x in { -0.24, 0.24 } do
		head(Vector3.new(0.24, 0.16, 0.24), x, -0.33, -0.66, EDGE, METAL, "Cyl", FORWARD)
		head(Vector3.new(0.16, 0.02, 0.16), x, -0.33, -0.735, PLATE_LIGHT, METAL, "Cyl", FORWARD)
	end

	-- torso: plate shell, a diamond-plate breastplate with rivets, belly bands, gorget, power pack
	local chest, t = on(model, "UpperTorso")
	chest(Vector3.new(t.X * 1.16, t.Y * 0.9, t.Z * 1.4), 0, -0.02, 0, CHARCOAL, METAL)
	chest(Vector3.new(t.X * 0.82, t.Y * 0.56, 0.18), 0, 0.08, -0.75, PLATE, Enum.Material.DiamondPlate)
	for _, x in { -0.36, 0.36 } do
		for _, y in { 0.33, -0.17 } do
			chest(Vector3.new(0.1, 0.1, 0.06), x, y, -0.83, PLATE_LIGHT, METAL, "Ball")
		end
	end
	for _, y in { -0.3, -0.41 } do
		chest(Vector3.new(t.X * 0.9, 0.16, t.Z * 1.42), 0, y, 0, PLATE, METAL)
	end
	chest(Vector3.new(t.X * 0.7, 0.3, t.Z * 1.2), 0, 0.5, 0, EDGE, METAL, "Cyl")
	chest(Vector3.new(t.X * 0.7, t.Y * 0.62, 0.5), 0, 0, 0.88, EDGE, METAL)
	for _, x in { -0.18, 0.18 } do
		chest(Vector3.new(0.3, 0.5, 0.3), x, 0.16, 1.1, PLATE, METAL, "Cyl")
		chest(Vector3.new(0.22, 0.04, 0.22), x, 0.3, 1.1, GLOW, Enum.Material.Neon, "Cyl") -- vents
	end

	-- arms: layered pauldrons, rerebraces, gauntlets with knuckle plates
	for _, side in { "Left", "Right" } do
		local sign = side == "Left" and -1 or 1
		local upper, ua = on(model, side .. "UpperArm")
		upper(Vector3.new(ua.X * 1.9, ua.Y * 0.58, ua.Z * 1.5), sign * 0.14, 0.3, 0, PLATE, METAL, "Ball")
		for i, y in { 0.12, -0.02 } do
			upper(Vector3.new(ua.X * (1.8 - i * 0.2), 0.12, ua.Z * (1.36 - i * 0.1)), sign * 0.2, y, 0, CHARCOAL, METAL, nil, CFrame.Angles(0, 0, math.rad(sign * 18)))
		end
		upper(Vector3.new(ua.X * 1.22, ua.Y * 0.4, ua.Z * 1.2), 0, -0.24, 0, CHARCOAL, METAL)
		local lower, la = on(model, side .. "LowerArm")
		lower(Vector3.new(la.X * 1.3, la.Y * 0.74, la.Z * 1.3), 0, -0.04, 0, CHARCOAL, METAL)
		lower(Vector3.new(la.X * 1.36, 0.12, la.Z * 1.36), 0, 0.3, 0, PLATE, METAL)
		lower(Vector3.new(0.12, la.Y * 0.6, 0.12), sign * 0.62, -0.04, 0, PLATE_LIGHT, METAL) -- ridge
		local hand = on(model, side .. "Hand")
		hand(Vector3.new(0.5, 0.26, 0.24), 0, -0.05, -0.3, PLATE, METAL)
	end

	-- hips: armoured belt with an ammo box, a groin plate, tassets
	local hips, l = on(model, "LowerTorso")
	hips(Vector3.new(l.X * 1.12, l.Y * 0.9, l.Z * 1.24), 0, 0.05, 0, CHARCOAL, METAL)
	hips(Vector3.new(l.X * 1.14, 0.12, l.Z * 1.26), 0, 0.3, 0, PLATE, METAL)
	hips(Vector3.new(0.5, 0.42, 0.34), 0.55, -0.1, 0.25, EDGE, METAL)
	hips(Vector3.new(l.X * 0.36, l.Y * 1.1, 0.2), 0, -0.45, -0.6, PLATE, METAL, "Wedge", CFrame.Angles(0, math.rad(180), 0))
	for _, x in { -0.36, 0.36 } do
		hips(Vector3.new(l.X * 0.36, l.Y * 1.2, 0.14), x, -0.55, -0.58, PLATE, METAL, nil, CFrame.Angles(math.rad(-8), 0, 0))
	end

	-- legs: thigh plates, knee cops, shin guards with a ridge, armoured boot shells
	for _, side in { "Left", "Right" } do
		local thigh, ul = on(model, side .. "UpperLeg")
		thigh(Vector3.new(ul.X * 1.18, ul.Y * 0.62, 0.22), 0, -0.08, -0.55, PLATE, METAL)
		thigh(Vector3.new(0.18, ul.Y * 0.56, ul.Z * 0.8), (side == "Left" and -1 or 1) * 0.58, -0.08, 0, CHARCOAL, METAL)
		local shin, ll = on(model, side .. "LowerLeg")
		shin(Vector3.new(ll.X * 1.06, 0.5, 0.42), 0, 0.38, -0.46, PLATE_LIGHT, METAL, "Ball")
		shin(Vector3.new(ll.X * 1.16, ll.Y * 0.64, 0.24), 0, -0.08, -0.56, CHARCOAL, METAL)
		shin(Vector3.new(0.12, ll.Y * 0.6, 0.08), 0, -0.08, -0.7, PLATE, METAL)
		local foot, f = on(model, side .. "Foot")
		foot(Vector3.new(f.X * 1.1, f.Y * 0.6, f.Z * 1.08), 0, 0.1, 0, CHARCOAL, METAL)
		foot(Vector3.new(f.X * 1.12, 0.1, 0.3), 0, 0.02, -0.46, PLATE, METAL)
	end
end

-- The Blender kit (assets/army: build.py, export.py, install.luau): ReplicatedStorage.ArmyKit holds a
-- folder per piece ("Soldier_Head", "Heavy_LeftFoot" ...), each a MeshPart per colour with its place
-- on that body part in its "Place" attribute (a CFrame). Uploaded meshes, so no EditableMesh budget.
local function fromKit(model: Model, name: string): boolean
	local kit = game:GetService("ReplicatedStorage"):FindFirstChild("ArmyKit")
	if not (kit and kit:FindFirstChild(name .. "_UpperTorso")) then
		return false
	end
	for _, folder in kit:GetChildren() do
		local part = folder.Name:match("^" .. name .. "_(.+)$")
		local body = part and model:FindFirstChild(part) :: BasePart?
		if not body then
			continue
		end
		for _, mesh in folder:GetChildren() do
			local p = mesh:Clone() :: BasePart
			p.CFrame = body.CFrame * (p:GetAttribute("Place") or CFrame.identity)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = body, p, p
			p.Parent = body -- with its limb: a cut-off arm takes its guard along
		end
	end
	return true
end

-- What the kit leaves bare and gets a colour instead: [outfit] = { hands (gloves), feet }.
local BARE = {
	Soldier = { BLACK, STRAP },
	Heavy = { EDGE, EDGE },
	Worker = { Color3.fromHex("C9A060"), Color3.fromHex("7A5230") }, -- leather gloves, boots
	Zombie = { nil, Color3.fromHex("7FA05A") }, -- a bare green foot; the other has its shoe in the kit
}

-- Dresses `model` (a dummy, built but not yet ragdolled) as `name` ("Soldier", "Heavy", "Worker",
-- "Zombie"): the Blender kit when the place has it, else (Soldier, Heavy) the same out of plain parts.
function Outfits.dress(model: Model, name: string)
	if fromKit(model, name) then
		local bare = BARE[name] or {}
		if bare[1] then
			paint(model, { "LeftHand", "RightHand" }, bare[1])
		end
		if bare[2] then
			paint(model, { "LeftFoot", "RightFoot" }, bare[2])
		end
		if name == "Zombie" then -- its shirt and trousers are the body itself: cloth, not plastic, like its rags
			for _, part in { "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" } do
				local p = model:FindFirstChild(part) :: BasePart?
				if p then
					p.Material = Enum.Material.Fabric
				end
			end
		end
		return
	end
	local fn = Outfits[name]
	if type(fn) == "function" and name ~= "dress" then
		fn(model)
	end
end

return Outfits
