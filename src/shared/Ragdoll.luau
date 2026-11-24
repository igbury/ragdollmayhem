-- R15 ragdoll: joint drive <-> physics constraints toggle. Constraints are prebuilt (disabled) in setup().
local Players = game:GetService("Players")

local Ragdoll = {}

local DOWN = CFrame.Angles(0, 0, -math.pi / 2) -- attachment X axis along the limb (down)
local UP = CFrame.Angles(0, 0, math.pi / 2)

-- [motor name] = { kind, axis rotation, cone/lower angle, twist/upper angle, friction torque }
-- Friction is the muscle tone left in a limp body: limbs swing and flop but stop instead of
-- wobbling forever, so a body at rest goes to sleep (no physics, nothing to replicate).
-- Calibration knob: roughly a fifth of the torque gravity puts on what hangs off the joint.
local JOINTS = {
	Neck = { "Ball", UP, 55, 60, 12 },
	Waist = { "Ball", UP, 40, 35, 40 },
	LeftShoulder = { "Ball", DOWN, 150, 90, 14 },
	RightShoulder = { "Ball", DOWN, 150, 90, 14 },
	LeftElbow = { "Hinge", nil, 0, 150, 7 },
	RightElbow = { "Hinge", nil, 0, 150, 7 },
	LeftWrist = { "Ball", DOWN, 50, 30, 3 },
	RightWrist = { "Ball", DOWN, 50, 30, 3 },
	LeftHip = { "Ball", DOWN, 95, 40, 25 },
	RightHip = { "Ball", DOWN, 95, 40, 25 },
	LeftKnee = { "Hinge", nil, -150, 0, 12 },
	RightKnee = { "Hinge", nil, -150, 0, 12 },
	LeftAnkle = { "Ball", DOWN, 40, 25, 4 },
	RightAnkle = { "Ball", DOWN, 40, 25, 4 },
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
			joint.MaxFrictionTorque = spec[5]
		else
			joint = Instance.new("HingeConstraint")
			joint.LimitsEnabled = true
			joint.LowerAngle = spec[3]
			joint.UpperAngle = spec[4]
			-- a hinge has no friction setting: a weak motor told to stand still is one
			joint.ActuatorType = Enum.ActuatorType.Motor
			joint.AngularVelocity = 0
			joint.MotorMaxTorque = spec[5]
		end
		joint.Name = "RagJoint"
		joint:SetAttribute("Joint", motor.Name) -- which motor it stands in for (see Ragdoll.joints)
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

-- Let only the named joints go limp (or drive them again) on a body that is otherwise up and
-- animated: an arm that hangs and swings after a hit, a head that snaps back. Does nothing while
-- the whole body is ragdolled; set() switches every joint, so limp ones are re-applied after it.
function Ragdoll.joints(model: Model, names: { string }, limp: boolean)
	if model:GetAttribute("Ragdolled") then
		return
	end
	for _, d in model:GetDescendants() do
		if d:GetAttribute("Splint") then
			continue -- held by a cast (server Body.splint): welded, neither driven nor limp
		elseif (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and table.find(names, d.Name) then
			d.Enabled = not limp
		elseif d.Name == "RagJoint" and d:IsA("Constraint") and table.find(names, d:GetAttribute("Joint")) then
			d.Enabled = limp
		end
	end
end

function Ragdoll.set(model: Model, on: boolean)
	if (model:GetAttribute("Ragdolled") == true) == on then
		return
	end
	for _, d in model:GetDescendants() do
		-- Motor6D = classic rigs; AnimationConstraint = new avatar joints, which already ship
		-- their own limited BallSocketConstraints, so disabling the drive is enough.
		if d:GetAttribute("Splint") then
			continue -- held by a cast (server Body.splint)
		elseif (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and JOINTS[d.Name] then
			d.Enabled = not on
		elseif d.Name == "RagJoint" and d:IsA("Constraint") then
			d.Enabled = on
		elseif d:IsA("BasePart") and d:GetAttribute("RagCollide") ~= nil then
			d.CanCollide = on or d:GetAttribute("RagCollide")
		end
	end
	-- The root is a big invisible box welded to the hips, and the heaviest part of the rig: while
	-- limp it neither collides nor weighs anything, or the hips swing as if they carried a brick.
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CanCollide = not on
		root.Massless = on
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
