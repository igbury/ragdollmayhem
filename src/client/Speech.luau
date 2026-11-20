-- Comic speech bubbles over dummies. The server sets Say / SayKind / SayId on the dummy model;
-- the bubble is built here so it can pop in and out smoothly. Images: assets/fx/make_bubbles.py.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Sfx"))
local rng = Random.new()

local Speech = {}

local SHOW_TIME = 2.5
local VOICE_GAP = 3 -- seconds between one dummy's voices (calibration knob)
local VOICE_RANGE = 60 -- studs from the camera within which bubbles are voiced
-- image, text box (centre x, y, size x, y as fractions of the 600x400 image)
local KINDS = {
	talk = { "rbxassetid://95011473481258", 0.517, 0.41, 0.68, 0.5, Enum.Font.Cartoon },
	shout = { "rbxassetid://92216727332232", 0.508, 0.44, 0.5, 0.38, Enum.Font.Bangers },
	think = { "rbxassetid://139047343430895", 0.517, 0.425, 0.64, 0.48, Enum.Font.Cartoon },
}
local POP_IN = {
	talk = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	shout = TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
	think = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local function show(model: Model, text: string, kind: string): BillboardGui?
	local part = model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso")
	if not part then
		return nil
	end
	local k = KINDS[kind] or KINDS.talk
	local w = math.clamp(3 + #text * 0.09, 4, 7.5) * (kind == "shout" and 1.15 or 1)
	local h = w * 400 / 600
	local gui = Instance.new("BillboardGui")
	gui.Adornee = part
	gui.Size = UDim2.fromScale(w, h)
	gui.StudsOffset = Vector3.new(0.38 * w, 1 + 0.4 * h, 0) -- the tail ends just above the head
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local pop = Instance.new("Frame") -- scales and tilts from the tail corner
	pop.BackgroundTransparency = 1
	pop.AnchorPoint = Vector2.new(0.12, 0.9)
	pop.Position = UDim2.fromScale(0.12, 0.9)
	pop.Size = UDim2.fromScale(1, 1)
	pop.Rotation = -12
	pop.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = pop
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = k[1]
	image.Parent = pop
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(k[2], k[3])
	label.Size = UDim2.fromScale(k[4], k[5])
	label.Font = k[6]
	label.Text = kind == "shout" and text:upper() or text
	label.TextColor3 = Color3.fromRGB(20, 20, 20)
	label.TextScaled = true
	label.TextWrapped = true
	label.ZIndex = 2
	label.Parent = pop
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local info = POP_IN[kind] or POP_IN.talk
	TweenService:Create(scale, info, { Scale = 1 }):Play()
	TweenService:Create(pop, info, { Rotation = math.random(-4, 4) }):Play()
	return gui
end

local function hide(gui: BillboardGui)
	local pop = gui:FindFirstChildOfClass("Frame")
	local scale = pop and pop:FindFirstChildOfClass("UIScale")
	if not scale then
		gui:Destroy()
		return
	end
	local t = TweenService:Create(scale, POP_OUT, { Scale = 0 })
	t.Completed:Connect(function()
		gui:Destroy()
	end)
	t:Play()
end

function Speech.start(folder: Instance)
	local function watch(model: Instance)
		if not model:IsA("Model") then
			return
		end
		local current: BillboardGui? = nil
		local voicedAt = 0
		model:GetAttributeChangedSignal("SayId"):Connect(function()
			if current then
				hide(current)
			end
			local text = model:GetAttribute("Say")
			local kind = model:GetAttribute("SayKind") or "talk"
			current = if text then show(model, text, kind) else nil
			-- the voice under the bubble: gibberish (a zombie groans), each dummy a little higher or lower;
			-- near the camera only and not more than once per VOICE_GAP, or a crowd is one long babble
			local voice = Sfx.VOICE[kind] or Sfx.VOICE.talk
			local head = text and (model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso")) :: BasePart?
			local camera = workspace.CurrentCamera
			if head and os.clock() - voicedAt > VOICE_GAP and camera
				and (camera.CFrame.Position - head.Position).Magnitude < VOICE_RANGE then
				voicedAt = os.clock()
				local id = if typeof(voice) == "table" then voice[rng:NextInteger(1, #voice)] else voice
				Sfx.playLocal({ id, rng:NextNumber(0.85, 1.15), 0.45 }, head.Position)
			end
			local mine = current
			task.delay(SHOW_TIME, function()
				if mine and current == mine then
					hide(mine)
					current = nil
				end
			end)
		end)
		model.Destroying:Connect(function()
			if current then
				current:Destroy()
			end
		end)
	end
	folder.ChildAdded:Connect(watch)
	for _, model in folder:GetChildren() do
		watch(model)
	end
end

return Speech
