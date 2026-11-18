-- Toolbox (Tab): pick what G puts down — a character to spawn, a block to build, or the delete tool.
-- The server checks and does the spawning and building (server/init.server.luau, "build" / "spawn").
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local GRID = 4 -- block size in studs; the server builds the same size
local RANGE = 150

local SECTIONS = {
	{ name = "CHARACTERS", items = {
		{ name = "Civilian", kind = "Normal", color = Color3.fromRGB(110, 170, 90) },
		{ name = "Cop", kind = "Cop", color = Color3.fromRGB(60, 90, 160) },
		{ name = "Hooligan", kind = "Hooligan", color = Color3.fromRGB(40, 40, 44) },
		{ name = "Soldier", kind = "Soldier", color = Color3.fromRGB(96, 108, 70) },
		{ name = "Heavy", kind = "Heavy", color = Color3.fromRGB(34, 36, 42) },
	} },
	{ name = "BLOCKS", items = {
		{ name = "White", block = Color3.fromRGB(235, 235, 235), material = "SmoothPlastic" },
		{ name = "Grey", block = Color3.fromRGB(120, 122, 128), material = "Concrete" },
		{ name = "Black", block = Color3.fromRGB(30, 30, 34), material = "SmoothPlastic" },
		{ name = "Red", block = Color3.fromRGB(200, 50, 45), material = "SmoothPlastic" },
		{ name = "Orange", block = Color3.fromRGB(230, 130, 40), material = "SmoothPlastic" },
		{ name = "Yellow", block = Color3.fromRGB(240, 210, 60), material = "SmoothPlastic" },
		{ name = "Green", block = Color3.fromRGB(70, 160, 70), material = "SmoothPlastic" },
		{ name = "Blue", block = Color3.fromRGB(50, 110, 210), material = "SmoothPlastic" },
		{ name = "Wood", block = Color3.fromRGB(150, 105, 65), material = "WoodPlanks" },
		{ name = "Brick", block = Color3.fromRGB(150, 70, 55), material = "Brick" },
		{ name = "Metal", block = Color3.fromRGB(150, 155, 160), material = "DiamondPlate" },
		{ name = "Glass", block = Color3.fromRGB(170, 210, 230), material = "Glass" },
		{ name = "Neon", block = Color3.fromRGB(80, 220, 255), material = "Neon" },
	} },
	{ name = "TOOLS", items = {
		{ name = "Delete block", tool = "delete", color = Color3.fromRGB(143, 46, 44) },
		{ name = "Clear my blocks", tool = "clear", color = Color3.fromRGB(90, 40, 40) },
	} },
}

local Toolbox = {}

local function button(parent, text, color)
	local b = Instance.new("TextButton")
	b.Text, b.Font, b.TextSize, b.TextColor3 = text, Enum.Font.GothamBold, 13, Color3.new(1, 1, 1)
	b.TextStrokeTransparency, b.BackgroundColor3, b.BorderSizePixel = 0.5, color, 0
	b.TextWrapped, b.ZIndex, b.Parent = true, 43, parent
	local c = Instance.new("UICorner")
	c.CornerRadius, c.Parent = UDim.new(0, 7), b
	return b
end

-- Where a block goes for this aim: flush against a built block's face, else resting on what was hit,
-- snapped to the grid across. ponytail: Y is not snapped on map surfaces, so blocks on uneven
-- ground do not line up with blocks built on other ground; snap Y too if that matters.
local function blockSpot(result, built: Instance?): Vector3
	local n = result.Normal
	n = Vector3.new(math.round(n.X), math.round(n.Y), math.round(n.Z))
	if built and result.Instance.Parent == built then
		return result.Instance.Position + n * GRID
	end
	local p = result.Position + result.Normal * (GRID / 2)
	local function snap(v)
		return math.floor(v / GRID) * GRID + GRID / 2
	end
	return Vector3.new(n.X ~= 0 and p.X or snap(p.X), n.Y ~= 0 and p.Y or snap(p.Y), n.Z ~= 0 and p.Z or snap(p.Z))
end

-- api: the hotbar's (blocked, freeze); aim(range) -> RaycastResult. Returns use(), for G.
function Toolbox.start(gui: ScreenGui, actionRemote: RemoteEvent, api, aim)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false) -- Tab is ours

	local selected = SECTIONS[1].items[1]

	local cover = Instance.new("Frame")
	cover.Name, cover.Size = "Toolbox", UDim2.fromScale(1, 1)
	cover.BackgroundColor3, cover.BackgroundTransparency = Color3.new(0, 0, 0), 0.35
	cover.ZIndex, cover.Visible, cover.Active, cover.Parent = 40, false, true, gui
	local panel = Instance.new("Frame")
	panel.Size, panel.Position, panel.AnchorPoint = UDim2.fromScale(0.92, 0.75), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	panel.BackgroundColor3, panel.BorderSizePixel, panel.ZIndex, panel.Parent = Color3.fromRGB(22, 24, 30), 0, 41, cover
	local max = Instance.new("UISizeConstraint")
	max.MaxSize, max.Parent = Vector2.new(760, 560), panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 12), panel

	local title = button(panel, "TOOLBOX", Color3.fromRGB(143, 46, 44))
	title.Size, title.Position, title.AutoButtonColor = UDim2.new(1, -62, 0, 42), UDim2.fromOffset(8, 8), false
	title.TextXAlignment, title.TextSize = Enum.TextXAlignment.Left, 16
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.Parent = UDim.new(0, 12), title
	local close = button(panel, "X", Color3.fromRGB(45, 48, 57))
	close.Size, close.Position = UDim2.fromOffset(38, 42), UDim2.new(1, -46, 0, 8)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position, scroll.Size = UDim2.fromOffset(8, 58), UDim2.new(1, -16, 1, -66)
	scroll.BackgroundTransparency, scroll.BorderSizePixel, scroll.ScrollBarThickness, scroll.ZIndex = 1, 0, 5, 42
	scroll.CanvasSize, scroll.AutomaticCanvasSize, scroll.Parent = UDim2.new(), Enum.AutomaticSize.Y, panel
	local list = Instance.new("UIListLayout")
	list.Padding, list.SortOrder, list.Parent = UDim.new(0, 6), Enum.SortOrder.LayoutOrder, scroll

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency, hint.Font, hint.TextSize = 1, Enum.Font.GothamBold, 14
	hint.TextColor3, hint.TextStrokeTransparency = Color3.new(1, 1, 1), 0.5
	hint.AnchorPoint, hint.Position, hint.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -110), UDim2.fromOffset(360, 18)
	hint.Parent = gui

	local cards = {}
	local function refresh()
		for item, b in cards do
			local stroke = b:FindFirstChildOfClass("UIStroke")
			stroke.Enabled = item == selected
		end
		local verb = selected.kind and "spawn" or selected.block and "build" or "delete"
		hint.Text = "Tab  Toolbox   ·   G  " .. verb .. ": " .. selected.name
	end

	local function setOpen(on: boolean)
		if on == cover.Visible then
			return
		end
		if on and (api.blocked() or gui:GetAttribute("WeaponPickerOpen")) then
			return -- the main menu, dead, or the weapon wheel is up
		end
		cover.Visible = on
		gui:SetAttribute("WeaponPickerOpen", on) -- frees the cursor and stops attacks (init, WeaponBar)
		api.freeze(on)
		UIS.MouseIconEnabled = on
	end

	local order = 0
	for _, section in SECTIONS do
		order += 1
		local header = Instance.new("TextLabel")
		header.Text, header.Font, header.TextSize, header.TextColor3 = section.name, Enum.Font.GothamBold, 13, Color3.fromRGB(171, 178, 188)
		header.BackgroundTransparency, header.TextXAlignment, header.Size = 1, Enum.TextXAlignment.Left, UDim2.new(1, 0, 0, 20)
		header.LayoutOrder, header.ZIndex, header.Parent = order, 43, scroll
		order += 1
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency, grid.Size, grid.AutomaticSize = 1, UDim2.fromScale(1, 0), Enum.AutomaticSize.Y
		grid.LayoutOrder, grid.ZIndex, grid.Parent = order, 42, scroll
		local layout = Instance.new("UIGridLayout")
		layout.CellSize, layout.CellPadding, layout.SortOrder = UDim2.new(0.25, -6, 0, 52), UDim2.fromOffset(6, 6), Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for i, item in section.items do
			local b = button(grid, item.name, item.color or item.block)
			b.LayoutOrder = i
			local stroke = Instance.new("UIStroke")
			stroke.Thickness, stroke.Color, stroke.ApplyStrokeMode = 3, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border
			stroke.Parent = b
			cards[item] = b
			b.Activated:Connect(function()
				if item.tool == "clear" then
					actionRemote:FireServer("clearbuild")
				else
					selected = item
					refresh()
				end
				setOpen(false)
			end)
		end
	end
	refresh()

	close.Activated:Connect(function()
		setOpen(false)
	end)
	UIS.InputBegan:Connect(function(input, processed)
		if UIS:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab then
			setOpen(not cover.Visible)
		elseif cover.Visible and input.KeyCode == Enum.KeyCode.Escape and not processed then
			setOpen(false)
		end
	end)

	-- the block that G would build (ghost), or the built block it would delete (outline)
	local ghost = Instance.new("Part")
	ghost.Name, ghost.Size, ghost.Anchored = "BuildGhost", Vector3.one * GRID, true
	ghost.CanCollide, ghost.CanQuery, ghost.CanTouch, ghost.CastShadow = false, false, false, false
	ghost.Transparency, ghost.Material = 0.6, Enum.Material.SmoothPlastic
	local outline = Instance.new("SelectionBox")
	outline.Color3, outline.LineThickness, outline.Parent = Color3.fromRGB(230, 60, 50), 0.06, gui
	RunService.RenderStepped:Connect(function()
		local built = workspace:FindFirstChild("Built")
		local show = not cover.Visible and not api.blocked() and (selected.block or selected.tool == "delete")
		local result = show and aim(RANGE)
		hint.Visible = not api.blocked()
		if not result then
			ghost.Parent, outline.Adornee = nil, nil
		elseif selected.block then
			ghost.Color, ghost.Position, ghost.Parent, outline.Adornee = selected.block, blockSpot(result, built), workspace, nil
		else
			ghost.Parent = nil
			outline.Adornee = built and result.Instance.Parent == built and result.Instance or nil
		end
	end)

	return function() -- G
		local result = aim(RANGE)
		if not result then
			return
		end
		local built = workspace:FindFirstChild("Built")
		if selected.kind then
			actionRemote:FireServer("spawn", result.Position, selected.kind)
		elseif selected.block then
			actionRemote:FireServer("build", blockSpot(result, built), selected.block, selected.material)
		elseif built and result.Instance.Parent == built then
			actionRemote:FireServer("unbuild", result.Instance)
		end
	end
end

return Toolbox
