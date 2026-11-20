local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Definitions = require(ReplicatedStorage.Shared.Mythology)
local Rig = require(ReplicatedStorage.Shared.MythRig)
local Sfx = require(ReplicatedStorage.Shared:WaitForChild("Sfx"))
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
	boss.Size, boss.BackgroundColor3, boss.BackgroundTransparency = UDim2.new(0.62, 0, 0, 66), Color3.fromRGB(22, 24, 29), 0.1
	boss.Visible, boss.Parent = false, container
	local cap = Instance.new("UISizeConstraint"); cap.MaxSize = Vector2.new(520, 66); cap.Parent = boss
	round(boss, 9)
	local title = label(boss, "Title", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 3), 15)
	local hint = label(boss, "Hint", UDim2.new(1, -16, 0, 19), UDim2.fromOffset(8, 40), 11)
	hint.TextScaled = true
	local textCap = Instance.new("UITextSizeConstraint"); textCap.MaxTextSize, textCap.MinTextSize, textCap.Parent = 11, 8, hint
	local track = Instance.new("Frame")
	track.Name, track.Position, track.Size = "HealthTrack", UDim2.fromOffset(12, 29), UDim2.new(1, -24, 0, 7)
	track.BackgroundColor3, track.BorderSizePixel, track.Parent = Color3.fromRGB(56, 57, 61), 0, boss
	round(track, 4)
	local fill = track:Clone(); fill.Name, fill.Position, fill.Size, fill.Parent = "Health", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), track
	local progress = label(container, "MythProgress", UDim2.fromOffset(195, 45), UDim2.fromOffset(14, 130), 12)
	progress.TextXAlignment, progress.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
	local toast = label(container, "Reward", UDim2.new(0.9, 0, 0, 42), UDim2.new(0.5, 0, 0.3, 0), 21)
	toast.AnchorPoint, toast.Visible = Vector2.new(0.5, 0), false
	local ammo = Instance.new("TextLabel") -- the bow's draw meter
	ammo.Name, ammo.AnchorPoint, ammo.Position = "BowDraw", Vector2.new(1, 1), UDim2.new(1, -18, 1, -175)
	ammo.Size, ammo.BackgroundColor3, ammo.BackgroundTransparency = UDim2.fromOffset(128, 55), Color3.fromRGB(22, 24, 29), 0.18
	ammo.Font, ammo.TextColor3, ammo.TextSize, ammo.Parent = Enum.Font.GothamBold, Color3.new(1, 1, 1), 16, container
	round(ammo, 8)
	local feedback = label(container, "ConfirmedHit", UDim2.fromOffset(100, 36), UDim2.new(0.5, 0, 0.5, 25), 17)
	feedback.AnchorPoint, feedback.Visible = Vector2.new(0.5, 0), false
	local hitUntil, toastUntil = 0, 0
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
			if kind == "Hit" then
				hitUntil = os.clock() + 0.4
				feedback.Text, feedback.TextColor3 = (c and "WEAK POINT  " or "+") .. tostring(b), c and Color3.fromRGB(255, 206, 76) or Color3.new(1, 1, 1)
			elseif kind == "Reward" then
				toastUntil = os.clock() + 3
				toast.Text, toast.TextColor3 = a .. " DEFEATED   +" .. b .. " XP", Color3.fromRGB(255, 211, 96)
				Sfx.ui(Sfx.UI_NOTIFICATION, 0.7)
			elseif kind == "Impact" then
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
			if root and r and (model:GetAttribute("HP") or 0) > 0 then
				local gap = (r.Position - root.Position).Magnitude
				if gap < distance then best, distance = model, gap end
			end
		end
		boss.Visible = best ~= nil
		if best then
			local def = Definitions[best:GetAttribute("MonsterKind")]
			local state = best:GetAttribute("MonsterState")
			title.Text = def.name .. "   " .. math.ceil(best:GetAttribute("HP")) .. " / " .. def.hp
			hint.Text = state == "Caged" and "Press Y at the pedestal to start" or state == "Windup" and def.attack .. "!  MOVE OUT OF THE MARKER" or state == "Recovery" and "EXPOSED!  +50% DAMAGE" or state == "Stunned" and "STUNNED!  ATTACK NOW" or def.hint
			fill.Size, fill.BackgroundColor3 = UDim2.fromScale(math.clamp(best:GetAttribute("HP") / def.hp, 0, 1), 1), def.accent
		end
		local kills, xp = player:GetAttribute("MonsterKills") or 0, player:GetAttribute("MythXP") or 0
		local inYard = root and root.Position.Z < -80 and math.abs(root.Position.X) < 100 and root.Position.X < 250
		progress.Visible = inYard == true
		progress.Text = "MYTH HUNT   " .. xp .. " XP\nNext medal: " .. kills .. " / " .. (math.floor(kills / 3) + 1) * 3 .. " defeats"
		local weapon = api.weapon()
		ammo.Visible = weapon.kind == "bow"
		if weapon.kind == "bow" and char then
			local drawAt = char:GetAttribute("LocalBowDrawAt")
			local power = drawAt and math.clamp((now - drawAt) / 1.1, 0, 1) or 0
			ammo.Text, ammo.TextColor3 = math.floor(power * 100) .. "% DRAW\nHOLD / RELEASE", power >= 1 and Color3.fromRGB(255, 206, 76) or Color3.new(1, 1, 1)
		end
		feedback.Visible, toast.Visible = os.clock() < hitUntil, os.clock() < toastUntil
	end)
end
return Presentation
