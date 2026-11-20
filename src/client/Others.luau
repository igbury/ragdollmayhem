-- Other players' movement. The movement animations are built in memory on each client (see
-- SprintFlail and the rest) and the sounds are played locally, so neither replicates on its own.
-- Instead every client reports what its body is doing (init.client fires the Move remote), the
-- server passes that on, and this plays the same animation and sound on that player's character
-- here. Looks only: positions still replicate the normal way.
-- ponytail: someone who joins mid-move sees a player's loop from its next change on, not at once;
-- keep the last loop per player on the server and send it on join if that ever shows.

local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Sfx"))
local RunService = game:GetService("RunService")
local Clips = require(game:GetService("ReplicatedStorage").Shared:WaitForChild("AnimationClips"))

local Others = {}

-- looping looks, and the priority each plays at (as on the owner's client)
local LOOPS = {
	sprint = Enum.AnimationPriority.Movement,
	wall1 = Enum.AnimationPriority.Action,
	["wall-1"] = Enum.AnimationPriority.Action,
	cling = Enum.AnimationPriority.Action,
	slide = Enum.AnimationPriority.Action,
	crouch = Enum.AnimationPriority.Action,
	crouchIdle = Enum.AnimationPriority.Action,
	dive = Enum.AnimationPriority.Action4,
}
-- one-off moves and the sound that goes with each ("" = none); the animation, when there is one,
-- has the same name
local SHOTS = { roll = "", flip = "", kick = "Kick", jump = "Jump", slam = "Slam", dash = "Dash",
	mantle = "", vault = "", slideEnter = "", slideExit = "", diveEnter = "" }
local SHOT_SPEED = { mantle = 0.5 / 0.4, vault = 0.5 / 0.28 }
local Fx = require(script.Parent:WaitForChild("Fx")) -- the dash leaves afterimages here too
local DASH_COLOR = Color3.fromRGB(120, 220, 255)
local RUN = { sprint = true, wall1 = true, ["wall-1"] = true } -- loops with the footsteps sound under them

local state = setmetatable({}, { __mode = "k" }) -- [character] = { tracks = { [name] = AnimationTrack }, loop = AnimationTrack? }

-- anims: [name] = Animation, sfx: [name] = asset id ("" = silent), both as init.client has them.
function Others.start(remote: RemoteEvent, anims: { [string]: Animation }, sfx: { [string]: string })
	local function sound(root: BasePart, name: string): Sound
		local s = root:FindFirstChild("Other" .. name) :: Sound?
		if not s then
			s = Instance.new("Sound")
			s.Name = "Other" .. name
			s.SoundId = (sfx[name] or "") ~= "" and "rbxassetid://" .. sfx[name] or ""
			s.Looped = name == "Run"
			s.Volume = name == "Run" and 0.4 or 0.7
			s.RollOffMaxDistance = 120
			Sfx.prepare(s)
			s.Parent = root
		end
		return s
	end

	remote.OnClientEvent:Connect(function(player: Player, kind: string, name: string)
		local char = player and player.Character -- nil when they left before this arrived
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (animator and root) then
			return
		end
		local s = state[char]
		if not s then
			s = { tracks = {} }
			state[char] = s
		end
		local function track(id: string): AnimationTrack?
			if not s.tracks[id] and anims[id] then
				local t = animator:LoadAnimation(anims[id])
			t.Priority = LOOPS[id] or ((id == "slideEnter" or id == "slideExit")
				and Enum.AnimationPriority.Action2 or Enum.AnimationPriority.Action4)
				t.Looped = LOOPS[id] ~= nil
				s.tracks[id] = t
			end
			return s.tracks[id]
		end
		if kind == "loop" then
			s.loopToken = (s.loopToken or 0) + 1
			local token = s.loopToken
			if s.loop then
				s.loop:Stop(0.2)
			end
			s.loopName = name
			s.loop = track(name)
			if s.loop then
				local function start()
					if s.loopToken == token and s.loop and char.Parent then
						s.loop:Play(0.12)
					end
				end
				local waitForEntry = name == "dive" and math.max((s.diveReadyAt or 0) - os.clock(), 0) or 0
				if waitForEntry > 0 then task.delay(waitForEntry, start) else start() end
			end
			local run = sound(root, "Run")
			if RUN[name] and not run.IsPlaying then
				run:Play()
			elseif not RUN[name] then
				run:Stop()
			end
		elseif SHOTS[name] then
			local t = track(name)
			if t then
				t:Play(0.05, 1, SHOT_SPEED[name] or 1)
			end
			if name == "diveEnter" then
				s.diveReadyAt = os.clock() + 0.18
			elseif name == "slam" and s.tracks.diveEnter then
				s.tracks.diveEnter:Stop(0.04)
			end
			if SHOTS[name] ~= "" then
				sound(root, SHOTS[name]):Play()
			end
			if name == "dash" then
				Fx.ghosts(char, DASH_COLOR, 5, 0.035, 0.32)
			end
		end
	end)
	-- Observers use replicated travel speed too; a crouching player no longer
	-- shuffles at full speed while standing still on somebody else's screen.
	RunService.Heartbeat:Connect(function(dt)
		for char, s in state do
			if not char.Parent then
				state[char] = nil
				continue
			end
			local root = char:FindFirstChild("HumanoidRootPart")
			local reference = s.loopName == "sprint" and Clips.referenceSpeed("SprintFlail")
				or s.loopName == "crouch" and Clips.referenceSpeed("crouch") or nil
			if root and reference and s.loop and s.loop.IsPlaying then
				local v = root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				s.speed = (s.speed or speed) + (speed - (s.speed or speed)) * (1 - math.exp(-12 * dt))
				s.loop:AdjustSpeed(math.clamp(s.speed / reference, 0.2, 2.4))
			end
		end
	end)
end

return Others
