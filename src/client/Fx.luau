-- Anime-style effects built only from parts (no texture assets), following the Anime vault rules:
-- white flash first -> coloured body -> sparks/detail -> dust trail, short lives, nothing grows
-- linearly, colour + black "ink" pairs so shapes read on bright grass. No impact frames.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Attacks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Attacks"))
local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"))
local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))
local PerfMode = require(script.Parent:WaitForChild("PerfMode"))

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

-- Comfort settings (shared/Settings, the Toolbox SETTINGS page). SCREEN SHAKE scales every shake; a
-- player who never set it but has the device's Reduce Motion on gets 0.3 of it. FLASHES off drops the
-- full-screen flashes (the sniper's impact frames; client/Disasters dims its own).
function Fx.shakeScale(): number
	local set = player:GetAttribute("ShakeScale")
	if set == nil and GuiService.ReducedMotionEnabled then
		return 0.3
	end
	return math.clamp(if type(set) == "number" then set else 1, 0, 1)
end
function Fx.flashes(): boolean
	return Settings.get(player, "Flashes") ~= false
end

-- The body nearest `at` within `radius` (a dummy, a player, a monster): the nearest thing with a
-- Humanoid, not ourselves. Not just what touches it: a round has usually flung the body clear by the
-- time the server's Shot reaches us.
local bodyParams = OverlapParams.new()
bodyParams.FilterType = Enum.RaycastFilterType.Exclude
local function victimAt(at: Vector3, radius: number): Model?
	bodyParams.FilterDescendantsInstances = { folder, player.Character :: Instance }
	local victim: Model? = nil
	local best = radius
	for _, p in workspace:GetPartBoundsInRadius(at, radius, bodyParams) do
		local m = p:FindFirstAncestorOfClass("Model")
		while m and not m:FindFirstChildOfClass("Humanoid") do m = m:FindFirstAncestorOfClass("Model") end
		local dist = m and (p.Position - at).Magnitude
		if dist and dist < best then victim, best = m, dist end
	end
	return victim
end

-- Impact frames (our own scoped sniper hits, and our KOs): a few frames of manga "impact" - the screen
-- goes hard black and white with whoever was hit as a solid black silhouette ringed in white, then
-- the same inverted with a tint, over the comic overlay's ink lines and sticker word (Fx.comic).
-- ~0.13 s in all. A miss, a hip shot or a round that hits no body gets none. FLASHES off: nothing
-- flashes, only the sticker word pops (and the shake).
Fx.IMPACT_FRAMES = true
Fx.scopedShotAt = -math.huge -- os.clock() of our last sniper shot fired through the scope (set by the client)
local impactCC = Instance.new("ColorCorrectionEffect")
impactCC.Name, impactCC.Enabled, impactCC.Parent = "ImpactFrames", false, Lighting
local impactToken = 0
-- { seconds, brightness, tint, silhouette fill, silhouette outline }; contrast this high leaves
-- nearly pure black and white (manga ink), the brightness picks which way the greys fall
local SNIPER_FRAMES = {
	{ 0.05, -0.25, WHITE, BLACK, WHITE },
	{ 0.05, 0.35, Color3.fromRGB(255, 90, 80), WHITE, BLACK },
	{ 0.035, -0.25, WHITE, BLACK, WHITE },
}
Fx.KO_FRAMES = { -- shorter, a yellow cast: a KO is a win, not a wound
	{ 0.04, -0.25, WHITE, BLACK, WHITE },
	{ 0.045, 0.35, Color3.fromRGB(255, 215, 60), WHITE, BLACK },
}
function Fx.impactFrames(at: Vector3, word: string?, frames: { { any } }?, victim: Model?)
	victim = victim or victimAt(at, 8)
	if not Fx.flashes() then
		Fx.shake(at, 0.6, 0.18)
		if victim and word then
			Fx.comic(at, word, 3)
		end
		return
	end
	if not victim then return end -- the round hit a wall or the floor: no impact frames
	impactToken += 1
	local token = impactToken
	local glow = Instance.new("Highlight")
	glow.DepthMode, glow.FillTransparency, glow.OutlineTransparency = Enum.HighlightDepthMode.AlwaysOnTop, 0, 0
	glow.Adornee, glow.Parent = victim, folder
	impactCC.Saturation, impactCC.Contrast, impactCC.Enabled = -1, 12, true
	task.spawn(function()
		for _, f in frames or SNIPER_FRAMES do
			if token ~= impactToken then break end -- a newer shot took over
			impactCC.Brightness, impactCC.TintColor = f[2], f[3]
			glow.FillColor, glow.OutlineColor = f[4], f[5]
			task.wait(f[1])
		end
		glow:Destroy()
		if token == impactToken then impactCC.Enabled = false end
	end)
	Fx.comic(at, word, 3)
	Fx.shake(at, 0.6, 0.18)
end

Fx.fovBoost = 0 -- extra FOV set by the client (sprint)
Fx.muzzle = nil :: ((weaponId: string) -> Vector3?)? -- set by the client: our held weapon's muzzle, now
Fx.weaponPoint = nil :: ((weaponId: string, point: Vector3) -> CFrame?)? -- set by the client: a point on it
Fx.hookAt = nil :: number? -- os.clock() our crowbar's claw went into a shoulder (EVENTS.Hook)
Fx.cameraOffset = Vector3.zero -- Humanoid.CameraOffset set by the client (over the shoulder), shake goes on top
local active = {} -- { t0, dur, fn, parts, real }
local shakeMag, shakeStart, shakeEnd = 0, 0, 0
local shakeOffset = Vector3.zero -- the shake's last jolt, held still through a hitstop
local fovKick = 0 -- degrees the view punches in on our blows (Fx.kick), springs back
-- The effects' own clock: real time, but crawling at HITSTOP_SCALE through a hitstop (Fx.hitstop).
-- Only this client's drawing slows: physics, the server and the remotes never wait on it.
local fxClock = 0
Fx.timeScale = 1 -- 1, or HITSTOP_SCALE during a hitstop (the client's viewmodel reads it too)
local HITSTOP_SCALE = 0.05
local stopStart, stopEnd = 0, 0

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

-- Performance mode (client/PerfMode, on by itself on phones and tablets): the detail pieces (sparks,
-- dust, crystals, spikes) come in half the number and the black ink twins are left out; every shape,
-- flash, word and shake stays. Off, nothing changes.
local function few(n: number): number
	return if PerfMode.active() then math.max(1, math.ceil(n / 2)) else n
end

-- Drive `fn(alpha 0..1)` every frame for `dur` seconds, then destroy `parts`. On the effects' clock
-- (held through a hitstop), or `real` time for the screen overlays that are the hitstop's own frame.
local function run(dur: number, parts: { Instance }, fn: (number) -> (), real: boolean?)
	table.insert(active, { t0 = if real then os.clock() else fxClock, dur = dur, fn = fn, parts = parts, real = real })
	fn(0)
end

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	local stopped = now >= stopStart and now < stopEnd
	Fx.timeScale = if stopped then HITSTOP_SCALE else 1
	fxClock += dt * Fx.timeScale
	if stopped then -- the shake and the kick wait out the freeze where they are
		shakeStart += dt
		shakeEnd += dt
	else
		fovKick *= math.exp(-dt * 14)
	end
	for i = #active, 1, -1 do
		local a = active[i]
		local alpha = math.min(((if a.real then now else fxClock) - a.t0) / a.dur, 1)
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
	if not stopped then
		shakeOffset = if left > 0 then rng:NextUnitVector() * shakeMag * left else Vector3.zero
	end
	if humanoid then
		humanoid.CameraOffset = Fx.cameraOffset + shakeOffset
	end
	camera.FieldOfView = BASE_FOV + Fx.fovBoost + shakeMag * 5 * left + fovKick
end)

-- Hitstop: the effects (Fx's clock), the camera's shake and kick and our viewmodel (Fx.timeScale) all
-- but stop for HITSTOP_MIN..HITSTOP_MAX s, longer the harder the blow (`strength` 1 a jab .. 3 a KO;
-- under 1 none). Purely this client's drawing. They never stack: one already running is only stretched,
-- never past HITSTOP_MAX in all, and a lighter one waits HITSTOP_GAP after the last (auto fire never
-- stutters). SCREEN SHAKE scales it (0 = none) and Reduce Motion halves it; too short to see, it is skipped.
local HITSTOP_MIN, HITSTOP_MAX, HITSTOP_GAP = 0.035, 0.08, 0.12
function Fx.hitstop(strength: number, delay: number?)
	if strength < 1 then
		return
	end
	local scale = Fx.shakeScale() * (if GuiService.ReducedMotionEnabled then 0.5 else 1)
	local dur = (HITSTOP_MIN + (HITSTOP_MAX - HITSTOP_MIN) * (math.min(strength, 3) - 1) / 2) * scale
	if dur < 0.025 then
		return
	end
	local start = os.clock() + (delay or 0)
	if start < stopEnd then
		stopEnd = math.max(stopEnd, math.min(start + dur, stopStart + HITSTOP_MAX))
	elseif start >= stopEnd + HITSTOP_GAP or strength >= 3 then
		stopStart, stopEnd = start, start + dur
	end
end

-- Camera kick: the view punches in a few degrees and springs back (SCREEN SHAKE scales it).
function Fx.kick(strength: number)
	fovKick = math.min(fovKick, -math.min(0.8 + strength, 4) * Fx.shakeScale())
end

-- Afterimages of a body (the dash): `count` see-through neon copies of its limbs left behind
-- along the way, `gap` seconds apart, each fading and thinning out in `life` seconds. The copies
-- are the limbs' own meshes (cloned bare), so they read as the character, not as boxes.
function Fx.ghosts(char: Model, color: Color3, count: number, gap: number, life: number)
	task.spawn(function()
		for i = 1, count do
			if not char.Parent then
				return
			end
			local parts = {}
			for _, limb in char:GetChildren() do
				local was = limb.Archivable
				limb.Archivable = true -- a part that is not archivable clones to nil
				local copy = limb:IsA("BasePart") and limb.Name ~= "HumanoidRootPart" and limb.Transparency < 1 and limb:Clone() or nil
				limb.Archivable = was
				if copy then
					copy:ClearAllChildren() -- no joints, faces, sounds or attachments
					copy.Anchored = true
					copy.CanCollide, copy.CanQuery, copy.CanTouch, copy.CastShadow = false, false, false, false
					copy.Material = Enum.Material.Neon
					copy.Color = i == 1 and WHITE or color -- the first one flashes white
					copy.Transparency = 0.35
					copy.CFrame = limb.CFrame
					copy.Parent = folder
					table.insert(parts, copy)
				end
			end
			local start = 0.35 + (i - 1) / count * 0.25 -- later copies start fainter
			run(life, parts, function(a)
				local fade = start + (1 - start) * out(a)
				for _, p in parts do
					p.Transparency = fade
				end
			end)
			task.wait(gap)
		end
	end)
end

-- Shakes don't add up: the strongest one running wins. Capped at MAX_SHAKE studs (an earthquake asked
-- for 3, which with the FOV wobble on top threw the view about 15 degrees).
local MAX_SHAKE = 1.2
function Fx.shake(position: Vector3, magnitude: number, duration: number)
	local falloff = math.clamp(1 - (camera.CFrame.Position - position).Magnitude / 150, 0, 1)
	magnitude = math.min(magnitude * falloff, MAX_SHAKE) * Fx.shakeScale()
	local now = os.clock()
	if magnitude > (now < shakeEnd and shakeMag or 0) then
		shakeMag, shakeStart, shakeEnd = magnitude, now, now + duration
		if now >= stopStart and now < stopEnd then
			shakeOffset = rng:NextUnitVector() * magnitude -- in a hitstop: the jolt now, held for the freeze
		end
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
	if color ~= BLACK and opt.ink ~= false and not PerfMode.active() then
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
	local ink = color ~= BLACK and opt.ink ~= false and not PerfMode.active()
	count = few(count)
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
	for i = 1, few(count) do
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
	for i = 1, few(count) do
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
	for i = 1, few(count) do
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

-- Comic overlay, on screen over the hit: manga focus lines bursting out of it, a scatter of halftone
-- dots and, with a `word`, the comic starburst sticker (BURST_IMAGE) popping in with it. One set of
-- frames, built once and reused (a newer hit takes it over). FLASHES off: only the sticker, no ink.
-- Runs on real time, so it holds still on screen through the hitstop it comes with.
local COMIC_LINES, COMIC_DOTS = 16, 10
local comicSet: { [string]: any }? = nil
local comicToken, comicAt = 0, -math.huge
local function comicBuild(): { [string]: any }
	local screen = Instance.new("ScreenGui")
	screen.Name, screen.IgnoreGuiInset, screen.ResetOnSpawn, screen.DisplayOrder = "ComicFrames", true, false, 40
	local set = { screen = screen, lines = {}, dots = {} }
	local taper = NumberSequence.new({ -- each line thickens away from the hit
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.15), NumberSequenceKeypoint.new(1, 0),
	})
	for i = 1, COMIC_LINES do
		local line = Instance.new("Frame")
		line.AnchorPoint, line.BorderSizePixel, line.BackgroundColor3, line.Visible = Vector2.new(0.5, 0.5), 0, BLACK, false
		local grad = Instance.new("UIGradient")
		grad.Transparency = taper
		grad.Parent = line
		line.Parent = screen
		set.lines[i] = { frame = line, angle = 0, length = 0, width = 0 }
	end
	for i = 1, COMIC_DOTS do
		local dot = Instance.new("Frame")
		dot.AnchorPoint, dot.BorderSizePixel, dot.BackgroundColor3, dot.Visible = Vector2.new(0.5, 0.5), 0, BLACK, false
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = dot
		dot.Parent = screen
		set.dots[i] = { frame = dot, at = Vector2.zero, size = 0 }
	end
	local sticker = Instance.new("ImageLabel")
	sticker.AnchorPoint, sticker.BackgroundTransparency, sticker.Image, sticker.Visible = Vector2.new(0.5, 0.5), 1, BURST_IMAGE, false
	sticker.ZIndex = 2
	local word = Instance.new("TextLabel")
	word.AnchorPoint, word.Position, word.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.52, 0.5), UDim2.fromScale(0.64, 0.46)
	word.BackgroundTransparency, word.Font, word.TextScaled, word.TextColor3 = 1, Enum.Font.Bangers, true, BURST_YELLOW
	word.ZIndex = 3
	local stroke = Instance.new("UIStroke")
	stroke.Thickness, stroke.Color = 4, BURST_INK
	stroke.Parent = word
	word.Parent = sticker
	sticker.Parent = screen
	set.sticker, set.word, set.stroke = sticker, word, stroke
	screen.Parent = player:WaitForChild("PlayerGui")
	return set
end

function Fx.comic(at: Vector3, word: string?, strength: number)
	local ink = Fx.flashes()
	local now = os.clock()
	if not word and (not ink or now - comicAt < 0.35) then
		return -- a plain big hit right after another overlay: that one stands
	end
	comicAt = now
	local set = comicSet or comicBuild()
	comicSet = set
	comicToken += 1
	local token = comicToken
	local view = camera.ViewportSize
	local base = math.min(view.X, view.Y)
	local p, onScreen = camera:WorldToViewportPoint(at)
	local centre = if onScreen then Vector2.new(p.X, p.Y) else view * Vector2.new(0.5, 0.42)
	local reach = base * (0.3 + 0.06 * strength)
	for _, l in set.lines do
		l.angle = rng:NextNumber() * math.pi * 2
		l.length = base * rng:NextNumber(0.12, 0.26)
		l.width = math.max(2, base * rng:NextNumber(0.004, 0.011))
		l.frame.Rotation = math.deg(l.angle)
		l.frame.Visible = ink
	end
	for i, d in set.dots do -- two loose arcs of shrinking dots off the hit: halftone
		local arc = (if i % 2 == 0 then 0.6 else -2.4) + i * 0.16 + rng:NextNumber(-0.1, 0.1)
		local r = base * (0.16 + 0.05 * (i % 3))
		d.at = centre + Vector2.new(math.cos(arc), math.sin(arc)) * r
		d.size = base * (0.034 - 0.0025 * i) * rng:NextNumber(0.8, 1.2)
		d.frame.Visible = ink
	end
	local sticker = set.sticker
	local w = base * (0.32 + 0.05 * strength)
	local life = if word then 0.75 else 0.24
	sticker.Visible = word ~= nil
	sticker.Position = UDim2.fromOffset(centre.X, centre.Y - base * 0.1)
	sticker.Rotation = rng:NextInteger(-10, -4)
	set.word.Text = word or ""
	run(life, {}, function(a)
		if token ~= comicToken then
			return -- a newer hit has the overlay now
		end
		local la = math.min(a * life / 0.24, 1) -- the ink lasts 0.24 s
		if ink then
			local r0 = base * 0.08 + reach * 0.15 * out(la)
			for _, l in set.lines do
				local len = l.length * (1 - la * 0.6)
				local mid = centre + Vector2.new(math.cos(l.angle), math.sin(l.angle)) * (r0 + reach * 0.6 * out(la) + len / 2)
				l.frame.Position = UDim2.fromOffset(mid.X, mid.Y)
				l.frame.Size = UDim2.fromOffset(len, l.width * (1 - la * 0.7))
				l.frame.BackgroundTransparency = la * la
			end
			for _, d in set.dots do
				local s = d.size * math.min(la / 0.25, 1) * (1 - la * 0.4)
				d.frame.Position = UDim2.fromOffset(d.at.X, d.at.Y)
				d.frame.Size = UDim2.fromOffset(s, s)
				d.frame.BackgroundTransparency = la ^ 3
			end
		end
		if word then
			local s = if a < 0.12 then a / 0.12 * 1.25 else 1.25 - 0.25 * math.min((a - 0.12) / 0.1, 1)
			sticker.Size = UDim2.fromOffset(w * s, w * s / BURST_ASPECT)
			local fade = math.max(0, (a - 0.7) / 0.3)
			sticker.ImageTransparency, set.word.TextTransparency, set.stroke.Transparency = fade, fade, fade
		end
		if a >= 1 then
			for _, l in set.lines do l.frame.Visible = false end
			for _, d in set.dots do d.frame.Visible = false end
			sticker.Visible = false
		end
	end, true)
end

local HIT_WORDS = { "BAM!", "POW!", "WHAM!", "SMACK!", "THWACK!" }
function Fx.hit(position: Vector3)
	-- a punch lands ~3 studs from the eye: there a full-size glint would white out half the screen
	Fx.glint(position, math.min(2.4, (position - camera.CFrame.Position).Magnitude * 0.45), WHITE, 0.16)
	Fx.sparks(position, 6, 3.5, Color3.fromRGB(255, 220, 120), nil, 0.25)
	if rng:NextNumber() < 0.3 then
		Fx.text(position + UP * 1.5, HIT_WORDS[rng:NextInteger(1, #HIT_WORDS)], WHITE, 1.2)
	end
end

-- The victim of our blow flashes white (a soft tint with FLASHES off) and fades, held through the
-- hitstop: the freeze-frame, on this client only. One Highlight, reused: the newest victim takes it.
local hitGlow = Instance.new("Highlight")
hitGlow.Name, hitGlow.Enabled, hitGlow.FillColor, hitGlow.OutlineColor = "HitFlash", false, WHITE, BLACK
hitGlow.DepthMode = Enum.HighlightDepthMode.Occluded
hitGlow.Parent = folder
local glowToken = 0
local function flashVictim(victim: Model, strength: number)
	glowToken += 1
	local token = glowToken
	local fill = if Fx.flashes() then 0.1 else 0.6
	hitGlow.Adornee, hitGlow.Enabled = victim, true
	run(0.09 + 0.03 * strength, {}, function(a)
		if token ~= glowToken then
			return
		end
		hitGlow.FillTransparency = fill + (1 - fill) * a * a
		hitGlow.OutlineTransparency = 0.3 + 0.7 * a
		if a >= 1 then
			hitGlow.Enabled, hitGlow.Adornee = false, nil
		end
	end)
end

-- A thin white ring bursting flat out of the hit, facing the camera: the squash of the blow. Up close
-- (a punch is ~3 studs off in first person) it is shrunk to stay round the target, about a quarter of
-- the view high, instead of filling the screen.
local function radial(at: Vector3, strength: number)
	local face = CFrame.lookAt(at, camera.CFrame.Position) * CFrame.Angles(math.pi / 2, 0, 0)
	local size = 1.4 + strength
	local k = math.min(1, (at - camera.CFrame.Position).Magnitude * 0.3 / size)
	Fx.ring(face, 0.4 * k, size * k, 0.14 + 0.03 * strength, WHITE, { thick = (0.15 + 0.07 * strength) * k, height = 0.08, sides = 10, ink = false, spin = 2 })
end

-- Our own blow landing (the client's predicted punch or kick, or the server's Shot for our weapon):
-- the layers only the attacker gets, on top of what everyone sees (Fx.hit, the Shot's own look).
-- `strength`: 1 a jab .. 3 the heaviest; under 1 (bullets, sprays) only the victim's flash and a
-- small kick. `delay`: s until the blow visibly connects (the fist still on its way). No body near
-- `position`: nothing. client/HitFeel counts the combo and watches for the KO (Fx.onOurHit).
Fx.onOurHit = nil :: ((position: Vector3, strength: number, victim: Model) -> ())?
function Fx.ourHit(position: Vector3, strength: number, victim: Model?, delay: number?)
	local body = victim or victimAt(position, 3)
	if not body or strength <= 0 then
		return
	end
	flashVictim(body, strength)
	Fx.kick(strength * 0.8)
	if strength >= 1 then
		Fx.hitstop(strength, delay)
		radial(position, strength)
		Fx.shake(position, 0.1 + 0.1 * strength, 0.1 + 0.03 * strength)
	end
	if strength >= 2.2 then
		Fx.glint(position, 1.5 + strength, BURST_YELLOW, 0.14)
		Fx.comic(position, nil, strength) -- ink lines only (FLASHES off: none)
	end
	if Fx.onOurHit then
		Fx.onOurHit(position, strength, body)
	end
end

-- Stars flung out of a KO'd body, spinning, on a billboard (always faces the camera).
local KO_STAR = Color3.fromRGB(255, 220, 60)
local function starBurst(position: Vector3)
	local anchor = part(Enum.PartType.Block, WHITE)
	anchor.Transparency = 1
	anchor.Position = position
	local gui = Instance.new("BillboardGui")
	gui.Size, gui.AlwaysOnTop, gui.LightInfluence = UDim2.fromScale(9, 9), true, 0
	local stars = {}
	for i = 1, 7 do
		local star = Instance.new("TextLabel")
		star.AnchorPoint, star.Size, star.BackgroundTransparency = Vector2.new(0.5, 0.5), UDim2.fromScale(0.15, 0.15), 1
		star.Text, star.Font, star.TextScaled = "★", Enum.Font.GothamBold, true
		star.TextColor3, star.TextStrokeColor3, star.TextStrokeTransparency = if i % 3 == 0 then WHITE else KO_STAR, BLACK, 0
		star.Parent = gui
		stars[i] = { label = star, angle = (i + rng:NextNumber(-0.3, 0.3)) / 7 * math.pi * 2, spin = rng:NextNumber(-400, 400) }
	end
	gui.Parent = anchor
	run(0.65, { anchor }, function(a)
		local r = 0.42 * out(a)
		local fade = math.max(0, (a - 0.55) / 0.45)
		for _, s in stars do
			s.label.Position = UDim2.fromScale(0.5 + math.cos(s.angle) * r, 0.5 + math.sin(s.angle) * r * 0.8 + a * a * 0.08)
			s.label.Rotation = s.spin * a
			s.label.TextTransparency, s.label.TextStrokeTransparency = fade, fade
		end
	end)
end

-- The KO moment for a body we just put down (client/HitFeel): the longest hitstop and kick, the
-- comic impact frames with a "KO!" sticker (the black-and-white frames at most every KO_FRAMES_GAP s;
-- FLASHES off: the sticker only), a star burst out of it and yellow sparks. `quiet`: a kill that paid
-- us some time after the blow (a throw, a bleed-out): the word and stars, no freeze, kick or frames.
local KO_FRAMES_GAP = 2.5
local koFramesAt = -math.huge
function Fx.ko(position: Vector3, victim: Model?, quiet: boolean?)
	if not quiet then
		Fx.hitstop(3)
		Fx.kick(3)
		if victim then
			flashVictim(victim, 3)
		end
	end
	if not quiet and victim and Fx.flashes() and os.clock() - koFramesAt > KO_FRAMES_GAP then
		koFramesAt = os.clock()
		Fx.impactFrames(position, "KO!", Fx.KO_FRAMES, victim)
	else
		Fx.comic(position, "KO!", 3)
		Fx.shake(position, if quiet then 0.2 else 0.6, 0.2)
	end
	Fx.glint(position, 5, KO_STAR, 0.2)
	Fx.ring(CFrame.lookAt(position, camera.CFrame.Position) * CFrame.Angles(math.pi / 2, 0, 0), 0.6, 6, 0.3, WHITE,
		{ thick = 0.35, height = 0.08, sides = 12, ink = false, spin = 1.5 })
	Fx.sparks(position, 10, 6, KO_STAR, UP, 0.4)
	starBurst(position + UP * 1.5)
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

function TIMELINES.Barrage(root: BasePart, aim: CFrame, color: Color3)
	for i = 1, 18 do
		task.delay(i * 0.045, function()
			if not root.Parent then
				return
			end
			local cf = (aim.Rotation + root.Position) * CFrame.new(rng:NextNumber(-2.2, 2.2), rng:NextNumber(-1, 2), -2)
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
			local target = root.Position + aim.LookVector * 8
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

local SLASH = Color3.fromRGB(170, 225, 255)
local ICE = Color3.fromRGB(170, 225, 255)
local ZAP = Color3.fromRGB(255, 240, 90)
local ROPE = Color3.fromRGB(176, 132, 78)
local STEEL = Color3.fromRGB(205, 210, 220)

-- A straight stick of `width` from a to b (tracers, wires, rope).
local function stick(p: BasePart, a: Vector3, b: Vector3, width: number)
	p.Size = Vector3.new(width, width, math.max((b - a).Magnitude, 0.05))
	p.CFrame = CFrame.lookAt(a:Lerp(b, 0.5), b)
end

-- The comic set's shots (server/Specials sends them as "Shot"): (muzzle, to, aimCf, distance, landed,
-- primary). Harpoon: primary = it struck a body (into anything else it stays stuck a while).
local COMIC_SHOTS = {}

function COMIC_SHOTS.Frostgun(muzzle: Vector3, to: Vector3, aimCf: CFrame, _, landed: boolean)
	local beam, core = part(Enum.PartType.Block, ICE), part(Enum.PartType.Block, WHITE)
	run(0.3, { beam, core }, function(a)
		stick(beam, muzzle, to, 0.45 * (1 - a) + 0.02)
		stick(core, muzzle, to, 0.15 * (1 - a) + 0.01)
		beam.Transparency = 0.3 + 0.7 * a
	end)
	Fx.glint(muzzle, 2, ICE, 0.08)
	Fx.shake(muzzle, 0.15, 0.1)
	if landed then
		Fx.crystals(CFrame.new(to), 6, 1.6, 2.4, 0.7, ICE)
		Fx.sparks(to, 8, 4, WHITE, -aimCf.LookVector, 0.4)
		Fx.text(to + UP * 2, "FREEZE!", ICE, 2.2)
	end
end

function COMIC_SHOTS.Taser(muzzle: Vector3, to: Vector3, aimCf: CFrame, _, landed: boolean)
	local wires = { part(Enum.PartType.Block, ZAP), part(Enum.PartType.Block, ZAP) }
	run(0.6, wires, function(a)
		for i, w in wires do
			local side = aimCf.RightVector * (i == 1 and -0.08 or 0.08)
			stick(w, muzzle + side, to + side * 3 + UP * math.sin(a * 40 + i) * 0.05, 0.05)
			w.Transparency = a > 0.7 and (a - 0.7) / 0.3 or 0
		end
	end)
	if landed then
		Fx.sparks(to, 10, 3, ZAP, -aimCf.LookVector, 0.35)
		Fx.text(to + UP * 2, "ZZZT!", ZAP, 2.2)
	end
end

function COMIC_SHOTS.Boilgun(muzzle: Vector3, to: Vector3, aimCf: CFrame, _, landed: boolean, primary: boolean?)
	local puff = part(Enum.PartType.Ball, WHITE, Enum.Material.SmoothPlastic)
	run(0.28, { puff }, function(a)
		puff.Size = Vector3.one * (0.3 + 1.4 * out(a))
		puff.Position = muzzle:Lerp(to, out(a))
		puff.Transparency = 0.35 + 0.65 * a
	end)
	if primary ~= false then
		Fx.glint(muzzle, 2.2, WHITE, 0.08)
		Fx.shake(muzzle, 0.3, 0.12)
	end
	if landed then
		Fx.burst(to, 0.3, 1.6, 0.35, WHITE, 0.4)
	end
end

function COMIC_SHOTS.Lasso(hand: Vector3, to: Vector3, aimCf: CFrame, distance: number, landed: boolean)
	-- the loop flies out spinning flat, the rope paying out behind it (the server's rope takes over)
	local bits = {}
	for _ = 1, 12 do
		table.insert(bits, part(Enum.PartType.Block, ROPE, Enum.Material.SmoothPlastic))
	end
	local line = part(Enum.PartType.Block, ROPE, Enum.Material.SmoothPlastic)
	table.insert(bits, line)
	local start = hand + UP * 1.2
	run(math.clamp(distance / 90, 0.15, 0.5), bits, function(a)
		local p = start:Lerp(to, a) + UP * math.sin(a * math.pi) * distance * 0.08
		local spin = a * 10
		for i = 1, 12 do
			local t0, t1 = (i - 1) / 12 * math.pi * 2 + spin, i / 12 * math.pi * 2 + spin
			stick(bits[i], p + Vector3.new(math.cos(t0), 0, math.sin(t0)) * 1.2, p + Vector3.new(math.cos(t1), 0, math.sin(t1)) * 1.2, 0.12)
		end
		stick(line, start, p, 0.1)
	end)
	if landed then
		task.delay(math.clamp(distance / 90, 0.15, 0.5), Fx.text, to + UP * 2.5, "GOTCHA!", Color3.fromRGB(255, 220, 60), 2.2)
	end
end

function COMIC_SHOTS.Harpoon(muzzle: Vector3, to: Vector3, aimCf: CFrame, distance: number, landed: boolean, onBody: boolean?)
	local shaft, tip, line = part(Enum.PartType.Block, STEEL, Enum.Material.Metal), part(Enum.PartType.Block, STEEL, Enum.Material.Metal),
		part(Enum.PartType.Block, WHITE, Enum.Material.SmoothPlastic)
	local flight = distance / 160
	local look = aimCf.LookVector
	run(flight, { shaft, tip, line }, function(a)
		local p = muzzle:Lerp(to, a)
		stick(shaft, p - look * 2.4, p, 0.1)
		stick(tip, p - look * 0.3, p + look * 0.15, 0.22)
		stick(line, muzzle, p - look * 2.4, 0.04)
	end)
	Fx.shake(muzzle, 0.3, 0.12)
	if landed then
		task.delay(flight, function()
			Fx.hit(to)
			if not onBody then -- into a wall: it stays stuck there a while
				local stuck = part(Enum.PartType.Block, STEEL, Enum.Material.Metal)
				stick(stuck, to - look * 2.2, to + look * 0.2, 0.1)
				run(3, { stuck }, function() end)
			end
		end)
	end
end

local MELEE = {}
for _, w in require(ReplicatedStorage.Shared:WaitForChild("Weapons")) do
	if w.kind == "melee" then
		MELEE[w.id] = true
	end
	if w.slash then MELEE[w.slash.id] = true end
end
MELEE.Baton = true -- the cops' baton: a dummy weapon, not in Weapons

-- How hard our own weapon's blow lands, for the attacker's layers (Fx.ourHit: 1 a jab .. 3 the
-- heaviest, under 1 no hitstop, 0 none at all). Not listed: melee 1.5, anything else 0.5.
local HIT_STRENGTH = {
	BoxingGloves = 1, BoxingHeavy = 2.4, Pan = 2.2, Sledgehammer = 2.6, Bat = 1.8, Axe = 1.8, Crowbar = 1.3,
	Katana = 1.5, KnifeSlash = 1, Spear = 1.4, Lightsaber = 1.6, Baton = 1.3,
	Sniper = 2.4, Revolver = 1.2, Shotgun = 1.1, Harpoon = 1.4, Knife = 1.2,
	Minigun = 0.3, Chainsaw = 0.3, Lasso = 0, Flamethrower = 0, -- (the throwables' blasts shake on their own)
	Grenade = 0, Molotov = 0, TNT = 0, C4 = 0, Landmine = 0, Rocket = 0, Bandage = 0, Cast = 0, HealSyringe = 0,
}

function EVENTS.Shot(shooter: Model?, weaponId: string, from: Vector3, to: Vector3, landed: boolean, primary: boolean?,
	swing: Vector3?, center: Vector3?)
	-- our own shot leaves the muzzle of the gun as it is drawn right now, so it keeps up with the
	-- model however we move (the server's position for us lags a little behind)
	local ownMuzzle = shooter ~= nil and shooter == player.Character and Fx.muzzle and Fx.muzzle(weaponId)
	local aimCf = CFrame.lookAt(from, to)
	local distance = (to - from).Magnitude
	if landed and primary ~= false and shooter ~= nil and shooter == player.Character and (HIT_STRENGTH[weaponId] or 1) > 0 then
		-- our own weapon landed: the attacker's layers (Fx.ourHit), once the blade or harpoon gets there
		local strength = HIT_STRENGTH[weaponId] or (if MELEE[weaponId] then 1.5 else 0.5)
		local flight = if weaponId == "Knife" or weaponId == "Harpoon" then distance / 160 else 0
		task.delay(flight, Fx.ourHit, to, strength)
	end
	if weaponId == "BoxingGloves" or weaponId == "BoxingHeavy" then
		-- A padded punch gets a compact impact, never a blade's crescent or metal sparks.
		if landed then
			Fx.hit(to)
			if weaponId == "BoxingHeavy" then -- the heavy left out of the block
				Fx.shake(to, 0.55, 0.2)
				Fx.text(to + UP * 2, "POW!", Color3.fromRGB(255, 220, 60), 2.4)
			else
				Fx.shake(to, 0.22, 0.12)
			end
		end
	elseif weaponId == "Spear" then
		-- a thrust, not a swing: one quick straight streak along the point's path, no crescent
		local look = aimCf.LookVector
		local start = from + look * 1.5
		local streak = part(Enum.PartType.Block, WHITE)
		run(0.12, { streak }, function(a)
			local reach = start:Lerp(to, 0.35 + 0.65 * out(a))
			stick(streak, start:Lerp(reach, 0.6 * a), reach, 0.12 * (1 - a) + 0.02)
			streak.Transparency = 0.2 + 0.8 * a
		end)
		if landed then
			Fx.sparks(to, 4, 3, TRACER, -look, 0.25)
			Fx.shake(to, 0.25, 0.12)
		end
	elseif weaponId == "Crowbar" then
		-- no comic look (no crescent, no flash star or BAM!): a few metal sparks and a knock where it lands
		if landed then
			Fx.sparks(to, 5, 3, TRACER, -aimCf.LookVector, 0.25)
			Fx.shake(to, 0.3, 0.15)
		end
	elseif MELEE[weaponId] then
		-- swing: a crescent sweeping in front of the attacker; the katana's is a thin, wide,
		-- steel-blue slash cut at a slant, the others a fat white arc
		local katana = weaponId == "Katana"
		local knife = weaponId == "KnifeSlash"
		local tilt = (weaponId == "Axe" or katana) and rng:NextNumber(1.0, 1.6) * (rng:NextNumber() < 0.5 and -1 or 1) or rng:NextNumber(-0.4, 0.4)
		local ringCf = aimCf
		if typeof(swing) == "Vector3" and (swing.X ~= 0 or swing.Y ~= 0) then
			-- an aimed swing: the crescent lies along the drawn line (x right, y up), round the crosshair
			tilt = math.atan2(swing.Y, swing.X)
			if typeof(center) == "Vector3" and center.Magnitude > 0.5 then ringCf = CFrame.lookAlong(from, center) end
		end
		Fx.ring(ringCf * CFrame.Angles(0, 0, knife and -0.65 or tilt), knife and 2.4 or katana and 5 or 4.5,
			knife and 4 or katana and 8 or 6, knife and 0.12 or katana and 0.16 or 0.2, (katana or knife) and SLASH or WHITE,
			{ arc = katana and 2.8 or 2.2, thick = (katana or knife) and 0.5 or 1.4, height = 0.3, ink = false })
		if landed then
			Fx.hit(to)
			Fx.sparks(to, 6, weaponId == "Axe" and 5 or 8, TRACER, -aimCf.LookVector, 0.3)
			Fx.shake(to, weaponId == "Pan" and 0.5 or 0.3, 0.15)
			if weaponId == "Pan" then
				Fx.text(to + UP * 2, "BONK!", Color3.fromRGB(255, 220, 60), 2.4) -- the pan's whole point
			end
		end
	elseif weaponId == "Knife" then
		local mesh = WeaponMeshes.create("Knife")
		local blade = mesh or part(Enum.PartType.Block, Color3.fromRGB(210, 215, 225), Enum.Material.Metal)
		blade.Parent = folder
		local trail = part(Enum.PartType.Block, WHITE)
		local start = ownMuzzle or from
		run(distance / 160, { blade, trail }, function(a)
			local position = start:Lerp(to, a)
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
	elseif COMIC_SHOTS[weaponId] then
		-- the comic set's own looks (server/Specials); from the muzzle as the guns below
		COMIC_SHOTS[weaponId](ownMuzzle or (aimCf * CFrame.new(0.7, -0.6, -2.5)).Position, to, aimCf, distance, landed, primary)
	else
		-- guns: tracer from the hip so it does not start inside the shooter's camera
		-- a dummy's shot already leaves from its hand
		local muzzle = ownMuzzle or (shooter and shooter:GetAttribute("Gear") and from) or (aimCf * CFrame.new(0.7, -0.6, -2.5)).Position
		local sniper = weaponId == "Sniper"
		-- only a scoped shot of ours (the client stamps Fx.scopedShotAt as it fires) that lands on a body
		if sniper and Fx.IMPACT_FRAMES and primary ~= false and landed and shooter ~= nil and shooter == player.Character
			and os.clock() - Fx.scopedShotAt < 1.5 then
			Fx.impactFrames(to, "BLAM!")
		end
		local big = weaponId == "Revolver" or sniper
		local pellet = weaponId == "Shotgun"
		local tracer = part(Enum.PartType.Block, TRACER)
		run(sniper and 0.35 or big and 0.14 or 0.08, { tracer }, function(a)
			local w = (sniper and 0.9 or big and 0.6 or pellet and 0.2 or 0.35) * (1 - a)
			tracer.Size = Vector3.new(w, w, (to - muzzle).Magnitude)
			tracer.CFrame = CFrame.lookAt(muzzle:Lerp(to, 0.5), to)
			tracer.Transparency = 0.2 + 0.8 * a
		end)
		if primary ~= false then
			Fx.glint(muzzle, (big or pellet) and 3 or 1.6, TRACER, 0.055)
			local flash = part(Enum.PartType.Ball, WHITE)
			flash.Name = "MuzzleFlash"
			flash.Position = muzzle
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness = TRACER, 7, 1.8
			light.Parent = flash
			run(0.045, { flash }, function(a)
				flash.Size = Vector3.one * (1 - a) * ((big or pellet) and 0.28 or 0.16)
				flash.Transparency = a
				light.Brightness = 1.8 * (1 - a)
			end)
			-- Revolvers retain their cases. Other guns eject one case per trigger, not per pellet.
			if weaponId ~= "Revolver" then
				local casing = part(Enum.PartType.Cylinder, Color3.fromRGB(214, 166, 70), Enum.Material.Metal)
				casing.Name = "ShellCasing"
				casing.Size = pellet and Vector3.new(0.22, 0.11, 0.11) or Vector3.new(0.15, 0.07, 0.07)
				local start = muzzle - aimCf.LookVector * (pellet and 1.3 or 0.7)
				local velocity = aimCf.RightVector * 7 + UP * 4
				run(0.55, { casing }, function(a)
					local t = a * 0.55
					casing.CFrame = CFrame.new(start + velocity * t - UP * 24 * t * t)
						* CFrame.Angles(t * 17, t * 11, t * 23)
					casing.Transparency = math.max(0, (a - 0.7) / 0.3)
				end)
			end
		end
		if landed then
			Fx.sparks(to, big and 8 or 4, big and 6 or 3, TRACER, -aimCf.LookVector, 0.25)
			Fx.dust(to, big and 3 or 1, 2, 1)
		end
		if primary ~= false then
			Fx.shake(from, sniper and 0.7 or big and 0.35 or pellet and 0.35 or 0.12, sniper and 0.2 or 0.12)
		end
		if sniper and landed then
			Fx.ring(CFrame.lookAt(to, to - aimCf.LookVector) * CFrame.Angles(math.pi / 2, 0, 0), 0.5, 4, 0.25, WHITE, { thick = 0.3 })
		end
	end
end

function EVENTS.Boom(_, position: Vector3, radius: number)
	Fx.boom(position, radius, FLAME[1], "BOOM!", 5)
end

-- The flamethrower's spray (server/Specials, one per tick while it is held): a cone of tumbling flame
-- cubes from the muzzle out to `range`, every fourth one smoke.
function EVENTS.Flame(shooter: Model?, from: Vector3, dir: Vector3, range: number)
	local muzzle = shooter == player.Character and Fx.muzzle and Fx.muzzle("Flamethrower") or from + dir * 2
	for i = 1, 6 do
		local smoke = i % 4 == 0
		local cube = part(Enum.PartType.Block, smoke and BLACK or FLAME[rng:NextInteger(1, 3)])
		local spread = rng:NextUnitVector() * 0.18
		local aim = (dir + spread).Unit
		local reach = range * rng:NextNumber(0.6, 1)
		local tumble = rng:NextUnitVector() * 6
		run(rng:NextNumber(0.3, 0.45) * (smoke and 1.4 or 1), { cube }, function(a)
			local size = (0.4 + 2.2 * a) * (1 - a * 0.5)
			cube.Size = Vector3.one * size
			cube.CFrame = CFrame.new(muzzle + aim * reach * out(a) + UP * a * a * 2) * CFrame.Angles(tumble.X * a, tumble.Y * a, tumble.Z * a)
			cube.Transparency = smoke and 0.4 + 0.6 * a or a ^ 2
		end)
	end
	if rng:NextNumber() < 0.3 then
		Fx.glint(muzzle, 1.2, FLAME[2], 0.06)
	end
end

-- A tased body (server/Specials): crackling sparks round the part the wires hit for `dur` seconds.
function EVENTS.Tase(_, hitPart: BasePart, dur: number)
	for tick = 0, dur / 0.12 do
		task.delay(tick * 0.12, function()
			if hitPart.Parent then
				Fx.sparks(hitPart.Position, 3, 1.8, ZAP, nil, 0.2)
			end
		end)
	end
end

-- Steam off a scalded body (the boilgun).
function EVENTS.Steam(_, position: Vector3)
	for _ = 1, 3 do
		local puff = part(Enum.PartType.Ball, WHITE, Enum.Material.SmoothPlastic)
		local drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		run(0.8, { puff }, function(a)
			puff.Size = Vector3.one * (0.6 + 1.6 * a)
			puff.Position = position + drift + UP * (1 + 3 * out(a))
			puff.Transparency = 0.45 + 0.55 * a
		end)
	end
end

-- The crowbar's claw sinks into a shoulder (server/Specials ripArm), then tears the arm off: no comic
-- words or bursts here, only sparks off the claw and the camera's jolt.
function EVENTS.Hook(attacker: Model?, position: Vector3)
	Fx.sparks(position, 4, 2, TRACER, UP, 0.25)
	Fx.shake(position, 0.35, 0.15)
	if attacker and attacker == player.Character then
		Fx.hookAt = os.clock() -- our own claw is in: the client plays the tug (WeaponAnims Rip_Crowbar, view hookT)
	end
end

function EVENTS.Rip(_, position: Vector3)
	Fx.shake(position, 0.6, 0.25)
end

-- The torn arm on the claw (server/Specials ripArm). Everyone else sees the server move it on the
-- third-person crowbar; for the attacker it goes on the crowbar they actually see (first person: the
-- viewmodel), so the server's copy is hidden here and a local copy rides the claw's point instead.
local CLAW = Vector3.new(0, 1.37, -0.37) -- the hook's point in the Crowbar mesh (Specials CLAW_TIP)
local function hangCF(claw: CFrame, arm: BasePart): CFrame -- Specials.hangCF
	local look = claw.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.05 and look.Unit or Vector3.zAxis
	return CFrame.lookAlong(claw.Position, look) * CFrame.new(0, -arm.Size.Y * 0.4, 0)
end
function EVENTS.Hang(shooter: Model?, gib: Model, arm: BasePart, dur: number)
	if shooter ~= player.Character or not gib or not arm or not Fx.weaponPoint then
		return
	end
	local copies, rel, hidden = {}, {}, {}
	for _, p in gib:GetDescendants() do
		if p:IsA("BasePart") then
			local c = p:Clone()
			for _, kid in c:GetChildren() do
				if kid:IsA("Constraint") or kid:IsA("JointInstance") or kid:IsA("WeldConstraint") then
					kid:Destroy()
				end
			end
			c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch = true, false, false, false
			c.Parent = folder
			rel[c] = arm.CFrame:ToObjectSpace(p.CFrame)
			table.insert(copies, c)
			p.LocalTransparencyModifier = 1
			table.insert(hidden, p)
		end
	end
	run(dur, copies, function(a)
		local claw = Fx.weaponPoint("Crowbar", CLAW)
		if claw then
			local at = hangCF(claw, arm)
			for _, c in copies do
				c.CFrame = at * rel[c]
			end
		end
		if a >= 1 then
			for _, p in hidden do
				p.LocalTransparencyModifier = 0
			end
		end
	end)
end

-- A frozen dummy thaws: the ice cracks off.
function EVENTS.Thaw(_, position: Vector3)
	Fx.sparks(position, 12, 4, ICE, UP, 0.45)
end

local function bodyParts(model: Model): { BasePart }
	local parts = {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			table.insert(parts, p)
		end
	end
	return parts
end

-- Blood boiling in a body (the boilgun, server/Specials: one per tick while it boils): dark red
-- bubbles swell and pop on the skin, steam rolls off it.
local BOIL_RED = Color3.fromRGB(150, 15, 25)
function EVENTS.Boil(_, model: Model?)
	local parts = model and model.Parent and bodyParts(model) or {}
	if #parts == 0 then
		return
	end
	for _ = 1, 4 do
		local p = parts[rng:NextInteger(1, #parts)]
		local base = p.Position + rng:NextUnitVector() * math.min(p.Size.X, p.Size.Y, p.Size.Z) * 0.5
		local bubble = part(Enum.PartType.Ball, BOIL_RED, Enum.Material.SmoothPlastic)
		local size = rng:NextNumber(0.25, 0.55)
		run(rng:NextNumber(0.25, 0.4), { bubble }, function(a)
			bubble.Size = Vector3.one * size * (0.3 + 0.9 * out(a))
			bubble.Position = base + UP * a * 0.6
			bubble.Transparency = if a > 0.8 then (a - 0.8) / 0.2 else 0.05
		end)
	end
	EVENTS.Steam(nil, parts[rng:NextInteger(1, #parts)].Position - UP)
end

-- Burning dummies (server/Specials.alight sets "Burning"): the flamethrower's flame cubes lick up
-- off the body and a light flickers on it, for as long as it burns.
local function burnFx(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local running = false
	local function start()
		if running or model:GetAttribute("Burning") ~= true then
			return
		end
		running = true
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness = FLAME[1], 12, 2.5
		light.Parent = model:FindFirstChild("UpperTorso")
		task.spawn(function()
			while model.Parent and model:GetAttribute("Burning") == true do
				local parts = bodyParts(model)
				if #parts == 0 then
					break
				end
				for _ = 1, 3 do
					local p = parts[rng:NextInteger(1, #parts)]
					local base = p.Position + Vector3.new(rng:NextNumber(-0.5, 0.5) * p.Size.X, rng:NextNumber(-0.5, 0.5) * p.Size.Y,
						rng:NextNumber(-0.5, 0.5) * p.Size.Z)
					local smoke = rng:NextNumber() < 0.15
					local cube = part(Enum.PartType.Block, smoke and BLACK or FLAME[rng:NextInteger(1, 3)])
					local size, rise = rng:NextNumber(0.5, 1.1), rng:NextNumber(1.5, 3.5)
					local tumble = rng:NextUnitVector() * 5
					run(rng:NextNumber(0.35, 0.6) * (smoke and 1.5 or 1), { cube }, function(a)
						cube.Size = Vector3.one * (size * (1 - a) + 0.05)
						cube.CFrame = CFrame.new(base + UP * rise * out(a)) * CFrame.Angles(tumble.X * a, tumble.Y * a, tumble.Z * a)
						cube.Transparency = if smoke then 0.4 + 0.6 * a else a ^ 2
					end)
				end
				light.Brightness = rng:NextNumber(1.8, 3)
				task.wait(0.07)
			end
			light:Destroy()
			running = false
		end)
	end
	model:GetAttributeChangedSignal("Burning"):Connect(start)
	start()
end
task.spawn(function()
	local dummies = workspace:WaitForChild("Dummies")
	for _, m in dummies:GetChildren() do
		burnFx(m)
	end
	dummies.ChildAdded:Connect(burnFx)
end)

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

-- Injuries ----------------------------------------------------------------------
-- What the server's injury rules look like (server hit()): blood that sprays out of a wound, lands
-- and pools, wounds that keep dripping (the "Bleeder" tag), and the X-ray: the part that was hit
-- turns to glass for a moment and shows its bones, the broken ones in orange.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local BLOOD = Color3.fromRGB(178, 22, 32)
local BONE = Color3.fromRGB(245, 245, 235)
local BONE_BROKEN = Color3.fromRGB(255, 140, 40)
local GLASS = Color3.fromRGB(150, 200, 255)
local GRAVITY = 70
local MAX_PUDDLES = 140
local POOL_GROW = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- blood lands on the world, not on bodies, loose limbs or other effects
local bloodParams = RaycastParams.new()
bloodParams.FilterType = Enum.RaycastFilterType.Exclude
local function aimBlood()
	local skip = { folder }
	table.insert(skip, workspace:FindFirstChild("Dummies")) -- inserting nil adds nothing
	table.insert(skip, workspace:FindFirstChild("Gibs"))
	table.insert(skip, player.Character)
	bloodParams.FilterDescendantsInstances = skip
end

local puddles = {} -- oldest first
-- ponytail: a puddle stays where it fell when the floor under it is blown away; it is gone in
-- a minute anyway. Weld it to the hit part if floating puddles ever bother anyone.
-- `splat` makes it a splash rather than a neat disc: lobes round the rim and a few thin tongues
-- thrown out of it (a drop that hit the ground at speed); pools that drips fill stay round.
local function puddle(position: Vector3, normal: Vector3, radius: number, splat: boolean?): Part
	local p = part(Enum.PartType.Cylinder, BLOOD, Enum.Material.SmoothPlastic)
	local up = math.abs(normal.Y) > 0.9 and Vector3.xAxis or UP
	-- the cylinder's axis (X) along the normal; a hair of random lift so pools do not flicker in each other
	p.CFrame = CFrame.lookAt(position + normal * rng:NextNumber(0.02, 0.06), position + normal, up) * CFrame.Angles(0, math.pi / 2, 0)
	p.Size = Vector3.new(0.06, 0.3, 0.3)
	p.Reflectance = 0.12
	TweenService:Create(p, POOL_GROW, { Size = Vector3.new(0.06, radius * 2, radius * 2) }):Play()
	if splat then
		for _ = 1, rng:NextInteger(3, 5) do
			local angle = rng:NextNumber(0, math.pi * 2)
			local reach = radius * rng:NextNumber(0.7, 1.15)
			local r = radius * rng:NextNumber(0.25, 0.55)
			local lobe = part(Enum.PartType.Cylinder, BLOOD, Enum.Material.SmoothPlastic)
			lobe.Reflectance = 0.12
			lobe.CFrame = p.CFrame * CFrame.new(0, math.cos(angle) * reach, math.sin(angle) * reach)
			lobe.Parent = p -- goes when the puddle goes
			TweenService:Create(lobe, POOL_GROW, { Size = Vector3.new(0.06, r * 2, r * 2) }):Play()
		end
		for _ = 1, rng:NextInteger(2, 4) do
			local tongue = part(Enum.PartType.Block, BLOOD, Enum.Material.SmoothPlastic)
			local length = radius * rng:NextNumber(0.7, 1.4)
			tongue.CFrame = p.CFrame * CFrame.Angles(rng:NextNumber(0, math.pi * 2), 0, 0) * CFrame.new(0, radius * 0.8 + length / 2, 0)
			tongue.Parent = p
			TweenService:Create(tongue, POOL_GROW, { Size = Vector3.new(0.05, length, radius * rng:NextNumber(0.1, 0.2)) }):Play()
		end
	end
	table.insert(puddles, p)
	if #puddles > MAX_PUDDLES then
		table.remove(puddles, 1):Destroy()
	end
	Debris:AddItem(p, 60)
	return p
end

-- The haze a drop leaves where it bursts.
local function mist(at: Vector3)
	local m = part(Enum.PartType.Ball, BLOOD, Enum.Material.SmoothPlastic)
	local size = rng:NextNumber(0.5, 1.1)
	run(0.7, { m }, function(a)
		m.Size = Vector3.one * size * (0.4 + a)
		m.Position = at + UP * (0.15 + a * 0.5)
		m.Transparency = 0.55 + 0.45 * a
	end)
end

-- One drop on a ballistic arc, stretched into a tear along its flight; `onLand(position, normal)`
-- runs where and when it meets the ground.
local function droplet(from: Vector3, velocity: Vector3, size: number, onLand: ((Vector3, Vector3) -> ())?)
	local function fall(groundY: number): number
		local height = math.max(from.Y - groundY, 0)
		return (velocity.Y + math.sqrt(velocity.Y ^ 2 + 2 * GRAVITY * height)) / GRAVITY
	end
	local under = workspace:Raycast(from, -UP * 60, bloodParams)
	local t = fall(under and under.Position.Y or from.Y - 6)
	local over = from + velocity * t
	local top = math.max(from.Y, from.Y + velocity.Y ^ 2 / (2 * GRAVITY)) + 1
	local ground = workspace:Raycast(Vector3.new(over.X, top, over.Z), -UP * (top - from.Y + 60), bloodParams)
	if ground then
		t = fall(ground.Position.Y)
	end
	t = math.clamp(t, 0.1, 2.5)
	local p = part(Enum.PartType.Block, BLOOD, Enum.Material.SmoothPlastic)
	local round = Instance.new("SpecialMesh") -- an ellipsoid the size of the part
	round.MeshType = Enum.MeshType.Sphere
	round.Parent = p
	run(t, { p }, function(a)
		local s = a * t
		local flight = velocity - UP * (GRAVITY * s)
		local position = from + velocity * s - UP * (0.5 * GRAVITY * s * s)
		local width = size * (1 - a * 0.3)
		p.Size = Vector3.new(width, width, width * (1 + math.min(flight.Magnitude * 0.07, 2.2)))
		p.CFrame = CFrame.lookAt(position, position + flight)
	end)
	if ground then
		task.delay(t, onLand or mist, ground.Position, ground.Normal)
	end
end

-- A wound opening: `amount` 1 = a small hit, 2 = a heavy bullet, 3+ = a limb coming off. `kind`
-- shapes the spray: a bullet drives most of it out the far side in a cone and splashes a little
-- back, a blast throws it every way, anything else wells up and out.
function Fx.blood(position: Vector3, dir: Vector3, amount: number, kind: string?)
	aimBlood()
	for _ = 1, math.ceil(amount) do
		mist(position)
	end
	for i = 1, math.floor(6 + amount * 9) do
		local any = rng:NextUnitVector()
		local spray
		if kind == "bullet" then
			spray = i % 3 == 0 and (-dir + any * 0.7).Unit * rng:NextNumber(3, 8) or (dir + any * 0.45).Unit * rng:NextNumber(8, 18 + amount * 4) + UP * rng:NextNumber(0, 4)
		elseif kind == "blast" then
			spray = any * rng:NextNumber(8, 22) + UP * 4
		else
			spray = Vector3.new(any.X, math.abs(any.Y) * 1.3, any.Z) * rng:NextNumber(4, 10 + amount * 5) + dir * rng:NextNumber(0, 5)
		end
		local pool = i % 3 == 0 and rng:NextNumber(0.35, 0.9) * (amount >= 3 and 1.5 or 1) or nil
		droplet(position, spray, rng:NextNumber(0.18, 0.3 + amount * 0.1), pool and function(at, normal)
			puddle(at, normal, pool, true)
		end)
	end
end

-- Open wounds drip, and the drips under a body that lies still run together into one pool. A
-- stump does more than drip: it throws a jet out along the cut with every beat.
local pools = setmetatable({}, { __mode = "k" }) -- [bleeding part] = { part = Part, at = Vector3, radius = number }
task.spawn(function()
	while true do
		task.wait(0.35)
		aimBlood()
		for _, source in CollectionService:GetTagged("Bleeder") do
			if not source:IsDescendantOf(workspace) or (source.Position - camera.CFrame.Position).Magnitude > 160 then
				continue
			end
			local function land(at: Vector3, normal: Vector3)
				local pool = pools[source]
				if pool and pool.part.Parent and (pool.at - at).Magnitude < 1.3 then
					pool.radius = math.min(pool.radius + 0.06, 2.2)
					TweenService:Create(pool.part, POOL_GROW, { Size = Vector3.new(0.06, pool.radius * 2, pool.radius * 2) }):Play()
				else
					pools[source] = { part = puddle(at, normal, 0.4), at = at, radius = 0.4 }
				end
			end
			local carried = source.AssemblyLinearVelocity * 0.3
			if source.Name == "Stump" then
				local out = source.CFrame.XVector -- the cap faces along its X (server stump())
				for i = 1, 3 do
					droplet(source.Position, out * rng:NextNumber(4, 10) + UP * rng:NextNumber(1, 4) + rng:NextUnitVector() * 1.5 + carried, 0.26, i == 1 and land or nil)
				end
			else
				droplet(source.Position, rng:NextUnitVector() * 1.5 + carried, 0.22, land)
			end
		end
	end
end)

-- The bones inside one body part, in the part's own space: { shape, size, offset, hurt? }.
-- Boxy on purpose, like the bodies. `broken` snaps them: those pieces come back marked hurt.
local function bonesOf(name: string, size: Vector3, broken: boolean): { { any } }
	local list = {}
	local function add(shape: Enum.PartType, s: Vector3, cf: CFrame, hurt: boolean?)
		table.insert(list, { shape, s, cf, hurt })
	end
	local Block, Ball, Cylinder = Enum.PartType.Block, Enum.PartType.Ball, Enum.PartType.Cylinder
	local x, y, z = size.X, size.Y, size.Z
	if name == "UpperTorso" then
		local t = 0.09
		add(Block, Vector3.new(0.16, y * 0.95, 0.16), CFrame.new(0, 0, z * 0.3)) -- spine
		add(Block, Vector3.new(0.14, y * 0.55, 0.1), CFrame.new(0, y * 0.08, -z * 0.36)) -- sternum
		for i = 0, 3 do
			local h = y * 0.36 - i * y * 0.2
			local w = x * (0.4 - i * 0.02) -- half the rib cage's width at this rib
			for side = -1, 1, 2 do
				local snapped = broken and side == 1 and i >= 1 and i <= 2
				local sag = snapped and CFrame.new(0, -0.07, 0) * CFrame.Angles(0, 0, side * 0.3) or CFrame.identity
				add(Block, Vector3.new(w, t, t), CFrame.new(side * w / 2, h, z * 0.3)) -- back
				add(Block, Vector3.new(t, t, z * 0.66), CFrame.new(side * w, h - 0.03, 0) * sag, snapped) -- side
				add(Block, Vector3.new(w - 0.07, t, t), CFrame.new(side * (w + 0.07) / 2, h - 0.06, -z * 0.36) * sag, snapped) -- front
			end
		end
	elseif name == "LowerTorso" then
		add(Block, Vector3.new(0.16, y, 0.16), CFrame.new(0, 0, z * 0.3)) -- spine
		add(Block, Vector3.new(x * 0.8, y * 0.4, z * 0.5), CFrame.new(0, -y * 0.15, 0), broken) -- pelvis
	elseif name == "Head" then
		local r = math.min(x, y, z) * 0.7
		add(Ball, Vector3.one * r, CFrame.new(0, y * 0.06, 0)) -- skull
		add(Block, Vector3.new(r * 0.6, r * 0.22, r * 0.5), CFrame.new(0, -y * 0.3, -z * 0.1)) -- jaw
		if broken then
			add(Block, Vector3.new(0.06, r * 0.6, r * 0.9), CFrame.new(r * 0.15, y * 0.15, 0) * CFrame.Angles(0, 0, 0.4), true) -- crack
		end
	elseif name:find("Hand") or name:find("Foot") then
		add(Block, Vector3.new(x * 0.5, y * 0.5, z * 0.6), CFrame.identity, broken)
	else -- arm or leg segment: one long bone with a knuckle at each end
		local w = math.min(x, z) * 0.22
		local along = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is X
		if broken then
			add(Cylinder, Vector3.new(y * 0.4, w, w), CFrame.new(0.06, y * 0.2, 0) * CFrame.Angles(0, 0, 0.3) * along)
			add(Cylinder, Vector3.new(y * 0.4, w, w), CFrame.new(-0.06, -y * 0.2, 0) * CFrame.Angles(0, 0, -0.35) * along, true)
		else
			add(Cylinder, Vector3.new(y * 0.8, w, w), along)
		end
		add(Ball, Vector3.one * w * 1.7, CFrame.new(0, y * 0.4, 0))
		add(Ball, Vector3.one * w * 1.7, CFrame.new(0, -y * 0.4, 0))
	end
	return list
end

-- Show `target`'s bones through it for `dur` seconds. Only this client sees its own X-rays.
local xrayed = setmetatable({}, { __mode = "k" }) -- [BasePart] = true while one is running
function Fx.xray(target: BasePart, dur: number, broken: boolean)
	if xrayed[target] then
		return
	end
	xrayed[target] = true
	local parts, offsets = {}, {}
	for _, bone in bonesOf(target.Name, target.Size, broken) do
		local p = part(bone[1], bone[4] and BONE_BROKEN or BONE, Enum.Material.SmoothPlastic) -- solid, not glowing
		p.Size = bone[2]
		offsets[p] = bone[3]
		table.insert(parts, p)
	end
	local skin = target.Color
	target.Color = GLASS
	target.LocalTransparencyModifier = 0.72
	run(dur, parts, function(a)
		local cf = target.CFrame
		local fade = math.max(0, (a - 0.75) / 0.25)
		for _, p in parts do
			p.CFrame = cf * offsets[p]
			p.Transparency = fade
		end
		if a >= 1 then
			xrayed[target] = nil
			target.LocalTransparencyModifier = 0
			target.Color = target:GetAttribute("Skin") or skin -- the server's bruise colour, if it has one
		end
	end)
end

-- The whole skeleton of a dummy at once (the Scan key).
function Fx.scan(model: Model, dur: number)
	local broken = {}
	for name, level in (model:GetAttribute("Body") or ""):gmatch("(%w+):(%d)") do
		broken[name] = level == "2"
	end
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			Fx.xray(child, dur, broken[child.Name] or false)
		end
	end
end

-- `kind`: "blunt", "bullet", "blade", "cut" (a limb coming off) or "blast".
function EVENTS.Wound(_, target: BasePart?, position: Vector3, dir: Vector3, blood: number, bone: string?, kind: string?)
	if blood > 0 then
		Fx.blood(position, dir, blood, kind)
	end
	if kind == "blunt" then
		-- a thud: a flash and a ring off the skin, and a little blood once something has broken
		Fx.glint(position, 2, WHITE, 0.12)
		Fx.burst(position, 0.4, bone == "broken" and 3.2 or 1.8, 0.22, WHITE, 0.7)
		if bone == "broken" then
			Fx.blood(position, dir, 0.4)
		end
	elseif kind == "cut" then
		Fx.shake(position, 0.4, 0.2)
	end
	if bone and target and target.Parent then
		Fx.xray(target, 1.1, bone == "broken")
		if bone == "broken" then
			Fx.text(position + UP * 1.2, "CRACK!", WHITE, 1.2)
			Fx.shake(position, 0.3, 0.15)
		end
	end
end

-- A held body raked through the ground (F, looking down, mouse held): one stretch of the furrow it
-- ploughs, from `from` to `to`. A dark trough with the earth heaped up along both sides; each stretch
-- overlaps the last, so the furrow reads as one unbroken track. Clods and dust fly off the front.
local EARTH = Color3.fromRGB(150, 105, 70)
local SOIL = Color3.fromRGB(78, 54, 36)
local FURROW_WIDTH = 1.8
local MAX_FURROW = 240 -- stretches kept (3 parts each); the oldest go first
local furrows = {}
function EVENTS.Furrow(_, from: Vector3, to: Vector3, normal: Vector3, speed: number?)
	local along = to - from
	if along.Magnitude < 0.05 then
		return
	end
	local length = along.Magnitude + FURROW_WIDTH * 0.5 -- overlapping the next stretch: no seams
	local mid = (from + to) / 2 + normal * 0.03
	local frame = CFrame.lookAt(mid, mid + along, normal)
	local trough = part(Enum.PartType.Block, SOIL, Enum.Material.Ground)
	trough.CFrame = frame
	trough.Size = Vector3.new(FURROW_WIDTH, 0.06, length)
	local parts = { trough }
	for _, side in { -1, 1 } do
		local heap = part(Enum.PartType.Block, EARTH, Enum.Material.Ground)
		heap.CFrame = frame * CFrame.new(side * (FURROW_WIDTH / 2 + 0.15), 0.1, 0) * CFrame.Angles(0, 0, side * math.rad(18))
		heap.Size = Vector3.new(0.45, 0.25, length)
		table.insert(parts, heap)
	end
	table.insert(furrows, parts)
	if #furrows > MAX_FURROW then
		for _, p in table.remove(furrows, 1) do
			p:Destroy()
		end
	end
	for _, p in parts do
		Debris:AddItem(p, 45)
	end
	-- thrown up off the front: clods on arcs out both sides and back, a spray of grit, a dust trail,
	-- the ground rumbling under you - all of it more the faster it is dragged
	local fury = math.clamp((speed or 10) / 20, 0.4, 1.6)
	for _ = 1, math.round(2 * fury) do
		local clod = part(Enum.PartType.Block, rng:NextNumber() < 0.5 and SOIL or EARTH, Enum.Material.Ground)
		clod.Size = Vector3.one * rng:NextNumber(0.25, 0.55)
		local side = along.Unit:Cross(normal) * rng:NextNumber(-1, 1)
		local v = (side * 7 - along.Unit * rng:NextNumber(2, 6) + normal * rng:NextNumber(8, 15)) * fury
		local spin = CFrame.Angles(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), 0)
		run(0.7, { clod }, function(a)
			local t = a * 0.7
			clod.CFrame = CFrame.new(to + v * t - Vector3.yAxis * (45 * t * t)) * CFrame.Angles(spin.X * t, spin.Y * t, 0)
		end)
	end
	Fx.sparks(to, math.round(6 * fury), 3 * fury, EARTH, normal + along.Unit * 0.6, 0.55)
	Fx.dust(to - along.Unit * 0.5, math.round(3 * fury), 1.8 * fury, 0.8)
	Fx.shake(to, 0.12 * fury, 0.12)
end

-- The punt's kick landing on the body: no comic burst, just the jolt and a puff of dust off it.
function EVENTS.Punt(_, position: Vector3, dir: Vector3)
	Fx.dust(position, 4, 1.5, 0.7)
	Fx.shake(position, 0.6, 0.2)
end

-- A body dragged along the ground (F): a low puff of dust kicked up behind where it rubs.
function EVENTS.Scrape(_, position: Vector3, dir: Vector3)
	Fx.dust(position - dir * 0.8, 3, 1.6, 0.5)
end

-- A tomato bursting: red pulp sprayed back off what it hit, a "SPLAT!", and a stain stuck to the
-- surface (it rides along on a moving body) that fades out after a while.
local TOMATO = Color3.fromRGB(215, 30, 25)
local PULP = Color3.fromRGB(240, 90, 60)
local SEED = Color3.fromRGB(250, 220, 120)
local splatParams = RaycastParams.new()
splatParams.FilterType = Enum.RaycastFilterType.Exclude
function EVENTS.Splat(_, position: Vector3, dir: Vector3, other: BasePart?)
	Fx.sparks(position, 16, 3.5, TOMATO, -dir, 0.45)
	Fx.sparks(position, 6, 2.5, SEED, -dir, 0.35)
	Fx.burst(position, 0.3, 2.2, 0.18, PULP, 0.3)
	Fx.text(position + UP * 1.5, "SPLAT!", TOMATO, 1.6)
	-- find the surface: straight along the flight, else straight down
	splatParams.FilterDescendantsInstances = { folder, camera }
	local result = workspace:Raycast(position - dir * 1.5, dir * 4, splatParams) or workspace:Raycast(position + UP, -UP * 4, splatParams)
	local surface = result and result.Instance :: BasePart?
	if not result or not surface then
		return
	end
	local at = CFrame.lookAt(result.Position + result.Normal * 0.03, result.Position + result.Normal * 2)
	local offset = surface.CFrame:ToObjectSpace(at)
	local blobs = {}
	for i = 0, 5 do
		local blob = part(Enum.PartType.Cylinder, i == 0 and TOMATO or PULP, Enum.Material.SmoothPlastic)
		local size = i == 0 and rng:NextNumber(1.6, 2.1) or rng:NextNumber(0.35, 0.8)
		blob.Size = Vector3.new(0.05, size, size)
		local spread = i == 0 and Vector2.zero or Vector2.new(rng:NextNumber(-1.4, 1.4), rng:NextNumber(-1.4, 1.4))
		-- the cylinder's axis is X: turn it to lie flat on the surface (axis along the normal)
		table.insert(blobs, { part = blob, local_ = CFrame.new(spread.X, spread.Y, -0.01 * i) * CFrame.Angles(0, math.pi / 2, 0) })
	end
	local parts = {}
	for _, b in blobs do
		table.insert(parts, b.part)
	end
	run(9, parts, function(a)
		if not surface.Parent then
			for _, b in blobs do
				b.part.Transparency = 1
			end
			return
		end
		local base = surface.CFrame * offset
		local fade = a > 0.75 and (a - 0.75) / 0.25 or 0
		for i, b in blobs do
			local grow = math.min(a * 40, 1) -- slaps on in the first fraction of a second
			b.part.CFrame = base * b.local_ * CFrame.new(0, -a * 0.6 * (i % 3), 0) -- drips a little
			b.part.Transparency = 1 - grow + fade
		end
	end)
end

-- A tomato to your own face: red pulp all over the screen, sliding down and fading.
function EVENTS.Splatted()
	local screen = Instance.new("ScreenGui")
	screen.Name = "Splatted"
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 50
	screen.Parent = player:WaitForChild("PlayerGui")
	local blobs = {}
	for i = 1, 9 do
		local f = Instance.new("Frame")
		local size = i == 1 and rng:NextNumber(0.45, 0.6) or rng:NextNumber(0.08, 0.22)
		f.Size = UDim2.fromScale(size, size)
		f.SizeConstraint = Enum.SizeConstraint.RelativeYY
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		local x, y = i == 1 and 0.5 or rng:NextNumber(0.15, 0.85), i == 1 and 0.45 or rng:NextNumber(0.15, 0.8)
		f.Position = UDim2.fromScale(x, y)
		f.BackgroundColor3 = i % 3 == 0 and PULP or TOMATO
		f.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		f.Parent = screen
		table.insert(blobs, { frame = f, x = x, y = y, speed = rng:NextNumber(0.02, 0.08) })
	end
	Fx.shake(camera.CFrame.Position, 0.15, 0.15)
	run(3, { screen }, function(a)
		for _, b in blobs do
			b.frame.Position = UDim2.fromScale(b.x, b.y + b.speed * a * a * 3)
			b.frame.BackgroundTransparency = 0.05 + 0.95 * math.max(0, (a - 0.35) / 0.65)
		end
	end)
end

function EVENTS.Burst(_, position: Vector3, dir: Vector3)
	Fx.blood(position, dir, 4)
	Fx.glint(position, 4, WHITE, 0.15)
	Fx.sparks(position, 10, 5, BONE, nil, 0.35)
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
