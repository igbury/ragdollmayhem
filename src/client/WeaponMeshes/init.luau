-- Weapon models without any uploaded asset: the geometry lives in the sibling data modules
-- (exported from assets/weapons/weapons.blend) and is turned into MeshParts here with EditableMesh.
-- Colours are per face, so the part itself stays white SmoothPlastic.
local AssetService = game:GetService("AssetService")

local WeaponMeshes = {}

local editable = {} -- [id] = EditableMesh | false (false = build failed, don't retry)

local function build(data): EditableMesh
	local mesh = AssetService:CreateEditableMesh()
	local v, n, c = {}, {}, {}
	for i = 1, #data.v, 3 do
		table.insert(v, mesh:AddVertex(Vector3.new(data.v[i], data.v[i + 1], data.v[i + 2])))
	end
	for i = 1, #data.n, 3 do
		table.insert(n, mesh:AddNormal(Vector3.new(data.n[i], data.n[i + 1], data.n[i + 2])))
	end
	for i = 1, #data.c, 3 do
		table.insert(c, mesh:AddColor(Color3.new(data.c[i], data.c[i + 1], data.c[i + 2]), 1))
	end
	local f = data.f
	for i = 1, #f, 7 do
		local face = mesh:AddTriangle(v[f[i]], v[f[i + 1]], v[f[i + 2]])
		mesh:SetFaceNormals(face, { n[f[i + 3]], n[f[i + 4]], n[f[i + 5]] })
		local color = c[f[i + 6]]
		mesh:SetFaceColors(face, { color, color, color })
	end
	return mesh
end

-- Returns a new anchored, non-colliding MeshPart for the weapon, or nil if this client can't
-- build one (callers keep their block fallback). The part's origin is the modelled origin (the
-- grip), not the bounding-box centre. Yields.
function WeaponMeshes.create(id: string): MeshPart?
	local data = script:FindFirstChild(id)
	if not data or editable[id] == false then
		return nil
	end
	local ok, part = pcall(function()
		editable[id] = editable[id] or build(require(data))
		return AssetService:CreateMeshPartAsync(Content.fromObject(editable[id]), { CollisionFidelity = Enum.CollisionFidelity.Box })
	end)
	if not ok then
		warn(`WeaponMeshes: {id} failed, using blocks: {part}`)
		editable[id] = false
		return nil
	end
	part.Name = id
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

return WeaponMeshes
