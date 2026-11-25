-- Weapon models without any uploaded asset: the geometry lives in the sibling data modules
-- (exported from assets/weapons/weapons.blend by assets/weapons/export.py) and is turned into
-- MeshParts here with EditableMesh. Colours are per face, so the part itself stays white SmoothPlastic.
--
-- A Play client may only keep 8 EditableMeshes alive (whatever their size), and a MeshPart goes
-- blank when its EditableMesh is destroyed. So:
--  * create(id): one EditableMesh per weapon, shared by every part made from it, freed once the
--    last of those parts is destroyed (callers must :Destroy() what they stop using);
--  * icon(id): every weapon in a few atlas EditableMeshes (weapons stacked SPACING apart on Y,
--    ATLAS_CAP triangles per atlas), for ViewportFrames, where the camera only frames one of them.
local AssetService = game:GetService("AssetService")

local WeaponMeshes = {}

local SPACING = 12
local GLOW = { Lightsaber = Color3.fromRGB(110, 200, 255) } -- weapons that give off light (create)
-- Items that share another's mesh with some of its moving pieces recoloured: id = { data module, piece -> colour }.
-- The syringes' serum is the "Liquid" piece of Syringe (assets/weapons/comic_weapons.py).
local VARIANTS = {
	DeathSyringe = { data = "Syringe", tint = { Liquid = Color3.fromRGB(150, 40, 230) } },
	HealSyringe = { data = "Syringe", tint = { Liquid = Color3.fromRGB(255, 70, 110) } },
}
local function dataOf(id: string): ModuleScript?
	local variant = VARIANTS[id]
	return script:FindFirstChild(if variant then variant.data else id) :: ModuleScript?
end

-- noOutline: skip the comic outline shell (the pure black faces), which doubles every weapon's
-- triangles; each icon atlas must stay under the 20k cap.
-- tint: piece name -> colour for that piece's faces (VARIANTS); its outline stays black.
local function fill(mesh: EditableMesh, data, offset: Vector3, noOutline: boolean?, tint: { [string]: Color3 }?)
	local v, n, c = {}, {}, {}
	local tinted = {} -- vertex id -> the colour id its piece is tinted with
	for name, color in tint or {} do
		local id = mesh:AddColor(color, 1)
		for _, i in (data.p and data.p[name] or { v = {} }).v do
			tinted[i] = id
		end
	end
	local black = {}
	for i = 1, #data.c, 3 do
		black[(i + 2) // 3] = data.c[i] == 0 and data.c[i + 1] == 0 and data.c[i + 2] == 0
	end
	for i = 1, #data.v, 3 do
		table.insert(v, mesh:AddVertex(Vector3.new(data.v[i], data.v[i + 1], data.v[i + 2]) + offset))
	end
	for i = 1, #data.n, 3 do
		table.insert(n, mesh:AddNormal(Vector3.new(data.n[i], data.n[i + 1], data.n[i + 2])))
	end
	for i = 1, #data.c, 3 do
		table.insert(c, mesh:AddColor(Color3.new(data.c[i], data.c[i + 1], data.c[i + 2]), 1))
	end
	local f = data.f
	for i = 1, #f, 7 do
		if noOutline and black[f[i + 6]] then
			continue
		end
		local face = mesh:AddTriangle(v[f[i]], v[f[i + 1]], v[f[i + 2]])
		mesh:SetFaceNormals(face, { n[f[i + 3]], n[f[i + 4]], n[f[i + 5]] })
		local color = if black[f[i + 6]] then c[f[i + 6]] else tinted[f[i]] or c[f[i + 6]]
		mesh:SetFaceColors(face, { color, color, color })
	end
	return v, n
end

-- The moving pieces of a built mesh: [name] = { verts = {{id, pos}}, normals = {{id, n}}, centre }.
local function pieces(data, v, n)
	local out = {}
	for name, p in data.p or {} do
		local piece = { verts = {}, normals = {}, centre = Vector3.zero }
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, i in p.v do
			local pos = Vector3.new(data.v[i * 3 - 2], data.v[i * 3 - 1], data.v[i * 3])
			table.insert(piece.verts, { v[i], pos })
			lo, hi = lo:Min(pos), hi:Max(pos)
		end
		for _, i in p.n do
			table.insert(piece.normals, { n[i], Vector3.new(data.n[i * 3 - 2], data.n[i * 3 - 1], data.n[i * 3]) })
		end
		piece.centre = (lo + hi) / 2
		out[name] = piece
	end
	return out
end

local function bounds(data): (Vector3, Vector3)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for i = 1, #data.v, 3 do
		local p = Vector3.new(data.v[i], data.v[i + 1], data.v[i + 2])
		lo, hi = lo:Min(p), hi:Max(p)
	end
	return lo, hi
end

local function meshPart(mesh: EditableMesh, name: string): MeshPart
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), { CollisionFidelity = Enum.CollisionFidelity.Box })
	part.Name = name
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

-- The weapon's bounding box (min, max corners) relative to its origin (the grip), in the mesh's
-- own space; a part from create() has its CFrame at that origin, not at the box centre.
local boxes = {}
function WeaponMeshes.bounds(id: string): (Vector3?, Vector3?)
	local data = dataOf(id)
	if not data then
		return nil, nil
	end
	boxes[id] = boxes[id] or { bounds(require(data)) }
	return boxes[id][1], boxes[id][2]
end

-- [id] = { part, mesh, users } | true (being built) | false (failed, don't retry)
local live = {}

-- Returns a new anchored, non-colliding MeshPart for the weapon, or nil if this client can't
-- build one (callers keep their block fallback). The part's origin is the modelled origin (the
-- grip), not the bounding-box centre. Destroy it when done. Yields. `module`: a data module kept
-- elsewhere (client/DisasterMeshes), for a model that is not a weapon (no icon); default: script[id].
function WeaponMeshes.create(id: string, module: ModuleScript?): MeshPart?
	local data = module or dataOf(id)
	if not data then
		return nil
	end
	while live[id] == true do
		task.wait()
	end
	if live[id] == nil then
		live[id] = true
		local mesh, moving
		local ok, part = pcall(function()
			mesh = AssetService:CreateEditableMesh() -- may be refused in a live game: blocks then
			local d = require(data)
			moving = pieces(d, fill(mesh, d, Vector3.zero, false, VARIANTS[id] and VARIANTS[id].tint))
			return meshPart(mesh, id)
		end)
		if not ok then
			warn(`WeaponMeshes: {id} failed, using blocks: {part}`)
			live[id] = false
			return nil
		end
		live[id] = { part = part, mesh = mesh, users = 0, pieces = moving }
	end
	local entry = live[id]
	if not entry then
		return nil
	end
	local clone = entry.part:Clone()
	if GLOW[id] then -- the lightsaber's blade lights up whatever is round it
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = GLOW[id], 9, 2
		light.Parent = clone
	end
	entry.users += 1
	clone.Destroying:Once(function()
		entry.users -= 1
		if entry.users == 0 and live[id] == entry then
			live[id] = nil
			entry.part:Destroy()
			entry.mesh:Destroy()
		end
	end)
	return clone
end

-- The centre of a moving piece (mesh space), if the weapon's live mesh has one by that name.
function WeaponMeshes.pieceCentre(id: string, name: string): Vector3?
	local entry = live[id]
	local piece = type(entry) == "table" and entry.pieces[name]
	return piece and piece.centre or nil
end

-- Moves a piece of the weapon's live mesh (every part made from it) to off * rest, mesh space;
-- CFrame.identity puts it back. Cheap to call every frame: an unchanged pose writes nothing.
function WeaponMeshes.pose(id: string, name: string, off: CFrame)
	local entry = live[id]
	local piece = type(entry) == "table" and entry.pieces[name]
	if not piece or (piece.off and piece.off:FuzzyEq(off, 1e-4)) then
		return
	end
	piece.off = off
	local mesh = entry.mesh
	for _, pair in piece.verts do
		mesh:SetPosition(pair[1], off * pair[2])
	end
	for _, pair in piece.normals do
		mesh:SetNormal(pair[1], off:VectorToWorldSpace(pair[2]))
	end
end

-- The icon atlases: { parts = { MeshPart }, at = { [id] = { part = index, centre, size } } } | true
-- (being built) | false (failed). Each atlas mesh is filled up to ATLAS_CAP triangles (an EditableMesh
-- holds 20k), outline shells left out, then the next one starts.
local ATLAS_CAP = 19000
local atlas

-- The triangles fill() adds with noOutline (the pure black ones are the outline shell).
local function visibleTris(data): number
	local black = {}
	for i = 1, #data.c, 3 do
		black[(i + 2) // 3] = data.c[i] == 0 and data.c[i + 1] == 0 and data.c[i + 2] == 0
	end
	local n = 0
	for i = 7, #data.f, 7 do
		if not black[data.f[i]] then
			n += 1
		end
	end
	return n
end

-- A MeshPart for a ViewportFrame, placed so the weapon's bounding-box centre is at the origin,
-- plus that box's size; the rest of the atlas sits SPACING studs and more above / below it. Yields.
function WeaponMeshes.icon(id: string): (MeshPart?, Vector3?)
	while atlas == true do
		task.wait()
	end
	if atlas == nil then
		atlas = true
		local ok, result = pcall(function()
			local parts, at = {}, {}
			local mesh, used, k = nil, 0, 0
			local entries = {} -- { icon id, data module, tint }
			for _, data in script:GetChildren() do
				if data.Name ~= "BoxingGloveLeft" and data.Name ~= "Baton" and data.Name ~= "Syringe" then -- never an icon (the glove's mirror, the cops' baton, the variants' base)
					table.insert(entries, { data.Name, data })
				end
			end
			for id, variant in VARIANTS do
				table.insert(entries, { id, script[variant.data], variant.tint })
			end
			for _, entry in entries do
				local d = require(entry[2])
				local tris = visibleTris(d)
				if mesh and used + tris > ATLAS_CAP then -- full: this one starts the next atlas
					table.insert(parts, meshPart(mesh, "WeaponAtlas"))
					mesh, used, k = nil, 0, 0
				end
				mesh = mesh or AssetService:CreateEditableMesh()
				k += 1
				used += tris
				local offset = Vector3.new(0, k * SPACING, 0)
				local lo, hi = bounds(d)
				fill(mesh, d, offset, true, entry[3])
				at[entry[1]] = { part = #parts + 1, centre = offset + (lo + hi) / 2, size = hi - lo }
			end
			if mesh then
				table.insert(parts, meshPart(mesh, "WeaponAtlas"))
			end
			return { parts = parts, at = at }
		end)
		if not ok then
			warn(`WeaponMeshes: atlas failed, icons use blocks: {result}`)
		end
		atlas = ok and result or false
	end
	local spot = atlas and atlas.at[id]
	if not spot then
		return nil
	end
	local part = atlas.parts[spot.part]:Clone()
	part.Name = id
	part.CFrame = CFrame.new(-spot.centre)
	return part, spot.size
end

return WeaponMeshes
