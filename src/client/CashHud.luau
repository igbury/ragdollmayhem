-- The cash counter, top right under the wanted stars: Grow an Egg's cash-stack icon and the player's
-- "Cash" (shared/Progression, kept by server/Progress). Shown only in a map (the "Map" attribute),
-- not in the menu. A kill (server: the Fx remote's "Cash", body position, cash paid) bursts a few
-- bills out of the body on screen with a "+N", then they fly into the counter, which counts the cash
-- in as they land and pops.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))

local CashHud = {}

local ICON = "rbxassetid://94966977849477" -- Grow an Egg's cash_small (its shared/UiArt)
local GREEN = Color3.fromRGB(110, 235, 90)
local INK = Color3.fromRGB(20, 18, 26)
local HEIGHT = 40
local BILLS = 6 -- bills per kill
local BILL = 30 -- their size in px
local BURST_TIME = 0.28 -- out of the body
local FLY_TIME = 0.45 -- into the counter (staggered a little per bill)

local function format(n: number): string -- 12345 -> "12,345"
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function CashHud.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "CashHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local row = Instance.new("Frame")
	row.Name = "Cash"
	row.AnchorPoint, row.Position = Vector2.new(1, 0), UDim2.new(1, -16, 0, 46) -- under the wanted stars (WantedHud)
	row.Size, row.AutomaticSize = UDim2.fromOffset(0, HEIGHT), Enum.AutomaticSize.X
	row.BackgroundTransparency = 1
	row.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection, list.HorizontalAlignment = Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right
	list.VerticalAlignment, list.Padding = Enum.VerticalAlignment.Center, UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	local scale = Instance.new("UIScale")
	scale.Parent = row

	local amount = Instance.new("TextLabel")
	amount.LayoutOrder = 1
	amount.Size, amount.AutomaticSize = UDim2.fromOffset(0, HEIGHT - 6), Enum.AutomaticSize.X
	amount.BackgroundTransparency = 1
	amount.Font, amount.TextSize, amount.TextColor3 = Enum.Font.FredokaOne, HEIGHT - 8, GREEN
	amount.Parent = row
	local stroke = Instance.new("UIStroke")
	stroke.Thickness, stroke.Color, stroke.LineJoinMode = 3, INK, Enum.LineJoinMode.Round
	stroke.Parent = amount

	local icon = Instance.new("ImageLabel")
	icon.LayoutOrder = 2
	icon.Size = UDim2.fromOffset(HEIGHT, HEIGHT)
	icon.BackgroundTransparency = 1
	icon.Image = ICON
	icon.Parent = row

	local pending = 0 -- cash still flying in: the counter shows it once it lands
	local shown = player:GetAttribute(Progression.CASH) or 0
	local function update()
		local cash = math.max(0, (player:GetAttribute(Progression.CASH) or 0) - pending)
		amount.Text = format(cash)
		if cash > shown then
			scale.Scale = 1.2
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		shown = cash
	end

	local function tween(o: Instance, t: number, goal, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
		local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
		tw:Play()
		return tw
	end
	local function burst(position: Vector3, paid: number)
		local camera = workspace.CurrentCamera
		local at, onScreen = camera:WorldToScreenPoint(position) -- GUI space (the top bar left out)
		if not row.Visible or not onScreen then
			return -- the counter takes it at once
		end
		pending += paid
		local from = Vector2.new(at.X, at.Y)
		local plus = Instance.new("TextLabel")
		plus.AnchorPoint, plus.Position, plus.Size = Vector2.new(0.5, 1), UDim2.fromOffset(from.X, from.Y), UDim2.fromOffset(120, 30)
		plus.BackgroundTransparency, plus.Text = 1, `+{paid}`
		plus.Font, plus.TextSize, plus.TextColor3 = Enum.Font.FredokaOne, 28, GREEN
		local ps = Instance.new("UIStroke")
		ps.Thickness, ps.Color = 3, INK
		ps.Parent = plus
		plus.Parent = gui
		tween(plus, 0.7, { Position = UDim2.fromOffset(from.X, from.Y - 50), TextTransparency = 1 })
		tween(ps, 0.7, { Transparency = 1 })
		task.delay(0.7, plus.Destroy, plus)
		local left = BILLS
		for i = 1, BILLS do
			local bill = Instance.new("ImageLabel")
			bill.AnchorPoint, bill.Position = Vector2.new(0.5, 0.5), UDim2.fromOffset(from.X, from.Y)
			bill.Size, bill.BackgroundTransparency, bill.Image = UDim2.fromOffset(BILL * 0.4, BILL * 0.4), 1, ICON
			bill.Rotation = math.random(-40, 40)
			bill.Parent = gui
			local a = (i / BILLS + math.random() * 0.15) * math.pi * 2
			local out = from + Vector2.new(math.cos(a), math.sin(a) * 0.7 - 0.5) * math.random(45, 85)
			tween(bill, BURST_TIME, { Position = UDim2.fromOffset(out.X, out.Y), Size = UDim2.fromOffset(BILL, BILL), Rotation = math.random(-25, 25) }, Enum.EasingStyle.Back)
			task.delay(BURST_TIME + i * 0.04, function()
				local target = icon.AbsolutePosition + icon.AbsoluteSize / 2
				local fly = tween(bill, FLY_TIME, { Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(BILL * 0.6, BILL * 0.6), Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				fly.Completed:Once(function()
					bill:Destroy()
					left -= 1
					if left == 0 then -- the last one in: the counter takes the cash
						pending -= paid
						update()
					end
				end)
			end)
		end
	end
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx").OnClientEvent:Connect(function(id: string, _, position: Vector3, paid: number)
		if id == "Cash" and typeof(position) == "Vector3" and type(paid) == "number" then
			burst(position, paid)
		end
	end)
	local function showRow()
		row.Visible = player:GetAttribute("Map") ~= nil
	end
	player:GetAttributeChangedSignal(Progression.CASH):Connect(function()
		task.delay(0.1, update) -- the kill's "Cash" event comes right after: let it count the cash as flying first
	end)
	player:GetAttributeChangedSignal("Map"):Connect(showRow)
	update()
	showRow()
end

return CashHud
