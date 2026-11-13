-- R15 ragdoll: joint drive <-> physics constraints toggle. Constraints are prebuilt (disabled) in setup().
local Players = game:GetService("Players")

local Ragdoll = {}

local DOWN = CFrame.Angles(0, 0, -math.pi / 2) -- attachment X axis along the limb (down)
local UP = CFrame.Angles(0, 0, math.pi / 2)

-- [motor name] = { kind, axis rotation, cone/lower angle, twist/upper angle }
local JOINTS = {
	Neck = { "Ball", UP, 55, 60 },
	Waist = { "Ball", UP, 40, 35 },
	LeftShoulder = { "Ball", DOWN, 150, 90 },
	RightShoulder = { "Ball", DOWN, 150, 90 },
	LeftElbow = { "Hinge", nil, 0, 150 },
	RightElbow = { "Hinge", nil, 0, 150 },
	LeftWrist = { "Ball", DOWN, 50, 30 },
	RightWrist = { "Ball", DOWN, 50, 30 },
	LeftHip = { "Ball", DOWN, 95, 40 },
	RightHip = { "Ball", DOWN, 95, 40 },
	LeftKnee = { "Hinge", nil, -150, 0 },
	RightKnee = { "Hinge", nil, -150, 0 },
	LeftAnkle = { "Ball", DOWN, 40, 25 },
	RightAnkle = { "Ball", DOWN, 40, 25 },
}

local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Exclude

function Ragdoll.setup(model: Model)
	if model:GetAttribute("RagdollReady") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
	end
	for _, motor in model:GetDescendants() do
		local spec = motor:IsA("Motor6D") and JOINTS[motor.Name]
		if not spec then
			continue
		end
		local rot = spec[2] or CFrame.identity
		local a0 = Instance.new("Attachment")
		a0.Name = "RagA0"
		a0.CFrame = motor.C0 * rot
		a0.Parent = motor.Part0
		local a1 = Instance.new("Attachment")
		a1.Name = "RagA1"
		a1.CFrame = motor.C1 * rot
		a1.Parent = motor.Part1

		local joint
		if spec[1] == "Ball" then
			joint = Instance.new("BallSocketConstraint")
			joint.LimitsEnabled = true
			joint.TwistLimitsEnabled = true
			joint.UpperAngle = spec[3]
			joint.TwistLowerAngle = -spec[4]
			joint.TwistUpperAngle = spec[4]
		else
			joint = Instance.new("HingeConstraint")
			joint.LimitsEnabled = true
			joint.LowerAngle = spec[3]
			joint.UpperAngle = spec[4]
		end
		joint.Name = "RagJoint"
		joint.Attachment0 = a0
		joint.Attachment1 = a1
		joint.Enabled = false
		joint.Parent = motor.Parent

		local noCollide = Instance.new("NoCollisionConstraint")
		noCollide.Part0 = motor.Part0
		noCollide.Part1 = motor.Part1
		noCollide.Parent = motor.Parent
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part:SetAttribute("RagCollide", part.CanCollide)
		end
	end
	model:SetAttribute("RagdollReady", true)
end

local function standUp(model: Model, humanoid: Humanoid?)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	if not (root and torso) then
		return
	end
	local facing = torso.CFrame.LookVector * Vector3.new(1, 0, 1)
	if facing.Magnitude < 0.2 then
		facing = torso.CFrame.UpVector * Vector3.new(1, 0, 1) -- lying flat: face where the head was
	end
	if facing.Magnitude < 0.01 then
		facing = Vector3.zAxis
	end
	downParams.FilterDescendantsInstances = { model }
	local origin = torso.Position + Vector3.new(0, 2, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -12, 0), downParams)
	local groundY = hit and hit.Position.Y or torso.Position.Y - 1
	local pos = Vector3.new(torso.Position.X, groundY + (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2, torso.Position.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(pos, pos + facing.Unit)
end

function Ragdoll.set(model: Model, on: boolean)
	if (model:GetAttribute("Ragdolled") == true) == on then
		return
	end
	for _, d in model:GetDescendants() do
		-- Motor6D = classic rigs; AnimationConstraint = new avatar joints, which already ship
		-- their own limited BallSocketConstraints, so disabling the drive is enough.
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and JOINTS[d.Name] then
			d.Enabled = not on
		elseif d.Name == "RagJoint" and d:IsA("Constraint") then
			d.Enabled = on
		elseif d:IsA("BasePart") and d:GetAttribute("RagCollide") ~= nil then
			d.CanCollide = on or d:GetAttribute("RagCollide")
		end
	end
	-- the root is a big invisible box: left solid, the body lies on it like a plank
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		root.CanCollide = not on
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not on then
		standUp(model, humanoid)
	end
	model:SetAttribute("Ragdolled", on)
	-- Player humanoids are driven by their own client (see client script).
	if humanoid and not Players:GetPlayerFromCharacter(model) then
		humanoid:ChangeState(on and Enum.HumanoidStateType.Physics or Enum.HumanoidStateType.GettingUp)
	end
end

return Ragdoll
