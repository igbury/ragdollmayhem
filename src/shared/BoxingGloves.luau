-- A small, asset-free glove model shared by the viewmodel, icons and replicated character.
-- Grip space: -Z out along the fingers, +Z toward the wrist. The thumb faces the other hand.
local Gloves = {}
local RED = Color3.fromRGB(198, 34, 43)
local DARK = Color3.fromRGB(104, 19, 30)
local WHITE = Color3.fromRGB(242, 236, 224)
-- The glove is grown about the cuff so it stays on the wrist while the padding swallows the whole hand.
local SCALE, CUFF = 1.2, Vector3.new(0, -0.08, 0.42)

function Gloves.specs(side: number)
	local specs = {
		{ Enum.PartType.Ball, Vector3.new(0.76, 0.78, 0.84), CFrame.new(0, 0.08, -0.25), RED },
		{ Enum.PartType.Ball, Vector3.new(0.66, 0.59, 0.64), CFrame.new(0, -0.10, 0.04), RED },
		{ Enum.PartType.Ball, Vector3.new(0.29, 0.43, 0.46), CFrame.new(-side * 0.35, -0.08, -0.05) * CFrame.Angles(0, 0, -side * 0.22), RED },
		{ Enum.PartType.Cylinder, Vector3.new(0.33, 0.66, 0.66), CFrame.new(0, -0.08, 0.38) * CFrame.Angles(0, math.pi / 2, 0), DARK },
		{ Enum.PartType.Cylinder, Vector3.new(0.10, 0.68, 0.68), CFrame.new(0, -0.08, 0.42) * CFrame.Angles(0, math.pi / 2, 0), WHITE },
		{ Enum.PartType.Ball, Vector3.new(0.38, 0.06, 0.27), CFrame.new(0, 0.45, -0.20), WHITE },
	}
	for _, spec in specs do
		spec[2] *= SCALE
		spec[3] = CFrame.new(CUFF + (spec[3].Position - CUFF) * SCALE) * spec[3].Rotation
	end
	return specs
end

function Gloves.icon()
	local specs = {}
	for _, side in { -1, 1 } do
		local offset = CFrame.new(side * 0.46, 0, side * 0.08) * CFrame.Angles(0, side * -0.16, 0)
		for _, spec in Gloves.specs(side) do
			table.insert(specs, { spec[1], spec[2], offset * spec[3], spec[4] })
		end
	end
	return specs
end

-- An R15 forearm runs ~0.35 behind the hand's centre: the glove is centred on the forearm instead,
-- or it hangs beside the arm. Grip space -> the glove's own space (the comic mesh's origin).
function Gloves.origin(side: number): CFrame
	return CFrame.new(-0.09 * side, -0.42, 0) -- measured on the viewmodel's stretched forearm
end

-- The hand's grip attachment, or where an R15 one would be.
function Gloves.grip(hand: BasePart): CFrame
	local grip = hand:FindFirstChild((hand.Name:gsub("Hand", "GripAttachment"))) :: Attachment?
	return grip and grip.CFrame or CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
end

-- A hand makes the pieces massless welded cosmetics. No hand makes an anchored viewmodel.
function Gloves.create(parent: Instance, name: string, side: number, hand: BasePart?)
	local model = Instance.new("Model")
	model.Name = name
	local pieces = {}
	local offset = hand and Gloves.grip(hand) or CFrame.identity
	local onForearm = Gloves.origin(side)
	for i, spec in Gloves.specs(side) do
		spec[3] = onForearm * spec[3]
		local p = Instance.new("Part")
		p.Name = "Padding" .. i
		p.Shape, p.Size, p.Color = spec[1], spec[2], spec[4]
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = hand == nil
		p.Massless = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		p.Transparency = hand and 0 or 1
		p.CFrame = hand and hand.CFrame * offset * spec[3] or spec[3]
		if hand then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = hand, p
			weld.Parent = p
		end
		p.Parent = model
		table.insert(pieces, { part = p, offset = spec[3] })
	end
	model.Parent = parent
	return { model = model, pieces = pieces, origin = onForearm, mesh = nil :: BasePart? }
end

-- cf: the hand's grip. A glove given a mesh (client GloveMeshes) moves that instead of its parts.
function Gloves.update(glove, cf: CFrame, visible: boolean)
	local mesh = glove.mesh
	for _, piece in glove.pieces do
		piece.part.Transparency = (visible and not mesh) and 0 or 1
		if visible and not mesh then piece.part.CFrame = cf * piece.offset end
	end
	if mesh then
		mesh.Transparency = visible and 0 or 1
		if visible then mesh.CFrame = cf * glove.origin end
	end
end

function Gloves.attach(character: Model): Model?
	local left, right = character:FindFirstChild("LeftHand"), character:FindFirstChild("RightHand")
	if not (left and left:IsA("BasePart") and right and right:IsA("BasePart")) then return nil end
	local model = Instance.new("Model")
	model.Name = "BoxingGloves"
	Gloves.create(model, "LeftGlove", -1, left)
	Gloves.create(model, "RightGlove", 1, right)
	-- The glove replaces the hand: a bare hand would poke through the padding.
	local was = { left.Transparency, right.Transparency }
	left.Transparency, right.Transparency = 1, 1
	model.Destroying:Connect(function()
		left.Transparency, right.Transparency = was[1], was[2]
	end)
	model.Parent = character
	return model
end

return Gloves
