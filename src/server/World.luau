-- The host's world settings (shared/Settings: the first player on the server decides):
--  * GRAVITY: workspace gravity times the setting (it replicates, so clients fall the same way);
--  * GRAVE ZOMBIES: a grave (Map.grave) still standing RISE_AFTER seconds after it was dug lets
--    the one buried in it out as a zombie, clawing up through the mound (Anims.rise).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Settings = require(ReplicatedStorage.Shared.Settings)
local Map = require(script.Parent.Map)
local Anims = require(script.Parent.Anims)

local RISE_AFTER = 60
local RISE_TIME = 3 -- seconds from under the mound to standing on it
local DEPTH = 5.5 -- studs under standing height it starts: the head well under the dirt

local World = {}

-- api: spawn(cf, name, kind) -> dummy record, trim(), play(d, animation) -> AnimationTrack
function World.start(api)
	local baseGravity = workspace.Gravity

	local function rise(grave: Model)
		grave:SetAttribute("Risen", true) -- once per grave
		local spot = grave:GetAttribute("Spot") :: CFrame
		-- on the mound, facing away from the stone (at the grave's -Z end)
		local ground = spot * CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.pi, 0)
		api.trim()
		local d = api.spawn(ground + Vector3.yAxis * 3, grave:GetAttribute("Buried"), "Zombie")
		local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart
		local stand = ground + Vector3.yAxis * (d.humanoid.HipHeight + root.Size.Y / 2)
		root.Anchored = true -- the rig is one rigid assembly while it stands: the root carries it
		d.model:PivotTo(stand - Vector3.yAxis * DEPTH)
		d.risingUntil = os.clock() + RISE_TIME + 0.3 -- no walking, posing or fighting until it is up
		local claw = api.play(d, Anims.rise)
		claw:Play(0.1)
		Map.blast(spot * Vector3.new(0, 0.3, 0.6), 2.2, 18, nil, true) -- the mound bursts open
		local tween = TweenService:Create(root, TweenInfo.new(RISE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = stand })
		tween.Completed:Once(function()
			claw:Stop(0.3)
			if root.Parent then
				root.Anchored = false
			end
		end)
		tween:Play()
	end

	task.spawn(function()
		while true do
			task.wait(1)
			local host = Settings.host()
			workspace.Gravity = baseGravity * Settings.get(host, "Gravity")
			if not (host and Settings.get(host, "GraveZombies")) then
				continue
			end
			local now = os.clock()
			-- broken graves fall apart (out of the folder) and never come back: nobody gets out of those
			for _, grave in Map.folder:GetChildren() do
				if grave.Name == "Grave" and grave:GetAttribute("DugAt") and not grave:GetAttribute("Risen") and now - (grave:GetAttribute("DugAt") or now) >= RISE_AFTER then
					task.spawn(rise, grave)
				end
			end
		end
	end)
end

return World
