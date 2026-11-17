-- The comic boxing glove meshes (WeaponMeshes BoxingGloves / BoxingGloveLeft, from
-- assets/weapons/glove.py) over the part-built gloves of shared BoxingGloves. The parts stay as the
-- server's cosmetic and the fallback for a client that cannot build meshes.
-- Both meshes stay alive for the session once dressed: 2 of the client's 8 EditableMeshes, shared by
-- the viewmodel and every character's gloves.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Gloves = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoxingGloves"))
local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))

local GloveMeshes = {}

local ID = { [1] = "BoxingGloves", [-1] = "BoxingGloveLeft" }

-- Gives a glove from Gloves.create its mesh; Gloves.update moves the mesh from then on. Yields.
function GloveMeshes.dress(glove, side: number, parent: Instance)
	local mesh = WeaponMeshes.create(ID[side])
	if not mesh then
		return
	end
	if not glove.model.Parent then
		mesh:Destroy()
		return
	end
	mesh.Name = glove.model.Name .. "Mesh"
	mesh.Transparency = 1
	mesh.Parent = parent
	glove.model.Destroying:Once(function()
		mesh:Destroy()
	end)
	glove.mesh = mesh
end

-- How far the glove whose mesh sits at `cf` reaches along the unit `dir` (world), measured on every
-- 4th vertex of the model, outline included. Plain data, so it works without a live mesh too.
local points = {} -- [side] = { Vector3 }
function GloveMeshes.reach(side: number, cf: CFrame, dir: Vector3): number
	local pts = points[side]
	if not pts then
		pts = {}
		local v = require(script.Parent:WaitForChild("WeaponMeshes"):WaitForChild(ID[side])).v
		for i = 1, #v, 12 do
			table.insert(pts, Vector3.new(v[i], v[i + 1], v[i + 2]))
		end
		points[side] = pts
	end
	local d = cf:VectorToObjectSpace(dir)
	local best = -math.huge
	for _, p in pts do
		best = math.max(best, p:Dot(d))
	end
	return best + cf.Position:Dot(dir)
end

-- Every character's replicated gloves (Gloves.attach, on the server) wear the meshes here.
-- hidden(character): true where that body's gloves must not draw (our own, in first person).
function GloveMeshes.watch(parent: Instance, hidden: (Model) -> boolean)
	local worn = {} -- { glove, hand, character }

	local function add(model: Instance)
		if model.Name ~= "BoxingGloves" or not model:IsA("Model") then
			return
		end
		local character = model.Parent :: Model
		for side, prefix in { [1] = "Right", [-1] = "Left" } do
			task.spawn(function()
				local gloveModel = model:WaitForChild(prefix .. "Glove", 5)
				local hand = character:FindFirstChild(prefix .. "Hand") :: BasePart?
				if not (gloveModel and hand) then
					return
				end
				local glove = { model = gloveModel, pieces = {}, origin = Gloves.origin(side) }
				GloveMeshes.dress(glove, side, parent)
				if not glove.mesh then
					return
				end
				for _, padding in gloveModel:GetChildren() do
					if padding:IsA("BasePart") then
						padding.Transparency = 1 -- locally: the mesh draws instead
					end
				end
				table.insert(worn, { glove = glove, hand = hand, character = character })
			end)
		end
	end

	for _, d in workspace:GetDescendants() do
		add(d)
	end
	workspace.DescendantAdded:Connect(add)

	RunService.RenderStepped:Connect(function()
		for i = #worn, 1, -1 do
			local w = worn[i]
			if not w.glove.model.Parent then
				table.remove(worn, i)
			else
				Gloves.update(w.glove, w.hand.CFrame * Gloves.grip(w.hand), not hidden(w.character))
			end
		end
	end)
end

return GloveMeshes
