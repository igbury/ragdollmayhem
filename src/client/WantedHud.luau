-- The wanted stars (server: Wanted, player attribute "Wanted" 0..5), top right. A star that was
-- just earned pops in; while any are lit they pulse, so a chase reads at a glance.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 206, 60)
local OFF = Color3.fromRGB(40, 40, 46)

local gui = Instance.new("ScreenGui")
gui.Name = "WantedHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
local row = Instance.new("Frame")
row.AnchorPoint, row.Position, row.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 10), UDim2.fromOffset(5 * 30, 30)
row.BackgroundTransparency = 1
row.Parent = gui
local stars = {}
for i = 1, 5 do
	local star = Instance.new("TextLabel")
	star.Size, star.Position = UDim2.fromOffset(30, 30), UDim2.fromOffset((i - 1) * 30, 0)
	star.BackgroundTransparency = 1
	star.Font = Enum.Font.GothamBlack
	star.Text = "★"
	star.TextSize = 28
	star.TextColor3 = OFF
	star.TextTransparency = 0.45
	star.TextStrokeTransparency = 0.2
	star.TextStrokeColor3 = Color3.fromRGB(15, 15, 18)
	star.Parent = row
	stars[i] = star
end
gui.Parent = player:WaitForChild("PlayerGui")

local shown = 0
local function update()
	local n = player:GetAttribute("Wanted") or 0
	for i, star in stars do
		local on = i <= n
		star.TextColor3, star.TextTransparency = on and GOLD or OFF, on and 0 or 0.45
		if on and i > shown then -- just earned: pop
			star.TextSize = 44
			TweenService:Create(star, TweenInfo.new(0.35, Enum.EasingStyle.Back), { TextSize = 28 }):Play()
		end
	end
	row.Visible = n > 0
	shown = n
end
player:GetAttributeChangedSignal("Wanted"):Connect(update)
update()

RunService.RenderStepped:Connect(function()
	if shown > 0 then
		local pulse = (math.sin(os.clock() * 6) + 1) / 2
		for i = 1, shown do
			stars[i].TextColor3 = GOLD:Lerp(Color3.new(1, 1, 1), pulse * 0.35)
		end
	end
end)

return nil
