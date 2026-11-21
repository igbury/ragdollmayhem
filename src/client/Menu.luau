-- Main menu: a full-screen comic page. Panels: STATS, SHOP, MAP, PLAY (bottom-left) and a
-- rectangular scene with the player's avatar on a chair (MenuPuppet). Panels are real polygons:
-- seam lines are offset by half a gutter, intersected into corners, and each panel is cut to shape by nested CanvasGroups with a hard-stepped UIGradient per
-- slanted edge (cut()). Outlines are lines drawn corner to corner, so every edge meets its neighbour.
-- Shading: gradient fills, a tiled halftone (assets/fx/make_halftone.py), drop shadows, 3D lettering.
-- Motion: one render step drives spinning / streaming rays, bobbing titles, hover and the PLAY burst.
-- Menu.active is true until Play is pressed; the rest of the client ignores input while it is.
-- M in the game brings it back (Menu.reopen).
-- STATS and SHOP are their own pages under the menu: the menu page turns off by its corner (turn()).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MenuPuppet = require(script.Parent:WaitForChild("MenuPuppet"))
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))

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
local PURPLE = Color3.fromRGB(135, 70, 210)
local IDLE = Color3.fromRGB(228, 228, 228) -- panel tint at rest; hover lifts it to white
local FONT = Enum.Font.LuckiestGuy
local BURST_IMAGE = "rbxassetid://121244599706688" -- same starburst as Fx.pop
local HALFTONE_IMAGE = "rbxassetid://82675619059195" -- assets/fx/halftone.png, 64px tile
-- Setting: show the MODE tile beside MAP. Off: MAP fills the whole bottom-left and the mode stays SANDBOX.
local SHOW_MODES = false
-- ponytail: only the choice is kept (Menu.mode); the server has no modes yet, send it like the map once it does.
local MODES = { "SANDBOX", "REALISM", "ZOMBIES" }
local MAPS = { "ARENA", "FACTORY", "PORT" } -- keys of SPAWNS on the server; "CITY SQUARE" hidden while in development (see City.luau)
local POWS = { "POW!", "BAM!", "ZOOM!", "WHAM!", "BOOM!" }
local MARGIN = 16 -- px of white page round the panels
local GAP = 9 -- px, half the white gutter between panels
local INK = 4 -- px, outline thickness

-- Seam lines across the page, each through two points in page scale (extended to infinity).
-- The player scene is a plain rectangle (HS, VS); H1 meets HS on VS so LOADOUT stays convex.
local SEAMS = {
	H1 = { Vector2.new(0, 0.31), Vector2.new(0.6, 0.31) }, -- under STATS, over PLAY: level with HS, so V1 is the only
	-- slanted edge of STATS and SHOP (two nest a CanvasGroup in another; those came out white now and then)
	HS = { Vector2.new(0, 0.31), Vector2.new(1, 0.31) }, -- under LOADOUT, over the scene
	VS = { Vector2.new(0.6, 0), Vector2.new(0.6, 1) }, -- STATS / PLAY | scene
	V1 = { Vector2.new(0.52, 0), Vector2.new(0.42, 0.29) }, -- MAP | LOADOUT
	H2 = { Vector2.new(0, 0.66), Vector2.new(0.6, 0.74) }, -- PLAY over MAP (low, so PLAY gets the bigger panel)
	VM = { Vector2.new(0.31, 0.7), Vector2.new(0.29, 1) }, -- MAP | MODE
}
-- The shop page: three rows of three. Only the top seam slants: a panel with two slanted edges nests
-- one CanvasGroup in another, and those came out plain white now and then (STATS did too). One cut
-- each always renders.
local SHOP_SEAMS = {
	R1 = { Vector2.new(0, 0.35), Vector2.new(1, 0.3) }, -- under the top row
	R2 = { Vector2.new(0, 0.7), Vector2.new(1, 0.7) }, -- over the bottom row (level: one slanted cut per panel at most)
	VA = { Vector2.new(0.34, 0), Vector2.new(0.34, 1) }, -- top row
	VB = { Vector2.new(0.68, 0), Vector2.new(0.68, 1) },
	VC = { Vector2.new(0.31, 0), Vector2.new(0.31, 1) }, -- middle row
	VD = { Vector2.new(0.65, 0), Vector2.new(0.65, 1) },
	VE = { Vector2.new(0.33, 0), Vector2.new(0.33, 1) }, -- bottom row
	VF = { Vector2.new(0.69, 0), Vector2.new(0.69, 1) },
}
-- The stats page: three columns between a top and a bottom row, tilted the other way from the shop;
-- one slanted edge per panel at most, like the shop (SHOP_SEAMS says why).
local STATS_SEAMS = {
	R1 = { Vector2.new(0, 0.3), Vector2.new(1, 0.24) }, -- under the top row
	V1 = { Vector2.new(0.44, 0), Vector2.new(0.44, 1) }, -- top row: left | right
	V2 = { Vector2.new(0.32, 0), Vector2.new(0.32, 1) }, -- middle: left | centre
	V3 = { Vector2.new(0.68, 0), Vector2.new(0.68, 1) }, -- middle: centre | right
	R2 = { Vector2.new(0, 0.73), Vector2.new(1, 0.73) }, -- over the bottom row
	V4 = { Vector2.new(0.52, 0), Vector2.new(0.52, 1) }, -- bottom row: left | right
}
for _, seams in { SEAMS, SHOP_SEAMS, STATS_SEAMS } do
	seams.TOP = { Vector2.new(0, 0), Vector2.new(1, 0) }
	seams.BOTTOM = { Vector2.new(0, 1), Vector2.new(1, 1) }
	seams.LEFT = { Vector2.new(0, 0), Vector2.new(0, 1) }
	seams.RIGHT = { Vector2.new(1, 0), Vector2.new(1, 1) }
end
local OUTER = { TOP = true, BOTTOM = true, LEFT = true, RIGHT = true }

-- A horizontal or vertical edge of a convex panel lies on its bounding box, so it needs no cut.
-- (Fewer CanvasGroups matters: over the texture budget, effects inside them stop rendering.)
local function slanted(seams, name: string): boolean
	local a, b = seams[name][1], seams[name][2]
	return a.X ~= b.X and a.Y ~= b.Y
end

-- One state table for every build of the menu: Menu.reopen runs a fresh copy of this module, and the
-- rest of the client keeps reading Menu.active off the table it required first.
local SHARED: any = shared
local Menu = SHARED.RagdollMenu or {}
SHARED.RagdollMenu = Menu
local source = SHARED.RagdollMenuSource or script -- the original, to copy from
SHARED.RagdollMenuSource = source
Menu.active = true
local mapIndex = Menu.mapIndex or 1 -- back from the game: the map it was on
local modeIndex = 1
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
local function offsetLine(seams, name: string, size: Vector2, inside: Vector2, off: number): (Vector2, Vector2, Vector2)
	local a, b = seams[name][1] * size, seams[name][2] * size
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
-- Where the cut falls on the gradient (unclamped) and its antialiasing step; t outside
-- [soft, 1 - 2 * soft] means the gradient cannot reach the line from a box this size.
local function reach(size: Vector2, a: Vector2, n: Vector2): (number, number)
	local r = math.atan2(n.Y, n.X)
	local c, s = math.abs(math.cos(r)), math.abs(math.sin(r))
	local span = math.min(c > 1e-4 and size.X / c or math.huge, s > 1e-4 and size.Y / s or math.huge)
	local soft = 1.2 / span -- about a pixel of antialiasing
	return 0.5 + (a - size / 2):Dot(n) / span, soft
end

local function cut(gradient: UIGradient, size: Vector2, a: Vector2, n: Vector2)
	local r = math.atan2(n.Y, n.X)
	local t, soft = reach(size, a, n)
	local t0 = math.clamp(t, soft, 1 - soft * 2)
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
-- Each page lies on its own full-screen sheet; the menu's inner frame moves into a cutting
-- CanvasGroup while the page turns (turn()).
local function sheet(z: number): (Frame, Frame)
	local s = new("Frame", back, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z })
	return s, new("Frame", s, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
end
local menuSheet, menuInner = sheet(3)
-- A page under the menu (shop, stats), shown only while the menu turns off it or back onto it.
local function underPage(): (Frame, Frame)
	local s, inner = sheet(2)
	s.Visible = false
	new("Frame", inner, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 14, 0.5, 16),
		Size = UDim2.fromScale(0.97, 0.95),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.5,
		ZIndex = 2,
	})
	return s, new("Frame", inner, { AnchorPoint = Vector2.new(0.5, 0.5), Position = PAGE_HOME, Size = UDim2.fromScale(0.97, 0.95), BackgroundColor3 = WHITE, ZIndex = 3 })
end
local shopSheet, shopPage = underPage()
local statsSheet, statsPage = underPage()
local pageShadow = new("Frame", menuInner, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 14, 1.6, 16),
	Size = UDim2.fromScale(0.97, 0.95),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.5,
	ZIndex = 2,
})
local page = new("Frame", menuInner, {
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
	cuts: { string }?, -- the slanted edge each group cuts, steepest first
	gradients: { UIGradient }?,
	content: CanvasGroup?,
	lines: { Frame }?,
	overlay: Frame?,
	poly: { Vector2 }?,
	words: { TextLabel }?,
	wordScales: { UIScale }?,
	onClick: (() -> ())?,
	word: string?, -- what the click's POW says (random when nil)
	page: Frame?,
	seams: any,
}
local PANELS: { Panel } = {
	{ edges = { "TOP", "V1", "H1", "LEFT" }, inside = Vector2.new(0.18, 0.13), color = PURPLE, ink = Color3.fromRGB(45, 15, 90) },
	{ edges = { "TOP", "RIGHT", "HS", "V1" }, inside = Vector2.new(0.75, 0.15), color = GREEN, ink = Color3.fromRGB(30, 70, 25) }, -- SHOP: green, money's colour (not yellow: PLAY below it is)
	{ edges = { "H2", SHOW_MODES and "VM" or "VS", "BOTTOM", "LEFT" }, inside = Vector2.new(0.15, 0.88), color = RED, ink = Color3.fromRGB(140, 15, 30) }, -- MAP, bottom left
	{ edges = { "H1", "VS", "H2", "LEFT" }, inside = Vector2.new(0.3, 0.42), color = YELLOW, ink = Color3.fromRGB(235, 105, 25) }, -- PLAY, in the middle
	{ edges = { "HS", "RIGHT", "BOTTOM", "VS" }, inside = Vector2.new(0.8, 0.7), color = BLUE, ink = Color3.fromRGB(10, 20, 60), inset = 1 },
}
if SHOW_MODES then
	table.insert(PANELS, { edges = { "H2", "VS", "BOTTOM", "VM" }, inside = Vector2.new(0.45, 0.88), color = GREEN, ink = Color3.fromRGB(30, 70, 25) }) -- MODE, beside MAP
end
local SKY = Color3.fromRGB(60, 140, 225)
local LIME = Color3.fromRGB(110, 190, 60)
local SHOP_PANELS: { Panel } = {
	{ edges = { "TOP", "VA", "R1", "LEFT" }, inside = Vector2.new(0.15, 0.15), color = SKY, ink = Color3.fromRGB(15, 50, 120) },
	{ edges = { "TOP", "VB", "R1", "VA" }, inside = Vector2.new(0.5, 0.15), color = YELLOW, ink = Color3.fromRGB(235, 105, 25) },
	{ edges = { "TOP", "RIGHT", "R1", "VB" }, inside = Vector2.new(0.85, 0.15), color = RED, ink = Color3.fromRGB(140, 15, 30) },
	{ edges = { "R1", "VC", "R2", "LEFT" }, inside = Vector2.new(0.15, 0.5), color = LIME, ink = Color3.fromRGB(30, 90, 25) },
	{ edges = { "R1", "VD", "R2", "VC" }, inside = Vector2.new(0.5, 0.5), color = RED, ink = Color3.fromRGB(140, 15, 30) },
	{ edges = { "R1", "RIGHT", "R2", "VD" }, inside = Vector2.new(0.85, 0.5), color = SKY, ink = Color3.fromRGB(15, 50, 120) },
	{ edges = { "R2", "VE", "BOTTOM", "LEFT" }, inside = Vector2.new(0.15, 0.85), color = SKY, ink = Color3.fromRGB(15, 50, 120) }, -- BACK
	{ edges = { "R2", "VF", "BOTTOM", "VE" }, inside = Vector2.new(0.5, 0.85), color = YELLOW, ink = Color3.fromRGB(235, 105, 25) },
	{ edges = { "R2", "RIGHT", "BOTTOM", "VF" }, inside = Vector2.new(0.85, 0.85), color = LIME, ink = Color3.fromRGB(30, 90, 25) },
}
local STATS_PANELS: { Panel } = {
	{ edges = { "TOP", "V1", "R1", "LEFT" }, inside = Vector2.new(0.2, 0.12), color = RED, ink = Color3.fromRGB(140, 15, 30) },
	{ edges = { "TOP", "RIGHT", "R1", "V1" }, inside = Vector2.new(0.75, 0.1), color = SKY, ink = Color3.fromRGB(15, 50, 120) },
	{ edges = { "R1", "V2", "R2", "LEFT" }, inside = Vector2.new(0.15, 0.5), color = YELLOW, ink = Color3.fromRGB(235, 105, 25) },
	{ edges = { "R1", "V3", "R2", "V2" }, inside = Vector2.new(0.5, 0.5), color = LIME, ink = Color3.fromRGB(30, 90, 25) },
	{ edges = { "R1", "RIGHT", "R2", "V3" }, inside = Vector2.new(0.85, 0.5), color = RED, ink = Color3.fromRGB(140, 15, 30) },
	{ edges = { "R2", "V4", "BOTTOM", "LEFT" }, inside = Vector2.new(0.25, 0.88), color = SKY, ink = Color3.fromRGB(15, 50, 120) },
	{ edges = { "R2", "RIGHT", "BOTTOM", "V4" }, inside = Vector2.new(0.8, 0.88), color = YELLOW, ink = Color3.fromRGB(235, 105, 25) },
}

local function build(pg: Frame, seams, panels: { Panel })
	for _, p in panels do
		p.page, p.seams = pg, seams
		-- A clipping frame the size of the bounding box does the straight edges; inside it, one nested
		-- CanvasGroup per slanted edge does the cuts. The groups are a square as wide as the box's
		-- diagonal: a UIGradient only reaches min(W/|cos|, H/|sin|) round its centre and clamps past
		-- that, so on a long flat box a seam through a corner (V1 on STATS) was out of its reach and the
		-- cut fell short, leaving a white strip. A panel with no slanted edge is just the clipping frame
		-- (the scene's ViewportFrame stays out of CanvasGroups that way).
		-- Only a group whose cut needs it is that big square (layout() checks); the rest are the bare
		-- box. Steep cuts go outermost, so the square wraps the box and not the other way round. All
		-- squares made the menu ~8 Mpx of group textures: over the budget, and STATS / SHOP flashed white.
		local clip = new("Frame", pg, { BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 })
		local cuts = {}
		for _, edge in p.edges do
			if slanted(seams, edge) then
				table.insert(cuts, edge)
			end
		end
		local function steep(edge: string): number
			local d = seams[edge][2] - seams[edge][1]
			return math.abs(d.Y / d.X)
		end
		table.sort(cuts, function(a, b)
			return steep(a) > steep(b)
		end)
		local groups, parent = {}, clip
		for _ in cuts do
			local g = new("CanvasGroup", parent, { BackgroundTransparency = 1, GroupColor3 = #groups == 0 and IDLE or WHITE, ZIndex = 2 })
			new("UIGradient", g, {})
			table.insert(groups, g)
			parent = g
		end
		p.clip, p.groups, p.cuts, p.content, p.outer = clip, groups, cuts, parent, groups[1] or clip
		local fill = new("Frame", parent, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE })
		p.gradients = { shade(fill, p.color, 60, p.color:Lerp(p.ink, 0.5)), halftone(parent, p.ink, 3):FindFirstChildOfClass("UIGradient") :: UIGradient }
		p.lines = {}
		for i = 1, #p.edges do
			p.lines[i] = new("Frame", pg, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = BLACK, ZIndex = 4 })
		end
		p.overlay = new("Frame", pg, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5 }) -- placed by layout()
	end
end
build(page, SEAMS, PANELS)
build(shopPage, SHOP_SEAMS, SHOP_PANELS)
build(statsPage, STATS_SEAMS, STATS_PANELS)

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
local function layoutPage(pg: Frame, panels: { Panel })
	local size = pg.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return
	end
	for _, p in panels do
		local inner = p.inside * size
		local lines = {}
		for i, edge in p.edges do
			local a, d, n = offsetLine(p.seams, edge, size, inner, OUTER[edge] and MARGIN or GAP)
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
		-- each group: the bare box if its gradient reaches its cut from there, else the square
		local byEdge = {}
		for _, line in lines do
			byEdge[line.edge] = line
		end
		local side = math.ceil(box.Magnitude)
		local squareAt = lo + Vector2.new(math.floor((box.X - side) / 2), math.floor((box.Y - side) / 2))
		local origin = lo -- page position of the content's frame
		for i, g in p.groups :: { CanvasGroup } do
			local line = byEdge[(p.cuts :: { string })[i]]
			local at, size = lo, box
			local t, soft = reach(box, line.a - lo, line.n)
			if t < soft or t > 1 - soft * 2 then
				at, size = squareAt, Vector2.new(side, side)
			end
			g.Position = UDim2.fromOffset(at.X - origin.X, at.Y - origin.Y)
			g.Size = UDim2.fromOffset(size.X, size.Y)
			cut(g:FindFirstChildOfClass("UIGradient") :: UIGradient, size, line.a - at, line.n)
			origin = at
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
local function layout()
	layoutPage(page, PANELS)
	layoutPage(shopPage, SHOP_PANELS)
	layoutPage(statsPage, STATS_PANELS)
end
page:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()

-- The page facing the player: the menu, or the shop once the page has turned.
local current = { frame = page, panels = PANELS }
local MENU_FACE = current
local SHOP_FACE = { frame = shopPage, panels = SHOP_PANELS, sheet = shopSheet }
local STATS_FACE = { frame = statsPage, panels = STATS_PANELS, sheet = statsSheet }

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
	local pg = current.frame
	pg.Position = PAGE_HOME + UDim2.fromOffset(math.random(-9, 9), math.random(-7, 7))
	tween(pg, 0.4, { Position = PAGE_HOME }, Enum.EasingStyle.Elastic)
end

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
statP.burst = rays(statP.content :: GuiObject, 0.5, 0.5, 22, 60, 0, Color3.fromRGB(185, 130, 245), 0.3, 14) -- light purple
title(statP, 1, "STATS", YELLOW, false) -- yellow on purple
shopP.burst = rays(shopP.content :: GuiObject, 0.5, 0.5, 22, 60, 0, Color3.fromRGB(150, 205, 80), 0.3, 14) -- light green
title(shopP, 2, "SHOP", YELLOW, false) -- yellow on green
mapP.burst = rays(mapP.content :: GuiObject, 0.5, 0.5, 18, 70, 0, Color3.fromRGB(255, 120, 100), 0.35, -10)
local mapValue = title(mapP, 3, "MAP", WHITE, true) :: TextLabel -- white on red
local modeP: Panel? = PANELS[6]
local modeValue: TextLabel? = nil
if modeP then
	modeP.burst = rays(modeP.content :: GuiObject, 0.5, 0.5, 18, 70, 0, Color3.fromRGB(150, 205, 80), 0.35, 10)
	modeValue = title(modeP, 6, "MODE", YELLOW, true) -- yellow on green
end

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

-- Shop page: the game passes (shared/Shop), one per panel in list order, BACK bottom-left.
-- A pass not on sale yet (id 0) says SOON!, an owned one OWNED; a click on the rest opens the purchase.
local SHOP_BACK = 7 -- bottom-left, like BACK on the stats page
local SHOP_NEXT = 9 -- bottom-right: the next page of passes, not there yet
local SHOP_SLOTS = { 1, 2, 3, 4, 5, 6, 8 }
local SHOP_TITLE = { YELLOW, RED, YELLOW, YELLOW, YELLOW, YELLOW, WHITE, RED, YELLOW } -- per panel, against its colour
for n, item in Shop.PASSES do
	local i = SHOP_SLOTS[n]
	if not i then
		break
	end
	local p = SHOP_PANELS[i]
	p.burst = rays(p.content :: GuiObject, 0.5, 0.5, 22, 60, 0, p.color:Lerp(WHITE, 0.35), 0.3, i % 2 == 0 and 14 or -14)
	local price = title(p, i, item.name, SHOP_TITLE[i], true) :: TextLabel
	local robux = item.price
	local function show()
		local owned = Shop.owns(player, item.key)
		price.Text = if owned then "OWNED" else "R$ " .. robux
		p.word = if owned then "OWNED!" elseif item.pass > 0 then nil else "SOON!"
	end
	show()
	player:GetAttributeChangedSignal(Shop.attribute(item.key)):Connect(show)
	if item.pass > 0 then
		task.spawn(function() -- the real price, as set in Creator Hub
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, item.pass, Enum.InfoType.GamePass)
			if ok and info and info.PriceInRobux then
				robux = info.PriceInRobux
				show()
			end
		end)
	end
	p.onClick = function()
		if item.pass > 0 and not Shop.owns(player, item.key) then
			MarketplaceService:PromptGamePassPurchase(player, item.pass)
		end
	end
end
do
	local p = SHOP_PANELS[SHOP_BACK]
	p.burst = rays(p.content :: GuiObject, 0.5, 0.5, 22, 60, 0, p.color:Lerp(WHITE, 0.35), 0.3, -14)
	title(p, SHOP_BACK, "< BACK", WHITE, false)
	p.word = "BACK!"
end
do
	local p = SHOP_PANELS[SHOP_NEXT]
	p.burst = rays(p.content :: GuiObject, 0.5, 0.5, 22, 60, 0, p.color:Lerp(WHITE, 0.35), 0.3, 14)
	local soon = title(p, SHOP_NEXT, "NEXT PAGE >", SHOP_TITLE[SHOP_NEXT], true) :: TextLabel
	soon.Text = "COMING SOON"
	p.word = "SOON!"
end

-- Stats page: one number per panel, BACK bottom-left like on the shop. The numbers are the
-- player's attributes, kept and saved by server/Progress; `show` turns one into its text.
local STUD_METRES = 0.28
local STATS = {
	{ name = "KILLS", attribute = "Kills", show = tostring, color = YELLOW },
	{ name = "BONES BROKEN", attribute = "StatBones", show = tostring, color = YELLOW },
	{ name = "DUMMIES THROWN", attribute = "StatThrown", show = tostring, color = RED },
	{ name = "BEST COMBO", attribute = "StatCombo", show = function(n) return n .. "x" end, color = YELLOW },
	{ name = "LONGEST THROW", attribute = "StatThrow", show = function(n) return math.floor(n * STUD_METRES) .. " m" end, color = YELLOW },
	"BACK",
	{ name = "PLAYTIME", attribute = "StatPlaytime", show = function(n)
		local minutes = math.floor(n / 60)
		return if minutes >= 60 then `{minutes // 60} h {minutes % 60} min` else `{minutes} min`
	end, color = RED },
}
for i, stat in STATS do
	local p = STATS_PANELS[i]
	p.burst = rays(p.content :: GuiObject, 0.5, 0.5, 22, 60, 0, p.color:Lerp(WHITE, 0.35), 0.3, i % 2 == 0 and -14 or 14)
	if stat == "BACK" then
		title(p, i, "< BACK", WHITE, false)
		p.word = "BACK!"
		continue
	end
	local value = title(p, i, stat.name, stat.color, true) :: TextLabel
	local function show()
		value.Text = stat.show(math.floor(tonumber(player:GetAttribute(stat.attribute)) or 0))
	end
	show()
	player:GetAttributeChangedSignal(stat.attribute):Connect(show)
end

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
local function squash(label: TextLabel)
	local scale = (label.Parent :: Instance):FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1.35
		tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

-- The first-time tutorial (server/Tutorial): a player who has not done it never sees the menu (the
-- end of this file sends them straight to the arena).
local function refresh()
	mapValue.Text = "< " .. MAPS[mapIndex] .. " >"
	Menu.mapIndex = mapIndex
	if modeValue then
		modeValue.Text = "< " .. MODES[modeIndex] .. " >"
	end
	Menu.mode = MODES[modeIndex]
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

-- As the camera starts chasing the avatar the whole screen floods blue with the scene's halftone
-- and speed lines (over the page), and the avatar's viewport grows from its panel to full screen
-- on top. It all stays until handOff cuts to the game.
local function zoom()
	local c = sceneP.content :: GuiObject
	local flood = new("CanvasGroup", gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLUE, GroupTransparency = 1, ZIndex = 29 })
	halftone(flood, Color3.fromRGB(30, 55, 115), 1)
	rays(flood, 0.5, 0.45, 40, 4, 120, WHITE, 0.45, 0, 160)
	tween(flood, 0.25, { GroupTransparency = 0 })
	local stage = new("Frame", gui, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(c.AbsolutePosition.X - gui.AbsolutePosition.X, c.AbsolutePosition.Y - gui.AbsolutePosition.Y),
		Size = UDim2.fromOffset(c.AbsoluteSize.X, c.AbsoluteSize.Y),
		ZIndex = 30,
	})
	viewport.Parent = stage
	tween(stage, 0.8, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
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
	local zoomed = false
	table.insert(tickers, function(t: number)
		local e = t - playAt
		if not zoomed and e >= MenuPuppet.ZOOM_AT then
			zoomed = true
			zoom()
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
if modeP then
	modeP.onClick = function()
		modeIndex = modeIndex % #MODES + 1
		refresh()
		squash(modeValue :: TextLabel)
	end
end
playP.onClick = play
sceneP.onClick = function()
	if puppet then
		puppet:wave()
	end
end

-- One invisible button over the page; the polygon under the mouse decides hover and click.
local hovered: Panel? = nil
local function panelAt(screen: Vector2): Panel?
	local at = screen - GuiService:GetGuiInset() - current.frame.AbsolutePosition -- mouse counts the top bar, AbsolutePosition does not
	for _, p in current.panels do
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

-- Turning the page: the hand grabs the menu's bottom-right corner and carries it over to the top-left.
-- The fold is the line halfway between where the corner was and where it is now; the menu stays on
-- the far side of it (cut by a gradient on a CanvasGroup it is moved into for the turn), the part
-- past it shows its back, mirrored over the fold, and the shop underneath gets a shadow along it.
-- Back to the menu is the same run backwards: the corner comes back down onto the shop.
local turning = false
local turnGroup = new("CanvasGroup", back, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 4 })
local turnCut = new("UIGradient", turnGroup, {})
local flapGroup = new("CanvasGroup", back, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5 })
local flapCut = new("UIGradient", flapGroup, {})
local flap = new("Frame", flapGroup, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(235, 236, 242) })
stroke(flap, 3)
halftone(flap, Color3.fromRGB(170, 175, 195), 1)
local fall = new("Frame", back, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = BLACK, Visible = false, ZIndex = 3 })
new("UIGradient", fall, { Transparency = NumberSequence.new(0.4, 1) })

-- Keep the side of a full-screen group that n points to; hide it all once the line has left it.
local function fold(group: CanvasGroup, gradient: UIGradient, a: Vector2, n: Vector2)
	local size = back.AbsoluteSize
	local t, soft = reach(size, a, n)
	group.GroupTransparency = if t > 1 - soft * 2 then 1 else 0
	cut(gradient, size, a, n)
end

local function turnTo(v: number) -- 0 = menu on top, 1 = turned all the way to the shop
	local lo = page.AbsolutePosition - back.AbsolutePosition
	local size = page.AbsoluteSize
	local corner = lo + size -- bottom-right
	local grab = corner - size * 2.05 * math.max(v, 0.001) -- carried past the top-left, so the menu is all gone
	local mid = (corner + grab) / 2
	local n = (corner - grab).Unit -- points into the turned-over part
	fold(turnGroup, turnCut, mid, -n)
	fold(flapGroup, flapCut, mid, -n) -- the flap lies over what is left of the menu
	local centre = lo + size / 2
	centre -= 2 * (centre - mid):Dot(n) * n -- the page mirrored over the fold
	local x = Vector2.new(1, 0) - 2 * n.X * n
	flap.Position = UDim2.fromOffset(centre.X, centre.Y)
	flap.Size = UDim2.fromOffset(size.X, size.Y)
	flap.Rotation = math.deg(math.atan2(x.Y, x.X))
	local shadow = 40 * math.sin(math.pi * v)
	local at = mid + n * shadow / 2
	fall.Position = UDim2.fromOffset(at.X, at.Y)
	fall.Size = UDim2.fromOffset(shadow, 4000)
	fall.Rotation = math.deg(math.atan2(n.Y, n.X))
end
local function turn(to)
	local forward = to ~= MENU_FACE -- the menu turns off onto `to`; back: it comes down over the current page
	local under = (if forward then to else current).sheet
	turning = true
	if hovered then
		hover(hovered, false)
		hovered = nil
	end
	menuInner.Parent = turnGroup
	turnGroup.Visible, flapGroup.Visible, fall.Visible, under.Visible = true, true, true, true
	layout() -- also kicks the gradients: a group that was hidden can come back grey
	turnTo(forward and 0 or 1)
	local value = new("NumberValue", nil, { Value = forward and 0 or 1 })
	value.Changed:Connect(turnTo)
	tween(value, 0.9, { Value = forward and 1 or 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut).Completed:Wait()
	value:Destroy()
	menuInner.Parent = menuSheet
	turnGroup.Visible, flapGroup.Visible, fall.Visible = false, false, false
	-- only the page facing up renders: both at once is a lot of CanvasGroup texture
	menuSheet.Visible, under.Visible = not forward, forward
	current = to
	turning = false
end
shopP.onClick = function()
	task.spawn(turn, SHOP_FACE)
	ReplicatedStorage.Remotes.Action:FireServer("opened", "Shop") -- the Menus funnel (server/Funnels)
end
statP.onClick = function()
	task.spawn(turn, STATS_FACE)
	ReplicatedStorage.Remotes.Action:FireServer("opened", "Stats")
end
local function backToMenu()
	task.spawn(turn, MENU_FACE)
end
SHOP_PANELS[SHOP_BACK].onClick = backToMenu
STATS_PANELS[6].onClick = backToMenu

local hit = new("TextButton", back, { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10 })
hit.Activated:Connect(function()
	local p = panelAt(UserInputService:GetMouseLocation())
	if p and p.onClick and Menu.active and not leaving and not turning then
		pow(p.word)
		;(p.onClick :: () -> ())()
	end
end)
table.insert(tickers, function()
	local p = if turning then nil else panelAt(UserInputService:GetMouseLocation())
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

-- Back to the menu from the game (M, client/init): the server takes the character off the map
-- ("menu") and this builds the whole menu again from a fresh copy of the module.
function Menu.reopen()
	if Menu.active then
		return
	end
	ReplicatedStorage.Remotes.Action:FireServer("opened", "Menu") -- the Menus funnel (server/Funnels)
	if SHARED.RagdollMenuCopy then -- the last copy has run; nothing needs the instance any more
		SHARED.RagdollMenuCopy:Destroy()
	end
	local copy = source:Clone()
	copy.Name = "MenuAgain"
	copy.Parent = source.Parent
	SHARED.RagdollMenuCopy = copy
	local _ = require(copy)
end

-- Everyone gets the menu first. A first-time player used to skip it straight into the tutorial once
-- the saved progress was in, but that wait had a time limit, so whether the menu showed depended on
-- how fast the DataStore answered. PLAY takes them to the tutorial anyway: the server sends anyone
-- still in it to the arena ("map").
gui.Enabled = true

return Menu
