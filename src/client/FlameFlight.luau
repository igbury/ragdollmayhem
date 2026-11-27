-- Flame On's flight (shared/Weapons FlameOn): the double jump with Flame On out starts it, a double jump
-- in the air stops it (init.client jumpPressed). Superman style: the body lies along where it flies,
-- chest down, and goes where the camera looks (W/S along the look, A/D across it); with no keys held it
-- hovers upright. The Humanoid stands aside (PlatformStand) while a LinearVelocity and an
-- AlignOrientation on the root fly it; init.client's own movement (updateWallRun) skips while `active`.
-- It ends by itself when Flame On is put away, the body ragdolls or dies, or sits in a vehicle.
-- The server hears of it ("flameFly"): no fire punch while flying (server/Specials flameOn).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local actionRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action")

local SPEED = 70 -- studs/s
local TURN = 18 -- AlignOrientation responsiveness
local ACCEL = 6 -- how fast the velocity follows the keys (per s)

local FlameFlight = { active = false }

-- the keys / stick as (right, forward) against the camera; MoveDirection still follows them while
-- PlatformStand (this place has no PlayerModule to ask; init.client pressed() reads it the same way)
local function moveVector(humanoid: Humanoid, cam: CFrame): (number, number)
	local right = cam.RightVector
	local move = humanoid.MoveDirection
	return move:Dot(right), move:Dot(Vector3.yAxis:Cross(right))
end

local state -- { char, humanoid, root, attachment, velocity, align, step }

function FlameFlight.stop()
	local s = state
	if not s then
		return
	end
	state, FlameFlight.active = nil, false
	s.step:Disconnect()
	s.attachment:Destroy() -- the movers go with it
	if s.humanoid.Parent then
		s.humanoid.PlatformStand = false
		s.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if s.root.Parent and not s.char:GetAttribute("Ragdolled") then -- stand back up, facing the way we lay
		local look = s.root.CFrame.UpVector * Vector3.new(1, 0, 1)
		look = if look.Magnitude > 0.1 then look.Unit else s.root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.1 then
			s.root.CFrame = CFrame.lookAlong(s.root.Position, look)
		end
	end
	actionRemote:FireServer("flameFly", false)
end

function FlameFlight.start(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if state or not humanoid or not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlameFlight"
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = root.AssemblyLinearVelocity * 0.5
	velocity.Parent = attachment
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = math.huge
	align.Responsiveness = TURN
	align.CFrame = root.CFrame.Rotation
	align.Parent = attachment
	attachment.Parent = root
	humanoid.PlatformStand = true
	local s = { char = char, humanoid = humanoid, root = root, attachment = attachment }
	s.step = RunService.Heartbeat:Connect(function(dt)
		if not root.Parent or humanoid.Health <= 0 or humanoid.SeatPart or char:GetAttribute("Ragdolled")
			or char:GetAttribute("EquippedWeapon") ~= "FlameOn" then
			FlameFlight.stop()
			return
		end
		local cam = workspace.CurrentCamera.CFrame
		local x, z = moveVector(humanoid, cam)
		local want = cam.LookVector * z + cam.RightVector * x
		want = if want.Magnitude > 1 then want.Unit else want
		velocity.VectorVelocity = velocity.VectorVelocity:Lerp(want * SPEED, math.min(dt * ACCEL, 1))
		if want.Magnitude > 0.2 then -- lying along the flight, head first, chest down
			align.CFrame = CFrame.lookAlong(Vector3.zero, want.Unit, cam.UpVector) * CFrame.Angles(-math.pi / 2, 0, 0)
		else -- hovering: upright, facing the camera's way
			local flat = cam.LookVector * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.1 then
				align.CFrame = CFrame.lookAlong(Vector3.zero, flat.Unit)
			end
		end
	end)
	state, FlameFlight.active = s, true
	actionRemote:FireServer("flameFly", true)
end

return FlameFlight
