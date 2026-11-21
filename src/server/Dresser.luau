-- The Toolbox WARDROBE on the server: dresses a dummy in a player's style (shared/Wardrobe), or back
-- in its own kind's clothes, and keeps that player's mannequin preview (PlayerGui.WardrobePreview,
-- drawn on the WARDROBE stage). Catalog items arrive by CreateHumanoidModelFromDescription, built once
-- per item and kept; the dummy gets copies of their Shirt, Pants and hats, so it is never rebuilt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Wardrobe = require(ReplicatedStorage.Shared.Wardrobe)
local Looks = require(script.Parent.Looks)

local Dresser = {}
local WHITE = Color3.new(1, 1, 1)
local sources: { [string]: Model | false } = {} -- [key] = the built model; false while it builds

-- the model `desc` builds, made once per key (yields while it loads)
local function source(key: string, desc: HumanoidDescription): Model?
	if sources[key] == nil then
		sources[key] = false
		local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, Enum.HumanoidRigType.R15)
		if ok then
			sources[key] = model
		else
			sources[key] = nil
			warn("Dresser: could not load", key, model)
			return nil
		end
	end
	while sources[key] == false do
		task.wait()
	end
	return sources[key] or nil
end

-- A catalog hat's handle is a textured MeshPart, which no colour tints. A Part with a SpecialMesh of
-- the same mesh and texture does: VertexColor multiplies the texture.
local function tinted(handle: BasePart, color: Color3): BasePart
	if color == WHITE or not handle:IsA("MeshPart") then
		return handle
	end
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame, part.Transparency = "Handle", handle.Size, handle.CFrame, handle.Transparency
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType, mesh.MeshId, mesh.TextureId = Enum.MeshType.FileMesh, handle.MeshId, handle.TextureID
	mesh.Scale = handle.Size / handle.MeshSize
	mesh.VertexColor = Vector3.new(color.R, color.G, color.B)
	mesh.Parent = part
	for _, child in handle:GetChildren() do
		if child:IsA("Attachment") then
			child.Parent = part
		end
	end
	handle:Destroy()
	return part
end

-- Takes `model`'s Shirt, Pants and hats off and puts these on: { Shirt | Pants | Accessory } copies,
-- each with its tint (nil: as it comes).
local function put(model: Model, pieces: { { thing: Instance, color: Color3? } })
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	for _, child in model:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("Accessory") then
			child:Destroy()
		end
	end
	for _, piece in pieces do
		local copy = piece.thing:Clone()
		local color = piece.color or WHITE
		if copy:IsA("Clothing") then
			copy.Color3 = color
			copy.Parent = model
		elseif copy:IsA("Accessory") then
			local handle = copy:FindFirstChild("Handle") :: BasePart?
			if not handle then
				continue
			end
			for _, w in handle:GetChildren() do -- still welded to the source model's head
				if w:IsA("JointInstance") or w:IsA("WeldConstraint") then
					w:Destroy()
				end
			end
			handle = tinted(handle, color)
			handle.Parent = copy
			handle.CanCollide, handle.CanTouch, handle.Massless = false, false, true
			local at = handle:FindFirstChildOfClass("Attachment")
			if at and model:FindFirstChild(at.Name, true) then -- no head left: no hat
				humanoid:AddAccessory(copy)
			else
				copy:Destroy()
			end
		end
	end
end

-- the Shirt / Pants / hats of `model`, as pieces for put
local function piecesOf(model: Model?, color: Color3?)
	local pieces = {}
	for _, child in if model then model:GetChildren() else {} do
		if child:IsA("Clothing") or child:IsA("Accessory") then
			table.insert(pieces, { thing = child, color = color })
		end
	end
	return pieces
end

-- the pieces a style wears (each item loaded on its own, so 45 loads at most)
local FIELDS = { "HatAccessory", "Shirt", "Pants" }
local function stylePieces(style: Wardrobe.Style)
	local pieces = {}
	for i in Wardrobe.CATEGORIES do
		local id = Wardrobe.id(style, i)
		if id then
			local desc = Instance.new("HumanoidDescription")
			desc[FIELDS[i]] = if i == 1 then tostring(id) else id
			for _, piece in piecesOf(source(FIELDS[i] .. id, desc), Wardrobe.COLORS[style.colors[i]]) do
				table.insert(pieces, piece)
			end
		end
	end
	return pieces
end

-- `player`'s style, cleaned up (the "setting" action keeps this, not what the client sent)
function Dresser.clean(text: any): string
	return Wardrobe.format(Wardrobe.parse(text))
end

function Dresser.dress(model: Model, player: Player)
	put(model, stylePieces(Wardrobe.parse(player:GetAttribute("Wardrobe"))))
end

-- back in what its kind wears; `kindName` keys the cache, `desc` is that kind's HumanoidDescription
function Dresser.reset(model: Model, kindName: string, desc: HumanoidDescription)
	put(model, piecesOf(source("kind:" .. kindName, desc)))
end

-- The WARDROBE stage's mannequin, in the player's style: rebuilt into their PlayerGui (only they see
-- it) whenever the style changes. `base`: the plain mannequin's description.
function Dresser.watch(player: Player, base: HumanoidDescription)
	local version = 0
	local function rebuild()
		version += 1
		local mine = version
		local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, base, Enum.HumanoidRigType.R15)
		if not ok then
			return
		end
		Looks.buildFace(Looks.plainHead(model))
		put(model, stylePieces(Wardrobe.parse(player:GetAttribute("Wardrobe"))))
		for _, acc in model:GetChildren() do -- outside workspace the hat welds never solve: place each by hand
			local handle = acc:IsA("Accessory") and acc:FindFirstChild("Handle") :: BasePart?
			local own = handle and handle:FindFirstChildOfClass("Attachment")
			local body: Instance? = nil
			for _, part in model:GetChildren() do
				body = body or (own and part:IsA("BasePart") and part:FindFirstChild(own.Name))
			end
			if body and body:IsA("Attachment") then
				(handle :: BasePart).CFrame = body.WorldCFrame * (own :: Attachment).CFrame:Inverse()
			end
		end
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if mine ~= version or not gui then -- a newer style overtook this one
			model:Destroy()
			return
		end
		model.Name = "WardrobePreview"
		model:SetAttribute("Style", player:GetAttribute("Wardrobe") or "")
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			elseif d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		-- built at the origin, which is the spawn: the copy in PlayerGui showed up there in the world.
		-- Parked far below the map instead (the WARDROBE stage frames it wherever it is).
		model:PivotTo(CFrame.new(0, -10000, 0) * (model:GetPivot() - model:GetPivot().Position))
		local old = gui:FindFirstChild("WardrobePreview")
		model.Parent = gui
		if old then
			old:Destroy()
		end
	end
	player:GetAttributeChangedSignal("Wardrobe"):Connect(function()
		task.spawn(rebuild)
	end)
	task.spawn(rebuild)
end

return Dresser
