-- The army helicopter (Wanted, 5 stars): built out of parts, it flies in from far off, hovers over
-- the player's area, lets its troops down on ropes and flies off again. Everything is anchored and
-- moved by hand (no physics); the rotors are spun on each client (HeliRotors), from each rotor
-- piece's "Spin" (turns per second), "Axis", "Pivot" (Body space) and "Offset" (from the pivot).
local RunService = game:GetService("RunService")

local Helicopter = {}

local SPEED = 55 -- studs per second
local FROM = 380 -- how far off it comes in from (and leaves to)
local HOVER = 26 -- studs over the ground while it lets the troops down
local CRUISE = 70 -- studs up while it flies in and out
local DROP_EVERY = 1.1 -- seconds between troops
local GREEN = Color3.fromRGB(64, 76, 48)
local DARK = Color3.fromRGB(34, 38, 30)
local GLASS = Color3.fromRGB(40, 70, 90)

local folder = Instance.new("Folder")
folder.Name = "Helicopters"
folder.Parent = workspace

local function part(model: Model, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, mesh: string?, shape: Enum.PartType?): BasePart
	local p = Instance.new(mesh == "Wedge" and "WedgePart" or "Part") :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = at
	p.Color = color
	p.Material = material or Enum.Material.Metal
	if shape and p:IsA("Part") then
		p.Shape = shape
	end
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	if mesh == "Sphere" or mesh == "Cylinder" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType[mesh]
		m.Parent = p
	end
	p.Parent = model
	return p
end

local SIDE = CFrame.Angles(0, 0, math.rad(90)) -- an upright (Y) cylinder mesh laid along X
local FRONT = CFrame.Angles(math.rad(90), 0, 0) -- ... laid along Z
local GLASS_MAT = Enum.Material.Glass
local PLAIN = Enum.Material.SmoothPlastic
local OLIVE = Color3.fromRGB(84, 96, 58)
local SKIN = Color3.fromRGB(215, 215, 220)
local MARK = Color3.fromRGB(235, 230, 210)

-- Marks a part as a rotor piece: it turns `spin` times a second about the `axis` ("Y" or "X") of
-- `pivot` (Body space); HeliRotors does the turning on each client.
local function rotor(p: BasePart, body: BasePart, pivot: CFrame, spin: number, axis: string)
	p:SetAttribute("Spin", spin)
	p:SetAttribute("Axis", axis)
	p:SetAttribute("Pivot", pivot)
	p:SetAttribute("Offset", (body.CFrame * pivot):ToObjectSpace(p.CFrame))
end

-- White text on a part's face (the markings).
local function mark(p: BasePart, face: Enum.NormalId, text: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = MARK
	label.Text = text
	label.Parent = gui
	gui.Parent = p
end

-- Built at the origin facing -Z, the Body part as its pivot.
local function build(): Model
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local body = part(m, "Body", Vector3.new(6.2, 4.4, 8), CFrame.new(0, 0, 0), GREEN)
	m.PrimaryPart = body

	-- cabin: roof, belly, rounded nose, bubble canopy with its frame, chin windows, side windows
	part(m, "Roof", Vector3.new(5.6, 0.6, 8.2), CFrame.new(0, 2.45, 0), GREEN)
	part(m, "Belly", Vector3.new(5.6, 0.8, 9.4), CFrame.new(0, -2.5, -0.4), DARK)
	part(m, "Nose", Vector3.new(6, 4.4, 6.6), CFrame.new(0, -0.2, -4.4), GREEN, nil, "Sphere")
	-- tinted plastic, not Glass: Glass mirrors the sky and hides the crew
	part(m, "Canopy", Vector3.new(5.3, 3.5, 5.6), CFrame.new(0, 0.8, -5), GLASS, PLAIN, "Sphere").Transparency = 0.55
	part(m, "Chin", Vector3.new(3.6, 1.6, 3), CFrame.new(0, -1.4, -6.3), GLASS, PLAIN, "Sphere").Transparency = 0.55
	part(m, "Frame", Vector3.new(0.2, 0.2, 4.6), CFrame.new(0, 2.15, -5) * CFrame.Angles(math.rad(-24), 0, 0), DARK)
	for _, x in { -1, 1 } do
		part(m, "Frame", Vector3.new(0.18, 3.4, 0.18), CFrame.new(x * 2.05, 0.9, -6.3) * CFrame.Angles(math.rad(-30), 0, math.rad(x * -18)), DARK)
		part(m, "Window", Vector3.new(0.1, 1.3, 1.9), CFrame.new(x * 3.12, 1, -2.7), GLASS, GLASS_MAT).Transparency = 0.2
		-- open side door: the dark bay, rails, the slid-back door, a step under it, a stripe
		part(m, "Bay", Vector3.new(0.1, 3.2, 3.6), CFrame.new(x * 3.11, -0.2, 1.4), Color3.fromRGB(14, 15, 14), PLAIN)
		part(m, "Rail", Vector3.new(0.2, 0.16, 7.6), CFrame.new(x * 3.2, 1.55, 3), DARK)
		part(m, "Rail", Vector3.new(0.2, 0.16, 7.6), CFrame.new(x * 3.2, -1.95, 3), DARK)
		part(m, "Door", Vector3.new(0.12, 3.3, 3.5), CFrame.new(x * 3.3, -0.2, 4.6), GREEN)
		part(m, "DoorWindow", Vector3.new(0.13, 1.1, 1.4), CFrame.new(x * 3.31, 0.7, 4.6), GLASS, GLASS_MAT).Transparency = 0.2
		part(m, "Step", Vector3.new(0.9, 0.12, 2.2), CFrame.new(x * 3.4, -2.7, 1.4), DARK)
		part(m, "Stripe", Vector3.new(0.12, 0.5, 3.4), CFrame.new(x * 3.12, 1.9, -1.6), Color3.fromRGB(196, 182, 120), PLAIN)
		-- skids: tube, upturned front, two struts down from the belly
		part(m, "Skid", Vector3.new(12, 0.42, 0.42), CFrame.new(x * 2.8, -4.5, -0.2) * CFrame.Angles(0, math.rad(90), 0), DARK, nil, nil, Enum.PartType.Cylinder)
		part(m, "Skid", Vector3.new(2.2, 0.42, 0.42), CFrame.new(x * 2.8, -4.0, -6.8) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(35)), DARK, nil, nil, Enum.PartType.Cylinder)
		for _, z in { -3.2, 2.6 } do
			part(m, "Strut", Vector3.new(0.34, 1.9, 0.34), CFrame.new(x * 2.55, -3.6, z) * CFrame.Angles(0, 0, math.rad(x * -14)), DARK)
		end
		-- navigation light: red to port, green to starboard
		part(m, "NavLight", Vector3.new(0.32, 0.32, 0.32), CFrame.new(x * 3.1, -1.7, -3.4), x < 0 and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(40, 255, 80), Enum.Material.Neon, "Sphere")
	end

	-- the crew behind the canopy: seat, body, head, helmet, visor
	for _, x in { -1.2, 1.2 } do
		part(m, "Seat", Vector3.new(1.1, 1.8, 0.3), CFrame.new(x, 0.4, -3.6), DARK)
		part(m, "Pilot", Vector3.new(1.1, 1.3, 0.8), CFrame.new(x, 0.1, -4.1), OLIVE, Enum.Material.Fabric)
		part(m, "PilotHead", Vector3.new(0.85, 0.85, 0.85), CFrame.new(x, 1.15, -4.2), SKIN, PLAIN, "Sphere")
		part(m, "PilotHelmet", Vector3.new(0.98, 0.8, 1.02), CFrame.new(x, 1.3, -4.18), OLIVE, PLAIN, "Sphere")
		part(m, "PilotVisor", Vector3.new(0.7, 0.24, 0.1), CFrame.new(x, 1.22, -4.62), Color3.fromRGB(20, 20, 24), GLASS_MAT)
	end
	part(m, "Panel", Vector3.new(4.2, 0.9, 0.6), CFrame.new(0, 0.2, -5.6) * CFrame.Angles(math.rad(-25), 0, 0), DARK)

	-- engine: housing, rounded cowl, intakes, exhausts, grille lines, red beacon, antennas
	part(m, "Engine", Vector3.new(3.6, 1.5, 6.2), CFrame.new(0, 3.4, 0.8), GREEN)
	part(m, "Cowl", Vector3.new(3.6, 1.5, 2.4), CFrame.new(0, 3.4, -2.3), GREEN, nil, "Sphere")
	for _, x in { -1, 1 } do
		part(m, "Intake", Vector3.new(0.9, 0.5, 0.9), CFrame.new(x * 1.1, 3.4, -2.6) * FRONT, Color3.fromRGB(14, 15, 14), nil, "Cylinder")
		part(m, "Exhaust", Vector3.new(0.75, 1.6, 0.75), CFrame.new(x * 1.3, 3.6, 3.8) * CFrame.Angles(math.rad(70), 0, math.rad(x * -25)), DARK, nil, "Cylinder")
		for i = 0, 2 do
			part(m, "Grille", Vector3.new(0.06, 0.08, 2.6), CFrame.new(x * 1.82, 3.0 + i * 0.3, 1.2), DARK)
		end
	end
	part(m, "Beacon", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 4.25, 3.4), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, "Sphere")
	part(m, "Antenna", Vector3.new(0.06, 1.4, 0.06), CFrame.new(0.8, -3.4, 1.8), DARK, nil, "Cylinder")
	part(m, "Antenna", Vector3.new(0.06, 1.2, 0.06), CFrame.new(-0.6, 3.1, -3.2) * CFrame.Angles(math.rad(-30), 0, 0), DARK, nil, "Cylinder")

	-- searchlight under the nose, a real light in it
	local lamp = part(m, "Searchlight", Vector3.new(0.9, 0.7, 0.9), CFrame.new(1.4, -2.9, -5.2) * CFrame.Angles(math.rad(-55), 0, 0) * FRONT, DARK, nil, "Cylinder")
	local lens = part(m, "Lens", Vector3.new(0.7, 0.08, 0.7), lamp.CFrame * CFrame.new(0, -0.36, 0), Color3.fromRGB(255, 250, 220), Enum.Material.Neon, "Cylinder")
	local light = Instance.new("SpotLight")
	light.Face, light.Range, light.Angle, light.Brightness = Enum.NormalId.Bottom, 60, 50, 4
	light.Parent = lens

	-- door gun on the port side: mount, body, ammo box, four barrels
	local gun = CFrame.new(-3.7, 0, 0.6) * CFrame.Angles(0, math.rad(-35), 0)
	part(m, "GunMount", Vector3.new(0.3, 1.6, 0.3), gun * CFrame.new(0, -0.9, 0), DARK)
	part(m, "Gun", Vector3.new(0.45, 0.45, 1.4), gun, Color3.fromRGB(30, 30, 32))
	part(m, "Ammo", Vector3.new(0.5, 0.5, 0.6), gun * CFrame.new(0.45, -0.1, 0.3), OLIVE)
	for i = 0, 3 do
		local a = i * math.pi / 2
		part(m, "Barrel", Vector3.new(0.1, 1.8, 0.1), gun * CFrame.new(math.cos(a) * 0.1, math.sin(a) * 0.1, -1.5) * FRONT, Color3.fromRGB(30, 30, 32), nil, "Cylinder")
	end

	-- tail: stepped boom with a shaft cover and markings, fin, stabiliser with end plates, tail skid
	local boom = part(m, "Boom", Vector3.new(2.2, 2.0, 5), CFrame.new(0, 1.0, 6.4), GREEN)
	part(m, "Boom", Vector3.new(1.6, 1.5, 5), CFrame.new(0, 1.2, 11.2), GREEN)
	part(m, "Boom", Vector3.new(1.1, 1.1, 4), CFrame.new(0, 1.4, 15.4), GREEN)
	part(m, "ShaftCover", Vector3.new(0.6, 0.4, 13), CFrame.new(0, 2.15, 10.4), DARK)
	mark(boom, Enum.NormalId.Right, "★ ARMY 07")
	mark(boom, Enum.NormalId.Left, "★ ARMY 07")
	part(m, "Fin", Vector3.new(0.4, 4.4, 3.2), CFrame.new(0, 3.6, 17.2), GREEN, nil, "Wedge")
	part(m, "Stabiliser", Vector3.new(5.2, 0.3, 1.6), CFrame.new(0, 1.4, 15.0), GREEN)
	for _, x in { -1, 1 } do
		part(m, "EndPlate", Vector3.new(0.2, 1.2, 1.4), CFrame.new(x * 2.6, 1.4, 15.0), GREEN)
	end
	part(m, "TailLight", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 1.4, 17.5), Color3.new(1, 1, 1), Enum.Material.Neon, "Sphere")
	part(m, "TailSkid", Vector3.new(0.2, 1.4, 0.2), CFrame.new(0, 0.3, 16.6) * CFrame.Angles(math.rad(30), 0, 0), DARK)

	-- main rotor: mast, hub, cap, four grips, four blades with yellow tips (all turned by HeliRotors)
	part(m, "Mast", Vector3.new(0.6, 1.4, 0.6), CFrame.new(0, 4.6, 0), DARK, nil, "Cylinder")
	local pivot = CFrame.new(0, 5.35, 0)
	rotor(part(m, "Hub", Vector3.new(1.7, 0.45, 1.7), pivot, DARK, nil, "Cylinder"), body, pivot, 4.5, "Y")
	rotor(part(m, "HubCap", Vector3.new(0.8, 0.55, 0.8), pivot * CFrame.new(0, 0.32, 0), DARK, nil, "Sphere"), body, pivot, 4.5, "Y")
	for i = 0, 3 do
		local arm = pivot * CFrame.Angles(0, i * math.pi / 2, 0)
		rotor(part(m, "Grip", Vector3.new(1.3, 0.32, 0.55), arm * CFrame.new(1.2, 0, 0), DARK), body, pivot, 4.5, "Y")
		rotor(part(m, "Blade", Vector3.new(13.4, 0.14, 1.0), arm * CFrame.new(8.5, 0.02, 0) * CFrame.Angles(math.rad(4), 0, 0), Color3.fromRGB(28, 30, 26)), body, pivot, 4.5, "Y")
		rotor(part(m, "Tip", Vector3.new(0.9, 0.15, 1.02), arm * CFrame.new(15.6, 0.02, 0) * CFrame.Angles(math.rad(4), 0, 0), Color3.fromRGB(235, 200, 40), PLAIN), body, pivot, 4.5, "Y")
	end

	-- tail rotor on the fin's starboard side: hub and three blades, turning about X
	local tail = CFrame.new(0.55, 3.8, 18.0)
	rotor(part(m, "TailHub", Vector3.new(0.5, 0.5, 0.5), tail * SIDE, DARK, nil, "Cylinder"), body, tail, 9, "X")
	for i = 0, 2 do
		local arm = tail * CFrame.Angles(i * math.pi * 2 / 3, 0, 0)
		rotor(part(m, "TailBlade", Vector3.new(0.1, 2.3, 0.42), arm * CFrame.new(0.05, 1.2, 0), Color3.fromRGB(28, 30, 26)), body, tail, 9, "X")
	end
	return m
end

-- The Blender helicopter (assets/army: build.py, export.py, install.luau) when the place has
-- ReplicatedStorage.ArmyKit: an invisible Body box as the pivot, the body meshes on it, and the two
-- rotors turned by HeliRotors like the part-built ones. Same pivots as build().
local ROTOR_PIVOT, TAIL_PIVOT = CFrame.new(0, 5.35, 0), CFrame.new(0.55, 3.8, 18.0)
local function buildFromKit(): Model?
	local kit = game:GetService("ReplicatedStorage"):FindFirstChild("ArmyKit")
	local hull, main, tail = kit and kit:FindFirstChild("Heli_Body"), kit and kit:FindFirstChild("Heli_Rotor"), kit and kit:FindFirstChild("Heli_TailRotor")
	if not (hull and main and tail) then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "Helicopter"
	local body = part(m, "Body", Vector3.new(6.2, 4.4, 8), CFrame.identity, GREEN)
	body.Transparency = 1
	m.PrimaryPart = body
	local function add(folder: Instance, pivot: CFrame?, spin: number?, axis: string?)
		for _, mesh in folder:GetChildren() do
			local p = mesh:Clone() :: BasePart
			p.Anchored = true
			local at = p:GetAttribute("Place") or CFrame.identity
			p.CFrame = (pivot or CFrame.identity) * at
			if pivot then
				p:SetAttribute("Spin", spin)
				p:SetAttribute("Axis", axis)
				p:SetAttribute("Pivot", pivot)
				p:SetAttribute("Offset", at)
			end
			if mesh.Name == "FFF6D0" then -- the searchlight's lens
				local light = Instance.new("SpotLight")
				light.Face, light.Range, light.Angle, light.Brightness = Enum.NormalId.Front, 60, 60, 4
				light.Parent = p
			end
			p.Parent = m
		end
	end
	add(hull)
	add(main, ROTOR_PIVOT, 4.5, "Y")
	add(tail, TAIL_PIVOT, 9, "X")
	return m
end

Helicopter.build = function()
	return buildFromKit() or build()
end -- (also for a look at it in Studio)

-- Flies `model` from its pivot to `goal` (a position) at SPEED, nose first, tilting into it.
local function fly(model: Model, goal: Vector3)
	local start = model:GetPivot().Position
	local flat = (goal - start) * Vector3.new(1, 0, 1)
	local facing = flat.Magnitude > 1 and flat.Unit or model:GetPivot().LookVector
	local duration = (goal - start).Magnitude / SPEED
	local t = 0
	while t < duration and model.Parent do
		t += RunService.Heartbeat:Wait()
		local a = math.min(t / duration, 1)
		local eased = a * a * (3 - 2 * a)
		local at = start:Lerp(goal, eased)
		local tilt = math.sin(a * math.pi) * math.rad(14) -- nose down while it speeds along, level at either end
		model:PivotTo(CFrame.lookAt(at, at + facing) * CFrame.Angles(-tilt, 0, 0))
	end
end

-- A rope from the door down to `ground`, for `seconds`.
local function rope(from: Vector3, ground: Vector3, seconds: number)
	local length = (from - ground).Magnitude
	local p = Instance.new("Part")
	p.Name = "Rope"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, 0.18, 0.18)
	p.CFrame = CFrame.lookAt((from + ground) / 2, ground) * CFrame.Angles(0, math.rad(90), 0)
	p.Color, p.Material = Color3.fromRGB(70, 60, 44), Enum.Material.Fabric
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Parent = folder
	task.delay(seconds, p.Destroy, p)
end

-- Comes over `target` (a point on the ground), lets one trooper down a rope per kind in `kinds`
-- (`land(cf, kind)` makes each one, standing on the ground there), then leaves. Yields until it
-- is gone; run it in its own thread.
function Helicopter.drop(target: Vector3, kinds: { string }, land: (CFrame, string) -> ())
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder }
	local angle = math.random() * math.pi * 2
	local away = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local over = target + Vector3.yAxis * HOVER
	local model = Helicopter.build()
	model:PivotTo(CFrame.lookAt(target + away * FROM + Vector3.yAxis * CRUISE, over))
	model.Parent = folder
	fly(model, over + away * 30 + Vector3.yAxis * 10) -- in, slowing
	fly(model, over)
	for i, kind in kinds do
		if not model.Parent then
			return
		end
		local side = i % 2 == 0 and 1 or -1
		local door = model:GetPivot() * CFrame.new(side * 3.6, -0.4, 1)
		local hit = workspace:Raycast(door.Position, Vector3.yAxis * -(HOVER + 30), params)
		if hit then
			rope(door.Position, hit.Position, 2.5)
			land(CFrame.lookAt(hit.Position + Vector3.yAxis * 3, target * Vector3.new(1, 0, 1) + Vector3.yAxis * (hit.Position.Y + 3)), kind)
		end
		task.wait(DROP_EVERY)
	end
	task.wait(1)
	fly(model, over - away * 40 + Vector3.yAxis * 20)
	fly(model, target - away * FROM + Vector3.yAxis * CRUISE)
	model:Destroy()
end

return Helicopter
