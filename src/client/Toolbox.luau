-- Toolbox (Tab): a page per tab down the left. SPAWN: a character on a stage, its team and how many,
-- then SPAWN! (or G) where you aim. BUILD: the blocks, and building with them (the block wheel on Q and
-- the trash, instead of the weapons). WORLD: time stop, clearing the dummies, team paint. The server
-- checks and does it all (server/init.server.luau, "spawn" / "clearspawn" / "build" / "team" / "freeze").
-- Items with a `pass` are that game pass's (shared/Shop): locked, they wear its sticker and offer it.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))

local GRID = 4 -- block size in studs; the server builds the same size
local RANGE = 150

-- SPAWN tab: who G (or the SPAWN button) puts down, into which team, how many at once
local CHARACTERS = {
	{ name = "Civilian", kind = "Normal", color = Color3.fromRGB(110, 170, 90) },
	{ name = "Cop", kind = "Cop", color = Color3.fromRGB(60, 90, 160) },
	{ name = "Hooligan", kind = "Hooligan", color = Color3.fromRGB(40, 40, 44) },
	{ name = "Soldier", kind = "Soldier", color = Color3.fromRGB(96, 108, 70), pass = "SandboxPlus" },
	{ name = "Heavy", kind = "Heavy", color = Color3.fromRGB(34, 36, 42), pass = "SandboxPlus" },
	{ name = "Worker", kind = "Worker", color = Color3.fromRGB(255, 122, 26), pass = "SandboxPlus" },
	{ name = "Zombie", kind = "Zombie", color = Color3.fromRGB(127, 160, 90), pass = "SandboxPlus" },
}
-- a team: spawned into it (SPAWN), or a click puts a dummy in it (WORLD, team paint); teams fight each other
local TEAMS = {
	{ name = "No team", team = 0, color = Color3.fromRGB(110, 110, 118), pass = "SandboxPlus" },
	{ name = "Red team", team = 1, color = Color3.fromRGB(232, 70, 56), pass = "SandboxPlus" },
	{ name = "Blue team", team = 2, color = Color3.fromRGB(40, 110, 220), pass = "SandboxPlus" },
	{ name = "Green team", team = 3, color = Color3.fromRGB(90, 180, 60), pass = "SandboxPlus" },
	{ name = "Yellow team", team = 4, color = Color3.fromRGB(230, 170, 30), pass = "SandboxPlus" },
}
local MAX_SPAWN = 5 -- the server's Sandbox.MAX_SPAWN

-- BUILD (TOOLS) puts these on the Q wheel instead of the weapons: the map's own blocks, colours and
-- materials as server/Map.luau builds them. The trash sits on the build bar beside the block, always.
local BLOCKS = {
	{ name = "Brick", block = Color3.fromRGB(170, 95, 80), material = "Brick" },
	{ name = "Dirt", block = Color3.fromRGB(120, 85, 60), material = "Ground" },
	{ name = "Grass", block = Color3.fromRGB(40, 170, 80), material = "Grass" },
	{ name = "Wood", block = Color3.fromRGB(128, 82, 52), material = "Wood" },
	{ name = "Leaves", block = Color3.fromRGB(30, 125, 55), material = "Grass", pass = "SandboxPlus" },
	{ name = "Metal", block = Color3.fromRGB(120, 122, 130), material = "Metal", pass = "SandboxPlus" },
	{ name = "Rocks", block = Color3.fromRGB(120, 122, 130), material = "Slate", pass = "SandboxPlus" },
}
local TRASH = { name = "Trash", tool = "delete", color = Color3.fromRGB(143, 46, 44) }

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

	-- G spawns the picked character. Picking a team takes out a tool: a click on a dummy puts it in
	-- the team, until a weapon or ability comes off the bar (stop).
	-- BUILD swaps the weapons for the build bar (the block in hand and the trash, 1 / 2) and the
	-- block wheel (hold Q); a click builds or deletes, until BUILD again.
	local character = CHARACTERS[1]
	local team = 0 -- the team G spawns into (TEAMS), 0: none
	local count = 1 -- how many one spawn puts down (SPAWN tab)
	local tool = nil
	local building = false
	local buildMode, brick, trashing = false, BLOCKS[1], false
	local function current() -- what a click does now: a block, the trash, a team, or nothing
		if buildMode then
			return if trashing then TRASH else brick
		end
		return if building then tool else nil
	end
	local setBuild: (boolean) -> () -- below, with the build bar

	local cover = Instance.new("Frame")
	cover.Name, cover.Size = "Toolbox", UDim2.fromScale(1, 1)
	cover.BackgroundColor3, cover.BackgroundTransparency = Color3.fromRGB(44, 58, 94), 0.3
	cover.ZIndex, cover.Visible, cover.Active, cover.Parent = 40, false, true, gui
	local panel = Instance.new("Frame")
	panel.Size, panel.Position, panel.AnchorPoint = UDim2.fromScale(0.92, 0.75), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)
	panel.BackgroundColor3, panel.BorderSizePixel, panel.ZIndex, panel.Parent = WHITE, 0, 41, cover
	local max = Instance.new("UISizeConstraint")
	max.MaxSize, max.Parent = Vector2.new(900, 600), panel
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

	local refresh: () -> () -- below, once every page is built
	local player = Players.LocalPlayer
	-- a tilted yellow sticker naming the pass, on a tile while that pass is locked
	local function passSticker(b: GuiObject, key: string, width: number?)
		local sticker = Instance.new("TextLabel")
		sticker.Text, sticker.Font, sticker.TextSize, sticker.TextColor3 = Shop.item(key).name, FONT, 15, INK
		sticker.BackgroundColor3, sticker.BorderSizePixel, sticker.Rotation = YELLOW, 0, 6
		sticker.AnchorPoint, sticker.Position, sticker.Size = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4), UDim2.fromOffset(width or 96, 22)
		sticker.ZIndex, sticker.Parent = 48, b
		outline(sticker, 2)
		local function show()
			sticker.Visible = Shop.locked(player, key)
		end
		show()
		player:GetAttributeChangedSignal(Shop.attribute(key)):Connect(show)
		return sticker
	end
	local function locked(item): boolean -- and offers the pass when it is
		if item.pass and Shop.locked(player, item.pass) then
			MarketplaceService:PromptGamePassPurchase(player, Shop.item(item.pass).pass)
			return true
		end
		return false
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

	-- Small pieces the pages are made of -------------------------------------------------------
	local function heading(parent: Instance, text: string, order: number)
		local h = Instance.new("TextLabel")
		h.Text, h.Font, h.TextSize, h.TextColor3 = text, FONT, 22, INK
		h.BackgroundTransparency, h.TextXAlignment, h.Size = 1, Enum.TextXAlignment.Left, UDim2.new(1, 0, 0, 24)
		h.LayoutOrder, h.ZIndex, h.Parent = order, 44, parent
		return h
	end
	local function row(parent: Instance, order: number, height: number): Frame
		local r = Instance.new("Frame")
		r.BackgroundTransparency, r.Size, r.LayoutOrder, r.ZIndex, r.Parent = 1, UDim2.new(1, 0, 0, height), order, 43, parent
		local l = Instance.new("UIListLayout")
		l.FillDirection, l.Padding, l.SortOrder = Enum.FillDirection.Horizontal, UDim.new(0, 6), Enum.SortOrder.LayoutOrder
		l.VerticalAlignment, l.Parent = Enum.VerticalAlignment.Center, r
		return r
	end
	local function column(parent: Instance): Frame -- the right half of a page, top to bottom
		local c = Instance.new("Frame")
		c.BackgroundTransparency, c.Position, c.Size, c.ZIndex, c.Parent = 1, UDim2.new(0.5, 6, 0, 0), UDim2.new(0.5, -6, 1, 0), 43, parent
		local l = Instance.new("UIListLayout")
		l.Padding, l.SortOrder, l.Parent = UDim.new(0, 8), Enum.SortOrder.LayoutOrder, c
		return c
	end
	local function hint(parent: Instance, text: string, order: number)
		local t = Instance.new("TextLabel")
		t.Text, t.Font, t.TextSize, t.TextColor3, t.TextWrapped = text, FONT, 15, INK, true
		t.TextTransparency, t.BackgroundTransparency, t.TextXAlignment = 0.35, 1, Enum.TextXAlignment.Left
		t.Size, t.LayoutOrder, t.ZIndex, t.Parent = UDim2.new(1, 0, 0, 36), order, 44, parent
		return t
	end
	local function pick(b: GuiObject, on: boolean) -- yellow, thicker outline on the chosen one
		local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color, stroke.Thickness = on and YELLOW or INK, on and 5 or 3
	end
	-- A stage on the left half of a page: a comic panel in `color` with a 3D model turning in it and
	-- a name plate along the bottom. Returns the stage, its viewport, setColor and setName.
	local function stage(parent: Instance)
		local s = Instance.new("Frame")
		s.BackgroundTransparency, s.Size, s.ZIndex, s.Parent = 1, UDim2.new(0.5, -6, 1, -4), 43, parent
		outline(s, 4)
		local fill: Instance? = nil
		local function setColor(color: Color3)
			if fill then
				fill:Destroy()
			end
			comicFill(s, color, true)
			fill = s:FindFirstChild("Fill")
		end
		local view = Instance.new("ViewportFrame")
		view.BackgroundTransparency, view.ZIndex = 1, 45
		view.Position, view.Size = UDim2.fromOffset(10, 10), UDim2.new(1, -20, 1, -74)
		view.Ambient, view.LightColor, view.LightDirection = Color3.fromRGB(150, 150, 160), Color3.new(1, 1, 1), Vector3.new(-0.5, -1, -0.8)
		view.Parent = s
		local plate = Instance.new("TextLabel")
		plate.Font, plate.TextSize, plate.TextColor3, plate.BackgroundColor3, plate.BorderSizePixel = FONT, 28, INK, WHITE, 0
		plate.AnchorPoint, plate.Position, plate.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12), UDim2.new(1, -40, 0, 44)
		plate.Rotation, plate.ZIndex, plate.Parent = -2, 46, s
		outline(plate, 3)
		return s, view, setColor, function(text: string)
			plate.Text = text:upper()
		end
	end
	-- turns whatever model `get` returns in a stage, while the toolbox is open
	local function turning(get: () -> Instance?)
		table.insert(spinners, function(t)
			local m = get()
			if m and m:IsA("Model") then
				local base = m:GetAttribute("Base") or m:GetPivot()
				m:SetAttribute("Base", base)
				m:PivotTo(base * CFrame.Angles(0, t * 0.9, 0))
			elseif m and m:IsA("BasePart") then
				m.CFrame = CFrame.Angles(0, t * 0.9, 0)
			end
		end)
	end

	-- Tabs down the left, one page each on the right ---------------------------------------------
	local SIDE = 150
	local TABS = {
		{ name = "SPAWN", color = RED },
		{ name = "BUILD", color = Color3.fromRGB(40, 140, 70) },
		{ name = "WORLD", color = Color3.fromRGB(70, 60, 150) },
	}
	local area = Instance.new("Frame")
	area.BackgroundTransparency, area.Position, area.Size, area.ZIndex = 1, UDim2.fromOffset(SIDE + 30, 46), UDim2.new(1, -SIDE - 44, 1, -60), 42
	area.Parent = panel
	local rule = Instance.new("Frame") -- ink line between the tabs and the page
	rule.BackgroundColor3, rule.BorderSizePixel, rule.ZIndex = INK, 0, 42
	rule.Position, rule.Size, rule.Parent = UDim2.fromOffset(SIDE + 18, 40), UDim2.new(0, 3, 1, -52), panel
	local tabs, pages = {}, {}
	local shown = 1
	local function showTab(k: number)
		shown = k
		for i, b in tabs do
			local on = i == k
			pages[i].Visible = on
			pick(b, on)
			b.Position = UDim2.fromOffset(on and 22 or 12, 56 + (i - 1) * 80)
		end
	end
	for i, t in TABS do
		local b = button(panel, t.name, t.color, 43, true)
		b.Size, b.Rotation = UDim2.fromOffset(SIDE, 64), if i % 2 == 0 then 2 else -2
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize = 30
		tabs[i] = b
		local page = Instance.new("Frame")
		page.Name, page.BackgroundTransparency, page.Size, page.ZIndex, page.Parent = t.name, 1, UDim2.fromScale(1, 1), 42, area
		pages[i] = page
		b.Activated:Connect(function()
			showTab(i)
		end)
	end

	-- SPAWN: the character turning on a stage, the choices beside it, SPAWN! ------------------------
	local spawnNow: () -> () -- below, with use()
	local spawnPage = pages[1]
	local spawnStage, spawnView, spawnColor, spawnName = stage(spawnPage)
	local shownModel: Instance? = nil
	local shownFor = nil -- the character shownModel is
	turning(function()
		return shownModel
	end)
	local charLock = passSticker(spawnStage, "SandboxPlus", 120)
	local teamTag = Instance.new("TextLabel") -- the team it goes into, on the stage's top-left corner
	teamTag.Font, teamTag.TextSize, teamTag.TextColor3, teamTag.BorderSizePixel = FONT, 17, WHITE, 0
	teamTag.TextStrokeTransparency, teamTag.Rotation, teamTag.ZIndex = 0, -6, 47
	teamTag.Position, teamTag.Size, teamTag.Parent = UDim2.fromOffset(-8, -8), UDim2.fromOffset(120, 28), spawnStage
	outline(teamTag, 2)
	local function arrow(text: string, x: number, by: number)
		local b = button(spawnStage, text, YELLOW, 47, true)
		b.AnchorPoint, b.Position, b.Size = Vector2.new(0.5, 0.5), UDim2.new(x, 0, 0.45, 0), UDim2.fromOffset(40, 52)
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize, label.TextColor3, label.TextStrokeTransparency = 30, INK, 1
		b.Activated:Connect(function()
			local i = table.find(CHARACTERS, character) or 1
			character = CHARACTERS[(i - 1 + by) % #CHARACTERS + 1]
			refresh()
		end)
	end
	arrow("<", 0.06, -1)
	arrow(">", 0.94, 1)

	local spawnSide = column(spawnPage)
	heading(spawnSide, "CHARACTER", 1)
	local charRow = row(spawnSide, 2, 40)
	local charChips = {}
	for i, item in CHARACTERS do
		local b = button(charRow, "", item.color, 44, true)
		b.Size, b.LayoutOrder = UDim2.fromOffset(34, 34), i
		charChips[item] = b
		b.Activated:Connect(function()
			character = item
			refresh()
		end)
	end
	local teamHead = heading(spawnSide, "TEAM", 3)
	local teamRow = row(spawnSide, 4, 44)
	local teamChips = {}
	for i, item in TEAMS do
		local b = button(teamRow, if item.team == 0 then "-" else "", item.color, 44, true)
		b.Size, b.LayoutOrder = UDim2.fromOffset(46, 40), i
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize = 30
		teamChips[item] = b
		b.Activated:Connect(function()
			if item.team ~= 0 and locked(item) then
				return
			end
			team = item.team
			refresh()
		end)
	end
	passSticker(teamHead, "SandboxPlus")
	heading(spawnSide, "HOW MANY", 5)
	local countRow = row(spawnSide, 6, 44)
	local countLabel = Instance.new("TextLabel")
	local function stepper(text: string, by: number, order: number)
		local b = button(countRow, text, YELLOW, 44, true)
		b.Size, b.LayoutOrder = UDim2.fromOffset(46, 40), order
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize, label.TextColor3, label.TextStrokeTransparency = 30, INK, 1
		b.Activated:Connect(function()
			count = math.clamp(count + by, 1, MAX_SPAWN)
			refresh()
		end)
	end
	stepper("-", -1, 1)
	countLabel.Font, countLabel.TextSize, countLabel.TextColor3, countLabel.BackgroundColor3 = FONT, 30, INK, WHITE
	countLabel.BorderSizePixel, countLabel.Size, countLabel.LayoutOrder, countLabel.ZIndex = 0, UDim2.fromOffset(70, 40), 2, 44
	countLabel.Parent = countRow
	outline(countLabel, 3)
	stepper("+", 1, 3)
	local spacer = Instance.new("Frame")
	spacer.BackgroundTransparency, spacer.Size, spacer.LayoutOrder, spacer.Parent = 1, UDim2.new(1, 0, 0, 6), 7, spawnSide
	local spawnButton = button(spawnSide, "SPAWN!", RED, 44, true)
	spawnButton.Size, spawnButton.LayoutOrder, spawnButton.Rotation = UDim2.new(1, -10, 0, 78), 8, -2
	local spawnLabel = spawnButton:FindFirstChild("Label") :: TextLabel
	spawnLabel.TextSize, spawnLabel.TextColor3 = 44, YELLOW
	spawnButton.Activated:Connect(function()
		if locked(character) then
			return
		end
		setOpen(false)
		spawnNow()
	end)
	hint(spawnSide, `Where you aim. G spawns the same again. Up to {MAX_SPAWN} at once.`, 9)

	local function showCharacter()
		spawnColor(character.color)
		spawnName(character.name)
		charLock.Visible = character.pass ~= nil and Shop.locked(player, character.pass)
		if shownFor == character then
			return
		end
		shownFor = character
		if shownModel then
			shownModel:Destroy()
			shownModel = nil
		end
		local wanted = character
		task.spawn(function()
			local previews = ReplicatedStorage:WaitForChild("ToolboxPreviews", 30)
			local source = previews and previews:WaitForChild(wanted.kind, 10)
			if not source or character ~= wanted or shownModel then
				return
			end
			local model = source:Clone()
			model.Parent = spawnView
			frame(spawnView, model, Vector3.new(0, 0, -1)) -- it faces -Z, toward the camera
			shownModel = model
		end)
	end

	-- WORLD: time, clearing up, and team paint (a click on a dummy puts it in the team) ------------
	local worldSide = pages[3]
	local worldList = Instance.new("UIListLayout")
	worldList.Padding, worldList.SortOrder, worldList.Parent = UDim.new(0, 10), Enum.SortOrder.LayoutOrder, worldSide
	local freezeButton = button(worldSide, "STOP TIME", Color3.fromRGB(70, 60, 150), 44, true)
	freezeButton.Size, freezeButton.LayoutOrder, freezeButton.Rotation = UDim2.new(1, -10, 0, 70), 1, -1
	local freezeLabel = freezeButton:FindFirstChild("Label") :: TextLabel
	freezeLabel.TextSize = 34
	passSticker(freezeButton, "SandboxPlus")
	local function showFrozen()
		freezeLabel.Text = if workspace:GetAttribute("TimeFrozen") then "RESUME TIME" else "STOP TIME"
	end
	showFrozen()
	workspace:GetAttributeChangedSignal("TimeFrozen"):Connect(showFrozen)
	freezeButton.Activated:Connect(function()
		if not locked({ pass = "SandboxPlus" }) then
			actionRemote:FireServer("freeze")
		end
	end)
	hint(worldSide, "Everything stands still: set the dummies up, then let them go.", 2)
	local wipe = button(worldSide, "REMOVE ALL DUMMIES", Color3.fromRGB(143, 46, 44), 44, true)
	wipe.Size, wipe.LayoutOrder, wipe.Rotation = UDim2.new(1, -10, 0, 56), 3, 1
	local wipeLabel = wipe:FindFirstChild("Label") :: TextLabel
	wipeLabel.TextSize = 26
	wipe.Activated:Connect(function()
		actionRemote:FireServer("clearspawn")
	end)
	local paintHead = heading(worldSide, "TEAM PAINT", 4)
	local paintRow = row(worldSide, 5, 48)
	local paintChips = {}
	for i, item in TEAMS do
		local b = button(paintRow, if item.team == 0 then "-" else "", item.color, 44, true)
		b.Size, b.LayoutOrder = UDim2.fromOffset(60, 44), i
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize = 30
		paintChips[item] = b
		b.Activated:Connect(function()
			if locked(item) then
				return
			end
			tool, building = item, true
			refresh()
			setOpen(false)
		end)
	end
	passSticker(paintHead, "SandboxPlus")
	hint(worldSide, "Pick a colour, then click dummies to put them in that team. Teams fight each other.", 6)

	local buildLabel = function() end -- the BUILD page, below
	local showBlocks = function() end
	refresh = function()
		for item, b in charChips do
			pick(b, item == character)
		end
		for item, b in teamChips do
			pick(b, item.team == team)
		end
		for item, b in paintChips do
			pick(b, building and not buildMode and item == tool)
		end
		local t = TEAMS[1]
		for _, item in TEAMS do
			if item.team == team then
				t = item
			end
		end
		teamTag.Visible, teamTag.Text, teamTag.BackgroundColor3 = team ~= 0, t.name:upper(), t.color
		countLabel.Text = tostring(count)
		spawnLabel.Text = if count > 1 then `SPAWN {count}!` else "SPAWN!"
		showCharacter()
		showBlocks()
	end
	showTab(1)

	close.Activated:Connect(function()
		setOpen(false)
	end)
	UIS.InputBegan:Connect(function(input, processed)
		if UIS:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab then
			if not cover.Visible and buildMode then -- Tab ends building, and opens on BUILD
				setBuild(false)
				showTab(2)
			end
			setOpen(not cover.Visible)
		elseif cover.Visible and input.KeyCode == Enum.KeyCode.Escape and not processed then
			setOpen(false)
		end
	end)

	-- Build bar (in place of the weapons' hotbar): the block in hand (1) and the trash (2) -------------
	local buildBar = Instance.new("Frame")
	buildBar.Name, buildBar.BackgroundTransparency, buildBar.Visible = "BuildBar", 1, false
	buildBar.AnchorPoint, buildBar.Position, buildBar.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(220, 130)
	buildBar.ZIndex, buildBar.Parent = 30, gui
	local barHint = Instance.new("TextLabel")
	barHint.Text, barHint.Font, barHint.TextSize, barHint.TextColor3 = "HOLD Q  BLOCKS     TAB  STOP BUILDING", FONT, 16, WHITE
	barHint.TextStrokeTransparency, barHint.BackgroundTransparency = 0, 1
	barHint.Size, barHint.Position, barHint.ZIndex, barHint.Parent = UDim2.new(1, 200, 0, 20), UDim2.new(0, -100, 0, -4), 31, buildBar
	local function trashTile(parent): TextButton
		local b = button(parent, "🗑", TRASH.color)
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize, label.Size = 40, UDim2.new(1, 0, 1, -CAPTION)
		local name = Instance.new("TextLabel")
		name.Text, name.Font, name.TextSize, name.TextColor3 = "TRASH", FONT, 17, WHITE
		name.TextStrokeTransparency, name.BackgroundTransparency, name.ZIndex = 0, 1, b.ZIndex + 1
		name.AnchorPoint, name.Position, name.Size = Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, CAPTION)
		name.Parent = b
		return b
	end
	local brickSlot: GuiObject
	local trashSlot = trashTile(buildBar)
	trashSlot.Size, trashSlot.Position, trashSlot.ZIndex = UDim2.fromOffset(100, 100), UDim2.fromOffset(115, 24), 31
	local function mark(slot: GuiObject, on: boolean)
		local stroke = slot:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color, stroke.Thickness = on and YELLOW or INK, on and 6 or 3
	end
	local function showBar()
		if brickSlot then
			brickSlot:Destroy()
		end
		brickSlot = blockTile(buildBar, brick)
		brickSlot.Size, brickSlot.Position = UDim2.fromOffset(100, 100), UDim2.fromOffset(5, 24)
		brickSlot.Activated:Connect(function()
			trashing = false
			showBar()
		end)
		mark(brickSlot, not trashing)
		mark(trashSlot, trashing)
	end
	trashSlot.Activated:Connect(function()
		trashing = true
		showBar()
	end)

	-- Block wheel (hold Q while building): the blocks round the middle; point at one, let go of Q --
	local wheel = Instance.new("Frame")
	wheel.Name, wheel.Size, wheel.BackgroundColor3, wheel.BackgroundTransparency = "BlockWheel", UDim2.fromScale(1, 1), INK, 0.5
	wheel.ZIndex, wheel.Visible, wheel.Parent = 39, false, gui -- under the tiles (43+), the dimmer behind them
	local RADIUS = 200
	local petals = {}
	for i, item in BLOCKS do
		local b = blockTile(wheel, item)
		local a = (i - 1) / #BLOCKS * math.pi * 2
		b.AnchorPoint, b.Size = Vector2.new(0.5, 0.5), UDim2.fromOffset(120, 130)
		b.Position = UDim2.new(0.5, math.sin(a) * RADIUS, 0.5, -math.cos(a) * RADIUS)
		if item.pass then
			passSticker(b, item.pass)
		end
		petals[i] = { item = item, button = b, angle = a }
	end
	local hovered = nil
	local function pickBlock(item)
		if item.pass and Shop.locked(player, item.pass) then
			MarketplaceService:PromptGamePassPurchase(player, Shop.item(item.pass).pass)
			return
		end
		brick, trashing = item, false
		showBar()
		refresh()
	end
	local function showWheel(on: boolean)
		if on == wheel.Visible then
			return
		end
		wheel.Visible, hovered = on, nil
		gui:SetAttribute("WeaponPickerOpen", on)
		api.freeze(on)
		UIS.MouseIconEnabled = on
	end
	for _, p in petals do
		p.button.Activated:Connect(function()
			pickBlock(p.item)
			showWheel(false)
		end)
	end

	setBuild = function(on: boolean)
		if on and not buildMode then
			api.set(1) -- the fists, so no weapon is left drawn; this also stops a team tool
		end
		buildMode = on
		if not on then
			showWheel(false)
		end
		buildBar.Visible = on
		local hotbar = gui:FindFirstChild("Hotbar")
		if hotbar then
			hotbar.Visible = not on
		end
		showBar()
		buildLabel()
		refresh()
	end
	showBar()

	-- BUILD: the block in hand turning on a stage, every block beside it, START BUILDING ------------
	local buildPage = pages[2]
	local _, buildView, buildColor, buildName = stage(buildPage)
	local cube = Instance.new("Part")
	cube.Size, cube.Anchored, cube.CFrame = Vector3.one * GRID, true, CFrame.new()
	cube.TopSurface, cube.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	cube.Parent = buildView
	frame(buildView, cube, Vector3.new(1, 0.9, -1.2)) -- from above a corner: three faces show
	turning(function()
		return cube
	end)
	local buildSide = column(buildPage)
	heading(buildSide, "BLOCKS", 1)
	local blockGrid = Instance.new("Frame")
	blockGrid.BackgroundTransparency, blockGrid.Size, blockGrid.LayoutOrder, blockGrid.ZIndex = 1, UDim2.new(1, 0, 0, 196), 2, 43
	blockGrid.Parent = buildSide
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize, gridLayout.CellPadding = UDim2.new(0.25, -6, 0, 92), UDim2.fromOffset(6, 8)
	gridLayout.SortOrder, gridLayout.Parent = Enum.SortOrder.LayoutOrder, blockGrid
	local blockChips = {}
	for i, item in BLOCKS do
		local b = blockTile(blockGrid, item)
		b.LayoutOrder = i
		blockChips[item] = b
		if item.pass then
			local sticker = passSticker(b, item.pass, 64)
			sticker.TextSize = 11
		end
		b.Activated:Connect(function()
			if locked(item) then
				return
			end
			brick, trashing = item, false
			showBar()
			refresh()
		end)
	end
	local startButton = button(buildSide, "START BUILDING!", Color3.fromRGB(40, 140, 70), 44, true)
	startButton.Size, startButton.LayoutOrder, startButton.Rotation = UDim2.new(1, -10, 0, 66), 3, -2
	local startLabel = startButton:FindFirstChild("Label") :: TextLabel
	startLabel.TextSize, startLabel.TextColor3 = 32, YELLOW
	startButton.Activated:Connect(function()
		setBuild(not buildMode)
		if buildMode then
			setOpen(false)
		end
	end)
	local clearButton = button(buildSide, "CLEAR MY BLOCKS", Color3.fromRGB(90, 40, 40), 44, true)
	clearButton.Size, clearButton.LayoutOrder = UDim2.new(1, -10, 0, 44), 4
	clearButton.Activated:Connect(function()
		actionRemote:FireServer("clearbuild")
	end)
	hint(buildSide, "Hold Q: the block wheel. 1 block, 2 trash. Click to build or delete.", 5)
	buildLabel = function()
		startLabel.Text = if buildMode then "STOP BUILDING" else "START BUILDING!"
	end
	showBlocks = function()
		for item, b in blockChips do
			pick(b, item == brick)
		end
		buildColor(brick.block:Lerp(INK, 0.45))
		buildName(brick.name)
		cube.Color, cube.Material = brick.block, Enum.Material[brick.material]
	end
	buildLabel()
	refresh()

	UIS.InputBegan:Connect(function(input, processed)
		if not buildMode or processed or cover.Visible or api.blocked() or UIS:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q and not wheel.Visible then
			showWheel(true)
		elseif input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.Two then
			trashing = input.KeyCode == Enum.KeyCode.Two
			showBar()
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Q and wheel.Visible then
			if hovered then
				pickBlock(hovered.item)
			end
			showWheel(false)
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
		if wheel.Visible then -- the petal the mouse points at from the middle
			local off = UIS:GetMouseLocation() - workspace.CurrentCamera.ViewportSize / 2
			local best = nil
			if off.Magnitude > 40 then
				local a = math.atan2(off.X, -off.Y) % (math.pi * 2)
				local gap = math.huge
				for _, p in petals do
					local d = math.abs((a - p.angle + math.pi) % (math.pi * 2) - math.pi)
					if d < gap then
						best, gap = p, d
					end
				end
			end
			hovered = best
			for _, p in petals do
				mark(p.button, p == best)
			end
		end
		local built = workspace:FindFirstChild("Built")
		local tool = current()
		local result = tool and not cover.Visible and not wheel.Visible and not api.blocked() and aim(RANGE)
		if not result then
			ghost.Parent, outline.Adornee = nil, nil
		elseif tool.block then
			ghost.Color, ghost.Material = tool.block, Enum.Material[tool.material]
			ghost.Position, ghost.Parent, outline.Adornee = blockSpot(result, built), workspace, nil
		elseif tool.team then
			ghost.Parent = nil
			outline.Adornee = dummyAt(result)
		else
			ghost.Parent = nil
			outline.Adornee = built and result.Instance.Parent == built and result.Instance or nil
		end
	end)

	spawnNow = function() -- G, and SPAWN!: the picked character, team and count where the aim is
		local result = aim(RANGE)
		if result then
			actionRemote:FireServer("spawn", result.Position, character.kind, team, count)
		end
	end
	return {
		use = spawnNow,
		click = function(): boolean -- left click: true when the build tool took it
			local tool = current()
			if not tool then
				return false
			end
			local result = aim(RANGE)
			local built = workspace:FindFirstChild("Built")
			if not result then
				return true -- aimed at the sky: nothing to build on, but no swing either
			elseif tool.block then
				actionRemote:FireServer("build", blockSpot(result, built), tool.block, tool.material)
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
		building = function(): boolean -- BUILD is on: no weapon bar (init, WeaponBar)
			return buildMode
		end,
	}
end

return Toolbox
