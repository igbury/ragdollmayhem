-- A small, asset-free glove model shared by the viewmodel, icons and replicated character.
-- Grip space: -Z out along the fingers, +Z toward the wrist. The thumb faces the other hand.
local Gloves = {}
local RED = Color3.fromRGB(198, 34, 43)
local DARK = Color3.fromRGB(104, 19, 30)
local WHITE = Color3.fromRGB(242, 236, 224)

function Gloves.specs(side: number)
	return {
		{ Enum.PartType.Ball, Vector3.new(0.76, 0.78, 0.84), CFrame.new(0, 0.08, -0.25), RED },
		{ Enum.PartType.Ball, Vector3.new(0.66, 0.59, 0.64), CFrame.new(0, -0.10, 0.04), RED },
		{ Enum.PartType.Ball, Vector3.new(0.29, 0.43, 0.46), CFrame.new(-side * 0.35, -0.08, -0.05) * CFrame.Angles(0, 0, -side * 0.22), RED },
		{ Enum.PartType.Cylinder, Vector3.new(0.33, 0.66, 0.66), CFrame.new(0, -0.08, 0.38) * CFrame.Angles(0, math.pi / 2, 0), DARK },
		{ Enum.PartType.Cylinder, Vector3.new(0.10, 0.68, 0.68), CFrame.new(0, -0.08, 0.42) * CFrame.Angles(0, math.pi / 2, 0), WHITE },
		{ Enum.PartType.Ball, Vector3.new(0.38, 0.06, 0.27), CFrame.new(0, 0.45, -0.20), WHITE },
	}
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

-- A hand makes the pieces massless welded cosmetics. No hand makes an anchored viewmodel.
function Gloves.create(parent: Instance, name: string, side: number, hand: BasePart?)
	local model = Instance.new("Model")
	model.Name = name
	local pieces = {}
	local grip = hand and hand:FindFirstChild((hand.Name:gsub("Hand", "GripAttachment"))) :: Attachment?
	local offset = grip and grip.CFrame or CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	for i, spec in Gloves.specs(side) do
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
	return { model = model, pieces = pieces }
end

function Gloves.update(glove, cf: CFrame, visible: boolean)
	for _, piece in glove.pieces do
		piece.part.Transparency = visible and 0 or 1
		if visible then piece.part.CFrame = cf * piece.offset end
	end
end

function Gloves.attach(character: Model): Model?
	local left, right = character:FindFirstChild("LeftHand"), character:FindFirstChild("RightHand")
	if not (left and left:IsA("BasePart") and right and right:IsA("BasePart")) then return nil end
	local model = Instance.new("Model")
	model.Name = "BoxingGloves"
	Gloves.create(model, "LeftGlove", -1, left)
	Gloves.create(model, "RightGlove", 1, right)
	model.Parent = character
	return model
end

return Gloves
