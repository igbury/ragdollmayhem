-- The bosses' keyframed clips, made in Blender (assets/myth/boss_clips.py keyed by anim_bosses.py into
-- assets/myth/boss_anims.blend) and baked per kind into the data modules beside this one. They are played
-- on the rig's own Motor6Ds by MythRig.pose: no Animation assets, nothing to upload, and the server keeps
-- posing the bodies its hit boxes ride on.
local Clips = {}

-- The order every baked frame lists its joints in (anim_bosses.py PIVOT).
local JOINTS = {
	"Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle",
}
Clips.JOINTS = JOINTS

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 1, #B64 do
	DIGIT[string.byte(B64, i)] = i - 1
end
local function number(data, at, chars, lo, hi)
	local n = 0
	for k = 0, chars - 1 do
		n = n * 64 + DIGIT[string.byte(data, at + k)]
	end
	return lo + n / (64 ^ chars - 1) * (hi - lo)
end

export type Clip = {
	name: string,
	length: number,
	loop: boolean,
	additive: boolean,
	sections: { [string]: number },
	fps: number,
	count: number,
	roots: { Vector3 },
	rots: { { CFrame } },
}

local sources: { [string]: any } = {}
local decoded: { [string]: Clip | false } = {}

local function decode(name, raw, fps): Clip
	local per = 9 + #JOINTS * 6
	local data = raw.data
	assert(#data == per * raw.frames, "MythClips: " .. name .. " has the wrong amount of data")
	local roots, rots = table.create(raw.frames), table.create(raw.frames)
	for f = 0, raw.frames - 1 do
		local at = f * per + 1
		roots[f + 1] = Vector3.new(number(data, at, 3, -32, 32), number(data, at + 3, 3, -32, 32), number(data, at + 6, 3, -32, 32))
		at += 9
		local frame = table.create(#JOINTS)
		for j = 1, #JOINTS do
			local x, y, z = number(data, at, 2, -1, 1), number(data, at + 2, 2, -1, 1), number(data, at + 4, 2, -1, 1)
			frame[j] = CFrame.new(0, 0, 0, x, y, z, math.sqrt(math.max(0, 1 - x * x - y * y - z * z)))
			at += 6
		end
		rots[f + 1] = frame
	end
	return {
		name = name, length = raw.length, loop = raw.loop, additive = raw.additive == true,
		sections = raw.sections or {}, fps = fps, count = raw.frames, roots = roots, rots = rots,
	}
end

-- The clip `name` of boss `kind`, decoded on first use; nil when there is none.
function Clips.get(kind: string, name: string): Clip?
	local key = kind .. "/" .. name
	local hit = decoded[key]
	if hit ~= nil then return hit or nil end
	local source = sources[kind]
	if source == nil then
		local module = script:FindFirstChild(kind)
		local ok, result = pcall(function() return module and require(module) end)
		source = ok and result or false
		sources[kind] = source
	end
	local raw = source and source.clips[name]
	local clip = raw and decode(key, raw, source.fps) or false
	decoded[key] = clip
	return clip or nil
end

-- The clip at `t` seconds (wrapped when it loops, held at its ends when not): the root's offset in studs
-- at scale 1 and each joint's rotation, in JOINTS order, written into `out`.
function Clips.sample(clip: Clip, t: number, out: { CFrame }): Vector3
	local n = clip.count
	local x
	if clip.loop then
		x = (t % clip.length) * clip.fps
	else
		x = math.clamp(t, 0, clip.length) * clip.fps
	end
	local i = math.floor(x)
	local a = x - i
	local i1, i2
	if clip.loop then
		i1, i2 = i % n + 1, (i + 1) % n + 1
	else
		i1, i2 = math.min(i, n - 1) + 1, math.min(i + 1, n - 1) + 1
	end
	local f1, f2 = clip.rots[i1], clip.rots[i2]
	for j = 1, #JOINTS do
		out[j] = f1[j]:Lerp(f2[j], a)
	end
	return clip.roots[i1]:Lerp(clip.roots[i2], a)
end

return Clips
