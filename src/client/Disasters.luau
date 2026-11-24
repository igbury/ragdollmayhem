-- What a natural disaster looks like (server/Disasters does the harm, shared/Disasters has the
-- numbers). The server sends each one once ("start", kind, t0, data) to the players in that map; this
-- builds it from local parts and the comic models in client/DisasterMeshes (made in Blender by
-- assets/disasters/disasters.py, built here with EditableMesh like the weapons) and moves it by the
-- server clock, so it is where the server says it is. Around it: the banner with a countdown and a
-- siren ("banner"), the sky's mood and its rain / snow / ash while it lasts, comic sound words
-- (Fx.text), and the damage report at the end ("summary"). It also says why a SANDBOX + call was refused.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")

local Shared = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Disasters"))
local Sfx = require(ReplicatedStorage.Shared:WaitForChild("Sfx"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local WeaponMeshes = require(script.Parent:WaitForChild("WeaponMeshes"))
local Meshes = script.Parent:WaitForChild("DisasterMeshes")

local Disasters = {}

local UP = Vector3.yAxis
local FONT = Enum.Font.LuckiestGuy
local INK = Color3.fromRGB(20, 20, 24)
local YELLOW = Color3.fromRGB(252, 200, 50)
local WHITE = Color3.new(1, 1, 1)
local WATER = Color3.fromRGB(40, 120, 220)
local SMOKE = Color3.fromRGB(110, 104, 100)
local FIRE = Color3.fromRGB(255, 140, 40)
local ROCK_DUST = Color3.fromRGB(190, 160, 120)
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local folder: Folder
local gui: ScreenGui
local onDawn: (() -> ())? = nil -- zombie night's, for the server's "dawn"
local strikeAt: ((Vector3) -> ())? = nil -- the storm's, for the server's "strike"

local function now(): number
	return workspace:GetServerTimeNow()
end

local function camPos(): Vector3
	return workspace.CurrentCamera.CFrame.Position
end

local function part(shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Shape, p.Size, p.Color = shape, size, color
	p.Material, p.Transparency = material or Enum.Material.SmoothPlastic, transparency or 0
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Parent = folder
	return p
end

local function fadeOut(parts: { Instance }, seconds: number)
	for _, p in parts do
		if p:IsA("BasePart") then
			TweenService:Create(p, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		end
		for _, effect in p:GetChildren() do
			if effect:IsA("Smoke") or effect:IsA("Fire") or effect:IsA("ParticleEmitter") or effect:IsA("Trail") then
				effect.Enabled = false
			elseif effect:IsA("Sound") then
				TweenService:Create(effect, TweenInfo.new(seconds), { Volume = 0 }):Play()
			end
		end
	end
	task.delay(seconds + 0.1, function()
		for _, p in parts do
			p:Destroy()
		end
	end)
end

-- Runs step(t) every frame from t0 (server time) until `duration`, then fades `parts` out over `fade`.
local function drive(t0: number, duration: number, parts: { Instance }, step: (number) -> (), fade: number?)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = now() - t0
		if t > duration then
			conn:Disconnect()
			fadeOut(parts, fade or 1.5)
			return
		end
		step(math.max(t, 0))
	end)
end

-- A comic sound word in a burst (Fx.text), only where someone can see it.
local function word(position: Vector3, text: string, scale: number?)
	if (camPos() - position).Magnitude < 260 then
		Fx.text(position, text, YELLOW, scale or 3)
	end
end

-- A particle layer: smoke_main puffs (Roblox's own texture, no upload) off `shape` on an invisible
-- part, in a grey `color`, `size` studs, fading out. LockedToPart: they turn with the part (the spin).
local function puffs(host: BasePart, shape: Enum.ParticleEmitterShape, color: Color3, size: number, rate: number, life: number, speed: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture, e.Shape, e.ShapeStyle = SMOKE_TEXTURE, shape, Enum.ParticleEmitterShapeStyle.Surface
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Color = ColorSequence.new(color:Lerp(WHITE, 0.15), color:Lerp(INK, 0.2))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size * 1.3) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime, e.Rate, e.Speed = NumberRange.new(life * 0.7, life * 1.2), rate, NumberRange.new(speed * 0.5, speed)
	e.Rotation, e.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-80, 80)
	e.LockedToPart, e.LightInfluence, e.Drag = true, 0.6, 1
	e.Parent = host
	return e
end

-- A comic model (client/DisasterMeshes), `scale` times its modelled size, its pivot at the modelled
-- origin. If this client cannot build one more EditableMesh (8 at most), a plain block of `fallback`
-- studs in `color` stands in.
local function model(id: string, scale: number, fallback: Vector3, color: Color3): BasePart
	local mesh = WeaponMeshes.create(id, Meshes:FindFirstChild(id) :: ModuleScript?)
	if not mesh then
		return part(Enum.PartType.Block, fallback, color)
	end
	mesh.Size *= scale
	mesh.Parent = folder
	return mesh
end

-- A comic cloud (the CloudPuff model, ~3 across) `size` studs across, tinted `color` (the part's
-- colour multiplies the model's near-white).
local function cloud(color: Color3, size: number): BasePart
	local p = model("CloudPuff", size / 3, Vector3.one * size, color)
	p.Color = color
	return p
end

-- One puff that pops up at `at`, swells from `size` to twice that while rising `rise` studs, and fades
-- over `life` s (dust, steam, smoke).
local function puff(at: Vector3, color: Color3, size: number, life: number, rise: number)
	local p = cloud(color, size)
	local base = p.Size
	local spin = math.random() * 6
	local t0 = now()
	drive(t0, life, { p }, function(t)
		local a = t / life
		p.Size = base * (0.4 + 1.6 * (1 - (1 - a) ^ 3))
		p.CFrame = CFrame.new(at + UP * rise * a) * CFrame.Angles(0, spin + a, 0)
		p.Transparency = math.max(0, (a - 0.6) / 0.4)
	end, 0.1)
end

-- The sky ---------------------------------------------------------------------------------------
-- Each kind's mood while it lasts: a colour grade, night for the zombies, and its weather round the
-- camera (rain streaks, snow blown along `wind`, falling ash). The newest mood wins; when the last one
-- ends the sky goes back as it was.
local MOODS = {
	Tornado = { tint = Color3.fromRGB(195, 200, 212), bright = -0.08, sat = -0.3, weather = "rain" },
	Tsunami = { tint = Color3.fromRGB(190, 215, 240), bright = -0.05, sat = -0.15, weather = "rain" },
	Meteors = { tint = Color3.fromRGB(255, 205, 175), bright = -0.05, sat = 0.1 },
	Nuke = { tint = Color3.fromRGB(255, 232, 205), bright = 0, sat = -0.1 },
	Earthquake = { tint = Color3.fromRGB(232, 208, 175), bright = -0.05, sat = -0.2 },
	Volcano = { tint = Color3.fromRGB(255, 175, 145), bright = -0.08, sat = 0.1, weather = "ash" },
	Lightning = { tint = Color3.fromRGB(150, 160, 205), bright = -0.18, sat = -0.35, weather = "rain" },
	Blizzard = { tint = Color3.fromRGB(205, 232, 255), bright = 0.05, sat = -0.4, weather = "snow" },
	Ufo = { tint = Color3.fromRGB(195, 255, 205), bright = -0.05, sat = 0 },
	Zombies = { tint = Color3.fromRGB(165, 210, 160), bright = -0.06, sat = -0.25, night = true },
}
local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "DisasterMood"
local flashCC = Instance.new("ColorCorrectionEffect") -- the lightning's flash
flashCC.Name = "DisasterFlash"
local moods = {} -- { { mood, ends, wind } }, newest last
local weather: Part? = nil
local emitters: { [string]: ParticleEmitter } = {}
local dayTime: number? = nil -- the ClockTime the night replaced

local function makeWeather()
	weather = Instance.new("Part")
	weather.Name = "Weather"
	weather.Anchored, weather.CanCollide, weather.CanQuery, weather.CanTouch = true, false, false, false
	weather.Transparency, weather.Size = 1, Vector3.new(140, 1, 140)
	weather.Parent = folder
	local function emitter(name: string, color: Color3, size: number, squash: number, speed: number, life: number, rate: number)
		local e = Instance.new("ParticleEmitter")
		e.Name, e.Texture, e.Color = name, SMOKE_TEXTURE, ColorSequence.new(color)
		e.Size, e.Squash = NumberSequence.new(size), NumberSequence.new(squash)
		e.Transparency = NumberSequence.new(0.25)
		e.Speed, e.Lifetime, e.Rate = NumberRange.new(speed, speed * 1.2), NumberRange.new(life), rate
		e.EmissionDirection, e.LightInfluence, e.Enabled = Enum.NormalId.Bottom, 0.5, false
		e.Parent = weather
		emitters[name] = e
	end
	emitter("rain", Color3.fromRGB(200, 220, 255), 0.35, 3, 110, 0.75, 500)
	emitter("snow", WHITE, 0.7, 0, 14, 4, 320)
	emitter("ash", Color3.fromRGB(90, 84, 80), 0.6, 0, 9, 5, 140)
end

local function applyMood()
	local top = moods[#moods]
	if not top then
		TweenService:Create(grade, TweenInfo.new(2), { TintColor = WHITE, Brightness = 0, Saturation = 0 }):Play()
		if dayTime then
			TweenService:Create(Lighting, TweenInfo.new(3), { ClockTime = dayTime }):Play()
			dayTime = nil
		end
		for _, e in emitters do
			e.Enabled = false
		end
		return
	end
	local m = top.mood
	TweenService:Create(grade, TweenInfo.new(2), { TintColor = m.tint, Brightness = m.bright, Saturation = m.sat }):Play()
	if m.night and not dayTime then
		dayTime = Lighting.ClockTime
		TweenService:Create(Lighting, TweenInfo.new(3), { ClockTime = 19.6 }):Play() -- dusk: dark, but you still see them coming
	elseif not m.night and dayTime then
		TweenService:Create(Lighting, TweenInfo.new(3), { ClockTime = dayTime }):Play()
		dayTime = nil
	end
	if not weather then
		makeWeather()
	end
	for name, e in emitters do
		e.Enabled = name == m.weather
		e.Acceleration = if top.wind then top.wind * 25 else Vector3.zero
	end
end

-- `kind`'s mood from now until server time `ends`.
local function mood(kind: string, ends: number, wind: Vector3?)
	local entry = { mood = MOODS[kind], ends = ends, wind = wind }
	table.insert(moods, entry)
	applyMood()
	task.delay(math.max(ends - now(), 0), function()
		table.remove(moods, table.find(moods, entry))
		applyMood()
	end)
end

-- the zombies' night ends early, at dawn
local function endNight()
	for i = #moods, 1, -1 do
		if moods[i].mood.night then
			table.remove(moods, i)
		end
	end
	applyMood()
end

-- The banner: the name on a tilted comic panel at the top, a line under it -------------------------
local function banner(title: string, line: string, color: Color3, seconds: number?): TextLabel
	local plate = Instance.new("TextLabel")
	plate.AnchorPoint, plate.Position, plate.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 110), UDim2.fromOffset(460, 70)
	plate.BackgroundColor3, plate.BorderSizePixel, plate.Rotation = color, 0, -2
	plate.Font, plate.Text, plate.TextSize, plate.TextColor3 = FONT, title, 48, YELLOW
	plate.TextStrokeColor3, plate.TextStrokeTransparency, plate.Parent = INK, 0, gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness, stroke.Color, stroke.ApplyStrokeMode, stroke.Parent = 4, INK, Enum.ApplyStrokeMode.Border, plate
	local sub = Instance.new("TextLabel")
	sub.AnchorPoint, sub.Position, sub.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 1, 6), UDim2.fromOffset(380, 30)
	sub.BackgroundColor3, sub.BorderSizePixel, sub.Rotation = WHITE, 0, 3
	sub.Font, sub.Text, sub.TextSize, sub.TextColor3, sub.Parent = FONT, line, 20, INK, plate
	stroke:Clone().Parent = sub
	local scale = Instance.new("UIScale")
	scale.Scale, scale.Parent = 0.2, plate
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(seconds or 4, function()
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.3)
		plate:Destroy()
	end)
	return sub
end

local LINES = {
	Tornado = "GET AWAY FROM THE FUNNEL!",
	Tsunami = "HEAD FOR HIGH GROUND!",
	Meteors = "WATCH THE RED CIRCLES!",
	Nuke = "RUN FROM THE RED ZONE!",
	Earthquake = "HOLD ON TO SOMETHING!",
	Volcano = "MIND THE LAVA BOMBS!",
	Lightning = "DON'T STAND TALL!",
	Blizzard = "KEEP MOVING OR FREEZE!",
	Ufo = "STAY OUT OF THE BEAM!",
	Zombies = "SURVIVE TILL DAWN!",
}

local function entryOf(id: string)
	return Shared.BY_ID[id] or Shared.COMBO[id]
end

-- The countdown under the banner and the siren, until `t0`.
local function countdown(id: string, by: string?, t0: number)
	local entry = entryOf(id)
	local lead = math.max(t0 - now(), 0)
	local sub = banner(entry.name .. "!", if by then `CALLED BY {string.upper(by)}` else LINES[id] or "IT'S A COMBO!", entry.color, lead + 1.5)
	local siren = Sfx.loop(SoundService, Sfx.POLICE_SIREN_LOOP, 0.45, 10000)
	siren.PlaybackSpeed = 0.7
	Sfx.ui(Sfx.WANTED_ALARM, 0.6)
	task.spawn(function()
		task.wait(1.2) -- the line first, then the count
		while now() < t0 do
			sub.Text = `IN {math.ceil(t0 - now())}...`
			task.wait(0.1)
		end
		sub.Text = "HERE IT COMES!"
		TweenService:Create(siren, TweenInfo.new(0.8), { Volume = 0 }):Play()
		task.delay(0.9, siren.Destroy, siren)
	end)
end

-- The damage report: a comic panel counting up what it did --------------------------------------
local function summary(id: string, stats)
	local entry = entryOf(id)
	local panel = Instance.new("Frame")
	panel.AnchorPoint, panel.Position, panel.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -150), UDim2.fromOffset(420, 196)
	panel.BackgroundColor3, panel.BorderSizePixel, panel.Rotation, panel.Parent = WHITE, 0, 1.5, gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness, stroke.Color, stroke.ApplyStrokeMode, stroke.Parent = 4, INK, Enum.ApplyStrokeMode.Border, panel
	local title = Instance.new("TextLabel")
	title.Size, title.BackgroundColor3, title.BorderSizePixel = UDim2.new(1, 0, 0, 46), entry.color, 0
	title.Font, title.Text, title.TextSize, title.TextColor3 = FONT, entry.name .. " REPORT", 32, YELLOW
	title.TextStrokeColor3, title.TextStrokeTransparency, title.Parent = INK, 0, panel
	stroke:Clone().Parent = title
	local rows = {
		{ "BRICKS SMASHED", stats.bricks },
		{ "DUMMIES FLUNG", stats.flung },
		{ "DUMMIES KO'D", stats.killed },
		{ "HIGHEST FLIGHT", stats.height, " STUDS" },
	}
	local labels = {}
	for i, row in rows do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency, l.Position, l.Size = 1, UDim2.fromOffset(18, 50 + (i - 1) * 34), UDim2.new(1, -36, 0, 32)
		l.Font, l.TextSize, l.TextColor3, l.TextXAlignment, l.Parent = FONT, 24, INK, Enum.TextXAlignment.Left, panel
		labels[i] = l
	end
	local scale = Instance.new("UIScale")
	scale.Scale, scale.Parent = 0.2, panel
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Sfx.ui(Sfx.UI_NOTIFICATION, 0.6)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.min((os.clock() - t0) / 1.5, 1) -- the numbers count up
		for i, row in rows do
			labels[i].Text = `{row[1]}: {math.floor((row[2] or 0) * a)}{row[3] or ""}`
		end
		if a >= 1 then
			conn:Disconnect()
		end
	end)
	task.delay(7, function()
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.3)
		panel:Destroy()
	end)
end

-- Each look: build(t0, data) ---------------------------------------------------------------------
local BUILD = {}

-- One funnel (BUILD.Tornado makes TORNADOES of them): rings of smoke, narrow at the foot and wide up
-- top, each turning (LockedToPart), the low ones faster, so the whole column twists; inked comic storm
-- clouds over it, dust thrown out round the foot, debris whirling round it (half of it unseen, drawing
-- white wind streaks: comic speed lines). `fire`: FIRE TORNADO, it burns as it spins. Returns its parts
-- and place(foot, t, grow).
local function funnel(fire: boolean?, spinWay: number): ({ Instance }, (Vector3, number, number) -> ())
	local height = Shared.TORNADO_HEIGHT
	local parts = {}
	local function host(): Part -- an invisible part the particles come off
		local p = part(Enum.PartType.Block, Vector3.one, WHITE, nil, 1)
		table.insert(parts, p)
		return p
	end
	local RINGS = 8
	local rings = {}
	for i = 1, RINGS do
		local f = (i - 1) / (RINGS - 1)
		local p = host()
		local width = 7 + f ^ 1.5 * 44
		p.Size = Vector3.new(width, height / RINGS, width)
		local color = if fire then FIRE:Lerp(Color3.fromRGB(90, 40, 30), f) else SMOKE:Lerp(Color3.fromRGB(64, 64, 72), f)
		local e = puffs(p, Enum.ParticleEmitterShape.Cylinder, color, 7 + 12 * f, 10 + 7 * f, 1.4, 3) -- ~0.7 of one alone: there are several
		e.LightEmission = if fire then 0.6 else 0
		rings[i] = { p = p, f = f, spin = (4.5 - 2.5 * f) * spinWay }
	end
	local clouds = {}
	for i = 1, 5 do
		local c = cloud(if fire then Color3.fromRGB(120, 72, 56) else Color3.fromRGB(104, 108, 124), 30 + (i % 3) * 8)
		clouds[i] = { p = c, a = i / 5 * math.pi * 2, r = 16 + (i % 2) * 14 }
		table.insert(parts, c)
	end
	local dust = host()
	dust.Size = Vector3.new(30, 1, 30)
	local kick = puffs(dust, Enum.ParticleEmitterShape.Disc, Color3.fromRGB(150, 125, 95), 9, 30, 1.3, 22)
	kick.EmissionDirection, kick.LockedToPart = Enum.NormalId.Top, false
	kick.Acceleration = Vector3.new(0, 6, 0)
	local rng = Random.new()
	local debris = {}
	for i = 1, 12 do
		local size = rng:NextNumber(0.8, 2.6)
		local p = part(Enum.PartType.Block, Vector3.one * size, if i % 3 == 0 then Color3.fromRGB(120, 85, 60) else Color3.fromRGB(90, 92, 98))
		if i % 2 == 0 then
			p.Transparency = 1
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Position, a1.Position = Vector3.new(0, 0.8, 0), Vector3.new(0, -0.8, 0)
			a0.Parent, a1.Parent = p, p
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1, trail.Lifetime = a0, a1, 0.35
			trail.Color, trail.LightEmission, trail.FaceCamera = ColorSequence.new(if fire then FIRE else WHITE), 0.4, true
			trail.Transparency = NumberSequence.new(0.35, 1)
			trail.Parent = p
		elseif fire then
			local flame = Instance.new("Fire")
			flame.Size, flame.Heat, flame.Parent = 4, 6, p
		end
		debris[i] = { p = p, h = rng:NextNumber(0, height * 0.9), a = rng:NextNumber(0, math.pi * 2), speed = rng:NextNumber(2.5, 4.5) * spinWay }
		table.insert(parts, p)
	end
	if fire then
		local glow = Instance.new("PointLight")
		glow.Color, glow.Range, glow.Brightness, glow.Parent = FIRE, 40, 3, dust
	end
	Sfx.loop(dust, Sfx.WIND_LOOP, 1.4, 220).PlaybackSpeed = 0.6 + 0.1 * spinWay
	return parts, function(base: Vector3, t: number, grow: number)
		dust.CFrame = CFrame.new(base + UP)
		for _, c in clouds do
			local a = c.a + t * 0.25 * spinWay
			c.p.CFrame = CFrame.new(base + UP * (height + 6) + Vector3.new(math.cos(a), 0, math.sin(a)) * c.r) * CFrame.Angles(0, a, 0)
		end
		for i, ring in rings do
			local wob = Vector3.new(math.sin(t * 1.7 + i * 0.6), 0, math.cos(t * 1.3 + i * 0.7)) * ring.f * 10
			local y = (i - 0.5) / RINGS * height * grow
			ring.p.CFrame = CFrame.new(base + wob + UP * y) * CFrame.Angles(0, t * ring.spin, 0)
		end
		for _, d in debris do
			local f = d.h / height
			local r = (6 + f ^ 1.5 * 22) * grow
			local a = d.a + t * d.speed
			d.p.CFrame = CFrame.new(base + Vector3.new(math.cos(a) * r, d.h * grow, math.sin(a) * r)) * CFrame.Angles(a, a * 1.3, 0)
		end
	end
end

-- TORNADOES funnels touch down round the player they came for and circle them, following them
-- wherever they run (shared tornadoOrbits / tornadoCentre: the same places as the server's).
function BUILD.Tornado(t0: number, data)
	local duration = Shared.BY_ID.Tornado.duration
	local orbits = Shared.tornadoOrbits(data.seed)
	local all, places = {}, {}
	for i in orbits do
		local parts, place = funnel(data.fire, if orbits[i].w > 0 then 1 else -1)
		for _, p in parts do
			table.insert(all, p)
		end
		places[i] = place
	end
	local middle = data.centre
	local nextWord = 2
	drive(t0, duration, all, function(t)
		middle = Shared.tornadoCentre(data.around, middle)
		local grow = math.clamp(t / 2, 0, 1) -- they touch down, then grow to full
		for i, orbit in orbits do
			places[i](middle + Shared.orbitAt(orbit, t), t, grow)
		end
		if t > nextWord then
			nextWord = t + 4
			local orbit = orbits[math.random(#orbits)]
			word(middle + Shared.orbitAt(orbit, t) + UP * Shared.TORNADO_HEIGHT * 0.4, if data.fire then "FWOOOSH!" else "WHOOOSH!", 3.5)
		end
	end)
end

-- The wave mesh (DisasterMeshes.TsunamiWave) at 10x: 280 wide, ~43 high; its face's foot is WAVE_FOOT
-- studs ahead of its origin and its lip WAVE_LIP, the body runs 75 back. The foot rides the server's front.
local WAVE_SCALE, WAVE_FOOT, WAVE_LIP = 10, 13, 27
function BUILD.Tsunami(t0: number, data)
	local origin, dir = data.origin, data.dir
	local look = CFrame.lookAlong(origin, dir) -- -Z: the way it rolls
	local width = Shared.WAVE_WIDTH
	local wave = model("TsunamiWave", WAVE_SCALE, Vector3.new(width, Shared.WAVE_HEIGHT, 40), WATER)
	local full = wave.Size
	-- what it leaves: a shallow sheet of water over all the ground it flattened, still there for
	-- PUDDLE_LIFE s after the wave is gone, then it drains away
	local PUDDLE_LIFE, DEPTH = 14, 1.4
	local flood = part(Enum.PartType.Block, Vector3.new(width * 0.9, DEPTH, 1), WATER:Lerp(WHITE, 0.15), nil, 0.35)
	flood.Reflectance = 0.15
	local lip = part(Enum.PartType.Block, Vector3.new(width * 0.8, 2, 8), WHITE, nil, 1) -- the spray comes off the lip
	local spray = Instance.new("ParticleEmitter")
	spray.Texture, spray.Color, spray.LightEmission = SMOKE_TEXTURE, ColorSequence.new(WHITE), 0.3
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime, spray.Rate, spray.Speed = NumberRange.new(0.8, 1.4), 90, NumberRange.new(10, 22)
	spray.EmissionDirection, spray.SpreadAngle, spray.Acceleration = Enum.NormalId.Front, Vector2.new(35, 35), Vector3.new(0, -25, 0)
	spray.Parent = lip
	-- inked foam clouds tumbling along the crest
	local foam = {}
	for i = 1, 7 do
		local c = cloud(WHITE, 14 + (i % 3) * 4)
		foam[i] = { p = c, x = (i - 4) * width / 8.5, spin = i }
	end
	Sfx.loop(wave, Sfx.WIND_LOOP, 3, 400).PlaybackSpeed = 0.45
	local duration = Shared.BY_ID.Tsunami.duration
	local said = false
	local waveParts = { wave, lip }
	for _, f in foam do
		table.insert(waveParts, f.p)
	end
	drive(t0, duration, waveParts, function(t)
		local front = Shared.waveFront(t)
		local rise = math.clamp(t / 1.5, 0.05, 1) -- swells up out of the ground at the start line
		local at = look * CFrame.new(0, 0, -front)
		wave.Size = Vector3.new(full.X, full.Y * rise, full.Z)
		wave.CFrame = at * CFrame.new(0, 0, WAVE_FOOT)
		lip.CFrame = at * CFrame.new(0, full.Y * rise * 0.85, WAVE_FOOT - WAVE_LIP)
		for _, f in foam do
			f.p.CFrame = at * CFrame.new(f.x, full.Y * rise * 0.92, WAVE_FOOT - WAVE_LIP + 4) * CFrame.Angles(t * 2 + f.spin, 0, 0)
		end
		local toCam = (camPos() - at.Position):Dot(dir)
		if not said and toCam > 0 and toCam < 60 then -- about to hit the one watching
			said = true
			word(at.Position + UP * 30 + (camPos() - at.Position) * Vector3.new(1, 0, 1) * 0.3, "SPLOOOSH!", 4.5)
		end
	end)
	drive(t0, duration + PUDDLE_LIFE, { flood }, function(t)
		local behind = math.max(Shared.waveFront(math.min(t, duration)), 1) -- start line to the wave's foot
		local drain = math.clamp((t - duration - PUDDLE_LIFE + 4) / 4, 0, 1) -- its last 4 s it sinks away
		local depth = DEPTH * (1 - drain * 0.9)
		flood.Size = Vector3.new(width * 0.9, depth, behind)
		flood.CFrame = look * CFrame.new(0, depth / 2, -behind / 2)
		flood.Transparency = 0.35 + 0.6 * drain
	end)
end

-- A burning rock falling on `at` at server time `land` (the meteors, the volcano's lava bombs follow
-- their own path): a red circle where it lands first, then the rock with its fire and smoke.
local function fallingRock(at: Vector3, size: number, land: number, fall: number, path: ((number) -> Vector3)?)
	task.delay(math.max(land - fall - now(), 0), function()
		local mark = part(Enum.PartType.Cylinder, Vector3.new(0.3, 16 * size, 16 * size), Color3.fromRGB(230, 40, 30), Enum.Material.Neon, 0.5)
		mark.CFrame = CFrame.new(at + UP * 0.2) * CFrame.Angles(0, 0, math.pi / 2)
		local from = at + Vector3.new(math.random(-60, 60), 170, math.random(-60, 60))
		local stone = model("Meteor", 2.4 * size, Vector3.one * 5 * size, Color3.fromRGB(70, 50, 40))
		local glow = part(Enum.PartType.Ball, Vector3.one * 8 * size, Color3.fromRGB(255, 120, 30), Enum.Material.Neon, 0.7)
		local fire = Instance.new("Fire")
		fire.Size, fire.Heat, fire.Color, fire.SecondaryColor, fire.Parent = 12 * size, 18, FIRE, Color3.fromRGB(255, 60, 20), glow
		local tail = puffs(glow, Enum.ParticleEmitterShape.Sphere, Color3.fromRGB(70, 62, 58), 5 * size, 30, 1.2, 1) -- the smoke it leaves
		tail.LockedToPart = false
		drive(land - fall, fall, { mark, stone, glow }, function(t)
			local a = t / fall
			local cf = CFrame.new(if path then path(t) else from:Lerp(at, a * a)) -- speeds up as it falls
			stone.CFrame, glow.CFrame = cf * CFrame.Angles(t * 5, t * 3, 0), cf
			mark.Transparency = 0.6 - 0.3 * math.abs(math.sin(t * 12))
		end, 0.3)
		task.delay(math.max(land - now(), 0), function()
			if size > 1.5 then
				word(at + UP * 10, "KA-THOOM!", 3)
			end
		end)
	end)
end

function BUILD.Meteors(t0: number, data)
	for _, rock in data.rocks do
		fallingRock(rock.at, rock.size, t0 + rock.land, 1.4)
	end
end

function BUILD.Nuke(t0: number, data)
	local at = data.at
	local mega = if data.mega then Shared.MEGA else 1
	local blast = t0 + Shared.NUKE_FALL
	local siren = Sfx.loop(SoundService, Sfx.POLICE_SIREN_LOOP, 0.7, 10000)
	siren.PlaybackSpeed = 0.6
	local zone = part(Enum.PartType.Cylinder, Vector3.new(0.3, 90 * mega, 90 * mega), Color3.fromRGB(230, 40, 30), Enum.Material.Neon, 0.6)
	zone.CFrame = CFrame.new(at + UP * 0.25) * CFrame.Angles(0, 0, math.pi / 2)
	local bomb = model("NukeBomb", 4.5 * mega, Vector3.new(7, 16, 7) * mega, Color3.fromRGB(70, 80, 60)) -- nose down, ~16 long
	bomb.CFrame = CFrame.new(at + UP * 400)
	drive(t0, Shared.NUKE_FALL, { zone, siren, bomb }, function(t)
		zone.Transparency = 0.7 - 0.3 * math.abs(math.sin(t * 5))
		local a = math.max((t - (Shared.NUKE_FALL - 3)) / 3, 0) -- seen for its last 3 s
		local y = 320 * (1 - a * a) + 8 * mega
		bomb.CFrame = CFrame.new(at + UP * y) * CFrame.Angles(0, t * 1.5, math.rad(4) * math.sin(t * 3)) -- a lazy spin and wobble
	end, 0.3)
	task.delay(math.max(blast - now(), 0), function()
		local flash = Instance.new("Frame") -- the white-out
		flash.Size, flash.BackgroundColor3, flash.BorderSizePixel, flash.ZIndex, flash.Parent = UDim2.fromScale(1, 1), WHITE, 0, 100, gui
		local seen = (camPos() - at).Magnitude
		flash.BackgroundTransparency = math.clamp(seen / 600, 0, 0.7)
		TweenService:Create(flash, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
		task.delay(2.6, flash.Destroy, flash)
		Fx.shake(at, 3, 3)
		Fx.ring(CFrame.new(at + UP), 10, Shared.NUKE_RADIUS * mega, 2.2, WHITE, { thick = 6, height = 3, sides = 24, ink = false })
		word(at + UP * 60 * mega, if data.mega then "MEGA KA-BLAAAM!" else "KA-BLAAAM!", 8 * mega)
		-- the mushroom: inked comic clouds, glowing orange first, cooling to grey smoke
		local fireball = part(Enum.PartType.Ball, Vector3.one, Color3.fromRGB(255, 220, 110), Enum.Material.Neon)
		local stem, cap, skirt = {}, {}, {}
		for i = 1, 9 do -- close enough to overlap into one column
			stem[i] = cloud(FIRE, 22)
		end
		for i = 1, 11 do
			cap[i] = { p = cloud(FIRE, 34), a = i / 11 * math.pi * 2, r = if i % 2 == 0 then 0.35 else 0.75, y = (i % 3) * 0.12 }
		end
		for i = 1, 8 do
			skirt[i] = cloud(SMOKE, 18)
		end
		local all = { fireball }
		for _, p in stem do
			table.insert(all, p)
		end
		for _, c in cap do
			table.insert(all, c.p)
		end
		for _, p in skirt do
			table.insert(all, p)
		end
		local light = Instance.new("PointLight")
		light.Color, light.Brightness, light.Range, light.Parent = Color3.fromRGB(255, 170, 80), 10, 60, fireball
		local life = Shared.BY_ID.Nuke.duration - Shared.NUKE_FALL
		drive(blast, life, all, function(t)
			local grow = 1 - (1 - math.clamp(t / 4, 0, 1)) ^ 3 -- fast, then settling
			local cool = math.clamp((t - 1) / 4, 0, 1) -- glowing orange to grey smoke
			local color = FIRE:Lerp(SMOKE, cool)
			fireball.Size = Vector3.one * (12 + 70 * math.clamp(t / 0.7, 0, 1)) * mega
			fireball.CFrame = CFrame.new(at + UP * 10 * mega)
			fireball.Transparency = math.clamp((t - 0.6) / 0.8, 0, 1)
			local top = (25 + 115 * grow) * mega
			local fade = math.clamp((t - (life - 4)) / 4, 0, 1)
			for i, p in stem do
				local h = (i - 0.5) / #stem
				p.Size = Vector3.one * (18 + 8 * h) * mega * (0.5 + 0.5 * grow)
				p.CFrame = CFrame.new(at + UP * top * h * 0.95) * CFrame.Angles(0, t * 0.3 + i, 0)
				p.Color, p.Transparency = color, fade
			end
			local capR = (20 + 32 * grow) * mega
			for _, c in cap do
				local a = c.a + t * 0.25
				c.p.Size = Vector3.one * capR * 0.95
				c.p.CFrame = CFrame.new(at + UP * (top + capR * c.y) + Vector3.new(math.cos(a), 0, math.sin(a)) * capR * c.r) * CFrame.Angles(0, a, 0)
				c.p.Color, c.p.Transparency = color, fade
			end
			for i, p in skirt do
				local a = i / #skirt * math.pi * 2 - t * 0.3
				p.Size = Vector3.one * (12 + 10 * grow) * mega
				p.CFrame = CFrame.new(at + UP * top * 0.55 + Vector3.new(math.cos(a), 0, math.sin(a)) * (14 + 10 * grow) * mega)
				p.Color, p.Transparency = SMOKE, fade
			end
			light.Brightness = 10 * (1 - cool)
		end)
	end)
end

-- Cracks run out from the middle (black, inked, dust bursting along them), the camera never stops
-- shaking, dust clouds pop up all round.
function BUILD.Earthquake(t0: number, data)
	local duration = Shared.BY_ID.Earthquake.duration
	local centre = data.centre
	local cracks = {}
	for _, crack in data.cracks do
		task.delay(math.max(t0 + crack.at - now(), 0), function()
			word(crack.from + UP * 8, "KRAKK!", 3)
			for s = 0, crack.length, 8 do
				local p = crack.from + crack.dir * (s + 4)
				local slab = part(Enum.PartType.Block, Vector3.new(1.6, 0.5, 8.6), INK)
				slab.CFrame = CFrame.lookAlong(p + UP * 0.2, crack.dir) * CFrame.Angles(0, math.rad(math.random(-14, 14)), 0)
				table.insert(cracks, slab)
				puff(p, ROCK_DUST, 7, 1.2, 8)
				task.wait(0.08)
			end
		end)
	end
	local rng = Random.new()
	local nextPuff, nextWord = 0, 1
	drive(t0, duration, {}, function(t)
		local fadeIn = math.clamp(t / 0.6, 0, 1) * math.clamp((duration - t) / 1.5, 0, 1)
		Fx.shake(centre, 0.55 * fadeIn, 0.25)
		if t > nextPuff then
			nextPuff = t + 0.35
			local a = rng:NextNumber(0, math.pi * 2)
			puff(centre + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(5, 90), ROCK_DUST, rng:NextNumber(6, 11), 1.6, 10)
		end
		if t > nextWord then
			nextWord = t + 3
			word(centre + UP * 15 + Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30)), "RUMBLE RUMBLE!", 4)
		end
	end)
	task.delay(math.max(t0 + duration - now(), 0), function()
		fadeOut(cracks, 2)
	end)
end

-- The volcano erupts: belches inked smoke, glows, lobs burning bombs. On the arena it is the map's own
-- (data.at nil, data.crater its top); elsewhere a comic one grows out of the ground and sinks back after.
function BUILD.Volcano(t0: number, data)
	local duration = Shared.BY_ID.Volcano.duration
	local at, crater = data.at, data.crater
	local cone = if at then model("Volcano", 5, Vector3.new(40, 16, 40), Color3.fromRGB(80, 60, 50)) else part(Enum.PartType.Block, Vector3.one, WHITE, nil, 1)
	local base = cone.Size
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Parent = FIRE, 80, 0, cone
	Sfx.loop(cone, Sfx.FIRE_BURNING_LOOP, 3, 400).PlaybackSpeed = 0.5
	if at then
		Fx.ring(CFrame.new(at + UP), 6, 40, 1, ROCK_DUST, { thick = 3, sides = 10 })
	else
		cone.CFrame = CFrame.new(crater + UP * 2)
	end
	local riseTime = if at then Shared.VOLCANO_RISE else 1 -- the map's is already standing: it only wakes
	local nextSmoke, erupted = 0, false
	drive(t0, duration, { cone }, function(t)
		local rise = math.clamp(t / riseTime, 0, 1)
		local sink = if at then math.clamp((t - (duration - 2.5)) / 2.5, 0, 1) else 0
		if at then
			local up = (1 - (1 - rise) ^ 3) * (1 - sink)
			cone.Size = Vector3.new(base.X, base.Y * math.max(up, 0.05), base.Z)
			cone.CFrame = CFrame.new(at)
		end
		Fx.shake(crater, if rise < 1 or sink > 0 then 0.4 else 0.12, 0.2)
		if rise >= 1 and sink == 0 and t < duration - 2 then
			glow.Brightness = 4 + math.sin(t * 9)
			if not erupted then
				erupted = true
				word(crater + UP * 18, "BLAMMO!", 5)
			end
			if t > nextSmoke then -- the smoke column, puff after puff
				nextSmoke = t + 0.22
				puff(crater + Vector3.new(math.random(-3, 3), 2, math.random(-3, 3)), Color3.fromRGB(60, 56, 56), if at then 12 else 16, 3, if at then 45 else 60)
			end
		else
			glow.Brightness = 0
		end
	end, 0.5)
	for _, bomb in data.bombs do
		local launch = t0 + bomb.t
		fallingRock(bomb.to, bomb.size, launch + bomb.flight, bomb.flight, function(t)
			return Shared.lob(crater, bomb.to, bomb.flight, t)
		end)
	end
end

-- Dark inked thunderclouds over the players and rain; every strike ("strike" from the server) a target
-- ring glows, then the comic bolt comes down from the clouds with a flash and a sound word.
function BUILD.Lightning(t0: number, data)
	local duration = Shared.BY_ID.Lightning.duration
	local centre = data.centre
	local top = centre.Y + Shared.STORM_HEIGHT
	local clouds = {}
	local rng = Random.new()
	for i = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0, 110)
		clouds[i] = { p = cloud(Color3.fromRGB(96, 100, 122), rng:NextNumber(34, 52)), at = Vector3.new(centre.X + math.cos(a) * r, top + rng:NextNumber(-6, 6), centre.Z + math.sin(a) * r), spin = rng:NextNumber(-0.2, 0.2) }
	end
	local parts = {}
	for _, c in clouds do
		table.insert(parts, c.p)
	end
	drive(t0 - Shared.LEAD, duration + Shared.LEAD, parts, function(t)
		local grow = math.clamp(t / 2, 0.05, 1) -- the storm gathers during the countdown
		for _, c in clouds do
			c.p.Size = Vector3.one * c.p:GetAttribute("Full") * grow
			c.p.CFrame = CFrame.new(c.at + Vector3.new(math.sin(t * 0.2) * 6, 0, 0)) * CFrame.Angles(0, t * c.spin, 0)
		end
	end, 2)
	for _, c in clouds do
		c.p:SetAttribute("Full", c.p.Size.X)
	end
	local count = 0
	strikeAt = function(at: Vector3)
		count += 1
		local mark = part(Enum.PartType.Cylinder, Vector3.new(0.3, 10, 10), YELLOW, Enum.Material.Neon, 0.4)
		mark.CFrame = CFrame.new(at + UP * 0.2) * CFrame.Angles(0, 0, math.pi / 2)
		local t1 = now()
		drive(t1, Shared.STRIKE_WARN, { mark }, function(t)
			mark.Transparency = 0.7 - 0.4 * math.abs(math.sin(t * 25))
		end, 0.05)
		task.delay(Shared.STRIKE_WARN, function()
			local bolt = model("Bolt", 1, Vector3.new(6, 10, 1), YELLOW)
			local s0 = bolt.Size
			bolt.Size = Vector3.new(s0.X * 3.2, math.max(top - at.Y, 10), s0.Z * 3.2)
			bolt.CFrame = CFrame.new(at) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
			local light = Instance.new("PointLight")
			light.Color, light.Range, light.Brightness, light.Parent = Color3.fromRGB(255, 240, 160), 60, 8, bolt
			if (camPos() - at).Magnitude < 260 then
				flashCC.Brightness = 0.45
				TweenService:Create(flashCC, TweenInfo.new(0.3), { Brightness = 0 }):Play()
			end
			if count % 2 == 1 then
				word(at + UP * 12, "KRA-KOOM!", 3.5)
			end
			drive(now(), 0.3, { bolt }, function(t) -- it flickers out
				bolt.Transparency = if t % 0.1 < 0.05 then 0 else 0.5
			end, 0.1)
		end)
	end
	task.delay(math.max(t0 + duration + 1 - now(), 0), function()
		strikeAt = nil
	end)
end

-- Snow blown along the wind (the mood), white speed lines whipping past the camera, comic ice
-- crystals bursting out of the ground and staying till it is over.
function BUILD.Blizzard(t0: number, data)
	local duration = Shared.BY_ID.Blizzard.duration
	local wind = data.wind
	local shards = {}
	for _, spike in data.spikes do
		task.delay(math.max(t0 + spike.t - now(), 0), function()
			local ice = model("IceShards", 3.2, Vector3.new(6, 9, 6), Color3.fromRGB(170, 220, 255))
			local full = ice.Size
			local yaw = math.random() * math.pi * 2
			table.insert(shards, ice)
			puff(spike.at, WHITE, 9, 1, 6)
			if math.random() < 0.5 then
				word(spike.at + UP * 10, "KRSSSH!", 2.5)
			end
			local t1 = now()
			drive(t1, t0 + duration - t1, {}, function(t)
				local a = math.min(t / 0.2, 1)
				ice.Size = full * (0.2 + 0.8 * a)
				ice.CFrame = CFrame.new(spike.at) * CFrame.Angles(0, yaw, 0)
			end)
		end)
	end
	local rng = Random.new()
	local nextLine, nextWord = 0, 2
	drive(t0, duration, {}, function(t)
		if t > nextLine then -- comic speed lines in the wind, round the camera
			nextLine = t + 0.06
			local from = camPos() + Vector3.new(rng:NextNumber(-50, 50), rng:NextNumber(-8, 20), rng:NextNumber(-50, 50)) - wind * 30
			local line = part(Enum.PartType.Block, Vector3.new(0.18, 0.18, rng:NextNumber(5, 10)), WHITE, Enum.Material.Neon, 0.3)
			local t1 = now()
			drive(t1, 0.6, { line }, function(s)
				line.CFrame = CFrame.lookAlong(from + wind * 90 * s, wind)
				line.Transparency = 0.3 + s / 0.6 * 0.7
			end, 0.05)
		end
		if t > nextWord then
			nextWord = t + 4
			word(camPos() + workspace.CurrentCamera.CFrame.LookVector * 30 + UP * 6, "BRRRR!", 3)
		end
	end)
	task.delay(math.max(t0 + duration - now(), 0), function()
		fadeOut(shards, 1.5)
	end)
end

-- The saucer drifts over, spinning and bobbing, its green tractor beam on; zaps hit the ground with a
-- red laser; the last 2 s it shoots off into the sky.
function BUILD.Ufo(t0: number, data)
	local duration = Shared.BY_ID.Ufo.duration
	local fly = duration - 2
	local path = data.path
	local ufo = model("Ufo", 4, Vector3.new(26, 5, 26), Color3.fromRGB(190, 195, 205))
	local beam = part(Enum.PartType.Cylinder, Vector3.new(Shared.UFO_HEIGHT, Shared.UFO_BEAM * 2, Shared.UFO_BEAM * 2), Color3.fromRGB(120, 255, 120), Enum.Material.Neon, 0.75)
	local core = part(Enum.PartType.Cylinder, Vector3.new(Shared.UFO_HEIGHT, Shared.UFO_BEAM, Shared.UFO_BEAM), Color3.fromRGB(200, 255, 190), Enum.Material.Neon, 0.6)
	local spot = part(Enum.PartType.Cylinder, Vector3.new(0.3, Shared.UFO_BEAM * 2.4, Shared.UFO_BEAM * 2.4), Color3.fromRGB(120, 255, 120), Enum.Material.Neon, 0.5)
	local lift = Instance.new("ParticleEmitter") -- sparkles rising up the beam
	lift.Color, lift.LightEmission = ColorSequence.new(Color3.fromRGB(180, 255, 170)), 1
	lift.Size, lift.Speed, lift.Lifetime, lift.Rate = NumberSequence.new(0.6), NumberRange.new(10, 16), NumberRange.new(1.4), 60
	lift.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis
	lift.Parent = beam
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Parent = Color3.fromRGB(120, 255, 120), 40, 3, spot
	Sfx.loop(ufo, Sfx.ROCKET_FLIGHT_LOOP, 1.5, 300).PlaybackSpeed = 0.45
	local said = false
	drive(t0 - 1, duration + 1, { ufo, beam, core, spot }, function(tt)
		local t = tt - 1
		local pos
		if t < 0 then -- it swoops in during the last of the countdown
			pos = path[1] + UP * 120 * (-t)
		elseif t <= fly then
			pos = Shared.along(path, t, fly)
		else -- off it goes
			local a = (t - fly) / 2
			pos = path[#path] + (UP * 260 + (path[#path] - path[1]) * 2) * a * a
		end
		pos += UP * math.sin(tt * 2) * 1.5
		ufo.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(5) * math.sin(tt * 1.3), tt * 2.5, 0)
		local on = t >= 0 and t <= fly
		local floorY = pos.Y - Shared.UFO_HEIGHT
		for _, p in { beam, core } do
			p.CFrame = CFrame.new(Vector3.new(pos.X, (pos.Y + floorY) / 2 - 2, pos.Z)) * CFrame.Angles(0, 0, math.pi / 2)
		end
		beam.Transparency = if on then 0.72 + 0.06 * math.sin(tt * 20) else 1
		core.Transparency = if on then 0.6 else 1
		spot.Transparency = if on then 0.5 else 1
		spot.CFrame = CFrame.new(Vector3.new(pos.X, floorY + 0.25, pos.Z)) * CFrame.Angles(0, 0, math.pi / 2)
		lift.Enabled = on
		if on and not said then
			said = true
			word(pos + UP * 8, "ZWOOP!", 4)
		end
	end)
	for _, zap in data.zaps do
		task.delay(math.max(t0 + zap.t - 0.25 - now(), 0), function()
			local from = ufo.Position
			local ray = part(Enum.PartType.Block, Vector3.new(0.8, 0.8, (zap.at - from).Magnitude), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
			ray.CFrame = CFrame.lookAt((from + zap.at) / 2, zap.at)
			task.delay(0.3, ray.Destroy, ray)
			task.delay(0.25, word, zap.at + UP * 6, "ZAP!", 2.5)
		end)
	end
end

-- Night (the mood), dirt flying where the zombies climb out of the ground.
function BUILD.Zombies(t0: number, data)
	for i, spot in data.spots do
		task.delay(math.max(t0 + spot.t - now(), 0), function()
			puff(spot.at, Color3.fromRGB(110, 80, 55), 8, 1.2, 5)
			if i % 3 == 1 then
				word(spot.at + UP * 9, "BRAAAINS!", 3)
			end
		end)
	end
	onDawn = function()
		onDawn = nil
		endNight()
		word(data.centre + UP * 25, "DAWN!", 5)
	end
end

function Disasters.start()
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "DisasterFx", workspace
	grade.Parent, flashCC.Parent = Lighting, Lighting
	gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "DisasterHud", false, true, 20
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	RunService.RenderStepped:Connect(function()
		if weather then -- the rain / snow / ash comes down round the camera
			weather.CFrame = CFrame.new(camPos() + UP * 35)
		end
	end)
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Disaster") :: RemoteEvent
	remote.OnClientEvent:Connect(function(what, a, b, c)
		if what == "banner" then
			countdown(a, b, c)
		elseif what == "start" and BUILD[a] then
			mood(a, b + Shared.BY_ID[a].duration, c.wind)
			BUILD[a](b, c)
		elseif what == "strike" and strikeAt then
			strikeAt(a)
		elseif what == "dawn" and onDawn then
			onDawn()
		elseif what == "summary" then
			summary(a, b)
		elseif what == "refused" then
			banner(if a == "busy" then "NOT NOW!" else `WAIT {math.ceil(b)}s`, if a == "busy" then "ONE DISASTER IS ALREADY ON" else "DISASTERS ARE ON COOLDOWN", INK, 2)
		end
	end)
end

return Disasters
