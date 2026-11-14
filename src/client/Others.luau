-- Other players' movement. The movement animations are built in memory on each client (see
-- SprintFlail and the rest) and the sounds are played locally, so neither replicates on its own.
-- Instead every client reports what its body is doing (init.client fires the Move remote), the
-- server passes that on, and this plays the same animation and sound on that player's character
-- here. Looks only: positions still replicate the normal way.
-- ponytail: someone who joins mid-move sees a player's loop from its next change on, not at once;
-- keep the last loop per player on the server and send it on join if that ever shows.

local Others = {}

-- looping looks, and the priority each plays at (as on the owner's client)
local LOOPS = {
	sprint = Enum.AnimationPriority.Movement,
	wall1 = Enum.AnimationPriority.Action,
	["wall-1"] = Enum.AnimationPriority.Action,
	cling = Enum.AnimationPriority.Action,
	slide = Enum.AnimationPriority.Action,
	crouch = Enum.AnimationPriority.Action,
	dive = Enum.AnimationPriority.Action4,
}
-- one-off moves and the sound that goes with each ("" = none); the animation, when there is one,
-- has the same name
local SHOTS = { roll = "", flip = "", kick = "Kick", jump = "Jump", slam = "Slam" }
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
				t.Priority = LOOPS[id] or Enum.AnimationPriority.Action4
				t.Looped = LOOPS[id] ~= nil
				s.tracks[id] = t
			end
			return s.tracks[id]
		end
		if kind == "loop" then
			if s.loop then
				s.loop:Stop(0.2)
			end
			s.loop = track(name)
			if s.loop then
				s.loop:Play(0.15)
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
				t:Play(0.05)
			end
			if SHOTS[name] ~= "" then
				sound(root, SHOTS[name]):Play()
			end
		end
	end)
end

return Others
