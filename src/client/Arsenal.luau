-- The weapon picker (Q, the backpack, or J): an open comic book, two pages of panels per spread, one panel
-- per weapon coloured by its category (a click anywhere on it takes the weapon, or buys it),
-- turned with the arrows halfway up the outer edges (or the arrow keys).
-- A page turns like the main menu's (client/Menu turn()): peeled by its corner, its grey back over the spread.
-- A tap on the backdrop closes it. Shares the hotbar's selection and loadout (client/WeaponBar).
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))
local player = Players.LocalPlayer
local Arsenal = {}
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.fromRGB(15, 15, 20)
local GREY = Color3.fromRGB(120, 120, 128)
local FONT = Font.fromEnum(Enum.Font.LuckiestGuy)
local HALFTONE_IMAGE = "rbxassetid://82675619059195" -- same 64px dot tile as client/Menu
local INK = 3 -- px, panel outline
local TURN_TIME = 0.5 -- s a page turn (the menu's takes 0.9; leafing through the arsenal wants it quicker)
local ICON_ZOOM = 1.3 -- the icon camera's distance (client/WeaponBar icon()): the model at about three quarters of its box
-- category -> fill and the ink its halftone and shading lean to (client/Menu's pairs)
local KINDS = {
	thrown = { color = Color3.fromRGB(232, 70, 56), ink = Color3.fromRGB(140, 15, 30) }, -- explosives
	gun = { color = Color3.fromRGB(55, 110, 215), ink = Color3.fromRGB(10, 20, 60) }, -- ranged
	melee = { color = Color3.fromRGB(255, 212, 45), ink = Color3.fromRGB(225, 150, 15) },
	other = { color = Color3.fromRGB(95, 190, 75), ink = Color3.fromRGB(30, 70, 25) }, -- abilities and the rest
}
local function kindOf(tag: string): string
	return if tag == "heavy" or tag == "thrown" then "thrown" elseif KINDS[tag] then tag else "other"
end
-- A page is three rows of random height, and a row holds two panels side by side or one across: a weapon
-- whose name is long gets a row to itself, short names go two to a row (in their order, so a short one whose
-- neighbours are long can end up alone). One seed per opening, so the rows' heights change each time but
-- hold still while the book is open.
local MARGIN, GX, GY = 0.045, 0.04, 0.028 -- page scale: white margin, gutters across and down
local ROWS = 3 -- per page
local LONG_NAME = 10 -- letters: a name this long takes a whole row (FRYING PAN, SLEDGEHAMMER, ...)
local function weights(rng: Random, k: number, lo: number, hi: number): { number }
	local out, sum = {}, 0
	for j = 1, k do out[j] = rng:NextNumber(lo, hi); sum += out[j] end
	for j = 1, k do out[j] /= sum end
	return out
end
-- the cards (each with .w.name) in rows of one or two
local function rowsOf(cards: { any }): { { any } }
	local rows, waiting = {}, nil -- waiting: a row with one short name in it, open for the next
	for _, card in cards do
		if #card.w.name >= LONG_NAME then
			table.insert(rows, { card })
		elseif waiting then
			table.insert(waiting, card)
			waiting = nil
		else
			waiting = { card }
			table.insert(rows, waiting)
		end
	end
	return rows
end
-- one page's panels, row by row, as { x, y, w, h } in page scale; counts[j]: panels in row j (1 or 2)
local function pageRects(rng: Random, counts: { number }): { { number } }
	local heights = weights(rng, #counts, 0.7, 1.4)
	local inner, out, along = 1 - 2 * MARGIN, {}, MARGIN
	for j, count in counts do
		local w = inner / count
		for q = 0, count - 1 do
			table.insert(out, { MARGIN + q * w + GX / 2, along + GY / 2, w - GX, heights[j] * inner - GY })
		end
		along += heights[j] * inner
	end
	return out
end
local function new(class: string, parent: Instance?, props): any
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end
local function ink(parent: Instance, thickness: number, mode: Enum.ApplyStrokeMode?): UIStroke
	return new("UIStroke", parent, {
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border, BorderStrokePosition = Enum.BorderStrokePosition.Inner,
		Color = BLACK, Thickness = thickness, LineJoinMode = Enum.LineJoinMode.Miter,
	})
end
-- light top-left to deep bottom-right; the gradient carries the colour, so its frame stays white
local function shading(color: Color3, deep: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(WHITE, 0.3)), ColorSequenceKeypoint.new(0.55, color), ColorSequenceKeypoint.new(1, color:Lerp(deep, 0.5)),
	})
end
local function shade(parent: GuiObject, color: Color3, deep: Color3): UIGradient
	parent.BackgroundColor3 = WHITE
	return new("UIGradient", parent, { Rotation = 60, Color = shading(color, deep) })
end
local function halftone(parent: GuiObject, color: Color3, z: number)
	local dots = new("ImageLabel", parent, {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = HALFTONE_IMAGE, ImageColor3 = color,
		ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(13, 13), ZIndex = z,
	})
	new("UIGradient", dots, { Rotation = 35, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.9), NumberSequenceKeypoint.new(1, 0.2),
	}) })
	return dots
end
-- comic lettering: white, black outline, scaled to its box
local function letters(parent: Instance, text: string, props): TextButton
	local l = new("TextButton", parent, {
		Text = text, FontFace = FONT, TextColor3 = WHITE, BackgroundTransparency = 1, AutoButtonColor = false, BorderSizePixel = 0,
	})
	for k, v in props do l[k] = v end
	ink(l, 2, Enum.ApplyStrokeMode.Contextual)
	l.TextScaled = true
	return l
end
-- Cutting a CanvasGroup along a line, as client/Menu does (its reach() / cut() / fold() say how the
-- UIGradient was measured): a is a point on the line and n its normal, in the group's pixels; the
-- side n points to stays, and a group the line has left on the wrong side hides.
local function reach(size: Vector2, a: Vector2, n: Vector2): (number, number)
	local r = math.atan2(n.Y, n.X)
	local c, s = math.abs(math.cos(r)), math.abs(math.sin(r))
	local span = math.min(c > 1e-4 and size.X / c or math.huge, s > 1e-4 and size.Y / s or math.huge)
	local soft = 1.2 / span -- about a pixel of antialiasing
	return 0.5 + (a - size / 2):Dot(n) / span, soft
end
local function fold(group: CanvasGroup, gradient: UIGradient, size: Vector2, a: Vector2, n: Vector2)
	local t, soft = reach(size, a, n)
	local t0 = math.clamp(t, soft, 1 - soft * 2)
	group.GroupTransparency = if t > 1 - soft * 2 then 1 else 0
	gradient.Rotation = math.deg(math.atan2(n.Y, n.X))
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(t0, 1), NumberSequenceKeypoint.new(t0 + soft, 0), NumberSequenceKeypoint.new(1, 0),
	})
end
function Arsenal.start(gui, weapons, models, fist, icon, about, api, choose, closeWheel)
	-- its own ScreenGui: the page turn cuts CanvasGroups, which composite only under Sibling ZIndex (the HUD's
	-- is Global); just over the HUD, under the cash and the tutorial (5)
	local screen = new("ScreenGui", gui.Parent, {
		Name = "Arsenal", ResetOnSpawn = false, IgnoreGuiInset = gui.IgnoreGuiInset, DisplayOrder = 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local cover = new("Frame", screen, {
		Name = "Arsenal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 25), BackgroundTransparency = 0.35,
		BorderSizePixel = 0, ZIndex = 40, Visible = false, Active = true,
	})
	-- the backdrop: a tap off the book closes it (a phone has no Q or J, and the book covers the backpack);
	-- beside the book, not round it: a button's children do not stop its taps
	local backdrop = new("TextButton", cover, {
		Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 40,
	})
	backdrop:SetAttribute("Quiet", true) -- no click or tick (client/Music): closing has its own sound
	local panel = new("Frame", cover, {
		Name = "Panel", Size = UDim2.fromScale(0.94, 0.88), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = 41,
	})
	new("UISizeConstraint", panel, { MaxSize = Vector2.new(1080, 760) })
	local popScale = new("UIScale", panel, {})
	-- the open book: two white pages either side of the spine
	local book = new("Frame", panel, {
		Name = "Book", Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = 41,
	})
	new("UIAspectRatioConstraint", book, { AspectRatio = 1.42 })
	-- taps on the book stop here, short of the backdrop (an Active frame stops only the 3D world's input, not a button's)
	local sink = new("TextButton", book, { Name = "Sink", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 40 })
	sink:SetAttribute("Quiet", true)
	local function page(parent: Instance, side: number, size: UDim2, at: UDim2): Frame
		local p = new("Frame", parent, { Size = size, Position = at, BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 41 })
		ink(p, INK)
		-- printed paper: faint dots, thickest toward the outer bottom corner, gone by the spine
		local dots = halftone(p, Color3.fromRGB(165, 175, 205), 41)
		dots.ImageTransparency, dots.TileSize = 0.5, UDim2.fromOffset(10, 10)
		dots:FindFirstChildOfClass("UIGradient").Rotation = if side == 0 then 145 else 35
		-- the fold: a soft shadow on the spine side of each page
		new("UIGradient", new("Frame", p, {
			Size = UDim2.fromScale(0.08, 1), Position = UDim2.fromScale(side == 0 and 0.92 or 0, 0), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 42,
		}), { Rotation = side == 0 and 0 or 180, Transparency = NumberSequence.new(1, 0.82) })
		return p
	end
	-- The turn. The page's outer bottom corner is carried over the spine to the other page's, rising on
	-- the way; the page folds on the line halfway between where the corner was and where it is (the
	-- foot of the spine always stays on the side that holds). The next page shows in what the fold
	-- uncovers (reveals[side], cut to that side), the page's grey back lies past the fold (flap, cut
	-- to the other side), and a shadow runs along the fold on the uncovered page.
	local pages, reveals = {}, {}
	for side = 0, 1 do
		pages[side] = page(book, side, UDim2.fromScale(0.5, 1), UDim2.fromScale(side * 0.5, 0))
		pages[side].Name = if side == 0 then "LeftPage" else "RightPage"
		local group = new("CanvasGroup", book, {
			Name = "Reveal", Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(side * 0.5, 0), BackgroundTransparency = 1,
			BorderSizePixel = 0, ZIndex = 50, Visible = false,
		})
		reveals[side] = { group = group, cut = new("UIGradient", group, {}), page = page(group, side, UDim2.fromScale(1, 1), UDim2.new()) }
	end
	local fall = new("Frame", nil, { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 49 })
	new("UIGradient", fall, { Transparency = NumberSequence.new(0.4, 1) })
	-- twice the book each way, room for the back as it swings over (it rises up to a fifth of a page over the top)
	local flapGroup = new("CanvasGroup", book, {
		Name = "Flap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(2, 2),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 51, Visible = false,
	})
	local flapCut = new("UIGradient", flapGroup, {})
	local flap = new("Frame", flapGroup, {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.25, 0.5), BackgroundColor3 = Color3.fromRGB(235, 236, 242), BorderSizePixel = 0,
	})
	ink(flap, INK)
	halftone(flap, Color3.fromRGB(170, 175, 195), 2)
	-- the cover art on the right page, seen as the book opens: four colour blocks, one per category
	local coverArt = new("Frame", pages[1], { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 51, Visible = false })
	for k, kind in { "melee", "gun", "thrown", "other" } do
		local c = KINDS[kind]
		local block = new("Frame", coverArt, {
			Position = UDim2.fromScale(0.05 + ((k - 1) % 2) * 0.45, 0.04 + (k > 2 and 0.46 or 0)), Size = UDim2.fromScale(0.43, 0.44),
			BorderSizePixel = 0, ZIndex = 52,
		})
		shade(block, c.color, c.ink)
		halftone(block, c.ink, 53)
		ink(block, INK)
	end
	-- the page-turn arrows, halfway up the outer edges
	local turners = {}
	for side = 0, 1 do
		local b = letters(book, if side == 0 then "<" else ">", {
			Name = if side == 0 then "PrevPage" else "NextPage", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side, 0.5), Size = UDim2.fromScale(0.065, 0.092), ZIndex = 55,
			BackgroundTransparency = 0, BackgroundColor3 = KINDS.melee.color, TextColor3 = WHITE,
		})
		new("UIAspectRatioConstraint", b, { AspectRatio = 1 })
		new("UISizeConstraint", b, { MinSize = Vector2.new(44, 44) })
		new("UICorner", b, { CornerRadius = UDim.new(0.5, 0) })
		ink(b, INK).LineJoinMode = Enum.LineJoinMode.Round -- a mitred stroke ignores the UICorner: a square, cut to the circle
		new("UIPadding", b, { PaddingTop = UDim.new(0.24, 0), PaddingBottom = UDim.new(0.14, 0) })
		turners[side] = b
	end

	local cards, order = {}, {}
	local tutorialCard -- the pistol's: the tutorial's "pick" step rings it (below)
	local layout = {} -- pages: { rects, cards }
	local spread, turning, seed = 0, false, 0
	-- deal page `index` (0-based) onto a page frame; what it held before goes
	local function showPage(holder: Frame, index: number)
		for _, card in cards do
			if card.holder == holder then
				card.frame.Visible, card.holder = false, nil
				if card.hover then card.unhover() end -- hidden under the mouse: no MouseLeave comes
			end
		end
		local p = layout[index + 1]
		if not p then return end
		for k, card in p.cards do
			local r = p.rects[k]
			card.holder = holder
			card.frame.Parent = holder
			card.frame.Position = UDim2.fromScale(r[1] + r[3] / 2, r[2] + r[4] / 2) -- centre anchored for the hover grow
			card.frame.Size = UDim2.fromScale(r[3], r[4])
			card.frame.Visible = true
		end
	end
	local function showTurners()
		turners[0].Visible = spread > 0 and not turning
		turners[1].Visible = (spread + 1) * 2 < #layout and not turning
	end
	local function refresh(keepPage: boolean?)
		for _, card in order do
			local w, i = card.w, card.i
			-- the pack: while its abilities are on the bar; a weapon: in hand (an ability in hand holds the fists, not them)
			local equipped = if card.pack then api.packOut() else api.get() == i and not (api.held and api.held())
			local lock = api.locked and api.locked(i) -- weapon progression: what it still needs
			local price = lock and i <= #weapons and Progression.PRICE[w.id]
			local afford = price and (player:GetAttribute(Progression.CASH) or 0) >= price
			card.button.Text = afford and `BUY {lock}` or lock or equipped and "EQUIPPED!" or "EQUIP" -- out of reach: just what it takes (80$)
			card.button.BackgroundColor3 = if afford then KINDS.other.ink elseif equipped then WHITE else BLACK
			card.button.TextColor3 = if equipped and not lock then BLACK else WHITE
			card.glyphs.Enabled = card.button.TextColor3 == WHITE -- black on white needs no outline
			-- locked out of reach: the panel fades toward grey; equipped: a heavy frame
			local c = KINDS[kindOf(w.tag)]
			local dim = lock and not afford
			card.gradient.Color = shading(if dim then c.color:Lerp(GREY, 0.65) else c.color, c.ink)
			card.stroke.Thickness = if equipped then INK * 2.5 else INK
			if card.vp then card.vp.ImageColor3 = if dim then Color3.fromRGB(150, 150, 150) else WHITE end
		end
		-- deal the rows onto pages, ROWS a page; the leftovers get a short page
		table.clear(layout)
		local rows = rowsOf(order)
		for first = 1, #rows, ROWS do
			local p, counts = { cards = {} }, {}
			for j = first, math.min(first + ROWS - 1, #rows) do
				table.insert(counts, #rows[j])
				table.move(rows[j], 1, #rows[j], #p.cards + 1, p.cards)
			end
			p.rects = pageRects(Random.new(seed + #layout * 7919), counts)
			table.insert(layout, p)
		end
		if not keepPage then spread = 0 end
		spread = math.clamp(spread, 0, math.max(0, math.ceil(#layout / 2) - 1))
		if not turning then
			showPage(pages[0], spread * 2)
			showPage(pages[1], spread * 2 + 1)
		end
		showTurners()
	end
	-- dir 1 forward, -1 back; opening: the cover on the right turns over onto the current spread
	local function turn(dir: number, opening: boolean?)
		if turning then return end
		local to = if opening then spread else spread + dir
		if not opening and (to < 0 or to * 2 >= #layout) then return end
		turning = true
		showTurners()
		Sfx.ui(if opening then Sfx.COMIC_BOOK_OPEN else Sfx.COMIC_PAGE_TURN, 0.6)
		local near, far = if dir > 0 then 1 else 0, if dir > 0 then 0 else 1 -- the page lifts on `near`, lands on `far`
		if opening then showPage(pages[0], -1) end -- the left page starts empty
		coverArt.Visible = opening == true
		local reveal = reveals[near]
		showPage(reveal.page, to * 2 + near)
		fall.Parent = reveal.page
		reveal.group.Visible, flapGroup.Visible = true, true
		local function at(v: number) -- 0: flat on `near`, 1: over on `far`
			local size = book.AbsoluteSize -- (all in book pixels; positions go out as scale, which UIScale leaves alone)
			local w, h = size.X / 2, size.Y
			local outward = if near == 1 then 1 else -1
			local foot = Vector2.new(w, h) -- the foot of the spine
			local corner = foot + Vector2.new(outward * w, 0)
			local angle, radius = math.pi * math.max(v, 0.001), w * (1 - 0.3 * math.sin(math.pi * v))
			local grab = foot + Vector2.new(outward * math.cos(angle), -math.sin(angle)) * radius
			local mid = (corner + grab) / 2
			local n = (corner - grab).Unit -- points into the part that has turned over
			local pageAt = Vector2.new(near * w, 0)
			fold(reveal.group, reveal.cut, Vector2.new(w, h), mid - pageAt, n)
			fold(flapGroup, flapCut, size * 2, mid + size / 2, -n)
			local centre = pageAt + Vector2.new(w, h) / 2
			centre -= 2 * (centre - mid):Dot(n) * n -- the page mirrored over the fold
			local x = Vector2.new(1, 0) - 2 * n.X * n
			flap.Position = UDim2.fromScale((centre.X + size.X / 2) / (size.X * 2), (centre.Y + size.Y / 2) / (size.Y * 2))
			flap.Rotation = math.deg(math.atan2(x.Y, x.X))
			local shadow = 40 * math.sin(math.pi * v)
			local s = mid + n * shadow / 2 - pageAt
			fall.Position = UDim2.fromScale(s.X / w, s.Y / h)
			fall.Size = UDim2.fromOffset(shadow, 4000)
			fall.Rotation = math.deg(math.atan2(n.Y, n.X))
		end
		at(0)
		local value = new("NumberValue", nil, { Value = 0 })
		value.Changed:Connect(at)
		local tween = TweenService:Create(value, TweenInfo.new(TURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = 1 })
		tween.Completed:Connect(function()
			value:Destroy()
			spread = to
			showPage(pages[near], to * 2 + near)
			showPage(pages[far], to * 2 + far) -- under the back, which fades off it
			coverArt.Visible, reveal.group.Visible = false, false
			local fade = TweenService:Create(flapGroup, TweenInfo.new(0.1), { GroupTransparency = 1 })
			fade.Completed:Connect(function()
				flapGroup.Visible, turning = false, false
				showTurners()
			end)
			fade:Play()
		end)
		tween:Play()
	end
	turners[0].Activated:Connect(function() turn(-1) end)
	turners[1].Activated:Connect(function() turn(1) end)

	local isOpen = false
	local pop = TweenService:Create(popScale, TweenInfo.new(0), {})
	local function setOpen(on)
		if on and api.blocked() then return end
		if on then closeWheel() end
		if on and not isOpen then
			ReplicatedStorage.Remotes.Action:FireServer("opened", "Arsenal") -- the Menus funnel (server/Funnels)
			cover.Visible = true
			pop:Cancel()
			popScale.Scale = 0.85
			pop = TweenService:Create(popScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			pop:Play()
		elseif not on and isOpen then
			Sfx.ui(Sfx.COMIC_BOOK_CLOSE, 0.6)
			pop:Cancel()
			pop = TweenService:Create(popScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
			pop.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then cover.Visible = false end
			end)
			pop:Play()
		end
		local opening = on and not isOpen
		isOpen = on
		gui:SetAttribute("WeaponPickerOpen", on)
		api.freeze(on)
		UIS.MouseIconEnabled = on
		if on then
			if opening then seed = math.random(1, 1e6) end
			refresh(true)
			if opening and tutorialCard and player:GetAttribute("TutorialStep") == "pick" then -- straight to the pistol's spread
				for n, p in layout do
					if table.find(p.cards, tutorialCard) then
						spread = (n - 1) // 2
						refresh(true)
						break
					end
				end
			end
			if opening then turn(1, true) end -- the cover turns over to the left
		end
	end
	-- cards: the weapons cheapest first (free ones first, the group's Frostgun last), then the abilities
	local entries = {}
	for i, w in weapons do
		local price = Progression.PRICE[w.id] or (if Progression.GROUP[w.id] then math.huge else 0)
		table.insert(entries, { i = i, w = w, price = price })
	end
	table.sort(entries, function(a, b)
		return if a.price ~= b.price then a.price < b.price else a.i < b.i
	end)
	-- the abilities: one card, the Anime Pack, that puts them all on the hotbar (client/WeaponBar pack());
	-- its i is the first ability's, which carries their lock (the ANIME ATTACKS pass)
	if api.attacks and #api.attacks > 0 then
		table.insert(entries, { i = api.attackFrom + 1, pack = api.attacks, w = { id = "AnimePack", name = "Anime Pack", tag = "ability" } })
	end
	for _, e in entries do
		local i, w = e.i, e.w
		local c = KINDS[kindOf(w.tag)]
		local frame = new("Frame", pages[0], {
			Name = w.id, BorderSizePixel = 0, ZIndex = 43, Visible = false, AnchorPoint = Vector2.new(0.5, 0.5),
		})
		local gradient = shade(frame, c.color, c.ink)
		halftone(frame, c.ink, 44)
		local stroke = ink(frame, INK)
		local turnIcon, vp -- the icon's turntable (none for abilities)
		-- square, between the caption and the button: the model fits the panel's narrow side, not only its height
		local holder = new("Frame", frame, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.56), Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1, ZIndex = 45,
		})
		new("UIAspectRatioConstraint", holder, { AspectRatio = 1 })
		if e.pack then -- the Anime Pack: an orb per ability in its colour, in a ring
			for k, a in e.pack do
				local angle = (k - 1) / #e.pack * math.pi * 2 - math.pi / 2
				local orb = new("Frame", holder, {
					AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.3, 0.5 + math.sin(angle) * 0.3),
					Size = UDim2.fromScale(0.27, 0.27), BackgroundColor3 = a.color, ZIndex = 45,
				})
				new("UICorner", orb, { CornerRadius = UDim.new(0.5, 0) })
				ink(orb, INK).LineJoinMode = Enum.LineJoinMode.Round -- (a mitred one ignores the corner)
			end
		else
			vp, turnIcon = icon(models[w.id] or fist, holder, w.id, ICON_ZOOM); vp.ZIndex = 45
		end
		-- the caption box: the weapon's name in a white strip, top left
		local name = letters(frame, w.name:upper(), {
			Size = UDim2.fromScale(0.78, 0.15), Position = UDim2.fromScale(0.05, 0.05), BackgroundTransparency = 0, BackgroundColor3 = WHITE,
			TextColor3 = BLACK, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 46, Active = false,
		})
		name:FindFirstChildOfClass("UIStroke"):Destroy() -- black on white needs no glyph outline
		ink(name, 2)
		new("UIPadding", name, { PaddingLeft = UDim.new(0.04, 0), PaddingRight = UDim.new(0.04, 0), PaddingTop = UDim.new(0.16, 0), PaddingBottom = UDim.new(0.08, 0) })
		new("UITextSizeConstraint", name, { MaxTextSize = 22, MinTextSize = 8 })
		local equip = letters(frame, "EQUIP", {
			AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromScale(0.8, 0.17), Position = UDim2.fromScale(0.5, 0.95),
			BackgroundTransparency = 0, BackgroundColor3 = BLACK, ZIndex = 46,
		})
		local glyphs = equip:FindFirstChildOfClass("UIStroke")
		ink(equip, 2).Color = WHITE
		new("UIPadding", equip, { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.1, 0), PaddingLeft = UDim.new(0.05, 0), PaddingRight = UDim.new(0.05, 0) })
		new("UITextSizeConstraint", equip, { MaxTextSize = 24 })
		-- the whole panel is the button; the strip only says what a click does (EQUIP, BUY 20$, or what it still takes)
		local hit = new("TextButton", frame, {
			Name = "Pick", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 48,
		})
		hit.Activated:Connect(function()
			if e.pack then
				api.pack(); setOpen(false) -- (locked: it says what it needs)
				return
			end
			if i <= #weapons and api.locked(i) and Progression.PRICE[w.id] then
				api.buy(i) -- stays open: the card turns to EQUIP once it is theirs (refresh below)
				return
			end
			choose(i); setOpen(false)
		end)
		local card = { i = i, pack = e.pack ~= nil, glyphs = glyphs, frame = frame, button = equip, stroke = stroke, gradient = gradient, vp = vp, w = w, turn = turnIcon, hover = false, unhover = nil :: any, holder = nil :: Frame? }
		-- hover: the panel grows from its centre, drawn over its neighbours
		local grow = new("UIScale", frame, {})
		local function hover(on)
			card.hover = on
			frame.ZIndex = if on then 47 else 43
			TweenService:Create(grow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = if on then 1.06 else 1 }):Play()
		end
		hit.MouseEnter:Connect(function() hover(true) end)
		hit.MouseLeave:Connect(function() hover(false) end)
		card.unhover = function() hover(false) end
		if w.id == "Handgun" then
			-- the tutorial's last step (server/Tutorial "pick": buy the pistol and take it): a red outline round
			-- its panel, slowly growing and shrinking, as the wheel's red ring did
			local ring = new("Frame", frame, {
				Name = "TutorialRing", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1, ZIndex = 49,
			})
			local line = ink(ring, 5)
			line.Color, line.BorderStrokePosition = Color3.fromRGB(235, 40, 40), Enum.BorderStrokePosition.Outer
			local pulse = new("UIScale", ring, { Scale = 0.98 })
			TweenService:Create(pulse, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 }):Play()
			local function show()
				ring.Visible = player:GetAttribute("TutorialStep") == "pick"
			end
			player:GetAttributeChangedSignal("TutorialStep"):Connect(show)
			show()
			tutorialCard = card
		end
		cards[i] = card
		table.insert(order, card)
	end
	player.AttributeChanged:Connect(function(attribute) -- cash in, a weapon bought
		if cover.Visible and (attribute == Progression.CASH or attribute:sub(1, 3) == "Own") then refresh(true) end
	end)
	backdrop.Activated:Connect(function() setOpen(false) end)
	UIS.InputBegan:Connect(function(input, processed)
		if processed or UIS:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.J then setOpen(not isOpen)
		elseif isOpen and input.KeyCode == Enum.KeyCode.Escape then setOpen(false)
		elseif isOpen and input.KeyCode == Enum.KeyCode.Right then turn(1)
		elseif isOpen and input.KeyCode == Enum.KeyCode.Left then turn(-1) end
	end)
	local SPIN, HOVER_SPIN = 0.35, 0.42 -- rad/s: a slow turntable, 20% faster under the mouse
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		if cover.Visible then
			for _, card in cards do
				if card.turn and card.frame.Visible then card.turn(dt * (if card.hover then HOVER_SPIN else SPIN), true) end
			end
		end
		elapsed += dt
		if elapsed < 0.15 then return end
		elapsed = 0
		if isOpen and (api.blocked() or not gui.Enabled) then setOpen(false) end
	end)
	-- (on): open / close, (nil): toggle, (nil, true): only ask. Returns whether it is open.
	return function(on: boolean?, query: boolean?): boolean
		if not query then
			setOpen(if on == nil then not isOpen else on)
		end
		return isOpen
	end
end
return Arsenal
