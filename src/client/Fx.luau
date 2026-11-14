-- Anime-style effects built only from parts (no texture assets), following the Anime vault rules:
-- white flash first -> coloured body -> sparks/detail -> dust trail, short lives, nothing grows
-- linearly, colour + black "ink" pairs so shapes read on bright grass. No impact frames.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attacks"))
local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local rng = Random.new()

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local SKIN = Color3.fromRGB(240, 240, 240)
local DUST = Color3.fromRGB(235, 232, 220)
local UP = Vector3.yAxis
local BASE_FOV = 70

local folder = Instance.new("Folder")
folder.Name = "Fx"
folder.Parent = workspace

local tint = Instance.new("ColorCorrectionEffect")
tint.Parent = Lighting

local Fx = {}
Fx.fovBoost = 0 -- extra FOV set by the client (sprint)
local active = {} -- { t0, dur, fn, parts }
local shakeMag, shakeStart, shakeEnd = 0, 0, 0

local function out(a: number): number
	return 1 - (1 - a) ^ 4
end

local function part(shape: Enum.PartType, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Color = color
	p.Material = material or (color == BLACK and Enum.Material.SmoothPlastic or Enum.Material.Neon)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.one * 0.05
	p.Parent = folder
	return p
end

-- Drive `fn(alpha 0..1)` every frame for `dur` seconds, then destroy `parts`.
local function run(dur: number, parts: { Instance }, fn: (number) -> ())
	table.insert(active, { t0 = os.clock(), dur = dur, fn = fn, parts = parts })
	fn(0)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for i = #active, 1, -1 do
		local a = active[i]
		local alpha = math.min((now - a.t0) / a.dur, 1)
		a.fn(alpha)
		if alpha >= 1 then
			for _, p in a.parts do
				p:Destroy()
			end
			table.remove(active, i)
		end
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local left = now < shakeEnd and (shakeEnd - now) / (shakeEnd - shakeStart) or 0
	if humanoid then
		humanoid.CameraOffset = left > 0 and rng:NextUnitVector() * shakeMag * left or Vector3.zero
	end
	camera.FieldOfView = BASE_FOV + Fx.fovBoost + shakeMag * 5 * left
end)

function Fx.shake(position: Vector3, magnitude: number, duration: number)
	local falloff = math.clamp(1 - (camera.CFrame.Position - position).Magnitude / 150, 0, 1)
	magnitude *= falloff
	local now = os.clock()
	if magnitude > (now < shakeEnd and shakeMag or 0) then
		shakeMag, shakeStart, shakeEnd = magnitude, now, now + duration
	end
end

-- Core of an explosion: three cubes at clashing angles, so it reads as a jagged star-solid
-- instead of a smooth ball.
function Fx.burst(position: Vector3, r0: number, r1: number, dur: number, color: Color3, transparency: number)
	local parts = {}
	for i = 1, 3 do
		parts[i] = part(Enum.PartType.Block, color)
	end
	local spin = rng:NextNumber(-4, 4)
	run(dur, parts, function(a)
		local size = Vector3.one * (r0 + (r1 - r0) * out(a)) * 1.4
		for i, p in parts do
			p.Size = size
			p.CFrame = CFrame.new(position) * CFrame.Angles(i * 1.1 + a * spin, i * 2.3, i * 0.7 + a * spin)
			p.Transparency = transparency + (1 - transparency) * a
		end
	end)
	return parts[1]
end

-- Outline that expands r0 -> r1 and thins out. `sides` makes it a polygon (3 triangle, 4 diamond,
-- 6 hex...) and `spin` turns it while it grows; `arc` < 2pi gives a tapered crescent.
-- `cf` may be a function of alpha so the shape can travel.
-- opt: thick, height, arc, sides, spin, ink (false = no black twin)
function Fx.ring(cf: CFrame | (number) -> CFrame, r0: number, r1: number, dur: number, color: Color3, opt: { [string]: any }?)
	opt = opt or {}
	local arc = opt.arc or math.pi * 2
	local thick, height = opt.thick or 1, opt.height or 0.4
	local n = opt.sides or 12
	local spin = opt.spin or 0
	local parts = {}
	for i = 1, n do
		parts[i] = part(Enum.PartType.Block, color)
	end
	run(dur, parts, function(a)
		local base = (typeof(cf) == "function" and cf(a) or cf) * CFrame.Angles(0, spin * out(a), 0)
		local r = r0 + (r1 - r0) * out(a)
		local length = 2 * r * math.tan(arc / (2 * n)) + thick
		for i, p in parts do
			local f = (i - 0.5) / n
			local taper = arc < 6 and math.sin(f * math.pi) or 1
			p.Size = Vector3.new(length, math.max(height * taper, 0.05), math.max(thick * taper * (1 - a * 0.8), 0.05))
			p.CFrame = base * CFrame.Angles(0, (f - 0.5) * arc, 0) * CFrame.new(0, 0, -r)
			p.Transparency = a * a
		end
	end)
	if color ~= BLACK and opt.ink ~= false then
		-- black twin just outside: the manga ink line
		Fx.ring(cf, r0 + thick * 0.6, r1 + thick * 0.6, dur, BLACK, { arc = arc, sides = n, spin = spin, thick = thick * 0.5, height = height * 0.8 })
	end
end

-- Triangles (two wedges each) stabbing out around cf's Y axis, every one a different length and
-- width. tilt 0 = flat star on the floor, ~1 = crown rising out of it.
-- opt: tilt, width, thick, ink (false = no black twin)
function Fx.spikes(cf: CFrame, count: number, r0: number, length: number, dur: number, color: Color3, opt: { [string]: any }?)
	opt = opt or {}
	local tilt, thick = opt.tilt or 0, opt.thick or 0.2
	local ink = color ~= BLACK and opt.ink ~= false
	local parts, spikes = {}, {}
	local phase = rng:NextNumber() * math.pi * 2
	for i = 1, count do
		local theta = phase + (i + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local tangent = Vector3.new(-math.sin(theta), 0, math.cos(theta))
		local dir = Vector3.new(math.cos(theta), 0, math.sin(theta)) * math.cos(tilt) + UP * math.sin(tilt)
		local spike = {
			rot = CFrame.fromMatrix(Vector3.zero, dir:Cross(tangent), dir, tangent),
			length = length * (0.45 + rng:NextNumber()),
			width = (opt.width or length * 0.22) * (0.6 + rng:NextNumber() * 0.8),
			wedges = {},
		}
		for j = 1, ink and 4 or 2 do
			spike.wedges[j] = part(Enum.PartType.Wedge, j > 2 and BLACK or color)
			table.insert(parts, spike.wedges[j])
		end
		spikes[i] = spike
	end
	run(dur, parts, function(a)
		local grow = out(math.min(a / 0.35, 1))
		for _, spike in spikes do
			for j, wedge in spike.wedges do
				local inked = j > 2
				local l = math.max(spike.length * grow * (inked and 1.12 or 1), 0.05)
				local w = math.max(spike.width * (1 - a) * (inked and 1.6 or 1), 0.05)
				-- two right-angle wedges back to back = one isosceles triangle pointing along +Y
				local centre = cf * spike.rot * CFrame.new(inked and -thick or 0, r0 + l / 2, 0)
				wedge.Size = Vector3.new(thick, l, w / 2)
				wedge.CFrame = centre * CFrame.Angles(0, j % 2 * math.pi, 0) * CFrame.new(0, 0, -w / 4)
				wedge.Transparency = a * a
			end
		end
	end)
end

-- Jagged slabs that stab out of the ground, lean outward and sink back.
function Fx.crystals(cf: CFrame, count: number, radius: number, height: number, dur: number, color: Color3)
	for i = 1, count do
		local p = part(Enum.PartType.Block, i % 3 == 0 and WHITE or (i % 3 == 1 and color or BLACK))
		local h = height * (0.5 + rng:NextNumber() * 0.7)
		local w = h * rng:NextNumber(0.12, 0.24)
		local base = cf
			* CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
			* CFrame.new(0, 0, -radius * (0.35 + rng:NextNumber() * 0.65))
			* CFrame.Angles(-rng:NextNumber(0.2, 0.75), 0, rng:NextNumber(-0.3, 0.3))
			* CFrame.Angles(0, rng:NextNumber() * 3, 0)
		run(dur * (0.7 + rng:NextNumber() * 0.4), { p }, function(a)
			local up = a < 0.2 and out(a / 0.2) or 1 - ((a - 0.2) / 0.8) ^ 3
			p.Size = Vector3.new(w, h * up + 0.05, w)
			p.CFrame = base * CFrame.new(0, h * up / 2 - 0.5, 0)
			p.Transparency = a ^ 3
		end)
	end
end

-- Uneven star that always faces the camera: the hit flash.
function Fx.glint(position: Vector3, size: number, color: Color3, dur: number)
	local facing = CFrame.lookAt(position, camera.CFrame.Position) * CFrame.Angles(-math.pi / 2, 0, 0)
	Fx.spikes(facing, rng:NextInteger(4, 6), 0, size, dur, color, { ink = false, width = size * 0.3 })
end

-- Streaks that shoot out and brake hard ("anime snap"). `radius` < 0 makes them converge.
function Fx.sparks(position: Vector3, count: number, radius: number, color: Color3, bias: Vector3?, life: number?)
	for i = 1, count do
		local dir = rng:NextUnitVector()
		dir = (Vector3.new(dir.X, math.abs(dir.Y), dir.Z) + (bias or Vector3.zero) * 1.5).Unit
		local c = i % 3 == 0 and BLACK or (i % 3 == 1 and color or WHITE)
		local p = part(Enum.PartType.Block, c)
		local reach = math.abs(radius) * (0.5 + rng:NextNumber())
		local length = math.abs(radius) * 0.35 * (0.5 + rng:NextNumber())
		run((life or 0.45) * (0.6 + rng:NextNumber() * 0.7), { p }, function(a)
			local d = radius < 0 and reach * (1 - a * a) or reach * out(a)
			local w = 0.3 * (1 - a) + 0.03
			p.Size = Vector3.new(w, w, length * (1 - a * 0.7))
			p.CFrame = CFrame.lookAt(position + dir * d, position + dir * (d + 1))
		end)
	end
end

-- Voxel dust: tumbling cubes instead of round puffs.
function Fx.dust(position: Vector3, count: number, spread: number, size: number)
	for i = 1, count do
		local angle = rng:NextNumber() * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local p = part(Enum.PartType.Block, i % 4 == 0 and BLACK or DUST, Enum.Material.SmoothPlastic)
		local tumble = rng:NextUnitVector() * 3
		local reach = spread * (0.4 + rng:NextNumber() * 0.6)
		local s = math.min(size, 3.5) * (0.6 + rng:NextNumber() * 0.8) -- bigger puffs blot out the camera
		run(0.7 + rng:NextNumber() * 0.5, { p }, function(a)
			p.Size = Vector3.one * s * (0.4 + 0.6 * out(a)) * (1 - a * 0.5)
			p.CFrame = CFrame.new(position + dir * reach * out(a) + UP * (0.5 + a * s * 0.8)) * CFrame.Angles(tumble.X * a, tumble.Y * a, tumble.Z * a)
			p.Transparency = 0.1 + 0.9 * a * a
		end)
	end
end

-- Speed line: a white streak that rushes past the edge of the view, in camera space.
function Fx.speedLine()
	local angle = rng:NextNumber() * math.pi * 2
	local r = 2.5 + rng:NextNumber() * 1.5
	local offset = Vector3.new(math.cos(angle) * r * 1.5, math.sin(angle) * r, 0)
	local length = 3 + rng:NextNumber() * 3
	local p = part(Enum.PartType.Block, WHITE)
	p.Size = Vector3.new(0.04, 0.04, length)
	run(0.18, { p }, function(a)
		p.CFrame = camera.CFrame * CFrame.new(offset + Vector3.new(0, 0, -14 + 18 * a))
		p.Transparency = 0.3 + 0.7 * a
	end)
end

-- Comic-book word that pops in, settles, drifts up and fades. Strong hits (scale >= BURST_SCALE)
-- put it on the comic starburst image (assets/fx/burst.png, drawn by assets/fx/make_burst.py):
-- yellow letters with a dark outline, only the word changes.
local BURST_SCALE = 2
local BURST_IMAGE = "rbxassetid://121244599706688"
local BURST_ASPECT = 1232 / 772 -- burst.png width / height
local BURST_INK = Color3.fromRGB(70, 10, 10)
local BURST_YELLOW = Color3.fromRGB(255, 215, 40)

function Fx.text(position: Vector3, text: string, color: Color3, scale: number)
	local comic = scale >= BURST_SCALE
	local anchor = part(Enum.PartType.Block, WHITE)
	anchor.Transparency = 1
	anchor.Position = position
	local gui = Instance.new("BillboardGui")
	local w, h = scale * #text * 0.6, scale * 1.4
	if comic then
		local bw = math.max(w * 1.9, scale * 5) -- the burst keeps its own shape, words fit inside it
		gui.Size = UDim2.fromScale(bw, bw / BURST_ASPECT)
	else
		gui.Size = UDim2.fromScale(w, h)
	end
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local pop = Instance.new("Frame") -- everything scales together through this
	pop.BackgroundTransparency = 1
	pop.AnchorPoint = Vector2.new(0.5, 0.5)
	pop.Position = UDim2.fromScale(0.5, 0.5)
	pop.Parent = gui
	local burst: ImageLabel? = nil
	if comic then
		burst = Instance.new("ImageLabel")
		burst.BackgroundTransparency = 1
		burst.Image = BURST_IMAGE
		burst.Size = UDim2.fromScale(1, 1)
		burst.Parent = pop
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	-- the burst's body sits a touch right of and below the image centre
	label.Position = comic and UDim2.fromScale(0.52, 0.5) or UDim2.fromScale(0.5, 0.5)
	label.Size = comic and UDim2.fromScale(0.64, 0.46) or UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = comic and BURST_YELLOW or color
	label.Rotation = comic and rng:NextInteger(-10, -4) or rng:NextInteger(-9, 9) -- comic words tilt up
	label.ZIndex = 2
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = comic and 4 or 3
	stroke.Color = comic and BURST_INK or Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = pop
	gui.Parent = anchor
	run(comic and 1.2 or 1, { anchor }, function(a)
		local s = a < 0.12 and a / 0.12 * 1.25 or 1.25 - 0.25 * math.min((a - 0.12) / 0.1, 1)
		pop.Size = UDim2.fromScale(s, s)
		local fade = math.max(0, (a - 0.7) / 0.3)
		label.TextTransparency = fade
		stroke.Transparency = fade
		if burst then
			burst.ImageTransparency = fade
		end
		anchor.Position = position + UP * a * 2
	end)
end

function Fx.hit(position: Vector3)
	Fx.glint(position, 2.4, WHITE, 0.16)
	Fx.sparks(position, 6, 3.5, Color3.fromRGB(255, 220, 120), nil, 0.25)
	if rng:NextNumber() < 0.3 then
		Fx.text(position + UP * 1.5, "BAM!", WHITE, 1.2)
	end
end

-- Layered explosion; everything scales from `radius` (strength = scale, not new effects).
-- `sides` picks the polygon of the shockwave so each attack keeps its own shape.
function Fx.boom(position: Vector3, radius: number, color: Color3, word: string?, sides: number?)
	local flash = Fx.burst(position, radius * 0.2, radius * 0.45, 0.14, WHITE, 0)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 4
	light.Range = math.min(radius * 2.5, 60)
	light.Parent = flash
	Fx.glint(position + UP * radius * 0.3, radius * 1.4, WHITE, 0.18)
	Fx.burst(position, radius * 0.3, radius * 0.7, 0.4, color, 0.3)
	local floor = CFrame.new(position.X, 0.3, position.Z)
	Fx.spikes(floor, 9, radius * 0.3, radius * 1.3, 0.5, color) -- flat star on the ground
	Fx.spikes(floor, 7, radius * 0.2, radius * 0.9, 0.45, WHITE, { tilt = 1, ink = false }) -- crown
	Fx.crystals(floor, math.clamp(math.floor(radius * 0.6), 4, 12), radius * 0.9, radius * 0.6, 0.7, color)
	task.delay(0.12, Fx.ring, floor, radius * 0.4, radius * 2, 0.5, WHITE, { thick = radius * 0.08, ink = false, sides = sides or 5, spin = 1.2 })
	Fx.sparks(position, math.clamp(math.floor(radius * 1.5), 8, 28), radius * 1.8, color)
	Fx.dust(position, math.clamp(math.floor(radius), 6, 16), radius * 1.3, radius * 0.35)
	if word then
		Fx.text(position + UP * (radius * 0.6 + 3), word, color, 1.5 + radius * 0.12)
	end
	Fx.shake(position, 0.15 + radius * 0.04, 0.3 + radius * 0.015)
end

-- Lines converging on a moving point + a growing core: "charging".
local function charge(getPosition: () -> Vector3, dur: number, radius: number, color: Color3)
	for i = 1, 6 do
		task.delay((i - 1) / 6 * dur, function()
			Fx.sparks(getPosition(), 5, -radius, color, nil, 0.3)
		end)
	end
	local core = part(Enum.PartType.Block, WHITE)
	run(dur, { core }, function(a)
		core.CFrame = CFrame.new(getPosition()) * CFrame.Angles(a * 9, a * 13, 0)
		core.Size = Vector3.one * radius * 0.2 * a
		core.Transparency = 0.2
	end)
end

local function giantFist(from: Vector3, to: Vector3, size: number, travel: number)
	local model = Instance.new("Model")
	local fist = part(Enum.PartType.Block, SKIN, Enum.Material.SmoothPlastic)
	fist.Size = Vector3.new(size, size * 0.85, size)
	local arm = part(Enum.PartType.Block, SKIN, Enum.Material.SmoothPlastic)
	fist.Parent, arm.Parent = model, model
	local outline = Instance.new("Highlight") -- ink outline
	outline.FillTransparency = 1
	outline.OutlineColor = BLACK
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
	model.Parent = folder
	local total = travel + 0.25
	run(total, { model }, function(a)
		local t = math.min(a * total / travel, 1)
		local position = from:Lerp(to, math.max(t * t, 0.02))
		fist.CFrame = CFrame.lookAt(position, position + (to - from))
		arm.Size = Vector3.new(size * 0.55, size * 0.55, (position - from).Magnitude)
		arm.CFrame = CFrame.lookAt(from:Lerp(position, 0.5), position)
		local fade = math.max(0, (a * total - travel) / 0.25)
		fist.Transparency, arm.Transparency = fade, fade
		outline.OutlineTransparency = fade
	end)
end

-- Attack timelines. Delays must match server/init.server.luau.
local TIMELINES = {}

function TIMELINES.Barrage(root: BasePart, _, color: Color3)
	for i = 1, 18 do
		task.delay(i * 0.045, function()
			if not root.Parent then
				return
			end
			local cf = root.CFrame * CFrame.new(rng:NextNumber(-2.2, 2.2), rng:NextNumber(-1, 2), -2)
			local fist = part(Enum.PartType.Block, SKIN, Enum.Material.SmoothPlastic)
			local streak = part(Enum.PartType.Block, i % 2 == 0 and WHITE or color)
			run(0.1, { fist, streak }, function(a)
				local reach = 7 * out(a)
				fist.Size = Vector3.new(1.4, 1.2, 1.5)
				fist.CFrame = cf * CFrame.new(0, 0, -reach)
				streak.Size = Vector3.new(0.5, 0.5, reach)
				streak.CFrame = cf * CFrame.new(0, 0, -reach / 2)
				streak.Transparency = 0.3 + 0.7 * a
			end)
			if i % 3 == 0 then
				Fx.hit((cf * CFrame.new(0, 0, -7)).Position)
			end
		end)
	end
	task.delay(0.84, function()
		if root.Parent then
			local target = root.Position + root.CFrame.LookVector * 8
			Fx.boom(Vector3.new(target.X, 0.5, target.Z), 6, color, "BAM!", 3)
		end
	end)
end

function TIMELINES.Fist(root: BasePart, cf: CFrame, color: Color3)
	local target = cf.Position * Vector3.new(1, 0, 1) + cf.LookVector * 22 + UP
	charge(function()
		return (root.CFrame * CFrame.new(1.5, 0.5, -1)).Position
	end, 0.35, 10, color)
	task.delay(0.35, function()
		giantFist(cf.Position + cf.LookVector * 2 + UP * 3, target + UP * 2, 9, 0.15)
		local muzzle = cf * CFrame.new(0, 1, -4) * CFrame.Angles(math.pi / 2, 0, 0)
		Fx.ring(muzzle, 2, 9, 0.3, WHITE, { thick = 1, ink = false, sides = 4, spin = 2 })
		Fx.spikes(muzzle, 6, 2, 7, 0.3, color)
	end)
	task.delay(0.5, Fx.boom, target, 11, color, "BOOM!", 4)
end

function TIMELINES.Flip(_, cf: CFrame, color: Color3)
	local centre = cf.Position * Vector3.new(1, 0, 1) + cf.LookVector * 18
	local slab = CFrame.lookAt(centre, centre + cf.LookVector)
	local mark = part(Enum.PartType.Block, color)
	mark.CFrame = slab + UP * 0.15
	run(0.45, { mark }, function(a)
		mark.Size = Vector3.new(20 * out(a), 0.2, 28 * out(a))
		mark.Transparency = 0.45
	end)
	task.delay(0.45, function()
		Fx.glint(centre + UP * 3, 12, WHITE, 0.16)
		-- slabs jut out along both long edges of the torn rectangle
		for z = -12, 12, 6 do
			for _, x in { -10, 10 } do
				Fx.crystals(slab * CFrame.new(x, 0, z), 2, 2.5, 9, 0.8, color)
			end
		end
		Fx.sparks(centre, 20, 22, color, UP)
		for z = -10, 10, 10 do
			Fx.dust((slab * CFrame.new(0, 0, z)).Position, 6, 12, 4)
		end
		Fx.ring(slab + UP * 0.3, 8, 24, 0.5, color, { thick = 2, sides = 4 }) -- square wave, same shape as the slab
		Fx.spikes(slab + UP * 0.3, 8, 4, 14, 0.5, WHITE, { tilt = 1.2, ink = false })
		Fx.text(centre + UP * 12, "FLIP!", color, 3)
		Fx.shake(centre, 0.6, 0.45)
	end)
end

function TIMELINES.Slash(_, cf: CFrame, color: Color3)
	local start = CFrame.lookAt(cf.Position * Vector3.new(1, 0, 1) + UP * 2.5, cf.Position * Vector3.new(1, 0, 1) + UP * 2.5 + cf.LookVector)
	for i, roll in { 0, 28, -28 } do
		Fx.ring(function(a)
			return start * CFrame.new(0, 0, -4 - 46 * a + 8) * CFrame.Angles(0, 0, math.rad(roll))
		end, 8, 8 + i, 0.5, i == 1 and WHITE or color, { arc = 2.3, thick = 1.8, height = 2.6 - i * 0.4 })
	end
	for i = 1, 9 do
		task.delay((i - 1) * 0.05, function()
			local point = (start * CFrame.new(0, -2.2, -4 - 5 * i)).Position
			Fx.sparks(point, 5, 9, color, UP, 0.35)
			Fx.dust(point, 2, 5, 2.5)
			Fx.crystals(CFrame.new(point), 2, 3, 5, 0.6, color) -- fins left standing in the trench
			if i % 3 == 0 then
				Fx.spikes(CFrame.new(point + UP * 0.3), 5, 1, 7, 0.35, color)
			end
			Fx.shake(point, 0.25, 0.15)
		end)
	end
	Fx.text(start.Position + UP * 5, "SLASH!", color, 2)
end

function TIMELINES.Nova(root: BasePart, cf: CFrame, color: Color3)
	local centre = cf.Position * Vector3.new(1, 0, 1) + UP * 0.5
	charge(function()
		return root.Position
	end, 0.6, 16, color)
	Fx.ring(CFrame.new(centre), 14, 3, 0.6, color, { thick = 1.2, sides = 6, spin = -2 }) -- pulls in
	task.delay(0.6, function()
		Fx.boom(centre, 14, color, "NOVA!", 6)
		-- instead of a dome: a tall crown of blades, then hexagons turning against each other
		Fx.spikes(CFrame.new(centre), 10, 11, 20, 0.6, color, { tilt = 0.9, width = 2.5 }) -- starts outside the camera
		Fx.crystals(CFrame.new(centre), 12, 22, 10, 0.9, color)
		for i = 1, 3 do
			local wave = { thick = 2.5 - i * 0.5, sides = 6, spin = i % 2 == 0 and 1.5 or -1.5 }
			task.delay(i * 0.16, Fx.ring, CFrame.new(centre), 8, 20 + i * 6, 0.55, i % 2 == 0 and WHITE or color, wave)
		end
	end)
end

function TIMELINES.Ult(root: BasePart, cf: CFrame, color: Color3)
	local target = cf.Position * Vector3.new(1, 0, 1) + cf.LookVector * 16 + UP
	local near = (camera.CFrame.Position - target).Magnitude < 150
	if near then -- the world dims while it charges, then snaps back: contrast instead of an impact frame
		TweenService:Create(tint, TweenInfo.new(0.5), { Brightness = -0.3, Contrast = 0.25, Saturation = -0.5 }):Play()
	end
	charge(function()
		return (root.CFrame * CFrame.new(1.5, 0.5, -1)).Position
	end, 1.1, 26, color)
	Fx.ring(CFrame.new(cf.Position * Vector3.new(1, 0, 1) + UP * 0.4), 22, 3, 1.1, color, { thick = 1.5, sides = 4, spin = 4 })
	task.delay(1.1, function()
		TweenService:Create(tint, TweenInfo.new(0.35), { Brightness = 0, Contrast = 0, Saturation = 0 }):Play()
		giantFist(cf.Position + UP * 3, target + UP * 2, 12, 0.08)
		Fx.boom(target, 26, color, "CATACLYSM!", 8)
		-- pillar of light
		local beam = part(Enum.PartType.Block, WHITE)
		run(0.9, { beam }, function(a)
			local w = 18 * (1 - out(a)) + 0.5
			beam.Size = Vector3.new(w, 160, w)
			beam.CFrame = CFrame.new(target + UP * 80) * CFrame.Angles(0, a * 3, 0)
			beam.Transparency = 0.2 + 0.8 * a
		end)
		-- follow-up waves so the blast has a tail instead of one pop
		for i = 1, 5 do
			task.delay(i * 0.22, function()
				local floor = CFrame.new(target.X, 0.3, target.Z)
				if i % 2 == 0 then
					Fx.ring(floor, 10, 30 + i * 7, 0.6, WHITE, { thick = 4 - i * 0.5, sides = 4, spin = i })
				else
					Fx.spikes(floor, 10, 8, 26 + i * 6, 0.6, color, { width = 6 })
					Fx.crystals(floor, 6, 20 + i * 4, 14, 0.8, color)
				end
				Fx.sparks(target, 10, 40, color, UP)
				Fx.dust(target, 6, 30 + i * 4, 7)
				Fx.shake(target, 0.8 - i * 0.1, 0.3)
			end)
		end
	end)
end

-- One-off events from weapons (not attack timelines).
local EVENTS = {}
local FLAME = { Color3.fromRGB(255, 120, 30), Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 70, 20), BLACK }
local TRACER = Color3.fromRGB(255, 235, 150)

function EVENTS.Shot(_, weaponId: string, from: Vector3, to: Vector3, landed: boolean)
	local aimCf = CFrame.lookAt(from, to)
	local distance = (to - from).Magnitude
	if weaponId == "Bat" or weaponId == "Axe" then
		-- swing: a white crescent sweeping in front of the attacker
		local tilt = weaponId == "Axe" and rng:NextNumber(1.2, 1.5) or rng:NextNumber(-0.4, 0.4)
		Fx.ring(aimCf * CFrame.Angles(0, 0, tilt), 4.5, 6, 0.2, WHITE, { arc = 2.2, thick = 1.4, height = 0.3, ink = false })
		if landed then
			Fx.hit(to)
			Fx.sparks(to, 6, weaponId == "Axe" and 5 or 8, TRACER, -aimCf.LookVector, 0.3)
			Fx.shake(to, 0.3, 0.15)
		end
	elseif weaponId == "Knife" then
		local mesh = WeaponMeshes.create("Knife")
		local blade = mesh or part(Enum.PartType.Block, Color3.fromRGB(210, 215, 225), Enum.Material.Metal)
		blade.Parent = folder
		local trail = part(Enum.PartType.Block, WHITE)
		run(distance / 160, { blade, trail }, function(a)
			local position = from:Lerp(to, a)
			if not mesh then
				blade.Size = Vector3.new(0.12, 0.3, 1.5)
			end
			blade.CFrame = CFrame.lookAt(position, to + aimCf.LookVector) * CFrame.Angles(a * distance * 0.5, 0, 0)
			trail.Size = Vector3.new(0.08, 0.08, 4)
			trail.CFrame = CFrame.lookAt(position, to + aimCf.LookVector) * CFrame.new(0, 0, 2.5)
			trail.Transparency = 0.5
		end)
		if landed then
			task.delay(distance / 160, Fx.hit, to)
		end
	else
		-- guns: tracer from the hip so it does not start inside the shooter's camera
		local muzzle = (aimCf * CFrame.new(0.7, -0.6, -2.5)).Position
		local big = weaponId == "Revolver"
		local tracer = part(Enum.PartType.Block, TRACER)
		run(big and 0.14 or 0.08, { tracer }, function(a)
			local w = (big and 0.35 or 0.18) * (1 - a)
			tracer.Size = Vector3.new(w, w, (to - muzzle).Magnitude)
			tracer.CFrame = CFrame.lookAt(muzzle:Lerp(to, 0.5), to)
			tracer.Transparency = 0.2 + 0.8 * a
		end)
		Fx.glint(muzzle, big and 3 or 1.6, TRACER, 0.08)
		if landed then
			Fx.sparks(to, big and 8 or 4, big and 6 or 3, TRACER, -aimCf.LookVector, 0.25)
			Fx.dust(to, big and 3 or 1, 2, 1)
		end
		Fx.shake(from, big and 0.35 or 0.12, 0.12)
	end
end

function EVENTS.Boom(_, position: Vector3, radius: number)
	Fx.boom(position, radius, FLAME[1], "BOOM!", 5)
end

-- Burning pool: flames are small cubes that rise, tumble and shrink; every fifth one is smoke.
function EVENTS.Slam(_, position: Vector3, radius: number)
	local red = Color3.fromRGB(255, 40, 40)
	local words = radius > 20 and { "KABOOM!", "KRAKOOM!", "KA-BLAM!" } or { "BANG!", "POW!", "WHAM!", "SMASH!", "SLAM!" }
	Fx.boom(position, radius, red, radius > 9 and words[rng:NextInteger(1, #words)] or nil, 6)
	Fx.sparks(position, math.clamp(math.floor(radius * 3), 16, 60), radius * 2.5, red, Vector3.yAxis) -- extra red debris spray
	Fx.dust(position, 8, radius, radius * 0.3)
end

function EVENTS.Fire(_, position: Vector3, radius: number, dur: number)
	Fx.boom(position, 3, FLAME[1])
	local floor = Vector3.new(position.X, math.max(position.Y - 1, 0.2), position.Z)
	local glow = part(Enum.PartType.Block, FLAME[1])
	glow.Transparency = 1
	glow.Position = floor + UP * 2
	local light = Instance.new("PointLight")
	light.Color = FLAME[1]
	light.Range = radius * 2
	light.Brightness = 3
	light.Parent = glow
	run(dur, { glow }, function(a)
		light.Brightness = 3 * (1 - a ^ 4) * rng:NextNumber(0.7, 1)
	end)
	for tick = 0, dur / 0.08 do
		task.delay(tick * 0.08, function()
			local fade = 1 - (tick * 0.08 / dur) ^ 3 -- the pool burns down at the end
			for i = 1, 3 do
				local angle, reach = rng:NextNumber() * math.pi * 2, radius * math.sqrt(rng:NextNumber()) * fade
				local base = floor + Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
				local smoke = (tick + i) % 5 == 0
				local flame = part(Enum.PartType.Block, smoke and BLACK or FLAME[rng:NextInteger(1, 3)])
				local size = rng:NextNumber(0.6, 1.6) * (smoke and 1.3 or 1)
				local height = rng:NextNumber(2, 5) * (smoke and 1.8 or 1)
				local tumble = rng:NextUnitVector() * 4
				run(rng:NextNumber(0.35, 0.7) * (smoke and 1.6 or 1), { flame }, function(a)
					flame.Size = Vector3.one * size * (1 - a) + Vector3.one * 0.05
					flame.CFrame = CFrame.new(base + UP * height * out(a)) * CFrame.Angles(tumble.X * a, tumble.Y * a, tumble.Z * a)
					flame.Transparency = smoke and 0.4 + 0.6 * a or 0
				end)
			end
		end)
	end
end

local colorOf = {}
for _, attack in Attacks do
	colorOf[attack.id] = attack.color
end

function Fx.play(id: string, char: Model?, cf: CFrame, ...)
	if EVENTS[id] then
		EVENTS[id](char, cf, ...)
		return
	end
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local timeline = TIMELINES[id]
	if root and timeline then
		timeline(root, cf, colorOf[id])
	end
end

return Fx
