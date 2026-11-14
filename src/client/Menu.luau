-- Main menu: red-and-white tilted buttons over a blurred camera that drifts around the arena.
-- Menu.active is true until Play is pressed; the rest of the client ignores input while it is.
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local RED = Color3.fromRGB(200, 30, 40)
local DARK_RED = Color3.fromRGB(120, 15, 25)
local WHITE = Color3.fromRGB(255, 255, 255)
local CREAM = Color3.fromRGB(245, 240, 240)
local BLUR = 16
local FONT = Enum.Font.LuckiestGuy

local Menu = { active = true }

-- Sink walking input while the menu is up (no PlayerModule dependency).
ContextActionService:BindActionAtPriority("MenuSink", function()
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right)
camera.CameraType = Enum.CameraType.Scriptable

local blur = Instance.new("BlurEffect")
blur.Size = BLUR
blur.Parent = Lighting

local gui = Instance.new("ScreenGui")
gui.Name = "Menu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local function style(frame: GuiObject, stroke: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local line = Instance.new("UIStroke")
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Color = RED
	line.Thickness = stroke
	line.Parent = frame
end

local function text(parent: Instance, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = RED
	l.TextScaled = true
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- Panel for Settings / Credits --------------------------------------------------
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.62, 0.5)
panel.Size = UDim2.fromOffset(420, 300)
panel.BackgroundColor3 = WHITE
panel.Visible = false
style(panel, 5)
panel.Parent = gui
local panelTitle = text(panel, { Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 44) })
local panelBody = text(panel, {
	Position = UDim2.fromOffset(20, 66),
	Size = UDim2.new(1, -40, 1, -86),
	TextScaled = false,
	TextSize = 22,
	TextColor3 = DARK_RED,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
})

local PANELS = {
	SETTINGS = "Shift  Sprint\nQ / F  Switch weapon\nE  Grab / drop\nC  Fall\nG  Spawn dummy\nR  Revive\nV  Camera",
	CREDITS = "Ragdoll Mayhem",
}

local function showPanel(name: string)
	if panel.Visible and panelTitle.Text == name then
		panel.Visible = false
		return
	end
	panelTitle.Text = name
	panelBody.Text = PANELS[name]
	panel.Visible = true
end

-- Buttons ------------------------------------------------------------------------
local function play()
	Menu.active = false
	RunService:UnbindFromRenderStep("MenuCamera")
	TweenService:Create(blur, TweenInfo.new(0.6), { Size = 0 }):Play()
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			TweenService:Create(child, TweenInfo.new(0.4), { Position = child.Position - UDim2.fromScale(0.6, 0) }):Play()
		end
	end
	task.delay(0.6, function()
		blur:Destroy()
		gui:Destroy()
	end)
	camera.CameraType = Enum.CameraType.Custom
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	ContextActionService:UnbindAction("MenuSink")
end

-- Two button lists: the main one, and the map picker PLAY swaps in.
local lists = { main = {}, maps = {} }
local current = "main"
local function show(name: string)
	panel.Visible = false
	current = name
	for listName, list in lists do
		for i, b in list do
			local on = listName == name
			b.button.Visible = true
			b.button.BackgroundColor3 = CREAM
			b.label.TextColor3 = RED
			TweenService:Create(b.button, TweenInfo.new(0.3 + i * 0.08, on and Enum.EasingStyle.Back or Enum.EasingStyle.Quad), {
				Position = on and b.home or b.home - UDim2.fromScale(0.6, 0),
			}):Play()
		end
	end
end

local function pickMap(name: string)
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action"):FireServer("map", name)
	play()
end

local ENTRIES = {
	{ "PLAY", function() show("maps") end, "main" },
	{ "SETTINGS", showPanel, "main" },
	{ "CREDITS", showPanel, "main" },
	{ "ARENA", pickMap, "maps" },
	{ "FACTORY", pickMap, "maps" },
	{ "BACK", function() show("main") end, "maps" },
}
for _, entry in ENTRIES do
	local name, action, listName = entry[1], entry[2], entry[3]
	local list = lists[listName]
	local i = #list + 1
	local home = UDim2.new(0.04 + (i - 1) * 0.02, 0, 0.45 + (i - 1) * 0.14, 0)
	table.insert(list, { button = nil, home = home })
	local button = Instance.new("TextButton")
	button.Text = ""
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.Position = home - UDim2.fromScale(0.5, 0) -- slides in
	button.Size = UDim2.fromOffset(380, 76)
	button.Rotation = -7
	button.BackgroundColor3 = CREAM
	style(button, 5)
	local label = text(button, { Text = name, Position = UDim2.fromOffset(20, 10), Size = UDim2.new(1, -40, 1, -20), TextXAlignment = Enum.TextXAlignment.Left })
	button.Parent = gui
	list[i].button = button
	list[i].label = label
	if listName == "main" then
		TweenService:Create(button, TweenInfo.new(0.5 + i * 0.12, Enum.EasingStyle.Back), { Position = home }):Play()
	else
		button.Visible = false
	end

	local function hover(on: boolean)
		if current ~= listName then
			return -- sliding away, leave its tween alone
		end
		TweenService:Create(button, TweenInfo.new(0.15), {
			BackgroundColor3 = on and RED or CREAM,
			Position = on and home + UDim2.fromOffset(24, 0) or home,
		}):Play()
		TweenService:Create(label, TweenInfo.new(0.15), { TextColor3 = on and WHITE or RED }):Play()
	end
	button.MouseEnter:Connect(function() hover(true) end)
	button.MouseLeave:Connect(function() hover(false) end)
	button.Activated:Connect(function()
		if current ~= listName or not Menu.active then
			return
		end
		action(name)
	end)
end

-- Camera: slow loop over the arena (it is 160 studs wide) -------------------------
local start = os.clock()
RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 1, function()
	camera.CameraType = Enum.CameraType.Scriptable -- the default camera script resets it on spawn
	local t = os.clock() - start
	local pos = Vector3.new(math.cos(t * 0.12) * 60, 24 + math.sin(t * 0.3) * 5, math.sin(t * 0.12) * 60)
	local look = Vector3.new(math.sin(t * 0.2) * 20, 4, math.cos(t * 0.17) * 20)
	camera.CFrame = CFrame.lookAt(pos, look)
	camera.Focus = camera.CFrame * CFrame.new(0, 0, -100) -- far focus: not first person, no fists
end)

return Menu
