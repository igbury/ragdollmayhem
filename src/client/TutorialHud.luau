-- What the first-time tutorial (server/Tutorial) shows: the player's own tutorial dummies outlined in
-- yellow through walls (a Highlight each, gone once it is dead), a line at the top of the screen saying
-- what to do (the player's "TutorialStep" attribute) and the controls hints under it ("Hint"). When a
-- line changes, the old text shrinks away and the new one pops in. On a phone the steps name the
-- touch buttons, and the F-drag hints are left out (the GRAB button grabs, it does not drag).
-- After the tutorial a goal line top right, under the cash (client/CashHud), names the cheapest weapon not owned yet.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sfx = require(Shared:WaitForChild("Sfx"))
local Progression = require(Shared:WaitForChild("Progression"))
local Weapons = require(Shared:WaitForChild("Weapons"))
local TouchControls = require(script.Parent:WaitForChild("TouchControls")) -- active(): playing by touch

local TutorialHud = {}

local YELLOW = Color3.fromRGB(255, 214, 40)
local INK = Color3.fromRGB(20, 18, 26)

local function tween(o: Instance, t: number, goal, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal):Play()
end

function TutorialHud.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local function line(y: number, height: number, width: number, color: Color3, stroke: number): TextLabel
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, y)
		l.Size = UDim2.new(width, 0, 0, height)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Visible = false
		local outline = Instance.new("UIStroke") -- thicker than TextStroke can be
		outline.Thickness, outline.Color, outline.LineJoinMode = stroke, INK, Enum.LineJoinMode.Round
		outline.Parent = l
		Instance.new("UIScale").Parent = l
		l.Parent = gui
		return l
	end
	local label = line(70, 46, 0.7, YELLOW, 4) -- the tutorial's step
	local hintLabel = line(124, 34, 0.6, Color3.new(1, 1, 1), 3.5) -- the controls hints (server/Tutorial.event)

	-- Puts `text` on line `l` (nil clears it): what is on it shrinks away first, then the new text pops in.
	local tokens = {}
	local function setLine(l: TextLabel, text: string?)
		if l.Visible and l.Text == text then
			return
		end
		local token = (tokens[l] or 0) + 1
		tokens[l] = token
		local scale = l:FindFirstChildOfClass("UIScale") :: UIScale
		local function popIn()
			if tokens[l] ~= token then
				return -- a newer change has it
			end
			if text then
				l.Text, l.Visible = text, true
				scale.Scale = 0.3
				tween(scale, 0.28, { Scale = 1 }, Enum.EasingStyle.Back)
			else
				l.Visible = false
			end
		end
		if l.Visible then
			tween(scale, 0.12, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.13, popIn)
		else
			popIn()
		end
	end

	local HINTS = {
		grab = "Press F on a ragdoll to grab it",
		kick = "Look straight ahead and LEFT CLICK to kick it into a wall!",
		done = "Nice kick!",
	}
	local function showHint()
		setLine(hintLabel, if TouchControls.active() then nil else HINTS[player:GetAttribute("Hint")])
	end
	player:GetAttributeChangedSignal("Hint"):Connect(showHint)
	showHint()

	local STEPS = {
		kill = "Take out one of the glowing dummies!",
		pick = "Press Q to open your inventory, buy the HANDGUN and pick it",
	}
	local TOUCH_STEPS = {
		kill = "Tap ATTACK to take out a glowing dummy!",
		pick = "Tap the 🎒 backpack, buy the HANDGUN and pick it",
	}
	local COMPLETE = "TUTORIAL COMPLETE! Have fun."
	local wasOn = false
	local function show()
		local step = player:GetAttribute("TutorialStep")
		if wasOn then -- a step done (or the last one)
			Sfx.ui(Sfx.TUTORIAL_STEP, 0.6)
		end
		if step then
			setLine(label, (if TouchControls.active() then TOUCH_STEPS else STEPS)[step])
		elseif wasOn then -- just done
			setLine(label, COMPLETE)
			task.delay(4, function()
				if label.Text == COMPLETE then
					setLine(label, nil)
				end
			end)
		end
		wasOn = step ~= nil
	end
	player:GetAttributeChangedSignal("TutorialStep"):Connect(show)
	UserInputService.LastInputTypeChanged:Connect(function() -- a hybrid switched between touch and keys
		task.defer(function() -- after TouchControls has judged the new input
			if player:GetAttribute("TutorialStep") then
				setLine(label, (if TouchControls.active() then TOUCH_STEPS else STEPS)[player:GetAttribute("TutorialStep")])
			end
			showHint()
		end)
	end)

	-- The goal line: once the tutorial is done, the cheapest weapon not owned yet (the cash is client/CashHud).
	local goal = line(46, 26, 0.34, Color3.new(1, 1, 1), 3)
	goal.AnchorPoint, goal.Position = Vector2.new(1, 0), UDim2.new(1, -16, 0, 92) -- under the wanted stars and the cash (client/CashHud)
	goal.TextXAlignment = Enum.TextXAlignment.Right
	local function nextGoal(): string?
		if player:GetAttribute("Tutorial") ~= false then
			return nil -- not loaded, or still in the tutorial
		end
		local cash = player:GetAttribute(Progression.CASH) or 0
		local best, bestPrice = nil, math.huge
		for _, w in Weapons do
			local price = Progression.PRICE[w.id]
			if price and price < bestPrice and Progression.missing(player, w.id) then
				best, bestPrice = w, price
			end
		end
		if not best then
			return nil
		end
		return if cash >= bestPrice then `BUY {best.name}!` else `NEXT: {best.name} {bestPrice}$`
	end
	local function showGoal()
		local text = nextGoal()
		if text and goal.Visible and goal.Text ~= text then
			goal.Text = text -- the count went up: a little bump, no pop-out
			local scale = goal:FindFirstChildOfClass("UIScale") :: UIScale
			scale.Scale = 1.15
			tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			setLine(goal, text)
		end
	end
	player.AttributeChanged:Connect(function(attribute)
		if attribute == "Tutorial" or attribute == Progression.CASH or attribute:sub(1, 3) == "Own" or attribute:sub(1, 4) == "Pass" then
			showGoal()
		end
	end)
	showGoal()

	-- the outline: on a dummy marked for this player, until it dies
	local function watch(model: Instance)
		if not model:IsA("Model") then
			return
		end
		local function update()
			local mine = model:GetAttribute("TutorialFor") == player.UserId and model:GetAttribute("State") ~= "Dead"
			local h = model:FindFirstChild("TutorialOutline")
			if mine and not h then
				h = Instance.new("Highlight")
				h.Name = "TutorialOutline"
				h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- seen through walls
				h.OutlineColor, h.OutlineTransparency = YELLOW, 0
				h.FillColor, h.FillTransparency = YELLOW, 0.85
				h.Parent = model
			elseif h and not mine then
				h:Destroy()
			end
		end
		update()
		model:GetAttributeChangedSignal("State"):Connect(update)
		model:GetAttributeChangedSignal("TutorialFor"):Connect(update)
	end
	task.spawn(function()
		local folder = workspace:WaitForChild("Dummies")
		for _, model in folder:GetChildren() do
			watch(model)
		end
		folder.ChildAdded:Connect(watch)
	end)
	show()
end

return TutorialHud
