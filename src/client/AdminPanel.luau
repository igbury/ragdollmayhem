-- Admin panel, the client side (server/Admin decides who is an admin and does everything). Styled
-- like Grow an Egg's panels: dark wood, a green header, a round red close button, FredokaOne with
-- black outlines, chunky rounded buttons. An ADMIN button in the top-left corner opens it, for
-- admins only (player attribute "Admin"), or F2. While it is open the cursor is free (as with the toolbox).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin", math.huge) :: RemoteEvent -- made late, after the maps (server/Admin)

-- Grow an Egg palette
local PANEL = Color3.fromRGB(58, 44, 34)
local PANEL_BORDER = Color3.fromRGB(122, 84, 48)
local ROW = Color3.fromRGB(78, 60, 46)
local TEXT = Color3.fromRGB(250, 245, 235)
local MUTED = Color3.fromRGB(230, 215, 190)
local GREEN = Color3.fromRGB(86, 160, 52)
local RED = Color3.fromRGB(240, 60, 55)
local TEAL = Color3.fromRGB(40, 170, 150)
local PURPLE = Color3.fromRGB(170, 70, 255)
local BLUE = Color3.fromRGB(70, 140, 255)
local GOLD = Color3.fromRGB(255, 200, 60)
local FONT = Enum.Font.FredokaOne
local SIZE = Vector2.new(600, 470)

local function round(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius, c.Parent = UDim.new(0, radius), parent
end
local function stroke(parent: Instance, thickness: number, color: Color3?, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Thickness, s.Color = thickness, color or Color3.new(0, 0, 0)
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
	return s
end
local function text(parent: Instance, value: string, size: number, color: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency, t.Font, t.Text, t.TextSize = 1, FONT, value, size
	t.TextColor3, t.TextStrokeTransparency, t.Parent = color or TEXT, 1, parent
	stroke(t, if size >= 24 then 2.5 else 1.5)
	return t
end
local function pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	scale.Scale = 0.88
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end
local function button(parent: Instance, label: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text, b.AutoButtonColor, b.BackgroundColor3, b.LayoutOrder = "", true, color, order
	b.Parent = parent
	round(b, 8)
	stroke(b, 1.5, nil, true)
	local t = text(b, label, 17)
	t.Name, t.Size, t.TextWrapped = "Label", UDim2.fromScale(1, 1), true
	b.Activated:Connect(function()
		pop(b)
		onClick()
	end)
	return b
end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder, gui.Enabled = "AdminPanel", false, 25, false

-- the ADMIN button, top left
local open = Instance.new("TextButton")
open.Text, open.AutoButtonColor, open.BackgroundColor3 = "", true, RED
open.Position, open.Size, open.Parent = UDim2.fromOffset(16, 8), UDim2.fromOffset(92, 36), gui
round(open, 8)
stroke(open, 1.5, nil, true)
local openLabel = text(open, "ADMIN", 20)
openLabel.Size = UDim2.fromScale(1, 1)

-- the panel
local panel = Instance.new("Frame")
panel.AnchorPoint, panel.Position, panel.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(SIZE.X, SIZE.Y)
panel.BackgroundColor3, panel.Visible, panel.Parent = PANEL, false, gui
round(panel, 12)
stroke(panel, 3, PANEL_BORDER, true)
local fit = Instance.new("UIScale") -- the design size, shrunk to fit a phone
fit.Parent = panel
local header = Instance.new("Frame")
header.BackgroundColor3, header.Size, header.Parent = GREEN, UDim2.new(1, 0, 0, 52), panel
round(header, 12)
local headerFill = Instance.new("Frame") -- squares off the header's bottom corners
headerFill.BackgroundColor3, headerFill.BorderSizePixel = GREEN, 0
headerFill.Position, headerFill.Size, headerFill.Parent = UDim2.new(0, 0, 1, -12), UDim2.new(1, 0, 0, 12), header
local title = text(header, "Admin Panel", 28)
title.Size = UDim2.fromScale(1, 1)
local close = Instance.new("TextButton")
close.Text, close.AutoButtonColor, close.BackgroundColor3 = "", true, RED
close.AnchorPoint, close.Position, close.Size, close.Parent = Vector2.new(0.5, 0.5), UDim2.new(1, -8, 0, 8), UDim2.fromOffset(44, 44), panel
round(close, 22)
stroke(close, 2, nil, true)
local x = text(close, "X", 24)
x.Size = UDim2.fromScale(1, 1)

local scroll = Instance.new("ScrollingFrame")
scroll.BackgroundTransparency, scroll.BorderSizePixel = 1, 0
scroll.Position, scroll.Size = UDim2.fromOffset(14, 62), UDim2.new(1, -28, 1, -112)
scroll.CanvasSize, scroll.AutomaticCanvasSize, scroll.ScrollBarThickness = UDim2.new(), Enum.AutomaticSize.Y, 6
scroll.ScrollBarImageColor3, scroll.Parent = PANEL_BORDER, panel
local list = Instance.new("UIListLayout")
list.Padding, list.SortOrder, list.Parent = UDim.new(0, 8), Enum.SortOrder.LayoutOrder, scroll

local status = text(panel, "Pick something.", 18, MUTED)
status.AnchorPoint, status.Position, status.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12), UDim2.new(1, -28, 0, 28)
local statusBack = Instance.new("Frame")
statusBack.BackgroundColor3, statusBack.ZIndex, statusBack.Parent = ROW, 0, panel
statusBack.AnchorPoint, statusBack.Position, statusBack.Size = status.AnchorPoint, status.Position, status.Size
round(statusBack, 8)

local order = 0
-- a section: its name, then a grid of buttons
local function section(name: string, columns: number): Frame
	order += 1
	local head = text(scroll, name, 20, MUTED)
	head.Size, head.TextXAlignment, head.LayoutOrder = UDim2.new(1, 0, 0, 24), Enum.TextXAlignment.Left, order
	order += 1
	local grid = Instance.new("Frame")
	grid.BackgroundColor3, grid.Size, grid.AutomaticSize, grid.LayoutOrder = ROW, UDim2.fromScale(1, 0), Enum.AutomaticSize.Y, order
	grid.Parent = scroll
	round(grid, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.CellSize, layout.CellPadding = UDim2.new(1 / columns, -8, 0, 42), UDim2.fromOffset(8, 8)
	layout.SortOrder, layout.Parent = Enum.SortOrder.LayoutOrder, grid
	return grid
end
local function ask(action: string, arg: any?)
	status.Text = "..."
	remote:FireServer(action, arg)
end

local you = section("You", 3)
button(you, "Unlock all weapons", GREEN, 1, function() ask("weapons") end)
button(you, "God mode", TEAL, 2, function() ask("god") end)
button(you, "Super speed", TEAL, 3, function() ask("speed") end)
button(you, "Heal", GREEN, 4, function() ask("heal") end)
button(you, "Reset kills and stats", RED, 5, function() ask("reset") end)

local wanted = section("Wanted level", 6)
for stars = 0, 5 do
	button(wanted, if stars == 0 then "None" else string.rep("★", stars), if stars == 0 then GREEN else GOLD, stars, function()
		ask("wanted", stars)
	end)
end

local passes = section("Game passes (give or take away, for testing)", 3)
for i, item in Shop.PASSES do
	local b = button(passes, item.name, PURPLE, i, function() ask("pass", item.key) end)
	local label = b:FindFirstChild("Label") :: TextLabel
	local function show()
		local owned = player:GetAttribute(Shop.attribute(item.key)) == true
		b.BackgroundColor3 = if owned then GREEN else PURPLE
		label.Text = (if owned then "✓ " else "") .. item.name
	end
	show()
	player:GetAttributeChangedSignal(Shop.attribute(item.key)):Connect(show)
end

local crowd = section("Dummies", 3)
button(crowd, "Spawn 5", GREEN, 1, function() ask("spawn") end)
button(crowd, "Spawn 5 zombies", TEAL, 2, function() ask("zombies") end)
button(crowd, "Spawn 3 soldiers", BLUE, 3, function() ask("soldiers") end)
button(crowd, "Everyone fights", PURPLE, 4, function() ask("brawl") end)
button(crowd, "Revive all", GREEN, 5, function() ask("reviveall") end)
button(crowd, "Drop them all", RED, 6, function() ask("killall") end)
button(crowd, "Remove all", RED, 7, function() ask("removeall") end)

local world = section("World", 3)
button(world, "Stop / start time", BLUE, 1, function() ask("freeze") end)

remote.OnClientEvent:Connect(function(message: string)
	status.Text = message
	pop(status)
end)

local function setOpen(on: boolean)
	panel.Visible = on
	local hud = player.PlayerGui:FindFirstChild("RagdollHud")
	local toolbox = hud and hud:FindFirstChild("Toolbox") :: GuiObject?
	if hud and not (toolbox and toolbox.Visible) then -- the toolbox open has the cursor already
		hud:SetAttribute("WeaponPickerOpen", on) -- frees the cursor and stops attacks (client init, WeaponBar)
	end
	UIS.MouseIconEnabled = on or (hud ~= nil and hud:GetAttribute("WeaponPickerOpen") == true)
	if on then
		local camera = workspace.CurrentCamera
		local view = camera and camera.ViewportSize or SIZE
		fit.Scale = math.min(1, view.X * 0.94 / SIZE.X, view.Y * 0.86 / SIZE.Y)
		local target = fit.Scale
		fit.Scale = target * 0.6
		TweenService:Create(fit, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target }):Play()
	end
end
open.Activated:Connect(function()
	pop(open)
	setOpen(not panel.Visible)
end)
close.Activated:Connect(function()
	setOpen(false)
end)
UIS.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.F2 and gui.Enabled and not UIS:GetFocusedTextBox() then
		setOpen(not panel.Visible)
	end
end)

local function showAdmin()
	gui.Enabled = player:GetAttribute("Admin") == true
	if not gui.Enabled then
		setOpen(false)
	end
end
showAdmin()
player:GetAttributeChangedSignal("Admin"):Connect(showAdmin)
gui.Parent = player:WaitForChild("PlayerGui")

return {}
