-- What a dummy does with its arms and spine when it is hurt or scared. The server only names the
-- pose (attributes "Arms" and "Lean" on the dummy, see express() in the server script); every
-- client plays it here as a held animation on that dummy, on top of its idle and walk.
--
-- The poses are worked out, not guessed: the arm angles come from solving the rig's own joint
-- positions for a hand that lies ON the body at the named spot with the elbow, forearm and wrist
-- all kept outside the torso and head (the arm folds round the chest instead of through it). An
-- arm with no pose is left to the idle animation: hanging at the side.
-- Signs, as in HighKick: shoulder +X raises the arm forward, elbow +X bends it; a torso or head
-- -X bends forward, +Z leans left.
-- ponytail: built in memory like the other animations here (no upload), so they play in Studio
-- only; upload them and use the asset ids before publishing.
local keyframeId = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("KeyframeId"))

local DummyPoses = {}

-- right arm: { shoulder x, y, z, elbow } in degrees; the left arm mirrors it (y and z flip)
local ARMS = {
	chest = { -39, 62, 82, 89 }, -- palm on the chest, own side of the middle
	hold = { 56, 85, 2, 73 }, -- forearm across the front of the chest, hand as far over as the arm reaches
	belly = { -21, 65, 24, 49 },
	head = { 93, 46, 33, 80 }, -- hand to the side of the head
	up = { 133, 23, 16, 32 }, -- hands up
}
-- spine: { waist x, y, z, neck x, y, z } in degrees
local LEANS = {
	doubled = { -24, 0, 0, -16, 0, 0 }, -- bent over a wound in the body
	favourleft = { -7, 0, 8, -10, 0, 8 }, -- curled toward a hurt left arm
	favourright = { -7, 0, -8, -10, 0, -8 },
	head = { -8, 0, 0, -18, 0, 12 },
	drowsy = { -10, 0, 3, -28, 0, 0 }, -- head hanging
	sore = { -12, 0, 0, -6, 0, 0 }, -- broken ribs
	limp = { -4, 0, 7, 0, 0, 0 },
	scared = { 8, 0, 0, 6, 0, 0 }, -- leaning away
}

local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm",
}
local ORDER = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- A looping animation that holds `poses` ({ [part name] = CFrame }) and leaves every other
-- joint alone.
local function hold(name: string, poses: { [string]: CFrame }): Animation
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = true
	sequence.Priority = Enum.AnimationPriority.Action2
	for _, t in { 0, 1 } do
		local frame = Instance.new("Keyframe")
		frame.Time = t
		local byName = {}
		for _, part in ORDER do
			local pose = Instance.new("Pose")
			pose.Name = part
			pose.CFrame = poses[part] or CFrame.identity
			pose.Weight = poses[part] and 1 or 0 -- 0: only there to carry its children
			pose.Parent = byName[PARENT[part]] or frame
			byName[part] = pose
		end
		frame.Parent = sequence
	end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = keyframeId(sequence)
	return animation
end

local anims = {} -- ["Right:chest"], ["Left:chest"], ..., ["lean:doubled"], ...
for name, a in ARMS do
	anims["Right:" .. name] = hold("Right" .. name, { RightUpperArm = rot(a[1], a[2], a[3]), RightLowerArm = rot(a[4], 0, 0) })
	anims["Left:" .. name] = hold("Left" .. name, { LeftUpperArm = rot(a[1], -a[2], -a[3]), LeftLowerArm = rot(a[4], 0, 0) })
end
for name, l in LEANS do
	anims["lean:" .. name] = hold("Lean" .. name, { UpperTorso = rot(l[1], l[2], l[3]), Head = rot(l[4], l[5], l[6]) })
end

local FADE = 0.3
local playing = setmetatable({}, { __mode = "k" }) -- [dummy] = { [slot] = { id = string, track = AnimationTrack } }

local function set(model: Model, slot: string, id: string?)
	local slots = playing[model]
	if not slots then
		slots = {}
		playing[model] = slots
	end
	local now = slots[slot]
	if (now and now.id) == id then
		return
	end
	if now then
		now.track:Stop(FADE)
		slots[slot] = nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if id and anims[id] and animator then
		local track = animator:LoadAnimation(anims[id])
		track.Priority = Enum.AnimationPriority.Action2
		track.Looped = true
		track:Play(FADE)
		slots[slot] = { id = id, track = track }
	end
end

local function update(model: Model)
	-- "Arms" is e.g. "Left:chest;Right:chest", "Right:hold" or ""
	local arms = {}
	for side, pose in (model:GetAttribute("Arms") or ""):gmatch("(%a+):(%a+)") do
		arms[side] = side .. ":" .. pose
	end
	set(model, "Left", arms.Left)
	set(model, "Right", arms.Right)
	local lean = model:GetAttribute("Lean") or ""
	set(model, "lean", lean ~= "" and "lean:" .. lean or nil)
end

function DummyPoses.start(folder: Instance)
	local function watch(model: Instance)
		if not model:IsA("Model") then
			return
		end
		model:GetAttributeChangedSignal("Arms"):Connect(function()
			update(model)
		end)
		model:GetAttributeChangedSignal("Lean"):Connect(function()
			update(model)
		end)
		task.defer(update, model)
	end
	folder.ChildAdded:Connect(watch)
	for _, model in folder:GetChildren() do
		watch(model)
	end
end

return DummyPoses
