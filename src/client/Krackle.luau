-- Comic "Kirby krackle" textures for Cosmic Power (Fx Cosmic), painted pixel by pixel into
-- EditableImages the first time they are asked for: Roblox has no custom shaders, so the look lives
-- in the textures, shown flat on BillboardGui ImageLabels (Beams and ParticleEmitters take an
-- EditableImage but draw nothing with it, checked in Studio 2026-11-26). Nothing is uploaded.
-- Hard edges only, no soft ramps: solid fills, black ink dots in bunches of every size, black
-- parallel hatching, ragged silhouettes. References: Kirby's cosmic-power panels (fields full of black
-- dot bunches with a ring round them, hatched flame tongues), recoloured to two greens.
-- Three 2x2 flipbooks (128 px cells): cloud (light green + dot bunches + dark green ring), flame (dark or light green
-- tongue hatched down one side), dots (black bunches on nothing).
local AssetService = game:GetService("AssetService")

local Krackle = {}

local TAU = math.pi * 2
local DARK = { 20, 105, 40 } -- Fx COSMIC_DARK / COSMIC_LIGHT: two greens and black ink only
local LIGHT = { 140, 235, 90 }
local INK = { 0, 0, 0 }

local function canvas(w: number, h: number)
	return { w = w, h = h, buf = buffer.create(w * h * 4), clip = { 0, 0, w, h } }
end

local function px(c, x: number, y: number, col)
	local clip = c.clip
	if x < clip[1] or x >= clip[3] or y < clip[2] or y >= clip[4] then
		return
	end
	local i = (y * c.w + x) * 4
	buffer.writeu8(c.buf, i, col[1])
	buffer.writeu8(c.buf, i + 1, col[2])
	buffer.writeu8(c.buf, i + 2, col[3])
	buffer.writeu8(c.buf, i + 3, 255)
end

local function disc(c, cx: number, cy: number, r: number, col)
	for y = math.floor(cy - r), math.ceil(cy + r) do
		for x = math.floor(cx - r), math.ceil(cx + r) do
			if (x - cx) ^ 2 + (y - cy) ^ 2 <= r * r then
				px(c, x, y, col)
			end
		end
	end
end

-- A periodic wave of u (0..1): a few sine harmonics, so a strip's edge tiles. spiky: |sin|, flame tongues.
local function wave(rng: Random, harmonics: number, amp: number, from: number?, spiky: boolean?)
	local hs = {}
	for k = from or 1, (from or 1) + harmonics - 1 do
		table.insert(hs, { k, rng:NextNumber(0, TAU), amp / k ^ 0.6 * rng:NextNumber(0.5, 1) })
	end
	return function(u: number): number
		local s = 0
		for _, h in hs do
			local v = math.sin(TAU * h[1] * u + h[2])
			s += h[3] * (if spiky then math.abs(v) * 2 - 1 else v)
		end
		return s
	end
end

-- One bunch of ink dots round (cx, cy): many small, some medium, a few big, piled on each other.
local function bunch(c, rng: Random, cx: number, cy: number, spread: number, count: number, scale: number)
	for _ = 1, count do
		local roll = rng:NextNumber()
		local r = (if roll < 0.55 then rng:NextNumber(1.5, 3) elseif roll < 0.9 then rng:NextNumber(3, 6) else rng:NextNumber(6, 10)) * scale
		local a, d = rng:NextNumber(0, TAU), spread * rng:NextNumber() ^ 0.7
		disc(c, cx + math.cos(a) * d, cy + math.sin(a) * d, r, INK)
	end
end

-- The four cells of a 2x2 flipbook, each painted by fn(c, rng, cx, cy, half) clipped to its cell.
local function flipbook(rng: Random, fn)
	local c = canvas(256, 256)
	for i = 0, 3 do
		local x0, y0 = (i % 2) * 128, (i // 2) * 128
		c.clip = { x0, y0, x0 + 128, y0 + 128 }
		fn(c, rng, x0 + 64, y0 + 64, 64)
	end
	return c
end

local function cloud(c, rng: Random, cx: number, cy: number, half: number)
	local edge = wave(rng, 5, 9)
	local R = half * 0.62
	for y = cy - half, cy + half - 1 do
		for x = cx - half, cx + half - 1 do
			local dx, dy = x - cx, y - cy
			local r = R + edge((math.atan2(dy, dx) / TAU) % 1)
			local d = math.sqrt(dx * dx + dy * dy)
			if d <= r then
				px(c, x, y, LIGHT)
			elseif d <= r + 5 then
				px(c, x, y, DARK)
			end
		end
	end
	for _ = 1, rng:NextInteger(3, 5) do -- bunches inside, leaning to the rim; big dots, the cloud is shown small
		local a, d = rng:NextNumber(0, TAU), R * rng:NextNumber(0.2, 0.85)
		bunch(c, rng, cx + math.cos(a) * d, cy + math.sin(a) * d, rng:NextNumber(8, 14), rng:NextInteger(4, 7), 1.8)
	end
end

local function flame(c, rng: Random, cx: number, cy: number, half: number)
	local col = if rng:NextNumber() < 0.5 then DARK else LIGHT
	local sway = wave(rng, 3, 6)
	local ragged = wave(rng, 5, 4, 3, true)
	for y = cy - half + 4, cy + half - 4 do
		local u = (cy + half - 4 - y) / (half * 2 - 8) -- 0 at the base, 1 at the tip
		local w = half * 0.55 * (1 - u) ^ 0.8 + ragged(u)
		local mid = cx + sway(u) * u * 2
		for x = math.floor(mid - w), math.ceil(mid + w) do
			local leftSide = x < mid - w * 0.2
			px(c, x, y, if leftSide and (x + y) % 6 < 2 then INK else col) -- hatched down one side
		end
	end
	bunch(c, rng, cx, cy + half * 0.55, 10, 6, 0.8)
end

-- One bunch filling the cell, drawn to read at a small size: a handful of big round dots, one or two
-- heavy ones in the middle, smaller ones round them, touching but still each a dot.
local function dots(c, rng: Random, cx: number, cy: number, half: number)
	disc(c, cx, cy, rng:NextNumber(14, 20), INK)
	for _ = 1, rng:NextInteger(7, 11) do
		local a = rng:NextNumber(0, TAU)
		local r = rng:NextNumber(5, 15)
		local d = rng:NextNumber(14, half - 4 - r)
		disc(c, cx + math.cos(a) * d, cy + math.sin(a) * d, r, INK)
	end
end

local cached: { [string]: Content }? = nil
local failed = false

-- { cloud, flame, dots } as Content, or nil where EditableImages are refused.
function Krackle.get(): { [string]: Content }?
	if cached or failed then
		return cached
	end
	local ok, result = pcall(function()
		local rng = Random.new(1968) -- the same look every time
		local out = {}
		for name, c in {
			cloud = flipbook(rng, cloud), flame = flipbook(rng, flame), dots = flipbook(rng, dots),
		} do
			local size = Vector2.new(c.w, c.h)
			local img = AssetService:CreateEditableImage({ Size = size })
			img:WritePixelsBuffer(Vector2.zero, size, c.buf)
			out[name] = Content.fromObject(img)
		end
		return out
	end)
	if ok then
		cached = result
	else
		failed = true
		warn("Krackle: no EditableImage, Cosmic Power falls back to flat colour:", result)
	end
	return cached
end

return Krackle
