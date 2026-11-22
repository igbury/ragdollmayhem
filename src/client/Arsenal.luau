-- The weapon picker (Q, the backpack, or J): an open comic book, two pages of panels per spread, one panel
-- per weapon coloured by its category, turned with the tabs on the outer bottom edges. Shares the hotbar's
-- selection and loadout (client/WeaponBar). Look borrowed from the main menu (client/Menu).
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local player = Players.LocalPlayer
local Arsenal = {}
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.fromRGB(15, 15, 20)
local GREY = Color3.fromRGB(120, 120, 128)
local FONT = Font.fromEnum(Enum.Font.LuckiestGuy)
local HALFTONE_IMAGE = "rbxassetid://82675619059195" -- same 64px dot tile as client/Menu
local INK = 3 -- px, panel outline
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
-- Page grids are random: rows or (sometimes) columns of uneven size, each split into 1-3 uneven panels.
-- One seed per opening, so the book reads differently each time but holds still while it is open.
local MARGIN, GX, GY = 0.045, 0.04, 0.028 -- page scale: white margin, gutters across and down
local function weights(rng: Random, k: number, lo: number, hi: number): { number }
	local out, sum = {}, 0
	for j = 1, k do out[j] = rng:NextNumber(lo, hi); sum += out[j] end
	for j = 1, k do out[j] /= sum end
	return out
end
-- n panels on one page, as { x, y, w, h } in page scale
local function pageRects(rng: Random, n: number): { { number } }
	local lines = if n <= 2 then n elseif n >= 7 then 3 else rng:NextInteger(2, 3)
	local counts = table.create(lines, 1)
	for _ = 1, n - lines do -- spread the rest over lines that still have room (3 at most)
		local open = {}
		for j, c in counts do if c < 3 then table.insert(open, j) end end
		local j = open[rng:NextInteger(1, #open)]
		counts[j] += 1
	end
	local columns = lines == 2 and rng:NextNumber() < 0.4 -- two tall columns instead of rows
	local sizes = weights(rng, lines, 0.7, 1.4)
	local inner, out, along = 1 - 2 * MARGIN, {}, MARGIN
	for j, count in counts do
		local across = MARGIN
		for _, w in weights(rng, count, 0.9, 1.6) do
			table.insert(out, if columns
				then { along + GX / 2, across + GY / 2, sizes[j] * inner - GX, w * inner - GY }
				else { across + GX / 2, along + GY / 2, w * inner - GX, sizes[j] * inner - GY })
			across += w * inner
		end
		along += sizes[j] * inner
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
function Arsenal.start(gui, weapons, models, fist, icon, about, api, choose, closeWheel)
	local cover = new("Frame", gui, {
		Name = "Arsenal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 12, 25), BackgroundTransparency = 0.35,
		ZIndex = 40, Visible = false, Active = true,
	})
	local panel = new("Frame", cover, {
		Name = "Panel", Size = UDim2.fromScale(0.94, 0.88), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = 41,
	})
	new("UISizeConstraint", panel, { MaxSize = Vector2.new(1080, 760) })
	local popScale = new("UIScale", panel, {})
	-- header: category tabs, search, funds, close
	local header = new("Frame", panel, { Name = "Header", Size = UDim2.fromScale(1, 0.09), BackgroundTransparency = 1, ZIndex = 42 })
	local tabs = new("Frame", header, { Name = "Categories", Size = UDim2.fromScale(0.56, 1), BackgroundTransparency = 1, ZIndex = 42 })
	new("UIListLayout", tabs, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.012, 0), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom })
	local search = new("TextBox", header, {
		Name = "Search", PlaceholderText = "SEARCH...", Text = "", Size = UDim2.fromScale(0.2, 0.8), Position = UDim2.fromScale(0.575, 0.1),
		BackgroundColor3 = WHITE, TextColor3 = BLACK, PlaceholderColor3 = GREY, BorderSizePixel = 0, FontFace = FONT,
		TextSize = 18, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 43,
	})
	new("UIPadding", search, { PaddingLeft = UDim.new(0.06, 0) })
	ink(search, INK)
	local funds = letters(header, "", {
		Name = "Funds", Size = UDim2.fromScale(0.13, 0.8), Position = UDim2.fromScale(0.79, 0.1), ZIndex = 43, Active = false,
		BackgroundTransparency = 0, BackgroundColor3 = KINDS.other.color,
	})
	ink(funds, INK)
	new("UIPadding", funds, { PaddingTop = UDim.new(0.18, 0), PaddingBottom = UDim.new(0.12, 0), PaddingLeft = UDim.new(0.06, 0), PaddingRight = UDim.new(0.06, 0) })
	local x = letters(header, "X", {
		Name = "Close", Size = UDim2.fromScale(0.06, 0.9), Position = UDim2.fromScale(0.94, 0.05), ZIndex = 43,
		BackgroundTransparency = 0, BackgroundColor3 = KINDS.thrown.color,
	})
	ink(x, INK)
	new("UIPadding", x, { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.12, 0) })
	-- the open book: two white pages either side of the spine
	local bookArea = new("Frame", panel, { Size = UDim2.fromScale(1, 0.89), Position = UDim2.fromScale(0, 0.11), BackgroundTransparency = 1, ZIndex = 41 })
	local book = new("Frame", bookArea, {
		Name = "Book", Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = 41,
	})
	new("UIAspectRatioConstraint", book, { AspectRatio = 1.42 })
	local pages = {}
	for side = 0, 1 do
		local page = new("Frame", book, {
			Name = if side == 0 then "LeftPage" else "RightPage", Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(side * 0.5, 0),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 41,
		})
		ink(page, INK)
		-- the fold: a soft shadow on the spine side of each page
		new("UIGradient", new("Frame", page, {
			Size = UDim2.fromScale(0.08, 1), Position = UDim2.fromScale(side == 0 and 0.92 or 0, 0), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 42,
		}), { Rotation = side == 0 and 0 or 180, Transparency = NumberSequence.new(1, 0.82) })
		pages[side] = page
	end
	-- the turning sheets: a blank page that folds to the spine on one side and lands on the other
	local function sheet(side: number): Frame
		local s = new("Frame", book, {
			Name = "Sheet", AnchorPoint = Vector2.new(1 - side, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.5, 1),
			BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 50, Visible = false, ClipsDescendants = true,
		})
		ink(s, INK)
		return s
	end
	local sheets = { [0] = sheet(0), [1] = sheet(1) }
	-- the cover art on the right sheet, seen as the book opens: four colour blocks, one per category
	local coverArt = new("Frame", sheets[1], { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 51, Visible = false })
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
	-- the page-turn tabs, on the outer edges near the bottom
	local turners = {}
	for side = 0, 1 do
		local b = letters(book, if side == 0 then "<" else ">", {
			Name = if side == 0 then "PrevPage" else "NextPage", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side, 0.9), Size = UDim2.fromScale(0.065, 0.092), ZIndex = 55,
			BackgroundTransparency = 0, BackgroundColor3 = KINDS.melee.color, TextColor3 = WHITE,
		})
		new("UIAspectRatioConstraint", b, { AspectRatio = 1 })
		new("UISizeConstraint", b, { MinSize = Vector2.new(44, 44) })
		new("UICorner", b, { CornerRadius = UDim.new(0.5, 0) })
		ink(b, INK)
		new("UIPadding", b, { PaddingTop = UDim.new(0.24, 0), PaddingBottom = UDim.new(0.14, 0) })
		turners[side] = b
	end

	local selectedCategory, cards, buttons, order = "all", {}, {}, {}
	local layout = {} -- pages: { rects, cards } for the current filter
	local spread, turning, seed = 0, false, 0
	local function showPage(side: number, index: number)
		for _, card in cards do
			if card.side == side then
				card.frame.Visible, card.side = false, nil
				if card.hover then card.unhover() end -- hidden under the mouse: no MouseLeave comes
			end
		end
		local p = layout[index + 1]
		if not p then return end
		for k, card in p.cards do
			local r = p.rects[k]
			card.side = side
			card.frame.Parent = pages[side]
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
		funds.Text = `${player:GetAttribute(Progression.CASH) or 0}`
		local query = search.Text:lower()
		local shown = {}
		for _, card in order do
			local w = card.w
			if (selectedCategory == "all" or kindOf(w.tag) == selectedCategory) and w.name:lower():find(query, 1, true) then
				table.insert(shown, card)
			end
			local i = card.i
			local equipped = api.get() == i
			local lock = api.locked and api.locked(i) -- weapon progression: what it still needs
			local price = lock and i <= #weapons and Progression.PRICE[w.id]
			local afford = price and (player:GetAttribute(Progression.CASH) or 0) >= price
			card.button.Text = afford and `BUY {lock}` or lock and `LOCKED {lock}` or equipped and "EQUIPPED!" or "EQUIP"
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
		-- deal the cards onto pages, cycling through the layouts; the leftovers get a short page
		table.clear(layout)
		local k = 1
		while k <= #shown do
			local rng = Random.new(seed + #layout * 7919)
			local n = math.min(rng:NextInteger(5, 7), #shown - k + 1)
			local p = { rects = pageRects(rng, n), cards = {} }
			for _ = 1, n do
				table.insert(p.cards, shown[k]); k += 1
			end
			table.insert(layout, p)
		end
		if not keepPage then spread = 0 end
		spread = math.clamp(spread, 0, math.max(0, math.ceil(#layout / 2) - 1))
		if not turning then
			showPage(0, spread * 2)
			showPage(1, spread * 2 + 1)
		end
		showTurners()
		for category, b in buttons do
			local on = category == selectedCategory
			local color = if category == "all" then WHITE else KINDS[category].color
			b.BackgroundColor3 = if on then color else color:Lerp(BLACK, 0.45)
			b.Size = UDim2.fromScale(0.188, if on then 1 else 0.8)
			if category == "all" then
				b.TextColor3 = if on then BLACK else WHITE
				b:FindFirstChildOfClass("UIStroke").Enabled = not on
			end
		end
	end
	-- one step of a turn: a sheet tweens its width, then calls on
	local function fold(s: Frame, from: number, to: number, style: Enum.EasingDirection, done: () -> ())
		s.Size, s.Visible = UDim2.fromScale(from, 1), true
		local t = TweenService:Create(s, TweenInfo.new(0.17, Enum.EasingStyle.Quad, style), { Size = UDim2.fromScale(to, 1) })
		t.Completed:Connect(done)
		t:Play()
	end
	local function fadeOut(s: Frame, done: () -> ())
		local info = TweenInfo.new(0.14)
		local stroke = s:FindFirstChildOfClass("UIStroke") :: UIStroke
		TweenService:Create(s, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
		task.delay(0.14, function()
			s.Visible, s.BackgroundTransparency, stroke.Transparency = false, 0, 0
			done()
		end)
	end
	-- dir 1 forward, -1 back; opening: the cover on the right swings over onto the current spread
	local function turn(dir: number, opening: boolean?)
		if turning then return end
		local to = spread + dir
		if not opening and (to < 0 or to * 2 >= #layout) then return end
		turning = true
		showTurners()
		local near, far = if dir > 0 then 1 else 0, if dir > 0 then 0 else 1 -- the sheet lifts on `near`, lands on `far`
		if opening then
			to = spread
			showPage(0, -1) -- the left page starts empty
		end
		coverArt.Visible = opening == true
		sheets[near].Visible, sheets[near].Size = true, UDim2.fromScale(0.5, 1)
		showPage(near, to * 2 + near) -- revealed under the turning sheet
		fold(sheets[near], 0.5, 0, Enum.EasingDirection.In, function()
			sheets[near].Visible = false
			fold(sheets[far], 0, 0.5, Enum.EasingDirection.Out, function()
				spread = to
				showPage(far, to * 2 + far)
				fadeOut(sheets[far], function()
					turning = false
					showTurners()
				end)
			end)
		end)
	end
	for n, entry in { { "all", "ALL" }, { "melee", "MELEE" }, { "gun", "RANGED" }, { "thrown", "BOOM" }, { "other", "SKILLS" } } do
		local b = letters(tabs, entry[2], {
			Name = entry[1], LayoutOrder = n, Size = UDim2.fromScale(0.188, 0.8), BackgroundTransparency = 0, ZIndex = 43,
		})
		ink(b, INK)
		new("UIPadding", b, { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.12, 0), PaddingLeft = UDim.new(0.08, 0), PaddingRight = UDim.new(0.08, 0) })
		buttons[entry[1]] = b
		b.Activated:Connect(function() selectedCategory = entry[1]; refresh() end)
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
			if opening then turn(1, true) end -- the cover swings over to the left
		else
			search:ReleaseFocus()
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
	for k, a in api.attacks or {} do
		table.insert(entries, { i = api.attackFrom + k, w = { id = a.id, name = a.name, tag = "ability", color = a.color, cd = a.cd } })
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
		local holder = new("Frame", frame, {
			Size = UDim2.fromScale(0.9, 0.56), Position = UDim2.fromScale(0.05, 0.22), BackgroundTransparency = 1, ZIndex = 45,
		})
		if w.tag == "ability" then -- a white star-ish orb in an ink ring
			local orb = new("Frame", holder, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.6),
				BackgroundColor3 = w.color or WHITE, ZIndex = 45,
			})
			new("UIAspectRatioConstraint", orb, { AspectRatio = 1 })
			new("UICorner", orb, { CornerRadius = UDim.new(0.5, 0) })
			ink(orb, INK)
		else
			vp, turnIcon = icon(models[w.id] or fist, holder, w.id); vp.ZIndex = 45
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
		equip.Activated:Connect(function()
			if i <= #weapons and api.locked(i) and Progression.PRICE[w.id] then
				api.buy(i) -- stays open: the card turns to EQUIP once it is theirs (refresh below)
				return
			end
			choose(i); setOpen(false)
		end)
		local card = { i = i, glyphs = glyphs, frame = frame, button = equip, stroke = stroke, gradient = gradient, vp = vp, w = w, turn = turnIcon, hover = false, unhover = nil :: any }
		-- hover: the panel grows from its centre, drawn over its neighbours
		local grow = new("UIScale", frame, {})
		local function hover(on)
			card.hover = on
			frame.ZIndex = if on then 47 else 43
			TweenService:Create(grow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = if on then 1.06 else 1 }):Play()
		end
		frame.MouseEnter:Connect(function() hover(true) end)
		frame.MouseLeave:Connect(function() hover(false) end)
		card.unhover = function() hover(false) end
		cards[i] = card
		table.insert(order, card)
	end
	search:GetPropertyChangedSignal("Text"):Connect(function() refresh() end)
	player.AttributeChanged:Connect(function(attribute) -- cash in, a weapon bought
		if cover.Visible and (attribute == Progression.CASH or attribute:sub(1, 3) == "Own") then refresh(true) end
	end)
	x.Activated:Connect(function() setOpen(false) end)
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
