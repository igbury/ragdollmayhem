-- Toolbox (Tab): a page per tab down the left. SPAWN: a character on a stage, its team and how many,
-- then SPAWN! (or G) where you aim. BUILD: the blocks, and building with them (the block wheel on Q and
-- the trash, instead of the weapons). WORLD: time stop, clearing the dummies, team paint. WARDROBE: a style
-- of catalog clothes (shared/Wardrobe) on a mannequin, then SELECT: the bar's 1 dresses the dummy you
-- click in it, 2 puts its own clothes back. The server
-- checks and does it all (server/init.server.luau, "spawn" / "clearspawn" / "build" / "team" / "freeze" / "dress").
-- Items with a `pass` are that game pass's (shared/Shop): locked, they wear its sticker and offer it.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))
local Wardrobe = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Wardrobe"))
local Audio =require(script.Parent:WaitForChild("Music")) -- the sound settings (SETTINGS page)
local PerfMode = require(script.Parent:WaitForChild("PerfMode"))

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
	-- off for now (server VEHICLES_ENABLED): { name = "Police car", kind = "PoliceCar", color = Color3.fromRGB(42, 45, 54) }, -- server/PoliceCar: T by the door gets in, Space out
	-- off for now (server VEHICLES_ENABLED): { name = "Sport car", kind = "SportCar", color = Color3.fromRGB(227, 36, 43) }, -- the same, and it smashes apart like the map
	-- off for now (server VEHICLES_ENABLED): { name = "Tank", kind = "Tank", color = Color3.fromRGB(201, 178, 124) }, -- server/Tank: turret, gun, breaks apart too
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
-- WARDROBE's bar: a click on a dummy dresses it in your style (1) or back in its own clothes (2)
local PINK = Color3.fromRGB(200, 70, 140)
local DRESS = { name = "Outfit", dress = true }
local UNDRESS = { name = "Reset", dress = false }

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
	-- a figure by its height (a car by its length: it turns on the stage), a cube from any side
	local fit = if model:IsA("Model") then math.max(size.X, size.Y, size.Z) * 1.15 else size.Magnitude * 1.05
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
	local wardrobe = false -- the bar is WARDROBE's (dress / reset), not the blocks
	local function current() -- what a click does now: a block, the trash, a team, an outfit, or nothing
		if buildMode and wardrobe then
			return if trashing then UNDRESS else DRESS
		elseif buildMode then
			return if trashing then TRASH else brick
		end
		return if building then tool else nil
	end
	local setBuild: (boolean, boolean?) -> () -- below, with the build bar

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
		if on then
			actionRemote:FireServer("opened", "Toolbox") -- the Menus funnel (server/Funnels)
		end
		Sfx.ui(if on then Sfx.UI_OPEN else Sfx.UI_CLOSE, 0.5)
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
		{ name = "WARDROBE", color = PINK },
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
		label.TextSize = if #t.name > 6 then 24 else 30
		tabs[i] = b
		local page = Instance.new("Frame")
		page.Name, page.BackgroundTransparency, page.Size, page.ZIndex, page.Parent = t.name, 1, UDim2.fromScale(1, 1), 42, area
		pages[i] = page
		b.Activated:Connect(function()
			showTab(i)
			actionRemote:FireServer("opened", if i == 1 then "Toolbox" else string.upper(t.name:sub(1, 1)) .. string.lower(t.name:sub(2)))
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
	passSticker(heading(spawnSide, "HOW MANY", 5), "SandboxPlus")
	local countRow = row(spawnSide, 6, 44)
	local countLabel = Instance.new("TextLabel")
	local function stepper(text: string, by: number, order: number)
		local b = button(countRow, text, YELLOW, 44, true)
		b.Size, b.LayoutOrder = UDim2.fromOffset(46, 40), order
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize, label.TextColor3, label.TextStrokeTransparency = 30, INK, 1
		b.Activated:Connect(function()
			if by > 0 and locked({ pass = "SandboxPlus" }) then -- more than 1 at once is SANDBOX +
				return
			end
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
	local paintHead = heading(worldSide, "TEAM PAINT", 5)
	local paintRow = row(worldSide, 6, 48)
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
	hint(worldSide, "Pick a colour, then click dummies to put them in that team. Teams fight each other.", 7)

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

	-- SETTINGS: a second title beside TOOLBOX!, its own page in place of the tabs (the sound, client/Music)
	local settingsTitle = button(panel, "SETTINGS", Color3.fromRGB(70, 60, 150), 46, true)
	settingsTitle.Size, settingsTitle.Position, settingsTitle.Rotation = UDim2.fromOffset(190, 40), UDim2.fromOffset(250, -10), 3
	local settingsLabel = settingsTitle:FindFirstChild("Label") :: TextLabel
	settingsLabel.TextSize = 24
	local settingsPage = Instance.new("ScrollingFrame") -- sound and game settings: more than fits, it scrolls
	settingsPage.Name, settingsPage.BackgroundTransparency, settingsPage.Visible, settingsPage.ZIndex = "Settings", 1, false, 42
	settingsPage.BorderSizePixel, settingsPage.ScrollBarThickness, settingsPage.ScrollBarImageColor3 = 0, 8, INK
	settingsPage.CanvasSize, settingsPage.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
	settingsPage.Position, settingsPage.Size, settingsPage.Parent = UDim2.fromOffset(30, 56), UDim2.new(1, -60, 1, -70), panel
	local settingsList = Instance.new("UIListLayout")
	settingsList.Padding, settingsList.SortOrder, settingsList.Parent = UDim.new(0, 14), Enum.SortOrder.LayoutOrder, settingsPage
	local function showSettings(on: boolean)
		settingsPage.Visible = on
		area.Visible, rule.Visible = not on, not on
		for _, b in tabs do
			b.Visible = not on
		end
		pick(title, not on)
		pick(settingsTitle, on)
		titleLabel.TextTransparency = if on then 0.4 else 0
		settingsLabel.TextTransparency = if on then 0 else 0.4
	end
	title.Activated:Connect(function()
		showSettings(false)
	end)
	settingsTitle.Activated:Connect(function()
		showSettings(true)
		actionRemote:FireServer("opened", "Settings")
	end)
	local function label(parent: Instance, text: string)
		local l = Instance.new("TextLabel")
		l.Text, l.Font, l.TextSize, l.TextColor3, l.BackgroundTransparency = text, FONT, 26, INK, 1
		l.TextXAlignment, l.Size, l.LayoutOrder, l.ZIndex, l.Parent = Enum.TextXAlignment.Left, UDim2.fromOffset(280, 44), 0, 44, parent
	end
	local shows = {} -- each control's redraw, run whenever a setting changes
	-- ON / OFF for a boolean setting; `off` names a setting that is on when false (MusicOff, NeverWanted).
	-- `get` / `set`: for a setting that is not a plain boolean (PerfMode: "auto" / "on" / "off").
	local function toggle(text: string, name: string, order: number, off: boolean?, get: (() -> boolean)?, set: ((boolean) -> ())?)
		local r = row(settingsPage, order, 50)
		label(r, text)
		local b = button(r, "ON", Color3.fromRGB(40, 140, 70), 44, true)
		b.Size, b.LayoutOrder = UDim2.fromOffset(130, 44), 1
		local l = b:FindFirstChild("Label") :: TextLabel
		l.TextSize = 24
		b.Activated:Connect(function()
			if set and get then
				set(not get())
			else
				Audio.set(name, not Audio.get(name))
			end
		end)
		table.insert(shows, function()
			local on = if get then get() else Audio.get(name) ~= (off == true)
			l.Text = if on then "ON" else "OFF"
			local fill = b:FindFirstChild("Fill")
			local shade = fill and fill:FindFirstChildOfClass("UIGradient")
			if shade then
				local color = if on then Color3.fromRGB(40, 140, 70) else Color3.fromRGB(143, 46, 44)
				shade.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.25)),
					ColorSequenceKeypoint.new(0.55, color),
					ColorSequenceKeypoint.new(1, color:Lerp(INK, 0.35)),
				})
			end
		end)
	end
	-- a number setting: - and + by `by`, a bar between them filled from its min to its max
	-- (Audio.RANGE, else 0-1). `times`: shown as x1.5 instead of a percentage.
	local function slider(text: string, name: string, order: number, by: number, times: boolean?)
		local range = Audio.RANGE[name] or { 0, 1 }
		local r = row(settingsPage, order, 50)
		label(r, text)
		local function step(sign: string, delta: number, at: number)
			local b = button(r, sign, YELLOW, 44, true)
			b.Size, b.LayoutOrder = UDim2.fromOffset(46, 44), at
			local l = b:FindFirstChild("Label") :: TextLabel
			l.TextSize, l.TextColor3, l.TextStrokeTransparency = 30, INK, 1
			b.Activated:Connect(function()
				Audio.set(name, math.clamp(math.round((Audio.get(name) + delta) * 10) / 10, range[1], range[2]))
			end)
		end
		step("-", -by, 1)
		local bar = Instance.new("Frame")
		bar.BackgroundColor3, bar.BorderSizePixel, bar.Size, bar.LayoutOrder, bar.ZIndex = WHITE, 0, UDim2.fromOffset(220, 34), 2, 44
		bar.Parent = r
		outline(bar, 3)
		local fill = Instance.new("Frame")
		fill.BackgroundColor3, fill.BorderSizePixel, fill.ZIndex, fill.Parent = Color3.fromRGB(40, 140, 70), 0, 45, bar
		local value = Instance.new("TextLabel")
		value.Font, value.TextSize, value.TextColor3, value.BackgroundTransparency = FONT, 22, INK, 1
		value.Size, value.Position, value.ZIndex, value.Parent = UDim2.fromScale(1, 1), UDim2.fromOffset(0, NUDGE), 46, bar
		step("+", by, 3)
		table.insert(shows, function()
			local v = Audio.get(name)
			fill.Size = UDim2.fromScale((v - range[1]) / (range[2] - range[1]), 1)
			value.Text = if times then `x{v}` else `{math.round(v * 100)}%`
		end)
	end
	heading(settingsPage, "SOUND", 1)
	toggle("MUSIC", "MusicOff", 2, true)
	slider("MUSIC VOLUME", "MusicVolume", 3, 0.1)
	slider("EFFECTS VOLUME", "SfxVolume", 4, 0.1)
	heading(settingsPage, "GAME", 6)
	toggle("WANTED STARS", "NeverWanted", 7, true)
	toggle("RAGDOLL DAMAGE", "RagdollDamage", 8)
	toggle("GRAVE ZOMBIES", "GraveZombies", 9)
	toggle("BURNING DUMMIES", "BurningDummies", 10)
	slider("BONE BREAKING", "BoneScale", 11, 0.5, true)
	slider("GRAVITY", "Gravity", 12, 0.1, true)
	slider("DAMAGE", "DamageScale", 13, 0.5, true)
	heading(settingsPage, "GRAPHICS", 15)
	toggle("PERFORMANCE MODE", "PerfMode", 16, false, PerfMode.wanted, function(v: boolean)
		Audio.set("PerfMode", if v then "on" else "off")
	end)
	hint(settingsPage, "Saved with your progress. Gravity, ragdoll damage, grave zombies and burning dummies follow whoever joined the server first. Performance mode turns itself on for phones.", 17)
	local function showSettingsValues()
		for _, show in shows do
			show()
		end
	end
	showSettingsValues()
	Audio.changed:Connect(showSettingsValues)
	showSettings(false)

	close.Activated:Connect(function()
		setOpen(false)
	end)
	UIS.InputBegan:Connect(function(input, processed)
		if UIS:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab then
			if not cover.Visible and buildMode then -- Tab ends building (or dressing), and opens on BUILD (WARDROBE)
				local page = if wardrobe then 4 else 2
				setBuild(false)
				showTab(page)
				showSettings(false)
			end
			setOpen(not cover.Visible)
		elseif cover.Visible and input.KeyCode == Enum.KeyCode.Escape and not processed then
			setOpen(false)
		end
	end)

	-- Build bar (in place of the weapons' hotbar): the block in hand (1), the trash (2), back to the weapons (3)
	local buildBar = Instance.new("Frame")
	buildBar.Name, buildBar.BackgroundTransparency, buildBar.Visible = "BuildBar", 1, false
	buildBar.AnchorPoint, buildBar.Position, buildBar.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -16), UDim2.fromOffset(330, 130)
	buildBar.ZIndex, buildBar.Parent = 30, gui
	local barHint = Instance.new("TextLabel")
	barHint.Text, barHint.Font, barHint.TextSize, barHint.TextColor3 = "HOLD Q  MORE BLOCKS", FONT, 16, WHITE
	barHint.TextStrokeTransparency, barHint.BackgroundTransparency = 0, 1
	barHint.Size, barHint.Position, barHint.ZIndex, barHint.Parent = UDim2.new(1, 200, 0, 20), UDim2.new(0, -100, 0, -4), 31, buildBar
	local function iconTile(parent, icon: string, caption: string, color: Color3): TextButton
		local b = button(parent, icon, color)
		local label = b:FindFirstChild("Label") :: TextLabel
		label.TextSize, label.Size = 40, UDim2.new(1, 0, 1, -CAPTION)
		local name = Instance.new("TextLabel")
		name.Name, name.Text, name.Font, name.TextSize, name.TextColor3 = "Caption", caption, FONT, 17, WHITE
		name.TextStrokeTransparency, name.BackgroundTransparency, name.ZIndex = 0, 1, b.ZIndex + 1
		name.AnchorPoint, name.Position, name.Size = Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0, CAPTION)
		name.Parent = b
		return b
	end
	local brickSlot: GuiObject
	local trashSlot = iconTile(buildBar, "🗑", "TRASH", TRASH.color)
	trashSlot.Size, trashSlot.Position, trashSlot.ZIndex = UDim2.fromOffset(100, 100), UDim2.fromOffset(115, 24), 31
	local function keyBadge(slot: GuiObject, key: string) -- the number key, on the slot's top-left corner
		local k = Instance.new("TextLabel")
		k.Text, k.Font, k.TextSize, k.TextColor3, k.BackgroundColor3 = key, FONT, 18, INK, WHITE
		k.BorderSizePixel, k.Position, k.Size, k.ZIndex, k.Parent = 0, UDim2.fromOffset(-8, -8), UDim2.fromOffset(24, 24), 48, slot
		outline(k, 2)
	end
	keyBadge(trashSlot, "2")
	local weaponsSlot = button(buildBar, "WEAPONS", RED, 31, true) -- out of building, like Tab
	weaponsSlot.Size, weaponsSlot.Position = UDim2.fromOffset(100, 100), UDim2.fromOffset(225, 24)
	local weaponsLabel = weaponsSlot:FindFirstChild("Label") :: TextLabel
	weaponsLabel.TextSize, weaponsLabel.TextColor3 = 20, YELLOW
	keyBadge(weaponsSlot, "3")
	weaponsSlot.Activated:Connect(function()
		setBuild(false)
	end)
	local function mark(slot: GuiObject, on: boolean)
		local stroke = slot:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color, stroke.Thickness = on and YELLOW or INK, on and 6 or 3
	end
	local function showBar()
		if brickSlot then
			brickSlot:Destroy()
		end
		brickSlot = if wardrobe then iconTile(buildBar, "👕", "OUTFIT", PINK) else blockTile(buildBar, brick)
		brickSlot.Size, brickSlot.Position = UDim2.fromOffset(100, 100), UDim2.fromOffset(5, 24)
		keyBadge(brickSlot, "1")
		brickSlot.Activated:Connect(function()
			trashing = false
			showBar()
		end)
		mark(brickSlot, not trashing)
		mark(trashSlot, trashing)
		;(trashSlot:FindFirstChild("Label") :: TextLabel).Text = if wardrobe then "🔄" else "🗑"
		;(trashSlot:FindFirstChild("Caption") :: TextLabel).Text = if wardrobe then "RESET" else "TRASH"
		barHint.Text = if wardrobe then "CLICK A DUMMY TO DRESS IT" else "HOLD Q  MORE BLOCKS"
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

	setBuild = function(on: boolean, wear: boolean?) -- wear: the WARDROBE bar instead of the blocks
		if on and not buildMode then
			api.set(1) -- the fists, so no weapon is left drawn; this also stops a team tool
		end
		buildMode, wardrobe, trashing = on, on and wear == true, false
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
		setBuild(wardrobe or not buildMode)
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
		startLabel.Text = if buildMode and not wardrobe then "STOP BUILDING" else "START BUILDING!"
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

	-- WARDROBE: the mannequin in your style on a stage (server/Dresser builds it into PlayerGui), the
	-- catalog beside it, SELECT ----------------------------------------------------------------------
	do
		local page = pages[4]
		local _, view, setColor, setName = stage(page)
		setColor(PINK:Lerp(INK, 0.3))
		setName("Mannequin")
		local shown: Model? = nil
		turning(function()
			return shown
		end)
		local playerGui = player:WaitForChild("PlayerGui")
		local function showPreview(source: Instance)
			if source.Name ~= "WardrobePreview" or not source:IsA("Model") then
				return
			end
			if shown then
				shown:Destroy()
			end
			local model = source:Clone()
			model.Parent = view
			frame(view, model, Vector3.new(0, 0, -1)) -- it faces -Z, toward the camera
			shown = model
		end
		playerGui.ChildAdded:Connect(showPreview)
		local first = playerGui:FindFirstChild("WardrobePreview")
		if first then
			showPreview(first)
		end

		local side = Instance.new("ScrollingFrame") -- three catalogs and their colours: more than fits
		side.BackgroundTransparency, side.BorderSizePixel, side.ZIndex = 1, 0, 43
		side.ScrollBarThickness, side.ScrollBarImageColor3 = 8, INK
		side.CanvasSize, side.AutomaticCanvasSize = UDim2.new(), Enum.AutomaticSize.Y
		side.Position, side.Size, side.Parent = UDim2.new(0.5, 6, 0, 0), UDim2.new(0.5, -6, 1, 0), page
		local list = Instance.new("UIListLayout")
		list.Padding, list.SortOrder, list.Parent = UDim.new(0, 8), Enum.SortOrder.LayoutOrder, side

		local style = Wardrobe.parse(Audio.get("Wardrobe"))
		local itemChips, colorChips = {}, {} -- [category] = { [index] = chip }
		local function showStyle()
			for i, chips in itemChips do
				for k, b in chips do
					pick(b, style.items[i] == k)
				end
			end
			for i, chips in colorChips do
				for k, b in chips do
					pick(b, style.colors[i] == k)
				end
			end
		end
		local function choose(i: number, field: string, k: number)
			style[field][i] = k
			showStyle()
			Audio.set("Wardrobe", Wardrobe.format(style)) -- kept, and saved with the progress
		end
		for i, category in Wardrobe.CATEGORIES do
			heading(side, category.name, i * 10)
			local grid = Instance.new("Frame")
			grid.BackgroundTransparency, grid.Size, grid.AutomaticSize = 1, UDim2.new(1, -12, 0, 0), Enum.AutomaticSize.Y
			grid.LayoutOrder, grid.ZIndex, grid.Parent = i * 10 + 1, 43, side
			local layout = Instance.new("UIGridLayout")
			layout.CellSize, layout.CellPadding = UDim2.new(0.25, -6, 0, 72), UDim2.fromOffset(6, 6)
			layout.SortOrder, layout.Parent = Enum.SortOrder.LayoutOrder, grid
			itemChips[i], colorChips[i] = {}, {}
			for k = 0, #category.items do
				local item = category.items[k]
				local b = button(grid, if item then "" else "NONE", if item then WHITE else Color3.fromRGB(110, 110, 118), 44, true)
				b.LayoutOrder = k
				if item then
					local thumb = Instance.new("ImageLabel")
					thumb.BackgroundTransparency, thumb.ZIndex = 1, 45
					thumb.Image = `rbxthumb://type=Asset&id={item.id}&w=150&h=150`
					thumb.Position, thumb.Size = UDim2.fromOffset(3, 3), UDim2.new(1, -6, 1, -6)
					thumb.ScaleType, thumb.Parent = Enum.ScaleType.Fit, b
				end
				itemChips[i][k] = b
				b.Activated:Connect(function()
					choose(i, "items", k)
				end)
			end
			local colors = row(side, i * 10 + 2, 34)
			for k, color in Wardrobe.COLORS do
				local b = button(colors, if k == 1 then "-" else "", color, 44, true)
				b.Size, b.LayoutOrder = UDim2.fromOffset(28, 28), k
				local l = b:FindFirstChild("Label") :: TextLabel
				l.TextColor3, l.TextStrokeTransparency = INK, 1
				colorChips[i][k] = b
				b.Activated:Connect(function()
					choose(i, "colors", k)
				end)
			end
		end
		local selectButton = button(side, "SELECT", PINK, 44, true)
		selectButton.Size, selectButton.LayoutOrder, selectButton.Rotation = UDim2.new(1, -20, 0, 66), 100, -2
		local selectLabel = selectButton:FindFirstChild("Label") :: TextLabel
		selectLabel.TextSize, selectLabel.TextColor3 = 36, YELLOW
		selectButton.Activated:Connect(function()
			setOpen(false)
			setBuild(true, true)
		end)
		hint(side, "Then click dummies: 1 dresses them in this, 2 puts their own clothes back, 3 weapons.", 101)
		player:GetAttributeChangedSignal("Wardrobe"):Connect(function() -- the saved one, once loaded
			style = Wardrobe.parse(Audio.get("Wardrobe"))
			showStyle()
		end)
		showStyle()
	end

	UIS.InputBegan:Connect(function(input, processed)
		if not buildMode or processed or cover.Visible or api.blocked() or UIS:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q and not wheel.Visible and not wardrobe then
			showWheel(true)
		elseif input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.Two then
			trashing = input.KeyCode == Enum.KeyCode.Two
			showBar()
		elseif input.KeyCode == Enum.KeyCode.Three then
			task.defer(setBuild, false) -- after this key's other handlers: the hotbar must not take its 3 too
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
		elseif tool.team or tool.dress ~= nil then
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
			elseif tool.dress ~= nil then
				local dummy = dummyAt(result)
				if dummy then
					actionRemote:FireServer("dress", dummy, tool.dress)
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
