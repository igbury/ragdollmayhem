-- Weapon picking. Replaces the old "Q / F and a name at the top" with:
--  * a hotbar, bottom centre: every weapon as a small 3D icon (its own viewmodel, rendered in a
--    ViewportFrame), the one in hand bigger, outlined in its group's colour, its cooldown filling
--    it from the bottom, its name above the bar;
--  * a weapon wheel (the backpack): hold Q and a segmented ring of 8 weapons a page opens; move the
--    mouse (or the right stick) toward one and let go of Q to take it; scroll / L1 R1 / the arrows
--    turn the page. The view stops turning while it is open (it still follows the body).
--  * tap Q / F for the next / previous one, or turn the mouse wheel.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))

local WeaponBar = {}

local GROUP = { -- outline colour per weapon group (Weapons `tag`)
	melee = Color3.fromRGB(255, 160, 70),
	gun = Color3.fromRGB(255, 220, 90),
	thrown = Color3.fromRGB(120, 230, 140),
	heavy = Color3.fromRGB(255, 90, 80),
}
local ABOUT = {
	Bow = "Hold attack to draw; release to shoot. Arrows drop.",
	Fists = "Punches, kicks, dive kicks",
	BoxingGloves = "Hold to box: alternating left and right punches",
	Bat = "Huge knockback, breaks bones",
	Pan = "BONK. Sends them flying",
	Katana = "Fast slashes, takes limbs off",
	Axe = "Slow and heavy, takes limbs off",
	Knife = "Click to slash; aim + click to throw",
	Handgun = "Quick, light rounds",
	Revolver = "Heavy rounds, breaks bones",
	Shotgun = "8 pellets, brutal up close",
	Rifle = "Full auto, hold to fire",
	Sniper = "One shot, pops heads",
	Grenade = "Two second fuse, then BOOM",
	Molotov = "Breaks on impact, sets fire",
	Tomato = "Harmless. Deeply humiliating",
	Rocket = "Flies straight, blows up anything",
}
local INK = Color3.fromRGB(16, 15, 20)
local HOLD_TIME = 0.18 -- a Q held this long opens the wheel; shorter is a tap (next weapon)

-- A 3D picture of a weapon: its viewmodel parts (as init.client builds them) in a ViewportFrame,
-- with the camera fitted to them and the long side laid across the frame diagonally.
-- The blocks show at once; the weapon's Blender mesh (WeaponMeshes) replaces them once it is built.
local function icon(specs, parent: GuiObject, id: string?): (ViewportFrame, (number?) -> ())
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.new(1, -8, 1, -8)
	vp.Position = UDim2.fromOffset(4, 4)
	vp.Ambient = Color3.fromRGB(170, 170, 180)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -1.5, -0.6)
	local model = Instance.new("Model")
	for _, spec in specs do
		local p = Instance.new("Part")
		p.Shape = spec[1]
		p.Size = spec[2]
		p.CFrame = spec[3]
		p.Color = spec[4]
		p.Transparency = spec[5] or 0
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = model
	end
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local box, upright, flat, dist
	local function fit(meshSize: Vector3?)
		local size
		box, size = model:GetBoundingBox()
		if meshSize then -- the atlas part is far bigger than the one weapon centred at the origin
			box, size = CFrame.identity, meshSize
		end
		upright = size.Y > size.Z -- melee stands up out of the fist, guns point along -Z
		flat = size.Z < size.X * 0.5 -- the pan: its face looks forward, so look at it from the front
		dist = math.max(size.Y, size.Z, size.X, 0.8) / (2 * math.tan(math.rad(15))) * 0.95
	end
	fit()
	local spin = 0
	local function place(dt: number?)
		spin += (dt or 0) * 1.2
		local side = CFrame.Angles(0, (flat and 0.35 or math.pi / 2) + math.sin(spin) * 0.35, 0) -- from the right (+X)
		cam.CFrame = CFrame.new(box.Position) * side * CFrame.new(0, 0, dist) * CFrame.Angles(0, 0, upright and math.rad(-42) or math.rad(18))
	end
	place()
	vp.Parent = parent
	if id then
		task.spawn(function()
			local mesh, size = WeaponMeshes.icon(id)
			if not mesh or not vp.Parent then
				return
			end
			model:ClearAllChildren()
			mesh.Parent = model
			fit(size)
			place()
		end)
	end
	return vp, place
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, props): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

-- api: get() -> index in hand, set(index), cooldown() -> 0..1 still to wait, blocked() -> true
-- while no picking may happen (menu, dead), scrollable() -> true when the mouse wheel is free
-- (not holding a body), freeze(on) stops / restores the camera while the wheel is open.
function WeaponBar.start(gui: ScreenGui, weapons, viewmodels, fistSpec, api)
	-- Entries: weapons by index, then the abilities (api.attacks) from a wheel page of their own,
	-- ability k at attackFrom + k. An ability goes on the hotbar like a weapon; taking it puts the
	-- fists in hand (api.ability) and the next click casts it.
	local PER = 8 -- segments on a wheel page
	local attacks = api.attacks or {}
	local attackFrom = math.ceil(#weapons / PER) * PER
	local function entry(at: number)
		return weapons[at] or (at > attackFrom and attacks[at - attackFrom]) or nil
	end
	local function inHand(): number
		local a = api.held and api.held()
		local k = a and table.find(attacks, a)
		return k and attackFrom + k or api.get()
	end
	local function take(i: number)
		if i > #weapons then
			if api.get() ~= 1 then
				api.set(1) -- Weapons[1], the fists
			end
			api.ability(entry(i))
		else
			api.set(i)
		end
	end

	-- Hotbar -------------------------------------------------------------------------------
	-- 5 slots hold a loadout; the 6th is the backpack (the wheel with every weapon). Taking one
	-- from the backpack that is not on the bar puts it in the slot in hand.
	local loadout = {}
	for _, id in { "Fists", "BoxingGloves", "Handgun", "Shotgun", "Grenade" } do
		for i, w in weapons do
			if w.id == id then
				table.insert(loadout, i)
			end
		end
	end
	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	bar.Size = UDim2.fromOffset((#loadout + 1) * 56 + 16, 70)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = bar

	local slots = {}
	local function fill(k: number)
		local s = slots[k]
		local w = entry(loadout[k])
		if s.vp then
			s.vp:Destroy()
		end
		if loadout[k] > #weapons then -- an ability: an orb in its colour
			local orb = Instance.new("Frame")
			orb.AnchorPoint = Vector2.new(0.5, 0.5)
			orb.Position = UDim2.fromScale(0.5, 0.42)
			orb.Size = UDim2.fromScale(0.42, 0.42)
			orb.BackgroundColor3 = w.color
			orb.ZIndex = 2
			corner(orb, 100)
			local ring = Instance.new("UIStroke")
			ring.Color, ring.Thickness, ring.Transparency = w.color, 3, 0.5
			ring.Parent = orb
			orb.Parent = s.frame
			s.vp = orb
			s.place = function() end
		else
			s.vp, s.place = icon(viewmodels[w.id] or fistSpec, s.frame, w.id)
		end
		s.stroke.Color = w.color or GROUP[w.tag] or GROUP.melee
		s.short.Text = w.short or w.id:upper()
	end
	local openWheel: () -> ()
	for k in loadout do
		local slot = Instance.new("TextButton")
		slot.Text = ""
		slot.AutoButtonColor = false
		slot.Size = UDim2.fromOffset(50, 50)
		slot.BackgroundColor3 = INK
		slot.BackgroundTransparency = 0.3
		slot.LayoutOrder = k
		corner(slot, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Transparency = 0.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = slot
		local cool = Instance.new("Frame") -- cooldown: a dark fill that drains downward
		cool.AnchorPoint = Vector2.new(0, 1)
		cool.Position = UDim2.fromScale(0, 1)
		cool.Size = UDim2.fromScale(1, 0)
		cool.BackgroundColor3 = Color3.new(0, 0, 0)
		cool.BackgroundTransparency = 0.35
		cool.BorderSizePixel = 0
		cool.ZIndex = 3
		corner(cool, 10)
		cool.Parent = slot
		local short = text(slot, {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, 0, 0, 10),
			TextSize = 9, Font = Enum.Font.GothamBold, ZIndex = 4,
		})
		slot.Parent = bar
		slots[k] = { frame = slot, stroke = stroke, cool = cool, short = short }
		fill(k)
		slot.Activated:Connect(function()
			if not api.blocked() then
				take(loadout[k])
			end
		end)
	end
	local pack = Instance.new("TextButton") -- slot 6: the backpack
	pack.Name = "Backpack"
	pack.Size = UDim2.fromOffset(50, 50)
	pack.BackgroundColor3 = INK
	pack.BackgroundTransparency = 0.35
	pack.AutoButtonColor = false
	pack.LayoutOrder = #loadout + 1
	pack.Text = "🎒"
	pack.TextSize = 26
	corner(pack, 10)
	local packStroke = Instance.new("UIStroke")
	packStroke.Thickness = 1.5
	packStroke.Color = Color3.fromRGB(200, 196, 210)
	packStroke.Transparency = 0.55
	packStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	packStroke.Parent = pack
	text(pack, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, 0, 0, 10),
		TextSize = 9, Font = Enum.Font.GothamBold, Text = "BAG", ZIndex = 4,
	})
	pack.Parent = bar
	pack.Activated:Connect(function()
		if not api.blocked() then
			openWheel()
		end
	end)

	-- Wheel --------------------------------------------------------------------------------
	local wheel = Instance.new("Frame")
	wheel.Name = "WeaponWheel"
	wheel.Size = UDim2.fromScale(1, 1)
	wheel.BackgroundColor3 = Color3.new(0, 0, 0)
	wheel.BackgroundTransparency = 1
	wheel.Visible = false
	wheel.ZIndex = 20
	wheel.Parent = gui
	-- a grey ring cut into PER segments, one weapon each, the pointed one lit blue, the one in
	-- hand with a blue rim; more weapons than segments go on further pages (< 1 / 2 >).
	local R_OUT, R_IN, SLICES = 260, 165, 10
	local pages = math.ceil((attackFrom + #attacks) / PER)
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(R_OUT * 2, R_OUT * 2)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 21
	ring.Parent = wheel
	local ringScale = Instance.new("UIScale")
	ringScale.Parent = ring
	local canvas = Instance.new("CanvasGroup") -- slices overlap; drawn as one so the overlap never shows
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.GroupTransparency = 0.12
	canvas.ZIndex = 21
	canvas.Parent = ring
	local SEG = Color3.fromRGB(140, 140, 146)
	local LIT = Color3.fromRGB(196, 226, 244)
	local RIM = Color3.fromRGB(70, 160, 230)
	local span = math.pi * 2 / PER
	local function arc(from: number, to: number, r0: number, r1: number, color: Color3, z: number): { Frame }
		local parts = {}
		local d = (to - from) / SLICES
		for n = 0, SLICES - 1 do
			local a = from + (n + 0.5) * d
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.new(0.5, math.cos(a) * (r0 + r1) / 2, 0.5, math.sin(a) * (r0 + r1) / 2)
			f.Size = UDim2.fromOffset(2 * r1 * math.tan(d / 2) + 1.5, r1 - r0)
			f.Rotation = math.deg(a) + 90
			f.BackgroundColor3 = color
			f.BorderSizePixel = 0
			f.ZIndex = z
			f.Parent = canvas
			table.insert(parts, f)
		end
		return parts
	end
	local segs = {}
	for k = 1, PER do
		local mid = -math.pi / 2 + (k - 1) * span -- first at the top, clockwise
		segs[k] = {
			angle = mid,
			fill = arc(mid - span / 2, mid + span / 2, R_IN, R_OUT, SEG, 21),
			rim = arc(mid - span / 2, mid + span / 2, R_OUT - 7, R_OUT, RIM, 22),
		}
		local cut = Instance.new("Frame") -- white line between this segment and the one before
		local a = mid - span / 2
		cut.AnchorPoint = Vector2.new(0.5, 0.5)
		cut.Position = UDim2.new(0.5, math.cos(a) * (R_IN + R_OUT) / 2, 0.5, math.sin(a) * (R_IN + R_OUT) / 2)
		cut.Size = UDim2.fromOffset(R_OUT - R_IN + 2, 3)
		cut.Rotation = math.deg(a)
		cut.BackgroundColor3 = Color3.new(1, 1, 1)
		cut.BorderSizePixel = 0
		cut.ZIndex = 23
		cut.Parent = canvas
	end
	local petals = {} -- one per weapon, in its segment, shown on its page
	for i, w in weapons do
		local seg = segs[(i - 1) % PER + 1]
		local r = (R_IN + R_OUT) / 2
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, math.cos(seg.angle) * r, 0.5, math.sin(seg.angle) * r - 8)
		holder.Size = UDim2.fromOffset(150, 96)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 24
		holder.Parent = ring
		local vp, place = icon(viewmodels[w.id] or fistSpec, holder, w.id)
		vp.ZIndex = 24
		text(holder, {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(110, 14),
			TextSize = 12, Font = Enum.Font.GothamBold, Text = w.short or w.id:upper(), TextStrokeTransparency = 0.3, ZIndex = 25,
		})
		petals[i] = { holder = holder, place = place, page = math.ceil(i / PER), seg = (i - 1) % PER + 1 }
	end
	for k, a in attacks do
		local i = attackFrom + k
		local seg = segs[(i - 1) % PER + 1]
		local r = (R_IN + R_OUT) / 2
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, math.cos(seg.angle) * r, 0.5, math.sin(seg.angle) * r)
		holder.Size = UDim2.fromOffset(110, 50)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 24
		holder.Parent = ring
		local name = text(holder, {
			Size = UDim2.fromScale(1, 1), TextSize = 13, TextWrapped = true, Font = Enum.Font.GothamBlack,
			Text = a.name, TextColor3 = a.color, TextStrokeTransparency = 0.2, ZIndex = 25,
		})
		petals[i] = { holder = holder, page = math.ceil(i / PER), seg = (i - 1) % PER + 1,
			place = function() name.TextTransparency = os.clock() < (a.readyAt or 0) and 0.6 or 0 end }
	end
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(R_IN * 2 - 20, 110)
	hub.BackgroundTransparency = 1
	hub.ZIndex = 24
	hub.Parent = ring
	local hubName = text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(1, 0, 0, 22), TextSize = 20, Font = Enum.Font.GothamBold, ZIndex = 25 })
	local hubPage = text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(80, 24), TextSize = 18, Font = Enum.Font.GothamBold, ZIndex = 25 })
	local hubAbout = text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.new(1, -20, 0, 30), TextSize = 12, Font = Enum.Font.GothamMedium, TextWrapped = true, TextColor3 = Color3.fromRGB(225, 225, 232), ZIndex = 25 })
	local arrows = {}
	for _, dirn in { -1, 1 } do
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.new(0.5, dirn * 62, 0, 28)
		b.Size = UDim2.fromOffset(28, 28)
		b.BackgroundTransparency = 1
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 26
		b.TextColor3 = RIM
		b.TextStrokeTransparency = 0.6
		b.Text = dirn < 0 and "‹" or "›"
		b.ZIndex = 25
		b.Visible = pages > 1
		b.Parent = hub
		arrows[dirn] = b
	end

	local open = false
	local pick: number? = inHand()
	local page = 1
	local aimAcc = Vector2.zero
	local stick = Vector2.zero
	local qDownAt: number? = nil
	local function show(on: boolean)
		if on == open then
			return
		end
		open = on
		gui:SetAttribute("WeaponPickerOpen", on)
		wheel.Visible = on
		aimAcc = Vector2.zero
		pick = inHand()
		page = petals[pick].page
		api.freeze(on)
		TweenService:Create(wheel, TweenInfo.new(0.12), { BackgroundTransparency = on and 0.45 or 1 }):Play()
		if on then
			ringScale.Scale = 0.75
			TweenService:Create(ringScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	openWheel = function()
		show(true)
	end
	local function step(by: number)
		local k = table.find(loadout, inHand()) or 1
		take(loadout[(k - 1 + by) % #loadout + 1])
	end
	local function flip(by: number)
		page = (page - 1 + by) % pages + 1
		local at = pick and (page - 1) * PER + petals[pick].seg
		pick = at and entry(at) and at or nil -- same segment on the new page, if it holds one
	end
	for dirn, b in arrows do
		b.Activated:Connect(function()
			flip(dirn)
		end)
	end
	local function choose(i: number?)
		qDownAt = nil -- a click while Q is held must not turn the Q release into a tap
		if not i then
			show(false)
			return
		end
		if not table.find(loadout, i) then
			local k = table.find(loadout, inHand()) or 1
			loadout[k] = i
			fill(k)
		end
		if i ~= inHand() then
			take(i)
		end
		show(false)
	end

	openWheel = require(script.Parent.Arsenal).start(gui, weapons, viewmodels, fistSpec, icon, ABOUT, api, choose, function() show(false) end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if gui:GetAttribute("WeaponPickerOpen") and not open then return end
		if open and input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			choose(pick) -- the backpack opened by a click closes on one (the page arrows are buttons)
			return
		end
		if open and (input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1) then
			flip(input.KeyCode == Enum.KeyCode.ButtonL1 and -1 or 1)
			return
		end
		if processed or api.blocked() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			local at = os.clock()
			qDownAt = at
			task.delay(HOLD_TIME, function()
				if qDownAt == at and not api.blocked() then
					show(true)
				end
			end)
		elseif input.KeyCode == Enum.KeyCode.F then
			if not (api.drag and api.drag()) then -- on a dummy in reach F drags it instead
				step(-1)
			end
		elseif input.KeyCode.Value >= Enum.KeyCode.One.Value and input.KeyCode.Value < Enum.KeyCode.One.Value + #loadout then
			take(loadout[input.KeyCode.Value - Enum.KeyCode.One.Value + 1]) -- 1-5: that hotbar slot
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			step(-1)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			step(1)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.Q or not qDownAt then
			return
		end
		qDownAt = nil
		if open then
			choose(pick)
		elseif not api.blocked() then
			step(1) -- a tap
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and open then
			flip(input.Position.Z > 0 and -1 or 1)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed and api.scrollable() and not api.blocked() then
			step(input.Position.Z > 0 and -1 or 1)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, -input.Position.Y)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local current = inHand()
		local cooldown = api.cooldown()
		packStroke.Transparency = open and 0 or 0.55
		for k, s in slots do
			local on = loadout[k] == current
			local size = on and 64 or 50
			s.frame.Size = s.frame.Size:Lerp(UDim2.fromOffset(size, size), math.min(dt * 18, 1))
			s.frame.BackgroundTransparency = on and 0.05 or 0.35
			s.stroke.Thickness = on and 3 or 1.5
			s.stroke.Transparency = on and 0 or 0.55
			s.short.TextTransparency = on and 0 or 0.35
			s.cool.Size = UDim2.fromScale(1, on and cooldown or 0)
			if on then
				s.place(dt)
			end
		end
		if not open then
			return
		end
		if api.blocked() then
			show(false)
			return
		end
		-- where the player points: the mouse off the centre when it is free, the accumulated
		-- movement when it is locked (first person), or the right stick
		aimAcc += UserInputService:GetMouseDelta()
		if aimAcc.Magnitude > 160 then
			aimAcc = aimAcc.Unit * 160
		end
		local screen = gui.AbsoluteSize
		local fromCentre = UserInputService:GetMouseLocation() - screen / 2
		local dir = stick.Magnitude > 0.5 and stick * 100 or (aimAcc.Magnitude > fromCentre.Magnitude and aimAcc or fromCentre)
		if dir.Magnitude > 30 then
			local angle = math.atan2(dir.Y, dir.X)
			local best, bestGap = 1, math.huge
			for k, seg in segs do
				local gap = math.abs((angle - seg.angle + math.pi) % (math.pi * 2) - math.pi)
				if gap < bestGap then
					best, bestGap = k, gap
				end
			end
			local at = (page - 1) * PER + best
			pick = entry(at) and at or nil
		end
		for k, seg in segs do
			local at = (page - 1) * PER + k
			for _, f in seg.fill do
				f.BackgroundColor3 = at == pick and LIT or SEG
			end
			for _, f in seg.rim do
				f.Visible = at == current
			end
		end
		for i, p in petals do
			p.holder.Visible = p.page == page
			if i == pick or i > #weapons then -- attacks dim while cooling down
				p.place(dt)
			end
		end
		local chosen = pick and entry(pick)
		hubName.Text = chosen and chosen.name or ""
		if chosen and pick > #weapons then
			local wait = (chosen.readyAt or 0) - os.clock()
			hubAbout.Text = wait > 0 and string.format("Ready in %.1f s", wait) or `Ability · click to use · {chosen.cd} s cooldown`
		else
			hubAbout.Text = chosen and ABOUT[chosen.id] or ""
		end
		hubPage.Text = page .. " / " .. pages
	end)
end

return WeaponBar
