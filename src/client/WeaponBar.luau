-- Weapon picking. Replaces the old "Q / F and a name at the top" with:
--  * a hotbar, bottom centre: every weapon as a small 3D icon (its own viewmodel, rendered in a
--    ViewportFrame), the one in hand bigger, outlined in its group's colour, its cooldown filling
--    it from the bottom, its name above the bar;
--  * a weapon wheel: hold Q and every weapon fans out round the screen centre; move the mouse (or
--    the right stick) toward one and let go of Q to take it. The view freezes while it is open.
--  * tap Q / F for the next / previous one, or turn the mouse wheel.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local WeaponBar = {}

local GROUP = { -- outline colour per weapon group (Weapons `tag`)
	melee = Color3.fromRGB(255, 160, 70),
	gun = Color3.fromRGB(255, 220, 90),
	thrown = Color3.fromRGB(120, 230, 140),
	heavy = Color3.fromRGB(255, 90, 80),
}
local GROUP_NAME = { melee = "MELEE", gun = "GUN", thrown = "THROWN", heavy = "HEAVY" }
local ABOUT = {
	Fists = "Punches, kicks, dive kicks",
	Bat = "Huge knockback, breaks bones",
	Pan = "BONK. Sends them flying",
	Katana = "Fast slashes, takes limbs off",
	Axe = "Slow and heavy, takes limbs off",
	Knife = "Thrown, flies to the crosshair",
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
local function icon(specs, parent: GuiObject): (ViewportFrame, () -> ())
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
	local box, size = model:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local upright = size.Y > size.Z -- melee stands up out of the fist, guns point along -Z
	local reach = math.max(size.Y, size.Z, size.X, 0.8)
	local dist = reach / (2 * math.tan(math.rad(15))) * 0.95
	local spin = 0
	local function place(dt: number?)
		spin += (dt or 0) * 1.2
		local side = CFrame.Angles(0, math.pi / 2 + math.sin(spin) * 0.35, 0) -- from the right (+X)
		cam.CFrame = CFrame.new(box.Position) * side * CFrame.new(0, 0, dist) * CFrame.Angles(0, 0, upright and math.rad(-42) or math.rad(18))
	end
	place()
	vp.Parent = parent
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
	-- Hotbar -------------------------------------------------------------------------------
	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	bar.Size = UDim2.fromOffset(#weapons * 56 + 16, 70)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Padding = UDim.new(0, 6)
	list.Parent = bar
	local title = text(gui, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -88), Size = UDim2.fromOffset(420, 24),
		TextSize = 20, Text = "",
	})
	local sub = text(gui, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(420, 14),
		TextSize = 11, Font = Enum.Font.GothamBold, TextTransparency = 0.25, Text = "HOLD Q: WHEEL   ·   SCROLL / Q / F: SWITCH",
	})

	local slots = {}
	for i, w in weapons do
		local slot = Instance.new("Frame")
		slot.Size = UDim2.fromOffset(50, 50)
		slot.BackgroundColor3 = INK
		slot.BackgroundTransparency = 0.3
		slot.LayoutOrder = i
		corner(slot, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.5
		stroke.Color = GROUP[w.tag] or GROUP.melee
		stroke.Transparency = 0.5
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
		local _, place = icon(viewmodels[w.id] or fistSpec, slot)
		local short = text(slot, {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, 0, 0, 10),
			TextSize = 9, Font = Enum.Font.GothamBold, Text = w.short or w.id:upper(), ZIndex = 4,
		})
		slot.Parent = bar
		slots[i] = { frame = slot, stroke = stroke, cool = cool, place = place, short = short }
	end

	-- Wheel --------------------------------------------------------------------------------
	local wheel = Instance.new("Frame")
	wheel.Name = "WeaponWheel"
	wheel.Size = UDim2.fromScale(1, 1)
	wheel.BackgroundColor3 = Color3.new(0, 0, 0)
	wheel.BackgroundTransparency = 1
	wheel.Visible = false
	wheel.ZIndex = 20
	wheel.Parent = gui
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(500, 500)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 21
	ring.Parent = wheel
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(190, 190)
	hub.BackgroundColor3 = INK
	hub.BackgroundTransparency = 0.15
	hub.ZIndex = 21
	corner(hub, 95)
	local hubStroke = Instance.new("UIStroke")
	hubStroke.Thickness = 3
	hubStroke.Parent = hub
	hub.Parent = ring
	local hubName = text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.new(1, -20, 0, 20), TextSize = 17, TextScaled = false, ZIndex = 23 })
	local hubGroup = text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.new(1, -20, 0, 12), TextSize = 10, Font = Enum.Font.GothamBold, ZIndex = 23 })
	local hubAbout = text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 146), Size = UDim2.new(1, -36, 0, 28), TextSize = 10, Font = Enum.Font.Gotham, TextWrapped = true, TextStrokeTransparency = 1, TextColor3 = Color3.fromRGB(200, 196, 210), ZIndex = 23 })
	local hubIcons = {} -- one big spinning icon per weapon, only the highlighted one shown
	for i, w in weapons do
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 14)
		holder.Size = UDim2.fromOffset(100, 100)
		holder.BackgroundTransparency = 1
		holder.Visible = false
		holder.ZIndex = 22
		holder.Parent = hub
		local _, place = icon(viewmodels[w.id] or fistSpec, holder)
		hubIcons[i] = { holder = holder, place = place }
	end
	local petals = {}
	local RADIUS = 200
	for i, w in weapons do
		local angle = -math.pi / 2 + (i - 1) / #weapons * math.pi * 2 -- first at the top, clockwise
		local petal = Instance.new("Frame")
		petal.AnchorPoint = Vector2.new(0.5, 0.5)
		petal.Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS)
		petal.Size = UDim2.fromOffset(72, 72)
		petal.BackgroundColor3 = INK
		petal.BackgroundTransparency = 0.2
		petal.ZIndex = 21
		corner(petal, 36)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = GROUP[w.tag] or GROUP.melee
		stroke.Parent = petal
		local scale = Instance.new("UIScale")
		scale.Parent = petal
		icon(viewmodels[w.id] or fistSpec, petal).ZIndex = 22
		text(petal, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(90, 12), TextSize = 10, Font = Enum.Font.GothamBold, Text = w.short or w.id:upper(), ZIndex = 22 })
		petal.Parent = ring
		petals[i] = { frame = petal, stroke = stroke, scale = scale, angle = angle }
	end

	local open = false
	local pick = api.get()
	local aimAcc = Vector2.zero
	local stick = Vector2.zero
	local qDownAt: number? = nil
	local function show(on: boolean)
		if on == open then
			return
		end
		open = on
		wheel.Visible = on
		aimAcc = Vector2.zero
		pick = api.get()
		api.freeze(on)
		TweenService:Create(wheel, TweenInfo.new(0.12), { BackgroundTransparency = on and 0.45 or 1 }):Play()
		if on then
			ring.Size = UDim2.fromOffset(380, 380)
			TweenService:Create(ring, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(500, 500) }):Play()
		end
	end
	local function step(by: number)
		api.set((api.get() - 1 + by) % #weapons + 1)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
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
			step(-1)
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
			if pick ~= api.get() then
				api.set(pick)
			end
			show(false)
		elseif not api.blocked() then
			step(1) -- a tap
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed and not open and api.scrollable() and not api.blocked() then
			step(input.Position.Z > 0 and -1 or 1)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, -input.Position.Y)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local current = api.get()
		local cooldown = api.cooldown()
		for i, s in slots do
			local on = i == current
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
		local w = weapons[current]
		title.Text = w.name
		title.TextColor3 = GROUP[w.tag] or GROUP.melee
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
			local best, bestGap = pick, math.huge
			for i, p in petals do
				local gap = math.abs((angle - p.angle + math.pi) % (math.pi * 2) - math.pi)
				if gap < bestGap then
					best, bestGap = i, gap
				end
			end
			pick = best
		end
		for i, p in petals do
			local on = i == pick
			p.scale.Scale += ((on and 1.22 or 0.92) - p.scale.Scale) * math.min(dt * 16, 1)
			p.stroke.Color = on and Color3.new(1, 1, 1) or GROUP[weapons[i].tag] or GROUP.melee
			p.stroke.Thickness = on and 3.5 or 2
			p.frame.BackgroundTransparency = on and 0 or 0.3
			hubIcons[i].holder.Visible = on
			if on then
				hubIcons[i].place(dt)
			end
		end
		local chosen = weapons[pick]
		hubName.Text = chosen.name
		hubGroup.Text = GROUP_NAME[chosen.tag] or ""
		hubGroup.TextColor3 = GROUP[chosen.tag] or GROUP.melee
		hubStroke.Color = GROUP[chosen.tag] or GROUP.melee
		hubAbout.Text = ABOUT[chosen.id] or ""
	end)
end

return WeaponBar
