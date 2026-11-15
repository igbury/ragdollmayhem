-- Main menu: a full-screen comic page. Panels: STATS, SHOP, MAP, PLAY (bottom-left) and a
-- rectangular scene with the player's avatar on a chair (MenuPuppet). Panels are real polygons:
-- seam lines are offset by half a gutter, intersected into corners, and each panel is cut to shape by nested CanvasGroups with a hard-stepped UIGradient per
-- slanted edge (cut()). Outlines are lines drawn corner to corner, so every edge meets its neighbour.
-- Shading: gradient fills, a tiled halftone (assets/fx/make_halftone.py), drop shadows, 3D lettering.
-- Motion: one render step drives spinning / streaming rays, bobbing titles, hover and the PLAY burst.
-- Menu.active is true until Play is pressed; the rest of the client ignores input while it is.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MenuPuppet = require(script.Parent:WaitForChild("MenuPuppet"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local NAVY = Color3.fromRGB(44, 58, 94)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(20, 20, 24)
local GREEN = Color3.fromRGB(104, 146, 56)
local YELLOW = Color3.fromRGB(252, 200, 50)
local RED = Color3.fromRGB(232, 70, 56)
local BLUE = Color3.fromRGB(40, 70, 140)
local ORANGE = Color3.fromRGB(255, 170, 40)
local IDLE = Color3.fromRGB(228, 228, 228) -- panel tint at rest; hover lifts it to white
local FONT = Enum.Font.LuckiestGuy
local BURST_IMAGE = "rbxassetid://121244599706688" -- same starburst as Fx.pop
local HALFTONE_IMAGE = "rbxassetid://82675619059195" -- assets/fx/halftone.png, 64px tile
local MAPS = { "ARENA", "FACTORY" } -- keys of SPAWNS on the server
local POWS = { "POW!", "BAM!", "ZOOM!", "WHAM!", "BOOM!" }
local MARGIN = 16 -- px of white page round the panels
local GAP = 9 -- px, half the white gutter between panels
local INK = 4 -- px, outline thickness

-- Seam lines across the page, each through two points in page scale (extended to infinity).
-- The player scene is a plain rectangle (HS, VS); H1 meets HS on VS so LOADOUT stays convex.
local SEAMS = {
	H1 = { Vector2.new(0, 0.24), Vector2.new(0.6, 0.31) }, -- under MAP, over STATS
	HS = { Vector2.new(0, 0.31), Vector2.new(1, 0.31) }, -- under LOADOUT, over the scene
	VS = { Vector2.new(0.6, 0), Vector2.new(0.6, 1) }, -- STATS / PLAY | scene
	V1 = { Vector2.new(0.52, 0), Vector2.new(0.42, 0.29) }, -- MAP | LOADOUT
	H2 = { Vector2.new(0, 0.53), Vector2.new(0.6, 0.61) }, -- STATS over PLAY
	TOP = { Vector2.new(0, 0), Vector2.new(1, 0) },
	BOTTOM = { Vector2.new(0, 1), Vector2.new(1, 1) },
	LEFT = { Vector2.new(0, 0), Vector2.new(0, 1) },
	RIGHT = { Vector2.new(1, 0), Vector2.new(1, 1) },
}
local OUTER = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true }

-- A horizontal or vertical edge of a convex panel lies on its bounding box, so it needs no cut.
-- (Fewer CanvasGroups matters: over the texture budget, effects inside them stop rendering.)
local function slanted(name: string): boolean
	local a, b = SEAMS[name][1], SEAMS[name][2]
	return a.X ~= b.X and a.Y ~= b.Y
end

local Menu = { active = true }
local mapIndex = 1
local tickers: { (number) -> () } = {} -- run every frame with the time since the menu opened
local start = os.clock()

-- Sink walking input while the menu is up (no PlayerModule dependency).
ContextActionService:BindActionAtPriority("MenuSink", function()
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right)
camera.CameraType = Enum.CameraType.Scriptable

local blur = Instance.new("BlurEffect")
blur.Size = 16
blur.Parent = Lighting

local gui = Instance.new("ScreenGui")
gui.Name = "Menu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- ZIndex below is per parent
gui.Parent = player:WaitForChild("PlayerGui")

local function new(class: string, parent: Instance?, props): any
	local o = Instance.new(class)
	if o:IsA("GuiObject") then
		o.BorderSizePixel = 0
	end
	for k, v in props or {} do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function tween(o: Instance, t: number, goal, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function stroke(parent: Instance, thickness: number, color: Color3?)
	return new("UIStroke", parent, { Thickness = thickness, Color = color or BLACK, LineJoinMode = Enum.LineJoinMode.Miter })
end

-- Top-to-bottom shading: light on top, deep (toward ink, default black) at the bottom.
local function shade(parent: Instance, color: Color3, rotation: number?, ink: Color3?)
	return new("UIGradient", parent, {
		Rotation = rotation or 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.3)),
			ColorSequenceKeypoint.new(0.55, color),
			ColorSequenceKeypoint.new(1, ink or color:Lerp(BLACK, 0.35)),
		}),
	})
end

-- Comic lettering: scaled text with a black outline.
local function letters(parent: Instance, text: string, props): TextLabel
	local l = new("TextLabel", parent, { BackgroundTransparency = 1, Font = FONT, Text = text, TextScaled = true, TextColor3 = WHITE })
	for k, v in props do
		l[k] = v
	end
	if l.TextColor3 ~= BLACK then -- black lettering on white needs no outline
		stroke(l, 3)
	end
	return l
end

-- 3D lettering: a black copy pushed down-right, then the shaded word on top. Returns both.
local function bigLetters(parent: Instance, text: string, color: Color3, props): (TextLabel, TextLabel)
	local back = letters(parent, text, props)
	back.TextColor3 = BLACK
	stroke(back, 3) -- same outline as the word, so TextScaled fits both the same
	back.Position += UDim2.fromOffset(5, 6)
	local word = letters(parent, text, props)
	word.ZIndex = back.ZIndex + 1
	shade(word, color)
	return word, back
end

-- Printed dot shading, dense toward the bottom-right.
local function halftone(parent: GuiObject, color: Color3, zIndex: number)
	local dots = new("ImageLabel", parent, {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = HALFTONE_IMAGE,
		ImageColor3 = color,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(13, 13),
		ZIndex = zIndex,
	})
	new("UIGradient", dots, {
		Rotation = 35,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 0.9),
			NumberSequenceKeypoint.new(1, 0.15),
		}),
	})
	return dots
end

-- Rays from a point (scale coords, inside a clipping panel): wide ones read as a sunburst, thin ones
-- as speed lines. spin turns them (deg/s), stream slides them in toward the centre (px/s).
-- Returns the centre frame, so a panel can move the burst onto its own centroid (layout()).
local function rays(parent: GuiObject, cx: number, cy: number, count: number, width: number, inner: number, color: Color3, transparency: number, spin: number, stream: number?): Frame
	local centre = new("Frame", parent, { BackgroundTransparency = 1, Position = UDim2.fromScale(cx, cy), ZIndex = 2 })
	local bars = {}
	for i = 1, count do
		local hub = new("Frame", centre, { BackgroundTransparency = 1 })
		local w = width * (1 + (i % 2) * 0.6)
		local bar = new("Frame", hub, { BackgroundColor3 = color, BackgroundTransparency = transparency, Size = UDim2.fromOffset(2000, w), Position = UDim2.fromOffset(inner + (i % 4) * 25, -w / 2) })
		bars[i] = { hub = hub, bar = bar, angle = i * 360 / count + (i % 3) * 2, w = w, phase = (i * 37) % 140 }
	end
	table.insert(tickers, function(t: number)
		for _, b in bars do
			b.hub.Rotation = b.angle + spin * t
			if stream then
				b.bar.Position = UDim2.fromOffset(inner + (b.phase - stream * t) % 140, -b.w / 2)
			end
		end
	end)
	return centre
end

-- Polygon geometry (page pixels) ---------------------------------------------------------------
-- A seam moved `off` px along its normal toward `inside`: returns a point, direction, inward normal.
local function offsetLine(name: string, size: Vector2, inside: Vector2, off: number): (Vector2, Vector2, Vector2)
	local a, b = SEAMS[name][1] * size, SEAMS[name][2] * size
	local d = (b - a).Unit
	local n = Vector2.new(-d.Y, d.X)
	if (inside - a):Dot(n) < 0 then
		n = -n
	end
	return a + n * off, d, n
end

local function intersect(p: Vector2, d: Vector2, q: Vector2, e: Vector2): Vector2
	local cross = d.X * e.Y - d.Y * e.X
	local t = ((q.X - p.X) * e.Y - (q.Y - p.Y) * e.X) / cross
	return p + d * t
end

-- Cut a CanvasGroup of the given pixel size along a line (point a, inward normal n, both local):
-- the side n points to stays. UIGradient runs in pixels from the box centre, its 0..1 spanning
-- 2 * min(W / |cos r|, H / |sin r|) (measured in Studio).
local function cut(gradient: UIGradient, size: Vector2, a: Vector2, n: Vector2)
	local r = math.atan2(n.Y, n.X)
	local c, s = math.abs(math.cos(r)), math.abs(math.sin(r))
	local span = math.min(c > 1e-4 and size.X / c or math.huge, s > 1e-4 and size.Y / s or math.huge)
	local soft = 1.2 / span -- about a pixel of antialiasing
	local t0 = math.clamp(0.5 + (a - size / 2):Dot(n) / span, soft, 1 - soft * 2)
	gradient.Rotation = math.deg(r)
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(t0, 1),
		NumberSequenceKeypoint.new(t0 + soft, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
end

local function inside(poly: { Vector2 }, p: Vector2): boolean
	local sign = 0
	for i, a in poly do
		local b = poly[i % #poly + 1]
		local cross = (b.X - a.X) * (p.Y - a.Y) - (b.Y - a.Y) * (p.X - a.X)
		if cross ~= 0 then
			if sign ~= 0 and (cross > 0) ~= (sign > 0) then
				return false
			end
			sign = cross
		end
	end
	return true
end

-- Page -----------------------------------------------------------------------------------------
local back = new("Frame", gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
shade(back, NAVY, 70)
halftone(back, BLACK, 1).ImageTransparency = 0.6
local PAGE_HOME = UDim2.fromScale(0.5, 0.5)
local pageShadow = new("Frame", back, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 14, 1.6, 16),
	Size = UDim2.fromScale(0.97, 0.95),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.5,
	ZIndex = 2,
})
local page = new("Frame", back, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 1.6), -- slides up
	Size = UDim2.fromScale(0.97, 0.95),
	BackgroundColor3 = WHITE,
	ZIndex = 3,
})

-- Panels ---------------------------------------------------------------------------------------
-- Each panel: its boundary seams in order round the polygon, a point inside it (page scale), its
-- colours, and the page-scale box its title sits in.
type Panel = {
	edges: { string },
	inside: Vector2,
	color: Color3,
	ink: Color3,
	inset: number?,
	burst: Frame?, -- rays centre, kept on the polygon's centroid -- share of the bounding box the overlay (titles) covers, centred on the panel
	outer: GuiObject?,
	clip: Frame?,
	groups: { CanvasGroup }?,
	gradients: { UIGradient }?,
	content: CanvasGroup?,
	lines: { Frame }?,
	overlay: Frame?,
	poly: { Vector2 }?,
	words: { TextLabel }?,
	wordScales: { UIScale }?,
	onClick: (() -> ())?,
}
local PANELS: { Panel } = {
	{ edges = { "TOP", "V1", "H1", "LEFT" }, inside = Vector2.new(0.18, 0.13), color = GREEN, ink = Color3.fromRGB(30, 70, 25) },
	{ edges = { "TOP", "RIGHT", "HS", "H1", "V1" }, inside = Vector2.new(0.75, 0.15), color = YELLOW, ink = Color3.fromRGB(235, 105, 25) },
	{ edges = { "H1", "VS", "H2", "LEFT" }, inside = Vector2.new(0.3, 0.42), color = RED, ink = Color3.fromRGB(140, 15, 30) },
	{ edges = { "H2", "VS", "BOTTOM", "LEFT" }, inside = Vector2.new(0.3, 0.88), color = YELLOW, ink = Color3.fromRGB(235, 105, 25) },
	{ edges = { "HS", "RIGHT", "BOTTOM", "VS" }, inside = Vector2.new(0.8, 0.7), color = BLUE, ink = Color3.fromRGB(10, 20, 60), inset = 1 },
}

for _, p in PANELS do
	-- A clipping frame the size of the bounding box does the straight edges; inside it, one nested
	-- CanvasGroup per slanted edge does the cuts. The groups are a square as wide as the box's
	-- diagonal: a UIGradient only reaches min(W/|cos|, H/|sin|) round its centre and clamps past
	-- that, so on a long flat box a seam through a corner (V1 on STATS) was out of its reach and the
	-- cut fell short, leaving a white strip. A panel with no slanted edge is just the clipping frame
	-- (the scene's ViewportFrame stays out of CanvasGroups that way).
	local clip = new("Frame", page, { BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 })
	local groups, parent = {}, clip
	for _, edge in p.edges do
		if slanted(edge) then
			local g = new("CanvasGroup", parent, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), GroupColor3 = #groups == 0 and IDLE or WHITE, ZIndex = 2 })
			new("UIGradient", g, {})
			table.insert(groups, g)
			parent = g
		end
	end
	p.clip, p.groups, p.content, p.outer = clip, groups, parent, groups[1] or clip
	local fill = new("Frame", parent, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
	p.gradients = { shade(fill, p.color, 60, p.color:Lerp(p.ink, 0.5)), halftone(parent, p.ink, 3):FindFirstChildOfClass("UIGradient") :: UIGradient }
	p.lines = {}
	for i = 1, #p.edges do
		p.lines[i] = new("Frame", page, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = BLACK, ZIndex = 4 })
	end
	p.overlay = new("Frame", page, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 }) -- placed by layout()
end

-- Engine quirk: a UIGradient deep in nested CanvasGroups can render stale (a blue panel came out
-- grey) until it changes; flicking Enabled once makes the group redraw it.
local function kick(p: Panel)
	for _, g in p.gradients :: { UIGradient } do
		g.Enabled = false
	end
	task.defer(function()
		for _, g in p.gradients :: { UIGradient } do
			g.Enabled = true
		end
	end)
end

-- Recompute every polygon from the page's pixel size (on open and on any resize).
local function layout()
	local size = page.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return
	end
	for _, p in PANELS do
		local inner = p.inside * size
		local lines = {}
		for i, edge in p.edges do
			local a, d, n = offsetLine(edge, size, inner, OUTER[edge] and MARGIN or GAP)
			lines[i] = { a = a, d = d, n = n, edge = edge }
		end
		local poly = {}
		for i, line in lines do
			local nextLine = lines[i % #lines + 1]
			poly[i] = intersect(line.a, line.d, nextLine.a, nextLine.d) -- corner where this edge meets the next
		end
		p.poly = poly
		local lo, hi = poly[1], poly[1]
		for _, v in poly do
			lo, hi = lo:Min(v), hi:Max(v)
		end
		lo, hi = Vector2.new(math.floor(lo.X), math.floor(lo.Y)), Vector2.new(math.ceil(hi.X), math.ceil(hi.Y))
		local box = hi - lo
		local clip = p.clip :: Frame
		clip.Position = UDim2.fromOffset(lo.X, lo.Y)
		clip.Size = UDim2.fromOffset(box.X, box.Y)
		local origin, cutSize = lo, box -- page position and size of the content's frame
		local groups = p.groups :: { CanvasGroup }
		if #groups > 0 then
			local side = math.ceil(box.Magnitude)
			local offset = Vector2.new(math.floor((box.X - side) / 2), math.floor((box.Y - side) / 2))
			groups[1].Position = UDim2.fromOffset(offset.X, offset.Y)
			groups[1].Size = UDim2.fromOffset(side, side)
			origin, cutSize = lo + offset, Vector2.new(side, side)
		end
		-- titles sit on the polygon's area centroid (a plain mean of the corners leans toward
		-- corners that bunch up, like SHOP's two at the bottom-left)
		local area, centre = 0, Vector2.zero
		for i, a in poly do
			local b = poly[i % #poly + 1]
			local cross = a.X * b.Y - b.X * a.Y
			area += cross
			centre += (a + b) * cross
		end
		centre /= 3 * area
		local overlay = p.overlay :: Frame
		overlay.Position = UDim2.fromOffset(centre.X, centre.Y)
		overlay.Size = UDim2.fromOffset(box.X * (p.inset or 0.72), box.Y * (p.inset or 0.72))
		if p.burst then
			p.burst.Position = UDim2.fromOffset(centre.X - origin.X, centre.Y - origin.Y)
		end
		local g = 1
		for _, line in lines do
			if slanted(line.edge) then
				cut(groups[g]:FindFirstChildOfClass("UIGradient") :: UIGradient, cutSize, line.a - origin, line.n)
				g += 1
			end
		end
		-- outlines run corner to corner plus half a stroke past each end, so corners close up
		for i, a in poly do
			local b = poly[i % #poly + 1]
			local along = b - a
			local frame = (p.lines :: { Frame })[i]
			local mid = (a + b) / 2
			frame.Position = UDim2.fromOffset(mid.X, mid.Y)
			frame.Size = UDim2.fromOffset(along.Magnitude + INK, INK)
			frame.Rotation = math.deg(math.atan2(along.Y, along.X))
		end
		kick(p)
	end
end
page:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

-- Click feedback: a comic word in a starburst at the mouse, and the page jolts.
local function pow(word: string?)
	local at = UserInputService:GetMouseLocation()
	local holder = new("Frame", gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(at.X, at.Y), Size = UDim2.fromOffset(190, 120), BackgroundTransparency = 1, Rotation = math.random(-15, 15), ZIndex = 40 })
	new("ImageLabel", holder, { BackgroundTransparency = 1, Image = BURST_IMAGE, Size = UDim2.fromScale(1, 1), ZIndex = 40 })
	local text = letters(holder, word or POWS[math.random(#POWS)], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromScale(0.62, 0.42), ZIndex = 41 })
	shade(text, YELLOW)
	local scale = new("UIScale", holder, { Scale = 0.2 })
	tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.35, function()
		tween(scale, 0.15, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.wait(0.16)
		holder:Destroy()
	end)
	page.Position = PAGE_HOME + UDim2.fromOffset(math.random(-9, 9), math.random(-7, 7))
	tween(page, 0.4, { Position = PAGE_HOME }, Enum.EasingStyle.Elastic)
end

-- Popup for STATS / SHOP: a white caption box over the page, click anywhere to close.
local dim = new("TextButton", gui, { Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.45, Visible = false, ZIndex = 50 })
local popup = new("Frame", dim, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.42, 0.62),
	BackgroundColor3 = WHITE,
	Rotation = -2,
	ZIndex = 51,
})
new("UISizeConstraint", popup, { MinSize = Vector2.new(320, 300) })
stroke(popup, 5)
halftone(popup, Color3.fromRGB(200, 205, 220), 51)
local popScale = new("UIScale", popup, {})
local popTitle, popTitleBack = bigLetters(popup, "", YELLOW, { Position = UDim2.new(0, 24, 0, 16), Size = UDim2.new(1, -48, 0.16, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 52 })
local popBody = new("TextLabel", popup, {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 28, 0.2, 10),
	Size = UDim2.new(1, -56, 0.8, -30),
	Font = Enum.Font.GothamBold,
	TextSize = 22,
	TextColor3 = BLACK,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 52,
})

local POPUPS = {
	-- ponytail: no stats are tracked yet; wire real numbers in here once the server keeps them
	STATS = "No stats yet.\n\nGo throw some dummies around!",
	-- ponytail: no shop yet; this is where its items go once there is something to sell
	SHOP = "The shop is closed.\n\nCome back later!",
}

local function openPopup(name: string)
	popTitle.Text = name
	popTitleBack.Text = name
	popBody.Text = POPUPS[name]
	dim.Visible = true
	popScale.Scale = 0.4
	popup.Rotation = -12
	tween(popScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(popup, 0.5, { Rotation = -2 }, Enum.EasingStyle.Elastic)
end
dim.Activated:Connect(function()
	tween(popScale, 0.15, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Wait()
	dim.Visible = false
end)

-- Panel contents -------------------------------------------------------------------------------
local titles = {} -- { word, shadow, phase } bobbing in the render step

-- A panel's title and an optional value line in the panel's overlay (n staggers the title bob).
local function title(p: Panel, n: number, text: string, color: Color3, withValue: boolean): TextLabel?
	local o = p.overlay :: Frame
	local word, wordBack = bigLetters(o, text, color, { Position = UDim2.fromScale(0.1, withValue and 0.02 or 0.15), Size = UDim2.fromScale(0.8, withValue and 0.56 or 0.7), Rotation = -5, ZIndex = 2 })
	table.insert(titles, { word, wordBack, n * 1.7 })
	p.words = { word, wordBack }
	if not withValue then
		return nil
	end
	local at = UDim2.fromScale(0.5, 0.8)
	new("Frame", o, { AnchorPoint = Vector2.new(0.5, 0.5), Position = at + UDim2.fromOffset(5, 6), Size = UDim2.fromScale(0.62, 0.26), BackgroundColor3 = BLACK, Rotation = 2, ZIndex = 3 }) -- box shadow
	local box = new("Frame", o, { AnchorPoint = Vector2.new(0.5, 0.5), Position = at, Size = UDim2.fromScale(0.62, 0.26), BackgroundColor3 = WHITE, Rotation = 2, ZIndex = 3 })
	stroke(box, 3)
	new("UIScale", box, {})
	return letters(box, "", { Position = UDim2.fromScale(0.04, 0.1), Size = UDim2.fromScale(0.92, 0.8), TextColor3 = BLACK, ZIndex = 4 })
end

local statP, shopP, mapP, playP, sceneP = PANELS[1], PANELS[2], PANELS[3], PANELS[4], PANELS[5]
statP.burst = rays(statP.content :: GuiObject, 0.5, 0.5, 22, 60, 0, Color3.fromRGB(150, 205, 80), 0.3, 14) -- PLAY's rays, light green
title(statP, 1, "STATS", YELLOW, false) -- yellow on green
shopP.burst = rays(shopP.content :: GuiObject, 0.5, 0.5, 22, 60, 0, Color3.fromRGB(240, 100, 70), 0.3, 14) -- PLAY's rays, red
title(shopP, 2, "SHOP", RED, false) -- red on yellow
mapP.burst = rays(mapP.content :: GuiObject, 0.5, 0.5, 18, 70, 0, Color3.fromRGB(255, 120, 100), 0.35, -10)
local mapValue = title(mapP, 3, "MAP", WHITE, true) :: TextLabel -- white on red

playP.burst = rays(playP.content :: GuiObject, 0.5, 0.5, 22, 60, 0, ORANGE, 0.3, 14)
local playO = playP.overlay :: Frame
local burst = new("ImageLabel", playO, {
	BackgroundTransparency = 1,
	Image = BURST_IMAGE,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.7, 1.05),
	ScaleType = Enum.ScaleType.Fit,
})
local burstScale = new("UIScale", burst, {})
local playText, playTextBack = bigLetters(playO, "PLAY!", YELLOW, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.fromScale(0.55, 0.5), Rotation = -4, ZIndex = 2 })
playP.words = { playText, playTextBack }
local playInfo = letters(playO, "", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -6), Size = UDim2.fromScale(0.5, 0.14), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 2 })

layout() -- again, now the bursts exist

-- The player scene: speed lines behind the avatar on its chair, name in a caption box.
rays(sceneP.content :: GuiObject, 0.5, 0.45, 40, 4, 120, WHITE, 0.45, 0, 160)
local viewport = new("ViewportFrame", sceneP.content, {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Ambient = Color3.fromRGB(150, 150, 165),
	LightColor = Color3.fromRGB(255, 245, 230),
	LightDirection = Vector3.new(-0.6, -1, 0.5),
	ZIndex = 4,
})
local caption = new("Frame", sceneP.overlay, { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(0.5, 0, 0, 40), BackgroundColor3 = YELLOW, Rotation = -2 })
stroke(caption, 3)
letters(caption, player.DisplayName, { Position = UDim2.fromScale(0.05, 0.12), Size = UDim2.fromScale(0.9, 0.76), TextColor3 = BLACK })
local puppet = nil
task.spawn(function()
	local char = player.Character or player.CharacterAdded:Wait()
	if not player:HasAppearanceLoaded() then
		player.CharacterAppearanceLoaded:Wait()
	end
	local ok, made = pcall(MenuPuppet.new, viewport, char)
	if ok then
		puppet = made
	else
		warn("menu puppet:", made)
	end
end)
table.insert(tickers, function(t: number)
	if puppet then
		puppet:step(t)
	end
end)
shade(playInfo, WHITE)

local function squash(label: TextLabel)
	local scale = (label.Parent :: Instance):FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.35
		tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local function refresh()
	mapValue.Text = "< " .. MAPS[mapIndex] .. " >"
	playInfo.Text = MAPS[mapIndex]
end
refresh()

-- Actions --------------------------------------------------------------------------------------
-- The cut to the game, on the frame the menu camera reaches the back of the avatar's head: the game
-- camera is put at the same spot behind the real character (the server has moved it to the map
-- by now) and first person takes it from there.
local function handOff()
	RunService:UnbindFromRenderStep("MenuCamera")
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if root and head then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local fwd = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
		camera.CFrame = MenuPuppet.chaseCamera(head.Position, fwd, MenuPuppet.headBack(head), 0)
	end
	Menu.active = false
	camera.CameraType = Enum.CameraType.Custom
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	ContextActionService:UnbindAction("MenuSink")
	blur:Destroy()
	gui:Destroy()
end

-- The scene panel grows to fill the screen as the camera starts chasing the avatar.
local function zoom(): Frame
	local c = sceneP.content :: GuiObject
	local stage = new("Frame", gui, {
		BackgroundColor3 = BLUE,
		Position = UDim2.fromOffset(c.AbsolutePosition.X - gui.AbsolutePosition.X, c.AbsolutePosition.Y - gui.AbsolutePosition.Y),
		Size = UDim2.fromOffset(c.AbsoluteSize.X, c.AbsoluteSize.Y),
		ClipsDescendants = true,
		ZIndex = 30,
	})
	halftone(stage, Color3.fromRGB(30, 55, 115), 1)
	rays(stage, 0.5, 0.45, 40, 4, 120, WHITE, 0.45, 0, 160)
	viewport.Parent = stage
	tween(stage, 0.8, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	tween(page, 0.5, { Position = UDim2.fromScale(0.5, 1.7), Rotation = 6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(pageShadow, 0.5, { Position = UDim2.new(0.5, 14, 1.7, 16), Rotation = 6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(back, 0.6, { BackgroundTransparency = 1 })
	for _, d in back:GetChildren() do
		if d:IsA("ImageLabel") then
			tween(d, 0.4, { ImageTransparency = 1 })
		end
	end
	return stage
end

-- PLAY: the avatar hops off its chair, turns and walks off; the camera follows him into the game.
-- Timed on the menu clock, the same one the avatar runs on, so the cut lands on the right frame.
local leaving = false
local function play()
	leaving = true
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Action"):FireServer("map", MAPS[mapIndex])
	tween(burstScale, 0.3, { Scale = 3 })
	tween(blur, 0.7, { Size = 0 })
	if not puppet then
		return handOff()
	end
	puppet:leave()
	local playAt = os.clock() - start
	local stage: Frame? = nil
	local stripesOff = false
	table.insert(tickers, function(t: number)
		local e = t - playAt
		if not stage and e >= MenuPuppet.ZOOM_AT then
			stage = zoom()
		end
		if stage and not stripesOff and e >= MenuPuppet.STRIPES_OFF_AT then
			stripesOff = true
			for _, d in stage:GetDescendants() do
				if d:IsA("ImageLabel") then
					tween(d, 0.3, { ImageTransparency = 1 })
				elseif d:IsA("Frame") then
					tween(d, 0.3, { BackgroundTransparency = 1 })
				end
			end
		end
		if e >= MenuPuppet.LEAVE_TIME and gui.Parent then
			handOff()
		end
	end)
end

mapP.onClick = function()
	mapIndex = mapIndex % #MAPS + 1
	refresh()
	squash(mapValue)
end
shopP.onClick = function() openPopup("SHOP") end
statP.onClick = function() openPopup("STATS") end
playP.onClick = play
sceneP.onClick = function()
	if puppet then
		puppet:wave()
	end
end

-- One invisible button over the page; the polygon under the mouse decides hover and click.
local hovered: Panel? = nil
local function panelAt(screen: Vector2): Panel?
	local at = screen - GuiService:GetGuiInset() - page.AbsolutePosition -- mouse counts the top bar, AbsolutePosition does not
	for _, p in PANELS do
		if p.poly and inside(p.poly, at) then
			return p
		end
	end
	return nil
end
local function hover(p: Panel, on: boolean)
	if (p.outer :: GuiObject):IsA("CanvasGroup") then
		tween(p.outer :: GuiObject, 0.12, { GroupColor3 = on and WHITE or IDLE })
	end
	if not p.wordScales then
		p.wordScales = {}
		for _, word in p.words or {} do
			table.insert(p.wordScales :: { UIScale }, new("UIScale", word, {}))
		end
	end
	for _, s in p.wordScales :: { UIScale } do
		tween(s, 0.2, { Scale = on and 1.15 or 1 }, Enum.EasingStyle.Back)
	end
end
local hit = new("TextButton", page, { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10 })
hit.Activated:Connect(function()
	local p = panelAt(UserInputService:GetMouseLocation())
	if p and p.onClick and Menu.active and not leaving and not dim.Visible then
		pow()
		;(p.onClick :: () -> ())()
	end
end)
table.insert(tickers, function()
	local p = if dim.Visible then nil else panelAt(UserInputService:GetMouseLocation())
	if p and not p.onClick then
		p = nil -- the scene is not a button
	end
	if p ~= hovered then
		if hovered then
			hover(hovered, false)
		end
		if p then
			hover(p, true)
		end
		hovered = p
	end
end)

-- Intro: the page slams up, black outlines first, then the panels fill in one after another.
tween(page, 0.7, { Position = PAGE_HOME }, Enum.EasingStyle.Back)
tween(pageShadow, 0.7, { Position = UDim2.new(0.5, 14, 0.5, 16) }, Enum.EasingStyle.Back)
for i, p in PANELS do
	local outer = p.outer :: any
	local overlayScale = new("UIScale", p.overlay, { Scale = 0 })
	local grouped = outer:IsA("CanvasGroup")
	if not grouped then
		outer.Visible = false
	else
		outer.GroupTransparency = 1
	end
	task.delay(0.35 + i * 0.09, function()
		if not grouped then
			outer.Visible = true
		else
			tween(outer, 0.3, { GroupTransparency = 0 }).Completed:Connect(function()
				kick(p)
			end)
		end
		tween(overlayScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

-- Idle motion: titles bob, the PLAY burst throbs and rocks.
table.insert(tickers, function(t: number)
	for _, entry in titles do
		local r = -5 + math.sin(t * 2.2 + entry[3]) * 2.5
		entry[1].Rotation = r
		entry[2].Rotation = r
	end
	burst.Rotation = math.sin(t * 1.6) * 6
	burstScale.Scale = 1 + math.abs(math.sin(t * 3)) * 0.08
	playText.Rotation = -4 + math.sin(t * 3) * 3
	playTextBack.Rotation = playText.Rotation
end)

-- Camera hidden behind the page; kept scriptable so the default camera shows no fists. -----------
RunService:BindToRenderStep("MenuCamera", Enum.RenderPriority.Camera.Value + 1, function()
	camera.CameraType = Enum.CameraType.Scriptable -- the default camera script resets it on spawn
	camera.CFrame = CFrame.lookAt(Vector3.new(60, 24, 0), Vector3.new(0, 4, 0))
	camera.Focus = camera.CFrame * CFrame.new(0, 0, -100) -- far focus: not first person, no fists
	local t = os.clock() - start
	for _, tick in tickers do
		tick(t)
	end
end)

return Menu
