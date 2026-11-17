-- How a dummy shows what it feels: a face drawn on the head, and a lean of the spine and neck.
-- Both are plain instances set on the server, so every client sees them and nothing needs an
-- uploaded image or animation.
local TweenService = game:GetService("TweenService")

local Looks = {}

-- Faces ---------------------------------------------------------------------------
-- Eyes, brows and a mouth made of Frames on a SurfaceGui over the front of the head.
-- eye: { width, height, tilt } in face fractions and degrees (tilt mirrors on the right eye);
-- "x" draws crossed-out eyes. brow: degrees, positive = pulled down in the middle (angry),
-- negative = raised in the middle (worried). mouth: { width, height }, teeth = gritted.
local FACES = {
	calm = { eye = { 0.085, 0.15, 0 }, brow = 0, mouth = { 0.2, 0.028 } },
	hurt = { eye = { 0.12, 0.035, 22 }, brow = -16, mouth = { 0.17, 0.13 } }, -- eyes screwed shut, shouting
	scared = { eye = { 0.1, 0.16, 0 }, brow = -22, browLift = 0.04, mouth = { 0.09, 0.1 } },
	angry = { eye = { 0.08, 0.09, 0 }, brow = 20, mouth = { 0.22, 0.07 }, teeth = true },
	dizzy = { eye = { 0.1, 0.05, -8 }, brow = -8, mouth = { 0.08, 0.07 } },
	out = { eye = { 0.11, 0.022, 0 }, brow = 0, mouth = { 0.14, 0.025 } },
	dead = { eye = "x", brow = 0, mouth = { 0.16, 0.025 } },
}
local INK = Color3.fromRGB(25, 22, 30)
local EYE_Y, BROW_Y, MOUTH_Y = 0.46, 0.33, 0.72

local function frame(parent: Instance, name: string, round: boolean): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = INK
	f.BorderSizePixel = 0
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
	end
	f.Parent = parent
	return f
end

local FACE_LIFT = 1.14
-- Swap a new-avatar dynamic head (modelled eyes that blink on their own, FaceControls) for the
-- classic smooth head: plain skin, so the only eyes are the drawn ones below. Its attachments move
-- over, so the neck joint and the ragdoll's socket keep working. Returns the new head.
function Looks.plainHead(model: Model): BasePart
	local old = model:FindFirstChild("Head") :: BasePart
	if not old:IsA("MeshPart") then
		return old
	end
	local head = Instance.new("Part")
	head.Name = "Head"
	-- the part a touch deeper than the mesh in it: the drawn face (a SurfaceGui on the part's front)
	-- then sits just in front of the rounded skin instead of inside it
	head.Size = old.Size * Vector3.new(1, 1, FACE_LIFT)
	head.Color = old.Color
	head.Material = Enum.Material.SmoothPlastic
	head.CFrame = old.CFrame
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head -- the rounded classic head, filling the part
	mesh.Scale = Vector3.new(1, 1, 1 / FACE_LIFT)
	mesh.Parent = head
	for _, child in old:GetChildren() do
		if child:IsA("Attachment") or child:IsA("Constraint") or child:IsA("Vector3Value") then
			child.Parent = head
		end
	end
	for _, c in model:GetDescendants() do
		if c:IsA("NoCollisionConstraint") then
			if c.Part0 == old then c.Part0 = head end
			if c.Part1 == old then c.Part1 = head end
		end
	end
	old:Destroy()
	head.Parent = model
	return head
end

-- Replace the head's stock face with the drawn one.
function Looks.buildFace(head: BasePart)
	for _, child in head:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
	if head:IsA("MeshPart") then
		head.TextureID = "" -- new heads have the stock face painted into the texture
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(200, 200)
	gui.LightInfluence = 1
	for _, side in { "L", "R" } do
		frame(gui, "Eye" .. side, true)
		frame(gui, "Brow" .. side, false)
		local cross = frame(gui, "Cross" .. side, false) -- one bar of the X; its child is the other
		frame(cross, "Bar", false)
	end
	local mouth = frame(gui, "Mouth", true)
	local teeth = frame(mouth, "Teeth", false)
	teeth.BackgroundColor3 = Color3.new(1, 1, 1)
	teeth.Position = UDim2.fromScale(0.5, 0.5)
	teeth.Size = UDim2.fromScale(0.86, 0.5)
	gui.Parent = head
	Looks.face(head.Parent :: Model, "calm")
end

function Looks.face(model: Model, name: string)
	local head = model:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("Face")
	local look = FACES[name]
	if not gui or not look or gui:GetAttribute("Look") == name then
		return
	end
	gui:SetAttribute("Look", name)
	local crossed = look.eye == "x"
	for i, side in { "L", "R" } do
		local x = i == 1 and 0.34 or 0.66
		local mirror = i == 1 and 1 or -1
		local eye, brow, cross = gui["Eye" .. side], gui["Brow" .. side], gui["Cross" .. side]
		eye.Visible = not crossed
		cross.Visible = crossed
		if crossed then
			cross.Position = UDim2.fromScale(x, EYE_Y)
			cross.Size = UDim2.fromScale(0.13, 0.03)
			cross.Rotation = 45
			cross.Bar.Position = UDim2.fromScale(0.5, 0.5)
			cross.Bar.Size = UDim2.fromScale(1, 1)
			cross.Bar.Rotation = 90
		else
			eye.Position = UDim2.fromScale(x, EYE_Y)
			eye.Size = UDim2.fromScale(look.eye[1], look.eye[2])
			eye.Rotation = look.eye[3] * mirror
		end
		brow.Position = UDim2.fromScale(x, BROW_Y - (look.browLift or 0))
		brow.Size = UDim2.fromScale(0.17, 0.034)
		brow.Rotation = look.brow * mirror
	end
	gui.Mouth.Position = UDim2.fromScale(0.5, MOUTH_Y)
	gui.Mouth.Size = UDim2.fromScale(look.mouth[1], look.mouth[2])
	gui.Mouth.Teeth.Visible = look.teeth == true
end

-- Posture ---------------------------------------------------------------------------
-- A lean added on top of whatever animation plays, by turning a joint's C0 about its own pivot.
-- pose = { Waist = Vector3(pitch, yaw, roll), Neck = ... } in radians; pitch < 0 bends forward.
-- A joint left out goes back to straight.
local LEAN = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

function Looks.posture(model: Model, pose: { [string]: Vector3 })
	for _, name in { "Waist", "Neck" } do
		-- classic rigs join the parts with a Motor6D (its C0 is the pivot on the lower part), new
		-- avatar rigs with an AnimationConstraint between two attachments (Attachment0 is that pivot)
		local joint = model:FindFirstChild(name, true)
		local pivot: Instance?, prop = nil, "CFrame"
		if joint and joint:IsA("Motor6D") then
			pivot, prop = joint, "C0"
		elseif joint and joint:IsA("AnimationConstraint") then
			pivot = joint.Attachment0
		end
		if not pivot then
			continue
		end
		local base = pivot:GetAttribute("Base")
		if not base then
			base = (pivot :: any)[prop]
			pivot:SetAttribute("Base", base)
		end
		local angles = pose[name] or Vector3.zero
		TweenService:Create(pivot, LEAN, { [prop] = base * CFrame.Angles(angles.X, angles.Y, angles.Z) }):Play()
	end
end

return Looks
