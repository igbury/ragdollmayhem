-- Weapon picking. Replaces the old "Q / F and a name at the top" with:
--  * a hotbar, bottom centre: every weapon as a small 3D icon (its own viewmodel, rendered in a
--    ViewportFrame), the one in hand bigger, outlined in its group's colour, its cooldown filling
--    it from the bottom, its name above the bar;
--  * the Arsenal (client/Arsenal): Q, the backpack or J; Q again closes it.
--    ponytail: the old weapon wheel below is no longer opened (nothing calls show(true)); delete it
--    once the Arsenal has settled in (petals still carry the lock marks relock() updates)
--  * F for the previous one, or turn the mouse wheel.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))
local Progression =require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))

local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))
local TouchControls = require(script.Parent:WaitForChild("TouchControls")) -- active(): playing by touch

local WeaponBar = {}

local GROUP = { -- outline colour per weapon group (Weapons `tag`)
	melee = Color3.fromRGB(255, 160, 70),
	gun = Color3.fromRGB(255, 220, 90),
	thrown = Color3.fromRGB(120, 230, 140),
	heavy = Color3.fromRGB(255, 90, 80),
	tool = Color3.fromRGB(240, 240, 235),
	power = Color3.fromRGB(120, 255, 140), -- the Doomsday Pack
}
local CATEGORY = { melee = "MELEE", gun = "RANGED", thrown = "EXPLOSIVES", heavy = "EXPLOSIVES", tool = "TOOLS", power = "DOOMSDAY" } -- wheel page per group
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
	Bandage = "Aim at a torn-off limb's stump and click to dress it",
	Cast = "Aim at a broken arm or leg and click to set it in plaster",
	Balloon = "Click a ragdoll's limb to tie a balloon on: 1 slows a fall, 2 hover, 3+ lift",
	DeathSyringe = "Jab a dummy: it staggers, then drops dead",
	HealSyringe = "Jab a dummy: fully healed, even back from the dead",
	SleepSyringe = "Jab a dummy: out cold and snoring for 10 s",
	SpeedSyringe = "Jab a dummy: it sprints about screaming, then collapses",
	JellySyringe = "Jab a dummy: its bones go soft, it flops like jelly",
	HeliumSyringe = "Jab a dummy: it floats up into the sky... then drops",
	ShrinkSyringe = "Jab a dummy: tiny for 15 s",
	GiantSyringe = "Jab a dummy: a giant for 15 s",
	FireSyringe = "Jab a dummy: it burns from the inside",
	ExplosiveSyringe = "Jab a dummy: it beeps for 3 s, then BOOM",
	ZombieSyringe = "Jab a dummy, alive or dead: it comes back a zombie",
	Rocket = "Flies straight, blows up anything",
	Crowbar = "Knocks the weapon out of their hands",
	Sledgehammer = "Floors them, the ground shakes",
	Spear = "Long thrust, skewers up to three",
	Lightsaber = "Glows, slices limbs clean off",
	Chainsaw = "Hold to saw: pins them down",
	Lasso = "Rope them, yank them in, drag them along",
	Taser = "Wires in: down and twitching",
	Frostgun = "Freezes them solid for a few seconds",
	Boilgun = "Scalding spray: shoves and burns",
	Flamethrower = "Hold to spray fire, sets them alight",
	Minigun = "Hold: spins up, then shreds",
	Harpoon = "Spears them and reels them in",
	Grapple = "Click: zip there, WASD steers (on them: flying kick)",
	Gravgun = "Right click: pull a body in and hold it. Click: launch it (empty: punt)",
	BalloonGun = "Ties a balloon to the limb you hit: 1 slows a fall, 2 hover, 3+ lift",
	LeafBlower = "Hold: blow them off their feet. Aim down: hover",
	Shield = "Throw it: it spins flat, glances off walls and always comes back to you",
	WebShot = "Click: web them to the wall behind them",
	GroundSlam = "Click: leap and slam the ground, throws everyone near",
	CosmicPower = "Hold: a cosmic beam from your hand fries them",
	LaserVisor = "Hold: short green lasers from your visor",
	FlameOn = "Burn all over. Double jump: fly. Click: fireball (close: fire punch). Right: flame beam",
	TNT = "Three second fuse, huge blast",
	C4 = "Click: stick a charge. Right click: BOOM",
	Landmine = "Place it: blows when they step close",
}
local INK = Color3.fromRGB(16, 15, 20)
-- hotbar only: these icons draw smaller in their slot (the camera backs off by this factor)
local SLOT_ZOOM = { Fists = 1.35, BoxingGloves = 1.35, Handgun = 1.35, Grenade = 1.35, Revolver = 1.35 }

-- A 3D picture of a weapon: its viewmodel parts (as init.client builds them) in a ViewportFrame,
-- with the camera fitted to them and the long side laid across the frame diagonally.
-- The blocks show at once; the weapon's Blender mesh (WeaponMeshes) replaces them once it is built.
-- weapons whose icon is their ReplicatedStorage.ArmyKit piece (no WeaponMeshes data), and how it is turned
local KIT_ICON = { LaserVisor = CFrame.Angles(math.rad(12), math.rad(-60), 0) }
-- icons looked at from the other side (the shield's painted face is its -Z, the camera starts on +Z)
local ICON_TURN = { Shield = math.pi }
-- icons that stand straight instead of leaning like a held melee weapon (Super Nova's flame, Cosmic Power's bolt)
local ICON_LEVEL = { FlameOn = true, CosmicPower = true }
local function icon(specs, parent: GuiObject, id: string?, zoom: number?): (ViewportFrame, (number?) -> ())
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
	local kit = id and KIT_ICON[id] and game:GetService("ReplicatedStorage"):FindFirstChild("ArmyKit")
	local kitPiece = kit and kit:FindFirstChild(id)
	if kitPiece then -- an uploaded kit piece instead of the blocks, turned to show its face
		model:ClearAllChildren()
		for _, mesh in kitPiece:GetChildren() do
			local p = mesh:Clone() :: BasePart
			p.CFrame = KIT_ICON[id] * (p:GetAttribute("Place") or CFrame.identity)
			p.Anchored = true
			p.Parent = model
		end
		id = nil -- WeaponMeshes has none to swap in
	end
	model.Parent = vp
	local weaponId = id
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
		dist = math.max(size.Y, size.Z, size.X, 0.8) / (2 * math.tan(math.rad(15))) * 0.95 * (zoom or 1)
	end
	fit()
	local spin = 0
	-- (dt): sway, as on the hotbar; (angle, true): a full turntable, turned on by that many radians
	local function place(dt: number?, turn: boolean?)
		spin += (dt or 0) * (if turn then 1 else 1.2)
		local base = (flat and 0.35 or math.pi / 2) + (ICON_TURN[weaponId] or 0)
		local side = CFrame.Angles(0, if turn then base + spin else base + math.sin(spin) * 0.35, 0) -- from the right (+X)
		cam.CFrame = CFrame.new(box.Position) * side * CFrame.new(0, 0, dist) * CFrame.Angles(0, 0, if ICON_LEVEL[weaponId] then 0 elseif upright then math.rad(-42) else math.rad(18))
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
	-- Wheel layout: one page per group (Weapons `tag`, in list order; a group past PER goes on), then the
	-- abilities. slotAt[page][segment] = entry, where[entry] = { page, segment }.
	local slotAt, where, pageName, pageColor = {}, {}, {}, {}
	local function lay(i: number, name: string, color: Color3?)
		local p = slotAt[#slotAt]
		if name ~= pageName[#slotAt] or #p == PER then
			p = {}
			table.insert(slotAt, p)
			pageName[#slotAt], pageColor[#slotAt] = name, color
		end
		table.insert(p, i)
		where[i] = { #slotAt, #p }
	end
	for i, w in weapons do
		lay(i, CATEGORY[w.tag] or w.tag:upper(), GROUP[w.tag])
	end
	for k in attacks do
		lay(attackFrom + k, "ABILITIES")
	end
	local function inHand(): number
		local a = api.held and api.held()
		local k = a and table.find(attacks, a)
		return k and attackFrom + k or api.get()
	end
	-- Weapon progression (shared/Progression; the server refuses a locked one too): what a weapon
	-- still needs ("1000$"), nil once it is unlocked. Abilities: only by the ANIME ATTACKS pass.
	local player = Players.LocalPlayer
	local function missing(i: number?): string?
		local w = i and i <= #weapons and weapons[i]
		if i and i > attackFrom and Shop.locked(player, "Anime") then
			return "ANIME ATTACKS PASS" -- the abilities (shared/Shop)
		end
		return w and Progression.missing(player, w.id) or nil
	end
	local flash: (string) -> () -- the banner over the hotbar, below
	-- Buying (server/Progress checks it): picking a weapon you can afford asks first, picking it again
	-- within CONFIRM_TIME buys it; the Arsenal's BUY button buys at once. Short of cash, the buy opens
	-- the cash pack that covers it instead (shared/Shop.packFor).
	local CONFIRM_TIME = 4
	local asked, askedAt = nil, 0
	local function buy(i: number)
		local short = (Progression.PRICE[weapons[i].id] or 0) - (player:GetAttribute(Progression.CASH) or 0)
		if short > 0 then
			game:GetService("MarketplaceService"):PromptProductPurchase(player, Shop.packFor(short).product)
			return
		end
		ReplicatedStorage.Remotes.Action:FireServer("buy", weapons[i].id)
	end
	local function take(i: number)
		local need = missing(i)
		local price = need and i <= #weapons and Progression.PRICE[weapons[i].id]
		if price then
			local cash = player:GetAttribute(Progression.CASH) or 0
			if asked == i and os.clock() - askedAt < CONFIRM_TIME then
				asked = nil
				buy(i)
			else
				asked, askedAt = i, os.clock()
				flash(if cash < price then `{weapons[i].name}: {cash} / {price}$ · PICK AGAIN FOR CASH` else `BUY {weapons[i].name} FOR {price}$? PICK AGAIN`)
			end
			return
		end
		if need then
			flash(`LOCKED: {need}`)
			if need == Progression.GROUP_NEED and game.CreatorType == Enum.CreatorType.Group then
				task.spawn(pcall, game:GetService("GroupService").PromptJoinAsync, game:GetService("GroupService"), game.CreatorId)
			end
			return
		end
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
	-- It starts with the fists and the other starting weapons (shared/Progression.START: a new player
	-- sees on keys 1-3 that they have a bat and a tomato). Each weapon taken from the wheel (hold Q) or the Arsenal (J)
	-- that is not on it yet gets a slot of its own, up to MAX_SLOTS; after that it replaces the one in hand.
	local MAX_SLOTS = 5
	local loadout = { 1 } -- Weapons[1], the fists
	for i, w in weapons do
		if i > 1 and Progression.START[w.id] then
			table.insert(loadout, i)
		end
	end
	local bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -12)
	bar.Size = UDim2.fromOffset((math.max(MAX_SLOTS, #attacks) + 1) * 56 + 16, 70) -- the weapons, then the backpack
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
	local function lockSlot(k: number) -- dark and a padlock while the weapon in it is locked
		local s = slots[k]
		local locked = missing(loadout[k]) ~= nil
		s.lock.Visible = locked
		if s.vp:IsA("ViewportFrame") then
			s.vp.ImageColor3 = locked and Color3.fromRGB(70, 70, 76) or Color3.new(1, 1, 1)
		end
	end
	local function fill(k: number)
		local s = slots[k]
		local w = entry(loadout[k])
		if s.vp then
			s.vp:Destroy()
		end
		if loadout[k] > #weapons then -- an ability: an orb in its colour
			local orb = Instance.new("Frame")
			orb.AnchorPoint = Vector2.new(0.5, 0.5)
			orb.Position = UDim2.fromScale(0.5, 0.5)
			orb.Size = UDim2.fromScale(0.46, 0.46)
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
			s.vp, s.place = icon(viewmodels[w.id] or fistSpec, s.frame, w.id, SLOT_ZOOM[w.id])
		end
		s.stroke.Color = w.color or GROUP[w.tag] or GROUP.melee
		s.showing = loadout[k]
		lockSlot(k)
	end
	local function addSlot(k: number)
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
		slot.Parent = bar
		local lock = text(slot, { Size = UDim2.fromScale(1, 1), Text = "🔒", TextSize = 20, ZIndex = 5, Visible = false })
		slots[k] = { frame = slot, stroke = stroke, cool = cool, lock = lock }
		fill(k)
		slot.Activated:Connect(function()
			if not api.blocked() then
				take(loadout[k])
			end
		end)
	end
	for k in loadout do
		addSlot(k)
	end
	-- the backpack, always last: a tap / click opens the wheel (as holding Q does)
	local show: (boolean) -> () -- the wheel, below
	local open = false
	local arsenal: (on: boolean?, query: boolean?) -> boolean -- client/Arsenal: open / close / toggle, or (nil, true): is it open
	local backpack = Instance.new("TextButton")
	backpack.Name = "Backpack"
	backpack.Text = "🎒"
	backpack.TextSize = 26
	backpack.AutoButtonColor = false
	backpack.Size = UDim2.fromOffset(50, 50)
	backpack.BackgroundColor3 = INK
	backpack.BackgroundTransparency = 0.35
	backpack.LayoutOrder = 1000
	corner(backpack, 10)
	local packStroke = Instance.new("UIStroke")
	packStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	packStroke.Color, packStroke.Thickness, packStroke.Transparency = Color3.fromRGB(196, 226, 244), 1.5, 0.45
	packStroke.Parent = backpack
	backpack.Parent = bar
	backpack.Activated:Connect(function()
		if not api.blocked() and not (api.building and api.building()) then
			arsenal() -- the Arsenal took the wheel's place (client/Arsenal)
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
	local pages = #slotAt
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(R_OUT * 2, R_OUT * 2)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 21
	ring.Parent = wheel
	local ringScale = Instance.new("UIScale")
	ringScale.Parent = ring
	-- the wheel's labels and their full-size TextSize: shrunk onto a phone they grow back to stay readable
	local readable: { [TextLabel]: number } = {}
	local function legible(l: TextLabel): TextLabel
		readable[l] = l.TextSize
		return l
	end
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
		local seg = segs[where[i][2]]
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
		local lock = text(holder, { Size = UDim2.new(1, 0, 1, -14), Text = "🔒", TextSize = 26, ZIndex = 26, Visible = false })
		legible(text(holder, {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(110, 18),
			TextSize = 12, Font = Enum.Font.GothamBold, Text = w.short or w.id:upper(), TextStrokeTransparency = 0.3, ZIndex = 25,
		}))
		petals[i] = { holder = holder, place = place, page = where[i][1], seg = where[i][2], vp = vp, lock = lock }
	end
	for k, a in attacks do
		local i = attackFrom + k
		local seg = segs[where[i][2]]
		local r = (R_IN + R_OUT) / 2
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, math.cos(seg.angle) * r, 0.5, math.sin(seg.angle) * r)
		holder.Size = UDim2.fromOffset(110, 50)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 24
		holder.Parent = ring
		local name = legible(text(holder, {
			Size = UDim2.fromScale(1, 1), TextSize = 13, TextWrapped = true, Font = Enum.Font.GothamBlack,
			Text = a.name, TextColor3 = a.color, TextStrokeTransparency = 0.2, ZIndex = 25,
		}))
		petals[i] = { holder = holder, page = where[i][1], seg = where[i][2],
			place = function() name.TextTransparency = os.clock() < (a.readyAt or 0) and 0.6 or 0 end }
	end
	-- The tutorial's last step (server/Tutorial: "pick"): the wheel opens on the pistol's page, the pistol
	-- in a red ring that slowly shrinks and grows.
	local tutorialGun = 1
	for i, w in weapons do
		if w.id == "Handgun" then
			tutorialGun = i
		end
	end
	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromOffset(118, 118)
	circle.BackgroundTransparency = 1
	circle.ZIndex = 26
	corner(circle, 59)
	local circleStroke = Instance.new("UIStroke")
	circleStroke.Color, circleStroke.Thickness = Color3.fromRGB(235, 40, 40), 4
	circleStroke.Parent = circle
	local circleScale = Instance.new("UIScale")
	circleScale.Scale = 0.85
	circleScale.Parent = circle
	TweenService:Create(circleScale, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.1 }):Play()
	circle.Parent = petals[tutorialGun].holder
	local function tutorialPick(): boolean
		return player:GetAttribute("TutorialStep") == "pick"
	end
	local function showCircle()
		circle.Visible = tutorialPick()
	end
	player:GetAttributeChangedSignal("TutorialStep"):Connect(showCircle)
	showCircle()

	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(R_IN * 2 - 20, 124)
	hub.BackgroundTransparency = 1
	hub.ZIndex = 24
	hub.Parent = ring
	local hubName = legible(text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(1, 0, 0, 22), TextSize = 20, Font = Enum.Font.GothamBold, ZIndex = 25 }))
	local hubPage = legible(text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(94, 24), TextSize = 16, Font = Enum.Font.GothamBlack, ZIndex = 25 }))
	local hubAbout = legible(text(hub, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.new(1, -20, 0, 60), TextSize = 12, Font = Enum.Font.GothamMedium, TextWrapped = true, TextColor3 = Color3.fromRGB(225, 225, 232), ZIndex = 25 }))
	local arrows = {}
	for _, dirn in { -1, 1 } do
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.new(0.5, dirn * 82, 0, 10)
		b.Size = UDim2.fromOffset(64, 64) -- a finger's worth, still once the wheel is shrunk onto a phone
		b.BackgroundTransparency = 1
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 34
		b.TextColor3 = RIM
		b.TextStrokeTransparency = 0.6
		b.Text = dirn < 0 and "‹" or "›"
		b.ZIndex = 25
		b.Visible = pages > 1
		b.Parent = hub
		arrows[dirn] = b
	end

	local pick: number? = inHand()
	local page = 1
	local aimAcc = Vector2.zero
	local stick = Vector2.zero
	show = function(on: boolean)
		if on == open then
			return
		end
		open = on
		gui:SetAttribute("WeaponPickerOpen", on)
		wheel.Visible = on
		if on then
			ReplicatedStorage.Remotes.Action:FireServer("opened", "WeaponWheel") -- the Menus funnel (server/Funnels)
		end
		aimAcc = Vector2.zero
		pick = inHand()
		page = petals[if tutorialPick() then tutorialGun else pick].page
		api.freeze(on)
		TweenService:Create(wheel, TweenInfo.new(0.12), { BackgroundTransparency = on and 0.45 or 1 }):Play()
		packStroke.Transparency = on and 0 or 0.45
		if on then
			-- fit the screen below the top bar (a phone is shorter than the wheel, portrait narrower);
			-- the labels grow back so none reads under 12 px
			local screen, inset = gui.AbsoluteSize, GuiService:GetGuiInset().Y
			local fit = math.min(1, (screen.X - 16) / (R_OUT * 2), (screen.Y - inset * 2 - 16) / (R_OUT * 2))
			for l, size in readable do
				l.TextSize = math.max(size, math.ceil(12 / fit))
			end
			local reach = math.max(64, math.ceil(46 / fit)) -- the page arrows stay a finger's size too
			for _, b in arrows do
				b.Size = UDim2.fromOffset(reach, reach)
				b.Position = UDim2.new(0.5, (b.Text == "‹" and -1 or 1) * (50 + reach / 2), 0, 42 - reach / 2)
			end
			ringScale.Scale = 0.75 * fit
			TweenService:Create(ringScale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fit }):Play()
		end
	end
	local function step(by: number)
		local k = table.find(loadout, inHand()) or 1
		for _ = 1, #loadout do -- past the locked slots
			k = (k - 1 + by) % #loadout + 1
			if not missing(loadout[k]) then
				take(loadout[k])
				return
			end
		end
	end
	local function flip(by: number)
		page = (page - 1 + by) % pages + 1
		pick = pick and slotAt[page][petals[pick].seg] -- same segment on the new page, if it holds one
	end
	for dirn, b in arrows do
		b.Activated:Connect(function()
			flip(dirn)
		end)
	end
	local function choose(i: number?)
		if not i then
			show(false)
			return
		end
		if missing(i) then
			take(i) -- says what it still needs, takes nothing
			show(false)
			return
		end
		if not table.find(loadout, i) then
			if #loadout < MAX_SLOTS then -- a new slot at the end
				table.insert(loadout, i)
				addSlot(#loadout)
			else -- the bar is full: it takes the place of the one in hand
				local k = table.find(loadout, inHand()) or 1
				loadout[k] = i
				fill(k)
			end
		end
		if i ~= inHand() then
			take(i)
		end
		show(false)
	end

	-- the Arsenal grid asks the same locks
	local bagApi = setmetatable({ locked = missing, buy = buy, attackFrom = attackFrom }, { __index = api })
	arsenal = require(script.Parent.Arsenal).start(gui, weapons, viewmodels, fistSpec, icon, ABOUT, bagApi, choose, function() show(false) end)

	-- Unlocks: a notice (below) and the locks redrawn (a new weapon goes on the bar once it is taken).
	-- The banner is for what a locked weapon still needs, and for a moment the name of what was just taken
	-- (the slots show only its picture).
	local banner = text(gui, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96), Size = UDim2.fromOffset(420, 34),
		TextSize = 24, Font = Enum.Font.GothamBlack, TextColor3 = Color3.fromRGB(255, 214, 90), TextStrokeTransparency = 0.2, Text = "", Visible = false,
	})
	local bannerToken = 0
	flash = function(message: string, seconds: number?)
		bannerToken += 1
		local token = bannerToken
		banner.Text, banner.Visible = message, true
		task.delay(seconds or 2.5, function()
			if bannerToken == token then
				banner.Visible = false
			end
		end)
	end
	-- Unlock notices: a comic card on the right of the screen per new weapon - its model turning in a
	-- disc of its group's colour, its name, its group - sliding in, stacking under the last one, gone
	-- after NOTICE_TIME (the stack closes up).
	local NOTICE_TIME = 4.5
	local CATEGORY = { melee = "MELEE", gun = "RANGED", thrown = "EXPLOSIVE", heavy = "EXPLOSIVE", power = "DOOMSDAY" }
	local PAPER = Color3.fromRGB(255, 248, 228)
	local CAPTION = Color3.fromRGB(252, 200, 50)
	local COMIC = Enum.Font.LuckiestGuy -- the menu's lettering
	local notices = Instance.new("Frame")
	notices.Name = "UnlockNotices"
	notices.AnchorPoint = Vector2.new(1, 0)
	notices.Position = UDim2.new(1, -12, 0.2, 0)
	notices.Size = UDim2.fromOffset(340, 520)
	notices.BackgroundTransparency = 1
	notices.Parent = gui
	local stack = Instance.new("UIListLayout")
	stack.Padding = UDim.new(0, 10)
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Right
	stack.Parent = notices
	local noticeCount = 0
	local function inked(parent: Instance, thickness: number)
		local line = Instance.new("UIStroke")
		line.Thickness, line.Color, line.LineJoinMode = thickness, INK, Enum.LineJoinMode.Miter
		line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		line.Parent = parent
	end
	local function notify(i: number, headline: string?) -- headline: the caption ("NEW WEAPON!" by default)
		local w = weapons[i]
		local tint = w.color or GROUP[w.tag] or GROUP.melee
		noticeCount += 1
		Sfx.ui(Sfx.UI_NOTIFICATION, 0.6)
		local slot = Instance.new("Frame") -- its place in the stack; the card slides about inside it
		slot.Size = UDim2.fromOffset(340, 132)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = noticeCount
		slot.Parent = notices
		local card = Instance.new("Frame")
		card.Size = UDim2.fromOffset(318, 108)
		card.Position = UDim2.fromOffset(380, 16)
		card.BackgroundTransparency = 1
		card.Rotation = -2
		card.Parent = slot
		local shadow = Instance.new("Frame")
		shadow.Size = UDim2.fromScale(1, 1)
		shadow.Position = UDim2.fromOffset(7, 8)
		shadow.BackgroundColor3 = INK
		shadow.BorderSizePixel = 0
		shadow.Parent = card
		local paper = Instance.new("Frame")
		paper.Size = UDim2.fromScale(1, 1)
		paper.BackgroundColor3 = PAPER
		paper.BorderSizePixel = 0
		paper.Parent = card
		inked(paper, 4)
		local disc = Instance.new("Frame") -- the model, turning, on a disc of its group's colour
		disc.Size = UDim2.fromOffset(88, 88)
		disc.Position = UDim2.fromOffset(12, 12)
		disc.BackgroundColor3 = tint
		disc.Parent = paper
		corner(disc, 100)
		inked(disc, 3)
		local _, place = icon(viewmodels[w.id] or fistSpec, disc, w.id)
		local name = text(paper, {
			Position = UDim2.fromOffset(110, 24), Size = UDim2.new(1, -120, 0, 44), Text = w.name,
			Font = COMIC, TextScaled = true, TextColor3 = INK, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
		})
		name.TextWrapped = true
		local badge = Instance.new("Frame") -- its group
		badge.Position = UDim2.fromOffset(110, 72)
		badge.Size = UDim2.fromOffset(118, 26)
		badge.BackgroundColor3 = tint
		badge.Rotation = 2
		badge.Parent = paper
		inked(badge, 2.5)
		text(badge, {
			Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), Text = CATEGORY[w.tag] or string.upper(w.tag or ""),
			Font = COMIC, TextScaled = true, TextColor3 = INK, TextStrokeTransparency = 1,
		})
		local caption = Instance.new("Frame") -- the comic caption on its top edge
		caption.Position = UDim2.fromOffset(-10, -16)
		caption.Size = UDim2.fromOffset(150, 30)
		caption.BackgroundColor3 = CAPTION
		caption.Rotation = -4
		caption.Parent = card
		inked(caption, 3)
		text(caption, {
			Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), Text = headline or "NEW WEAPON!",
			Font = COMIC, TextScaled = true, TextColor3 = INK, TextStrokeTransparency = 1,
		})
		local spin = RunService.RenderStepped:Connect(function(dt)
			place(dt)
		end)
		TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(14, 16) }):Play()
		task.delay(NOTICE_TIME, function()
			TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Position = UDim2.fromOffset(380, 16) }):Play()
			task.wait(0.32)
			spin:Disconnect()
			slot:Destroy()
		end)
	end

	local unlocked = {}
	for i in weapons do
		unlocked[i] = not missing(i)
	end
	local function relock()
		local quiet = not player:GetAttribute("ProgressLoaded") -- the saved counters coming in: no banners
		for i, p in petals do
			if i <= #weapons then
				local locked = missing(i) ~= nil
				p.lock.Visible = locked
				p.vp.ImageColor3 = locked and Color3.fromRGB(70, 70, 76) or Color3.new(1, 1, 1)
				if not locked and not unlocked[i] then
					unlocked[i] = true
					if not quiet then
						notify(i)
					end
				end
			end
		end
		for k, s in slots do
			if s.showing ~= loadout[k] then
				fill(k) -- a new weapon in it
			else
				lockSlot(k)
			end
		end
	end
	relock()
	-- Affordable notices: the first time a weapon for sale that is not theirs yet comes within their cash,
	-- the same card says they can buy it (once a session; what they could afford as the save came in stays quiet).
	local affordable = {}
	local function checkAfford()
		local quiet = not player:GetAttribute("ProgressLoaded")
		local cash = player:GetAttribute(Progression.CASH) or 0
		for i, w in weapons do
			local price = Progression.PRICE[w.id]
			if price and not affordable[i] and missing(i) and cash >= price then
				affordable[i] = true
				if not quiet then
					notify(i, `BUY IT: {price}$`)
				end
			end
		end
	end
	checkAfford()
	player:GetAttributeChangedSignal(Progression.CASH):Connect(checkAfford)
	player:GetAttributeChangedSignal("ProgressLoaded"):Connect(checkAfford)
	player.AttributeChanged:Connect(function(attribute) -- a weapon bought (shared/Progression)
		if attribute:sub(1, 3) == "Own" then
			relock()
		end
	end)
	player:GetAttributeChangedSignal(Progression.GROUP_ATTRIBUTE):Connect(relock)
	for _, key in { "AllWeapons", "AllGuns", "AllMelee", "AllExplosives", "Anime", "Doomsday" } do -- passes that unlock (shared/Shop)
		player:GetAttributeChangedSignal("Pass" .. key):Connect(relock)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if api.building and api.building() and input.KeyCode ~= Enum.KeyCode.F then return end -- BUILD (F still drags): Q, 1-5 are the build bar's (Toolbox)
		if input.KeyCode == Enum.KeyCode.Q and arsenal(nil, true) and not UserInputService:GetFocusedTextBox() then
			arsenal(false) -- Q again closes the Arsenal
			return
		end
		if gui:GetAttribute("WeaponPickerOpen") and not open then return end
		if open and input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			choose(pick) -- the backpack opened by a click closes on one (the page arrows are buttons)
			return
		end
		if open and input.UserInputType == Enum.UserInputType.Touch and not processed then
			-- a tap: the segment under the finger; in the hub nothing, outside the ring it closes
			local off = Vector2.new(input.Position.X, input.Position.Y) - (ring.AbsolutePosition + ring.AbsoluteSize / 2)
			local r = off.Magnitude / ringScale.Scale
			if r > R_OUT * 1.15 then
				choose(nil)
			elseif r > R_IN * 0.8 then
				local angle = math.atan2(off.Y, off.X)
				local best, bestGap = 1, math.huge
				for k, seg in segs do
					local gap = math.abs((angle - seg.angle + math.pi) % (math.pi * 2) - math.pi)
					if gap < bestGap then
						best, bestGap = k, gap
					end
				end
				if slotAt[page][best] then
					choose(slotAt[page][best])
				end
			end
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
			arsenal(true) -- the Arsenal took the wheel's place
		elseif input.KeyCode == Enum.KeyCode.F then
			if api.drag then
				api.drag() -- F only drags a dummy in reach, never steps the hotbar
			end
		elseif input.KeyCode.Value >= Enum.KeyCode.One.Value and input.KeyCode.Value < Enum.KeyCode.One.Value + #loadout then
			take(loadout[input.KeyCode.Value - Enum.KeyCode.One.Value + 1]) -- 1-5: that hotbar slot
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			step(-1)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			step(1)
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseWheel and open then
			flip(input.Position.Z > 0 and -1 or 1)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed and api.scrollable() and not api.blocked() and not (api.building and api.building()) then
			step(input.Position.Z > 0 and -1 or 1)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			stick = Vector2.new(input.Position.X, -input.Position.Y)
		end
	end)

	local named = inHand() -- what the banner last named
	RunService.RenderStepped:Connect(function(dt)
		-- the backpack is for phones and tablets (the keyboard holds Q, the mouse is locked in first person)
		backpack.Visible = TouchControls.active()
		-- centred, unless that runs it under the touch ATTACK button (a narrow phone): then left of it
		local half, centre, edge = list.AbsoluteContentSize.X / 2, gui.AbsoluteSize.X / 2, TouchControls.attackLeft()
		bar.Position = UDim2.new(0, if edge then math.max(half + 8, math.min(centre, edge - 8 - half)) else centre, 1, -12)
		local current = inHand()
		if current ~= named then -- something else in hand: its name over the bar for a moment
			named = current
			local e = entry(current)
			if e then
				flash(e.name, 1.5)
			end
		end
		local cooldown = api.cooldown()
		for k, s in slots do
			local on = loadout[k] == current
			local size = on and 64 or 50
			s.frame.Size = s.frame.Size:Lerp(UDim2.fromOffset(size, size), math.min(dt * 18, 1))
			s.frame.BackgroundTransparency = on and 0.05 or 0.35
			s.stroke.Thickness = on and 3 or 1.5
			s.stroke.Transparency = on and 0 or 0.55
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
			pick = slotAt[page][best]
		end
		for k, seg in segs do
			local at = slotAt[page][k]
			for _, f in seg.fill do
				f.BackgroundColor3 = at ~= nil and at == pick and LIT or SEG -- an empty segment is never lit
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
			local need = missing(pick)
			hubAbout.Text = need == Progression.GROUP_NEED and `🔒 {need} to unlock` or need and `🔒 {need} · you have {player:GetAttribute(Progression.CASH) or 0}$ · pick twice to buy` or chosen and ABOUT[chosen.id] or ""
		end
		hubPage.Text = pageName[page]
		hubPage.TextColor3 = pageColor[page] or Color3.new(1, 1, 1)
	end)
end

return WeaponBar
