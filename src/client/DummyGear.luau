-- What a dummy holds (the server's "Gear" attribute, a Weapons id): the same Blender mesh the
-- player holds, drawn here in the dummy's right hand. WeaponMeshes shares one EditableMesh per
-- weapon, so a crowd of cops costs a single mesh. Looks only: the server does the hitting.
local RunService = game:GetService("RunService")
local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))

-- RightGripAttachment * this, as the player holds them (init.client HOLD)
local GRIP = {
	Handgun = CFrame.new(0, -0.08, 0.08),
	Bat = CFrame.new(0, 0.05, 0),
	Baton = CFrame.new(0, 0.05, 0), -- cops, until they draw (Wanted: 3 stars)
	Rifle = CFrame.new(0, 0.12, -0.04), -- soldiers (Wanted)
	Rocket = CFrame.new(0, -0.2, 0),
}
local DEFAULT_GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)

local held = {} -- [Model] = { id, mesh } (mesh nil while it builds) | { id, parts, offsets } (from the kit)

local function drop(model: Instance)
	local entry = held[model]
	held[model] = nil
	if entry and entry.mesh then
		entry.mesh:Destroy()
	end
	for _, p in entry and entry.parts or {} do
		p:Destroy()
	end
end

-- A weapon from the Blender kit (ReplicatedStorage.ArmyKit, uploaded meshes: costs no EditableMesh):
-- its colour meshes, each with its place from the grip ("Place").
local function fromKit(id: string)
	local kit = game:GetService("ReplicatedStorage"):FindFirstChild("ArmyKit")
	local folder = kit and kit:FindFirstChild(id)
	if not folder then
		return nil
	end
	local parts, offsets = {}, {}
	for _, mesh in folder:GetChildren() do
		local p = mesh:Clone() :: BasePart
		p.Anchored = true
		p.LocalTransparencyModifier = 1
		p.Parent = workspace.CurrentCamera
		table.insert(parts, p)
		table.insert(offsets, p:GetAttribute("Place") or CFrame.identity)
	end
	return { id = id, parts = parts, offsets = offsets }
end

local function add(model: Instance)
	local id = model:GetAttribute("Gear")
	if held[model] and held[model].id == id then
		return
	end
	drop(model) -- a cop swapping its baton for the gun
	if not GRIP[id] then
		return
	end
	local kitted = fromKit(id)
	if kitted then
		held[model] = kitted
		return
	end
	local entry = { id = id, mesh = nil :: MeshPart? }
	held[model] = entry
	task.spawn(function()
		local mesh = WeaponMeshes.create(id)
		if mesh and held[model] == entry then
			mesh.Transparency = 1
			mesh.Parent = workspace.CurrentCamera
			entry.mesh = mesh
		elseif mesh then
			mesh:Destroy()
		end
	end)
end

local folder = workspace:WaitForChild("Dummies")
local function watch(model: Instance)
	add(model)
	model:GetAttributeChangedSignal("Gear"):Connect(function()
		add(model)
	end)
end
folder.ChildAdded:Connect(watch)
for _, model in folder:GetChildren() do
	watch(model)
end

RunService.RenderStepped:Connect(function()
	for model, entry in held do
		if not model.Parent then
			drop(model)
			continue
		end
		if entry.parts then -- the kit's meshes, moved together
			local hand = model:FindFirstChild("RightHand") :: BasePart?
			local grip = hand and hand:FindFirstChild("RightGripAttachment") :: Attachment?
			local at = hand and hand.CFrame * (grip and grip.CFrame or DEFAULT_GRIP) * GRIP[entry.id]
			local cframes = {}
			for i, p in entry.parts do
				p.LocalTransparencyModifier = at and 0 or 1
				cframes[i] = at and at * entry.offsets[i] or p.CFrame
			end
			workspace:BulkMoveTo(entry.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
			continue
		end
		local mesh = entry.mesh
		if not mesh then
			continue
		end
		-- a hand cut off or not streamed in: nothing to hold it
		local hand = model:FindFirstChild("RightHand") :: BasePart?
		mesh.Transparency = hand and 0 or 1
		if hand then
			local grip = hand:FindFirstChild("RightGripAttachment") :: Attachment?
			mesh.CFrame = hand.CFrame * (grip and grip.CFrame or DEFAULT_GRIP) * GRIP[entry.id]
		end
	end
end)

return nil
