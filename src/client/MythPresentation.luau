local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Definitions = require(ReplicatedStorage.Shared.Mythology)
local Rig = require(ReplicatedStorage.Shared.MythRig)
local Presentation = {}
local function label(parent, name, size, position, textSize)
	local l = Instance.new("TextLabel")
	l.Name, l.Size, l.Position = name, size, position
	l.BackgroundTransparency, l.Font, l.TextSize = 1, Enum.Font.GothamBold, textSize
	l.TextColor3, l.TextStrokeTransparency, l.Text = Color3.new(1, 1, 1), 0.5, ""
	l.Parent = parent
	return l
end
local function round(p, radius)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, radius); c.Parent = p
end
function Presentation.start(gui, remotes, api)
	local player = Players.LocalPlayer
	local container = Instance.new("Frame")
	container.Name, container.Size, container.BackgroundTransparency = "MythHUD", UDim2.fromScale(1, 1), 1
	container.Parent = gui
	local boss = Instance.new("Frame")
	boss.Name, boss.AnchorPoint, boss.Position = "Encounter", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 65)
	boss.Size, boss.BackgroundColor3, boss.BackgroundTransparency = UDim2.new(0.62, 0, 0, 50), Color3.fromRGB(22, 24, 29), 0.1
	boss.Visible, boss.Parent = false, container
	local cap = Instance.new("UISizeConstraint"); cap.MaxSize = Vector2.new(520, 50); cap.Parent = boss
	round(boss, 9)
	local title = label(boss, "Title", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 3), 15)
	local hint = label(boss, "Hint", UDim2.new(1, -16, 0, 19), UDim2.fromOffset(8, 26), 11)
	hint.TextScaled = true
	local textCap = Instance.new("UITextSizeConstraint"); textCap.MaxTextSize, textCap.MinTextSize, textCap.Parent = 11, 8, hint
	local ammo = Instance.new("TextLabel") -- the bow's draw meter
	ammo.Name, ammo.AnchorPoint, ammo.Position = "BowDraw", Vector2.new(1, 1), UDim2.new(1, -18, 1, -175)
	ammo.Size, ammo.BackgroundColor3, ammo.BackgroundTransparency = UDim2.fromOffset(128, 55), Color3.fromRGB(22, 24, 29), 0.18
	ammo.Font, ammo.TextColor3, ammo.TextSize, ammo.Parent = Enum.Font.GothamBold, Color3.new(1, 1, 1), 16, container
	round(ammo, 8)
	local actors, folder = {}, nil
	local function watch(model)
		if not model:IsA("Model") then return end
		local kind = model:GetAttribute("MonsterKind")
		if not Definitions[kind] then return end
		local joints = {}
		local function add(obj) if obj:IsA("Motor6D") then joints[obj.Name] = obj end end
		for _, obj in model:GetDescendants() do add(obj) end
		local changed = model.DescendantAdded:Connect(add)
		local ring = Instance.new("Part")
		ring.Name, ring.Shape, ring.Size = "AttackWarning", Enum.PartType.Cylinder, Vector3.new(0.1, 1, 1)
		ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
		ring.Color, ring.Material, ring.Transparency = Definitions[kind].accent, Enum.Material.Neon, 1
		ring.Parent = workspace.CurrentCamera
		actors[model] = { kind = kind, joints = joints, ring = ring }
		model.Destroying:Connect(function() changed:Disconnect(); ring:Destroy(); actors[model] = nil end)
	end
	task.spawn(function()
		folder = workspace:WaitForChild("Monsters", 120)
		if not folder then return end
		for _, model in folder:GetChildren() do watch(model) end
		folder.ChildAdded:Connect(watch)
		folder.ChildRemoved:Connect(function(model)
			local d = actors[model]
			if d then d.ring:Destroy(); actors[model] = nil end
		end)
	end)
	task.spawn(function()
		local remote = remotes:WaitForChild("MythFx", 120)
		if not remote then return end
		remote.OnClientEvent:Connect(function(kind, a, b, c)
			if kind == "Impact" then
				if (workspace.CurrentCamera.CFrame.Position - a).Magnitude > 200 then return end
				local pulse = Instance.new("Part")
				pulse.Name, pulse.Shape = "MythImpact", Enum.PartType.Cylinder
				pulse.Anchored, pulse.CanCollide, pulse.CanQuery, pulse.CanTouch = true, false, false, false
				pulse.Material, pulse.Color, pulse.Transparency = Enum.Material.Neon, c, 0.55
				pulse.Size, pulse.CFrame = Vector3.new(0.12, 1, 1), CFrame.new(a + Vector3.yAxis * 0.04) * CFrame.Angles(0, 0, math.pi / 2)
				pulse.Parent = workspace.CurrentCamera
				TweenService:Create(pulse, TweenInfo.new(0.35), { Size = Vector3.new(0.12, b * 2, b * 2), Transparency = 1 }):Play()
				Debris:AddItem(pulse, 0.4)
			end
		end)
	end)
	local nextHud = 0
	RunService.PreSimulation:Connect(function()
		local now = workspace:GetServerTimeNow()
		for model, data in actors do
			local state = model:GetAttribute("MonsterState")
			if not model:GetAttribute("Ragdolled") then
				local since, untilTime = model:GetAttribute("StateSince") or now, model:GetAttribute("StateUntil") or now
				local phase = math.clamp((now - since) / math.max(untilTime - since, 0.01), 0, 1)
				Rig.pose(data.joints, state, data.kind, now, model:GetAttribute("Moving") or 0, phase, math.clamp(1 - (now - (model:GetAttribute("HurtAt") or 0)) / 0.3, 0, 1))
				local impact = model:GetAttribute("ImpactAt")
				if state == "Windup" and impact then
					local radius = Definitions[data.kind].radius
					data.ring.Size = Vector3.new(0.08, radius * 2, radius * 2)
					data.ring.CFrame = CFrame.new(impact) * CFrame.Angles(0, 0, math.pi / 2)
					if data.kind == "Minotaur" and model.PrimaryPart then
						local direction = model:GetAttribute("ChargeDirection") or model.PrimaryPart.CFrame.LookVector
						data.ring.Shape, data.ring.Size = Enum.PartType.Block, Vector3.new(12, 0.08, 36)
						local center = model.PrimaryPart.Position + direction * 18
						data.ring.CFrame = CFrame.lookAlong(Vector3.new(center.X, 0.08, center.Z), direction)
					end
					data.ring.Transparency = 0.85 - phase * 0.35
				else data.ring.Transparency = 1 end
			else data.ring.Transparency = 1 end
		end
		if os.clock() < nextHud then return end
		nextHud = os.clock() + 0.1
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local best, distance = nil, 58
		for model in actors do
			local r = model.PrimaryPart
			if root and r then
				local gap = (r.Position - root.Position).Magnitude
				if gap < distance then best, distance = model, gap end
			end
		end
		boss.Visible = best ~= nil
		if best then
			local def = Definitions[best:GetAttribute("MonsterKind")]
			local state = best:GetAttribute("MonsterState")
			title.Text, title.TextColor3 = def.name, def.accent
			hint.Text = state == "Caged" and "Press Y at the pedestal to let it out" or state == "Windup" and def.attack .. "!" or state == "Eat" and "CHOMP CHOMP" or def.hint
		end
		local weapon = api.weapon()
		ammo.Visible = weapon.kind == "bow"
		if weapon.kind == "bow" and char then
			local drawAt = char:GetAttribute("LocalBowDrawAt")
			local power = drawAt and math.clamp((now - drawAt) / 1.1, 0, 1) or 0
			ammo.Text, ammo.TextColor3 = math.floor(power * 100) .. "% DRAW\nHOLD / RELEASE", power >= 1 and Color3.fromRGB(255, 206, 76) or Color3.new(1, 1, 1)
		end
	end)
end
return Presentation
