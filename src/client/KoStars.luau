-- Stars circling over a dummy that is out cold (server: State "Out cold"), so a knocked-out dummy
-- does not pass for a dead one: it gets back up, a dead one does not.
local RunService = game:GetService("RunService")

local STARS = 3
local RADIUS = 22 -- px, round the head
local SPIN = 4 -- rad/s

local shown: { [Model]: BillboardGui } = {}

local function update(model: Model)
	local out = model:GetAttribute("State") == "Out cold"
	local gui = shown[model]
	if out and not gui then
		local head = model:FindFirstChild("Head") :: BasePart?
		if not head then
			return
		end
		gui = Instance.new("BillboardGui")
		gui.Name, gui.Size, gui.StudsOffset, gui.AlwaysOnTop = "KoStars", UDim2.fromOffset(70, 40), Vector3.new(0, 1, 0), false
		gui.Adornee, gui.MaxDistance = head, 120
		for i = 1, STARS do
			local star = Instance.new("TextLabel")
			star.Name, star.Text, star.TextSize, star.Font = "Star", "★", 22, Enum.Font.GothamBold
			star.TextColor3, star.TextStrokeTransparency, star.BackgroundTransparency = Color3.fromRGB(255, 220, 60), 0, 1
			star.AnchorPoint, star.Size, star.LayoutOrder = Vector2.new(0.5, 0.5), UDim2.fromOffset(20, 20), i
			star.Parent = gui
		end
		gui.Parent = head
		shown[model] = gui
	elseif not out and gui then
		gui:Destroy()
		shown[model] = nil
	end
end

local function watch(model: Instance)
	if model:IsA("Model") then
		update(model)
		model:GetAttributeChangedSignal("State"):Connect(function()
			update(model)
		end)
	end
end

local dummies = workspace:WaitForChild("Dummies")
for _, model in dummies:GetChildren() do
	watch(model)
end
dummies.ChildAdded:Connect(watch)
dummies.ChildRemoved:Connect(function(model)
	shown[model :: Model] = nil
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock() * SPIN
	for model, gui in shown do
		if not gui.Parent then
			shown[model] = nil
			continue
		end
		for _, star in gui:GetChildren() do
			local a = t + (star.LayoutOrder - 1) / STARS * math.pi * 2
			star.Position = UDim2.new(0.5, math.cos(a) * RADIUS, 0.5, math.sin(a) * RADIUS * 0.4)
		end
	end
end)

return {}
