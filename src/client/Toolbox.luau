-- Toolbox (Tab): pick what G puts down — a character to spawn, a block to build, or the delete tool —
-- or an outfit or a team a click puts on a dummy, or time stopped. The server checks and does the spawning, building and dressing
-- (server/init.server.luau, "build" / "spawn" / "dress" / "team" / "freeze"). Items with a `pass` are that game pass's
-- (shared/Shop): while it is locked they wear its sticker, and a click offers the pass instead.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))

local GRID = 4 -- block size in studs; the server builds the same size
local RANGE = 150
local GAP = 10 -- px between tiles, rows and sections

local SECTIONS = {
	{ name = "CHARACTERS", items = {
		{ name = "Civilian", kind = "Normal", color = Color3.fromRGB(110, 170, 90) },
		{ name = "Cop", kind = "Cop", color = Color3.fromRGB(60, 90, 160) },
		{ name = "Hooligan", kind = "Hooligan", color = Color3.fromRGB(40, 40, 44) },
		{ name = "Soldier", kind = "Soldier", color = Color3.fromRGB(96, 108, 70), pass = "SandboxPlus" },
		{ name = "Heavy", kind = "Heavy", color = Color3.fromRGB(34, 36, 42), pass = "SandboxPlus" },
		{ name = "Worker", kind = "Worker", color = Color3.fromRGB(255, 122, 26), pass = "SandboxPlus" },
		{ name = "Zombie", kind = "Zombie", color = Color3.fromRGB(127, 160, 90), pass = "SandboxPlus" },
	} },
	{ name = "BLOCKS", items = { -- the map's own blocks: colours and materials as server/Map.luau builds them
		{ name = "Brick", block = Color3.fromRGB(170, 95, 80), material = "Brick" },
		{ name = "Dirt", block = Color3.fromRGB(120, 85, 60), material = "Ground" },
		{ name = "Grass", block = Color3.fromRGB(40, 170, 80), material = "Grass" },
		{ name = "Wood", block = Color3.fromRGB(128, 82, 52), material = "Wood" },
		{ name = "Leaves", block = Color3.fromRGB(30, 125, 55), material = "Grass", pass = "SandboxPlus" },
		{ name = "Metal", block = Color3.fromRGB(120, 122, 130), material = "Metal", pass = "SandboxPlus" },
		{ name = "Rocks", block = Color3.fromRGB(120, 122, 130), material = "Slate", pass = "SandboxPlus" },
	} },
	{ name = "OUTFITS", items = { -- `look`: the kind (server KINDS) whose clothes a click puts on a dummy
		{ name = "Civilian", look = "Normal", color = Color3.fromRGB(110, 170, 90), pass = "DressUp" },
		{ name = "Cop", look = "Cop", color = Color3.fromRGB(60, 90, 160), pass = "DressUp" },
		{ name = "Hooligan", look = "Hooligan", color = Color3.fromRGB(40, 40, 44), pass = "DressUp" },
		{ name = "Soldier", look = "Soldier", color = Color3.fromRGB(96, 108, 70), pass = "DressUp" },
		{ name = "Heavy", look = "Heavy", color = Color3.fromRGB(34, 36, 42), pass = "DressUp" },
		{ name = "Worker", look = "Worker", color = Color3.fromRGB(255, 122, 26), pass = "DressUp" },
		{ name = "Zombie", look = "Zombie", color = Color3.fromRGB(127, 160, 90), pass = "DressUp" },
	} },
	{ name = "TEAMS", items = { -- a click puts a dummy in the team, and G spawns into it; teams fight each other
		{ name = "Red team", team = 1, color = Color3.fromRGB(232, 70, 56), pass = "SandboxPlus" },
		{ name = "Blue team", team = 2, color = Color3.fromRGB(40, 110, 220), pass = "SandboxPlus" },
		{ name = "Green team", team = 3, color = Color3.fromRGB(90, 180, 60), pass = "SandboxPlus" },
		{ name = "Yellow team", team = 4, color = Color3.fromRGB(230, 170, 30), pass = "SandboxPlus" },
		{ name = "No team", team = 0, color = Color3.fromRGB(110, 110, 118), pass = "SandboxPlus" },
	} },
	{ name = "TOOLS", items = {
		{ name = "Stop time", tool = "freeze", color = Color3.fromRGB(70, 60, 150), pass = "SandboxPlus" },
		{ name = "Delete block", tool = "delete", color = Color3.fromRGB(143, 46, 44) },
		{ name = "Clear my blocks", tool = "clear", color = Color3.fromRGB(90, 40, 40) },
	} },
}

local Toolbox = {}

-- Comic look, same as the main menu (Menu.luau): white page, black ink outlines, LuckiestGuy
-- lettering, shaded panels with printed halftone dots.
local FONT = Enum.Font.LuckiestGuy
local INK = Color3.fromRGB(20, 20, 24)
local WHITE = Color3.new(1, 1, 1)
local YELLOW = Color3.fromRGB(252, 200, 50)
local RED = Color3.fromRGB(232, 70, 56)
local HALFTONE_IMAGE = "rbxassetid://82675619059195"
local DOT = 13 -- px, halftone tile
local DRIFT = 3 -- px/s the printed dots slide down-right while the toolbox is open; keep it barely there
local SWAY = math.rad(45) -- models turn this far each way...
local SWAY_SPEED = math.pi * 2 / 8 -- ...once there and back every 8 s
local NUDGE = 3 -- px: LuckiestGuy's letters sit high in their line box; this puts them back on its middle (calibration knob)

local prints: { { dots: ImageLabel, fade: UIGradient } } = {} -- drifting halftone layers
local spinners: { (number) -> () } = {} -- tile models swaying

local function outline(parent: GuiObject, thickness: number, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness, stroke.Color, stroke.ApplyStrokeMode = thickness, color or INK, Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode, stroke.Parent = Enum.LineJoinMode.Miter, parent
	return stroke
end

-- Printed dots thickening toward the bottom-right (densest at `darkest` transparency). Unless `still`,
-- they drift (Toolbox.start moves them): one tile wider than `parent`, which clips them, and the fade
-- is slid back by the same amount so only the dots move. ClipsDescendants is ignored under a
-- rotation, so rotated stickers keep still dots.
local function printDots(parent: GuiObject, color: Color3, darkest: number, still: boolean?)
	local dots = Instance.new("ImageLabel")
	dots.BackgroundTransparency, dots.Image, dots.ImageColor3 = 1, HALFTONE_IMAGE, color
	dots.Size = if still then UDim2.fromScale(1, 1) else UDim2.new(1, DOT, 1, DOT)
	dots.ScaleType, dots.TileSize, dots.ZIndex = Enum.ScaleType.Tile, UDim2.fromOffset(DOT, DOT), parent.ZIndex
	local fade = Instance.new("UIGradient")
	fade.Rotation, fade.Transparency = 35, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1 - (1 - darkest) / 8),
		NumberSequenceKeypoint.new(1, darkest),
	})
	fade.Parent, dots.Parent = dots, parent
	if not still then
		parent.ClipsDescendants = true
		table.insert(prints, { dots = dots, fade = fade })
	end
end

-- light on top, deep at the bottom, and printed dots thickening toward the bottom-right. A frame of
-- its own: a UIGradient on a TextButton would tint its text too.
local function comicFill(parent: GuiObject, color: Color3, still: boolean?)
	local fill = Instance.new("Frame")
	-- the HUD sorts ZIndex globally, so each layer is counted up from its parent's
	fill.Name, fill.Size, fill.BackgroundColor3, fill.BorderSizePixel, fill.ZIndex = "Fill", UDim2.fromScale(1, 1), WHITE, 0, parent.ZIndex
	fill.Parent = parent
	parent = fill
	local shade = Instance.new("UIGradient")
	shade.Rotation, shade.Color = 90, ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.25)),
		ColorSequenceKeypoint.new(0.55, color),
		ColorSequenceKeypoint.new(1, color:Lerp(INK, 0.35)),
	})
	shade.Parent = parent
	printDots(fill, color:Lerp(INK, 0.6), 0.2, still)
end

-- A comic panel to click; its lettering is the child "Label" (over the fill).
local function button(parent, text, color, z: number?, still: boolean?): TextButton
	local b = Instance.new("TextButton")
	b.Text, b.BackgroundTransparency, b.BorderSizePixel = "", 1, 0
	b.ZIndex, b.AutoButtonColor, b.Parent = z or 43, false, parent
	comicFill(b, color, still)
	outline(b, 3)
	local label = Instance.new("TextLabel")
	label.Name, label.BackgroundTransparency, label.Size, label.ZIndex = "Label", 1, UDim2.fromScale(1, 1), b.ZIndex + 1
	label.Position = UDim2.fromOffset(0, NUDGE)
	label.Text, label.Font, label.TextSize, label.TextColor3, label.TextWrapped = text, FONT, 18, WHITE, true
	label.TextStrokeTransparency, label.TextStrokeColor3, label.Parent = 0, INK, b
	return b
end

-- Points `view`'s camera at `model` so its height fills the frame (FOV 30, a little room round it).
local function frame(view: ViewportFrame, model: Instance, from: Vector3)
	local cf, size
	if model:IsA("Model") then
		cf, size = model:GetBoundingBox()
	else
		cf, size = (model :: BasePart).CFrame, (model :: BasePart).Size
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local fit = if model:IsA("Model") then size.Y * 1.15 else size.Magnitude * 1.05 -- a figure by its height, a cube from any side
	local distance = fit / 2 / math.tan(math.rad(camera.FieldOfView / 2))
	camera.CFrame = CFrame.lookAt(cf.Position + from.Unit * distance, cf.Position)
	camera.Parent = view
	view.CurrentCamera = camera
end

-- A picture tile: a viewport with the thing in it (filled in by `fill`), its name on a strip along the
-- bottom. Characters show the kind's model (ReplicatedStorage.ToolboxPreviews, built by the server),
-- blocks a cube of the block itself.
local CAPTION = 28
local RULE = 3 -- px, ink line between the picture and its caption
local INSET = 6 -- px between the tile's edge and the picture
local function pictureTile(parent, item, color: Color3, fill: (ViewportFrame) -> ())
	local b = button(parent, "", color)
	b.ClipsDescendants = true
	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency, view.ZIndex = 1, 44
	view.Position, view.Size = UDim2.fromOffset(INSET, INSET), UDim2.new(1, -INSET * 2, 1, -CAPTION - INSET * 2)
	view.Ambient, view.LightColor, view.LightDirection = Color3.fromRGB(150, 150, 160), Color3.new(1, 1, 1), Vector3.new(-0.5, -1, -0.8)
	view.Parent = b
	local caption = Instance.new("Frame") -- a white caption box, like the menu's name tag
	caption.BackgroundColor3, caption.BorderSizePixel = WHITE, 0
	caption.AnchorPoint, caption.Position, caption.Size, caption.ZIndex = Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, CAPTION), 44
	caption.Parent = b
	local rule = Instance.new("Frame")
	rule.BackgroundColor3, rule.BorderSizePixel, rule.Size, rule.ZIndex, rule.Parent = INK, 0, UDim2.new(1, 0, 0, RULE), 45, caption
	local name = Instance.new("TextLabel") -- centred in the white under the rule
	name.Text, name.Font, name.TextSize, name.TextColor3 = item.name:upper(), FONT, 17, INK
	name.BackgroundTransparency, name.ZIndex = 1, 45
	name.Position, name.Size = UDim2.fromOffset(0, RULE + NUDGE), UDim2.new(1, 0, 1, -RULE)
	name.Parent = caption
	task.spawn(fill, view)
	return b
end

local function characterTile(parent, item)
	return pictureTile(parent, item, item.color, function(view)
		local previews = ReplicatedStorage:WaitForChild("ToolboxPreviews", 30)
		local source = previews and previews:WaitForChild(item.kind or item.look, 10)
		if not source then
			return
		end
		local model = source:Clone()
		model.Parent = view
		frame(view, model, Vector3.new(0, 0, -1)) -- it faces -Z, toward the camera
		local base, phase = model:GetPivot(), #spinners * 0.7 -- tiles a little out of step
		table.insert(spinners, function(t)
			model:PivotTo(base * CFrame.Angles(0, SWAY * math.sin(t * SWAY_SPEED + phase), 0))
		end)
	end)
end

local function blockTile(parent, item)
	return pictureTile(parent, item, item.block:Lerp(Color3.new(0, 0, 0), 0.55), function(view)
		local cube = Instance.new("Part")
		cube.Size, cube.Anchored, cube.CFrame = Vector3.one * GRID, true, CFrame.new()
		cube.Color, cube.Material = item.block, Enum.Material[item.material]
		cube.TopSurface, cube.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		cube.Parent = view
		frame(view, cube, Vector3.new(1, 0.9, -1.2)) -- from above a corner: three faces show
		local phase = #spinners * 0.7
		table.insert(spinners, function(t)
			cube.CFrame = CFrame.Angles(0, SWAY * math.sin(t * SWAY_SPEED + phase), 0)
		end)
	end)
end

-- Where a block goes for this aim: flush against a built block's face, else resting on what was hit,
-- snapped to the grid across. ponytail: Y is not snapped on map surfaces, so blocks on uneven
-- ground do not line up with blocks built on other ground; snap Y too if that matters.
local function blockSpot(result, built: Instance?): Vector3
	local n = result.Normal
	n = Vector3.new(math.round(n.X), math.round(n.Y), math.round(n.Z))
	if built and result.Instance.Parent == built and result.Instance.Size.X >= GRID then -- a whole block, not a broken piece
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

	-- G spawns the picked character. Picking a block (or Delete block) takes out the build tool: then
	-- a click builds (or deletes) instead of attacking, until a weapon or ability comes off the bar (stop).
	-- Picking an outfit takes out the same tool: a click on a dummy dresses it.
	local character = SECTIONS[1].items[1]
	local team = 0 -- the team G spawns into (TEAMS), 0: none
	local tool = nil
	local building = false

	local cover = Instance.new("Frame")
	cover.Name, cover.Size = "Toolbox", UDim2.fromScale(1, 1)
	cover.BackgroundColor3, cover.BackgroundTransparency = Color3.fromRGB(44, 58, 94), 0.3
	cover.ZIndex, cover.Visible, cover.Active, cover.Parent = 40, false, true, gui
	local panel = Instance.new("Frame")
	panel.Size, panel.Position, panel.AnchorPoint = UDim2.fromScale(0.92, 0.75), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	panel.BackgroundColor3, panel.BorderSizePixel, panel.ZIndex, panel.Parent = WHITE, 0, 41, cover
	local max = Instance.new("UISizeConstraint")
	max.MaxSize, max.Parent = Vector2.new(760, 560), panel
	outline(panel, 4)
	local paper = Instance.new("Frame") -- clips the page's own drifting dots (the stickers stick out past the page)
	paper.BackgroundTransparency, paper.Size, paper.ZIndex, paper.Parent = 1, UDim2.fromScale(1, 1), 41, panel
	printDots(paper, INK, 0.88)
	local shadow = Instance.new("Frame") -- the page's drop shadow, down-right; beside the page, not in it (children draw on top)
	shadow.BackgroundColor3, shadow.BackgroundTransparency, shadow.BorderSizePixel = INK, 0.4, 0
	shadow.Size, shadow.AnchorPoint, shadow.ZIndex = panel.Size, panel.AnchorPoint, 40
	shadow.Position, shadow.Parent = panel.Position + UDim2.fromOffset(14, 16), cover
	max:Clone().Parent = shadow

	local title = button(panel, "TOOLBOX!", RED, 46, true)
	title.Size, title.Position, title.Rotation = UDim2.new(0, 230, 0, 46), UDim2.fromOffset(6, -14), -3
	local titleLabel = title.Label :: TextLabel
	titleLabel.TextColor3, titleLabel.TextSize = YELLOW, 30
	local close = button(panel, "X", YELLOW, 46, true)
	close.Size, close.Position, close.Rotation = UDim2.fromOffset(42, 42), UDim2.new(1, -48, 0, -14), 4
	local closeLabel = close.Label :: TextLabel
	closeLabel.TextColor3, closeLabel.TextSize, closeLabel.TextStrokeTransparency = INK, 26, 1

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position, scroll.Size = UDim2.fromOffset(10, 42), UDim2.new(1, -20, 1, -52)
	scroll.BackgroundTransparency, scroll.BorderSizePixel, scroll.ScrollBarThickness, scroll.ZIndex = 1, 0, 6, 42
	scroll.ScrollBarImageColor3, scroll.ScrollBarImageTransparency = INK, 0
	scroll.CanvasSize, scroll.AutomaticCanvasSize, scroll.Parent = UDim2.new(), Enum.AutomaticSize.Y, panel
	local list = Instance.new("UIListLayout")
	list.Padding, list.SortOrder, list.Parent = UDim.new(0, GAP), Enum.SortOrder.LayoutOrder, scroll
	local inner = Instance.new("UIPadding") -- room for the selection outline, and the scroll bar on the right
	inner.PaddingTop, inner.PaddingBottom, inner.PaddingLeft, inner.PaddingRight = UDim.new(0, 8), UDim.new(0, 14), UDim.new(0, 8), UDim.new(0, 18)
	inner.Parent = scroll

	local player = Players.LocalPlayer
	-- a tilted yellow sticker naming the pass, on a tile while that pass is locked
	local function passSticker(b: GuiObject, key: string)
		local sticker = Instance.new("TextLabel")
		sticker.Text, sticker.Font, sticker.TextSize, sticker.TextColor3 = Shop.item(key).name, FONT, 15, INK
		sticker.BackgroundColor3, sticker.BorderSizePixel, sticker.Rotation = YELLOW, 0, 6
		sticker.AnchorPoint, sticker.Position, sticker.Size = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4), UDim2.fromOffset(96, 22)
		sticker.ZIndex, sticker.Parent = 47, b
		outline(sticker, 2)
		local function show()
			sticker.Visible = Shop.locked(player, key)
		end
		show()
		player:GetAttributeChangedSignal(Shop.attribute(key)):Connect(show)
	end

	local cards = {}
	local function refresh()
		for item, b in cards do
			local stroke = b:FindFirstChildOfClass("UIStroke")
			local picked = item == character or (building and item == tool)
			stroke.Color, stroke.Thickness = picked and YELLOW or INK, picked and 6 or 3
		end
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
		header.Text, header.Font, header.TextSize, header.TextColor3 = section.name, FONT, 24, INK
		header.BackgroundTransparency, header.TextXAlignment, header.Size = 1, Enum.TextXAlignment.Left, UDim2.new(1, 0, 0, 28)
		header.LayoutOrder, header.ZIndex, header.Parent = order, 43, scroll
		order += 1
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency, grid.Size, grid.AutomaticSize = 1, UDim2.fromScale(1, 0), Enum.AutomaticSize.Y
		grid.LayoutOrder, grid.ZIndex, grid.Parent = order, 42, scroll
		local layout = Instance.new("UIGridLayout")
		local first = section.items[1]
		layout.CellSize = if first.kind or first.look then UDim2.new(0.2, -GAP, 0, 180) -- characters: upright tiles
			elseif first.block then UDim2.new(0.25, -GAP, 0, 130)
			else UDim2.new(0.25, -GAP, 0, 52)
		layout.CellPadding, layout.SortOrder = UDim2.fromOffset(GAP, GAP), Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for i, item in section.items do
			local b = if item.kind or item.look then characterTile(grid, item)
				elseif item.block then blockTile(grid, item)
				else button(grid, item.name, item.color)
			b.LayoutOrder = i
			cards[item] = b
			if item.tool == "freeze" then -- says what a click does now
				local label = b:FindFirstChild("Label") :: TextLabel
				local function show()
					label.Text = if workspace:GetAttribute("TimeFrozen") then "RESUME TIME" else "STOP TIME"
				end
				show()
				workspace:GetAttributeChangedSignal("TimeFrozen"):Connect(show)
			end
			if item.pass then
				passSticker(b, item.pass)
			end
			b.Activated:Connect(function()
				if item.pass and Shop.locked(player, item.pass) then
					MarketplaceService:PromptGamePassPurchase(player, Shop.item(item.pass).pass)
					return
				end
				if item.tool == "clear" then
					actionRemote:FireServer("clearbuild")
				elseif item.tool == "freeze" then
					actionRemote:FireServer("freeze")
				elseif item.kind then
					character = item
				else
					tool, building = item, true
					team = item.team or team -- G spawns into the last team picked ("No team": 0)
				end
				refresh()
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

	-- the dummy (a model in workspace.Dummies) the aim is on, for an outfit
	local function dummyAt(result: RaycastResult): Model?
		local dummies = workspace:FindFirstChild("Dummies")
		local inst: Instance? = result.Instance
		while inst and inst.Parent ~= dummies do
			inst = inst.Parent
		end
		return if inst and inst:IsA("Model") then inst else nil
	end

	-- the block a click would build (ghost), the built block it would delete or the dummy an outfit
	-- goes on (outline)
	local ghost = Instance.new("Part")
	ghost.Name, ghost.Size, ghost.Anchored = "BuildGhost", Vector3.one * GRID, true
	ghost.CanCollide, ghost.CanQuery, ghost.CanTouch, ghost.CastShadow = false, false, false, false
	ghost.Transparency, ghost.Material = 0.6, Enum.Material.SmoothPlastic
	local outline = Instance.new("SelectionBox")
	outline.Color3, outline.LineThickness, outline.Parent = Color3.fromRGB(230, 60, 50), 0.06, gui
	RunService.RenderStepped:Connect(function()
		if cover.Visible then
			local t = os.clock()
			for _, spin in spinners do
				spin(t)
			end
			local shift = (t * DRIFT) % DOT
			for _, p in prints do
				local size = p.dots.AbsoluteSize
				p.dots.Position = UDim2.fromOffset(shift - DOT, shift - DOT)
				if size.X > 0 and size.Y > 0 then
					p.fade.Offset = Vector2.new(-shift / size.X, -shift / size.Y)
				end
			end
		end
		local built = workspace:FindFirstChild("Built")
		local result = building and not cover.Visible and not api.blocked() and aim(RANGE)
		if not result then
			ghost.Parent, outline.Adornee = nil, nil
		elseif tool.block then
			ghost.Color, ghost.Material = tool.block, Enum.Material[tool.material]
			ghost.Position, ghost.Parent, outline.Adornee = blockSpot(result, built), workspace, nil
		elseif tool.look or tool.team then
			ghost.Parent = nil
			outline.Adornee = dummyAt(result)
		else
			ghost.Parent = nil
			outline.Adornee = built and result.Instance.Parent == built and result.Instance or nil
		end
	end)

	return {
		use = function() -- G
			local result = aim(RANGE)
			if result then
				actionRemote:FireServer("spawn", result.Position, character.kind, team)
			end
		end,
		click = function(): boolean -- left click: true when the build tool took it
			if not building then
				return false
			end
			local result = aim(RANGE)
			local built = workspace:FindFirstChild("Built")
			if not result then
				return true -- aimed at the sky: nothing to build on, but no swing either
			elseif tool.block then
				actionRemote:FireServer("build", blockSpot(result, built), tool.block, tool.material)
			elseif tool.look then
				local dummy = dummyAt(result)
				if dummy then
					actionRemote:FireServer("dress", dummy, tool.look)
				end
			elseif tool.team then
				local dummy = dummyAt(result)
				if dummy then
					actionRemote:FireServer("team", dummy, tool.team)
				end
			elseif built and result.Instance.Parent == built then
				actionRemote:FireServer("unbuild", result.Instance)
			end
			return true
		end,
		stop = function() -- a weapon or ability taken off the bar
			if building then
				building = false
				refresh()
			end
		end,
	}
end

return Toolbox
