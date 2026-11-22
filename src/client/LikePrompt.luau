-- A polite "like the game?" card, top centre. Nothing is locked behind it and nothing is given for
-- it (Roblox forbids rewarding likes, and cannot check one anyway). It shows when the saved play
-- time (StatPlaytime, server/Progress) passes one of ASK_AT during this session, so each player
-- sees it at most once per mark, ever, with no extra save. Gone on OK or after SHOW_TIME.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Sfx"))

local player = Players.LocalPlayer
local ASK_AT = { 600, 3600 } -- seconds played
local SHOW_TIME = 12
local INK = Color3.fromRGB(16, 15, 20)
local PAPER = Color3.fromRGB(255, 248, 228)
local CAPTION = Color3.fromRGB(252, 200, 50)
local COMIC = Enum.Font.LuckiestGuy

local gui = Instance.new("ScreenGui")
gui.Name = "LikePrompt"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local function inked(parent: Instance, thickness: number)
	local line = Instance.new("UIStroke")
	line.Thickness, line.Color, line.LineJoinMode = thickness, INK, Enum.LineJoinMode.Miter
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = parent
end

local function label(parent: Instance, text: string, y: number, h: number, font: Enum.Font, color: Color3)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position, t.Size = UDim2.fromOffset(16, y), UDim2.new(1, -32, 0, h)
	t.Font, t.Text, t.TextColor3, t.TextScaled = font, text, color, true
	t.Parent = parent
	return t
end

local function show()
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Size = UDim2.fromOffset(360, 150)
	card.Position = UDim2.new(0.5, 0, 0, -170)
	card.BackgroundTransparency = 1
	card.Rotation = -1.5
	card.Parent = gui
	local shadow = Instance.new("Frame")
	shadow.Size, shadow.Position = UDim2.fromScale(1, 1), UDim2.fromOffset(7, 8)
	shadow.BackgroundColor3, shadow.BorderSizePixel = INK, 0
	shadow.Parent = card
	local paper = Instance.new("Frame")
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3, paper.BorderSizePixel = PAPER, 0
	paper.Parent = card
	inked(paper, 4)
	label(paper, "HAVING FUN? 👍", 10, 36, COMIC, INK)
	label(paper, "A like on the game page really helps us keep adding weapons!", 50, 40, Enum.Font.GothamBold, INK)
	local ok = Instance.new("TextButton")
	ok.AnchorPoint = Vector2.new(0.5, 0)
	ok.Position, ok.Size = UDim2.new(0.5, 0, 0, 100), UDim2.fromOffset(120, 36)
	ok.BackgroundColor3, ok.BorderSizePixel = CAPTION, 0
	ok.Font, ok.Text, ok.TextColor3, ok.TextSize = COMIC, "OK!", INK, 26
	ok.Parent = paper
	inked(ok, 3)

	Sfx.ui(Sfx.UI_NOTIFICATION, 0.6)
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(card, info, { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		local away = TweenService:Create(card, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -170) })
		away.Completed:Once(function()
			card:Destroy()
		end)
		away:Play()
	end
	ok.Activated:Connect(close)
	task.delay(SHOW_TIME, close)
end

-- the saved play time arrives with ProgressLoaded; only what is played after that counts
if not player:GetAttribute("ProgressLoaded") then
	player:GetAttributeChangedSignal("ProgressLoaded"):Wait()
end
local last = player:GetAttribute("StatPlaytime") or 0
player:GetAttributeChangedSignal("StatPlaytime"):Connect(function()
	local now = player:GetAttribute("StatPlaytime") or 0
	for _, mark in ASK_AT do
		if last < mark and now >= mark then
			show()
			break
		end
	end
	last = now
end)

return nil
