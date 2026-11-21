-- Performance mode, for phones and tablets: on by itself on a touch device (the "PerfMode" setting,
-- shared/Settings: "auto" / "on" / "off"; the toolbox SETTINGS page sets it). What it turns off, on
-- this client only, put back as it was when it goes off:
--  * the sun's shadows (Lighting.GlobalShadows: thousands of parts cast them);
--  * bloom, sun rays and depth of field (full-screen passes; colour correction and the atmosphere stay);
--  * point, spot and surface lights in the world (muzzle flashes, lamps);
--  * half the particles of every emitter that streams (Rate; a burst by :Emit is left alone).
-- (Terrain.Decoration, the grass, cannot be written by a game script, so it stays.)
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local Music = require(script.Parent:WaitForChild("Music")) -- the settings (shared/Settings)

local PerfMode = {}

local POST = { BloomEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true }
local LIGHT = { PointLight = true, SpotLight = true, SurfaceLight = true }
local PARTICLE_SHARE = 0.5

-- a phone or tablet, not a laptop with a touch screen
local TOUCH_DEVICE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local on = false
local saved = {} -- [instance] = what it had before (weak: a destroyed one needs no restoring)
setmetatable(saved, { __mode = "k" })
local shadows = Lighting.GlobalShadows

local function dim(o: Instance)
	if saved[o] ~= nil then
		return
	end
	local name = o.ClassName
	if POST[name] or LIGHT[name] then
		saved[o] = (o :: any).Enabled
		;(o :: any).Enabled = false
	elseif name == "ParticleEmitter" then
		local e = o :: ParticleEmitter
		saved[o] = e.Rate
		e.Rate *= PARTICLE_SHARE
	end
end

local function restore()
	for o, v in saved do
		if o.Parent then
			if o:IsA("ParticleEmitter") then
				o.Rate = v
			else
				(o :: any).Enabled = v
			end
		end
	end
	table.clear(saved)
end

function PerfMode.wanted(): boolean
	local v = Music.get("PerfMode")
	return v == "on" or (v ~= "off" and TOUCH_DEVICE)
end

function PerfMode.active(): boolean
	return on
end

local function apply()
	local want = PerfMode.wanted()
	if want == on then
		return
	end
	on = want
	if on then
		shadows = Lighting.GlobalShadows
		Lighting.GlobalShadows = false
		for _, o in Lighting:GetDescendants() do
			dim(o)
		end
		for _, o in workspace:GetDescendants() do
			dim(o)
		end
	else
		Lighting.GlobalShadows = shadows
		restore()
	end
end

-- what turns up later: the map's effects (server/Map), weapon fire, new dummies' gear
local function added(o: Instance)
	if on then
		dim(o)
	end
end
Lighting.DescendantAdded:Connect(added)
workspace.DescendantAdded:Connect(added)
Music.changed:Connect(function(name)
	if name == "PerfMode" then
		apply()
	end
end)
apply()

return PerfMode
