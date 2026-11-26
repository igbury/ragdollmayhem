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
local Stickers = require(Shared:WaitForChild("Stickers"))
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
		punch = "Walk up to it and LEFT CLICK to punch!",
		grab = "Press F on a ragdoll to grab it",
		kick = "Look straight ahead and LEFT CLICK to kick it into a wall!",
		done = "Nice kick!",
	}
	-- The punch hint: only for whoever has not landed a blow PUNCH_HINT_AFTER s into the first step
	-- (most have by then; research: docs/research/pierwsze-5-minut.md). The server sets "HasHit".
	local PUNCH_HINT_AFTER = 6
	local killSince: number? = nil
	local function showHint() -- not over the Arsenal step: one instruction at a time
		local step = player:GetAttribute("TutorialStep")
		local quiet = TouchControls.active() or step == "pick"
		local hint = player:GetAttribute("Hint")
		if hint == nil and step == "kill" and not player:GetAttribute("HasHit") and killSince and os.clock() - killSince >= PUNCH_HINT_AFTER - 0.05 then
			hint = "punch"
		end
		setLine(hintLabel, if quiet then nil else HINTS[hint])
	end
	player:GetAttributeChangedSignal("Hint"):Connect(showHint)
	player:GetAttributeChangedSignal("HasHit"):Connect(showHint)
	local function stepChanged()
		if player:GetAttribute("TutorialStep") == "kill" and not killSince then
			killSince = os.clock()
			task.delay(PUNCH_HINT_AFTER, showHint)
		end
		showHint()
	end
	player:GetAttributeChangedSignal("TutorialStep"):Connect(stepChanged)
	stepChanged()

	-- FirstSession "FirstMove" (server/Funnels): the first step taken on a map
	task.spawn(function()
		local action = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Action")
		while true do
			task.wait(0.25)
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and player:GetAttribute("Map") and hum.MoveDirection.Magnitude > 0.1 then
				action:FireServer("fs", "FirstMove")
				return
			end
		end
	end)

	local STEPS = {
		kill = "Take out one of the glowing dummies!",
		pick = "Press Q: buy the HANDGUN, then EQUIP it",
	}
	local TOUCH_STEPS = {
		kill = "Tap ATTACK to take out a glowing dummy!",
		pick = "Tap 🎒: buy the HANDGUN, then EQUIP it",
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
	-- and under it a bar filling with the cash towards that weapon's price, green once it can be bought
	local GREEN = Color3.fromRGB(110, 230, 90)
	local track = Instance.new("Frame")
	track.AnchorPoint, track.Position, track.Size = Vector2.new(1, 0), UDim2.new(1, -16, 0, 122), UDim2.new(0.16, 0, 0, 8)
	track.BackgroundColor3, track.BorderSizePixel, track.Visible = INK, 0, false
	local trackLine = Instance.new("UIStroke")
	trackLine.Thickness, trackLine.Color = 2, INK
	trackLine.Parent = track
	local fill = Instance.new("Frame")
	fill.Size, fill.BackgroundColor3, fill.BorderSizePixel = UDim2.fromScale(0, 1), YELLOW, 0
	fill.Parent = track
	track.Parent = gui
	-- text, and how far the cash has got to the price (0..1); nil when there is no goal
	local function nextGoal(): (string?, number?)
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
		local ratio = math.clamp(cash / bestPrice, 0, 1)
		return if cash >= bestPrice then `BUY {best.name}!` else `NEXT: {best.name} {math.floor(cash)}/{bestPrice}$`, ratio
	end
	local function showGoal()
		local text, ratio = nextGoal()
		track.Visible = text ~= nil
		if ratio then
			fill.BackgroundColor3 = if ratio >= 1 then GREEN else YELLOW
			tween(fill, 0.3, { Size = UDim2.fromScale(ratio, 1) })
		end
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

	-- The controls of the weapon just taken out, for a few seconds under the tutorial's lines (as
	-- init.client reads the input: right mouse / AIM aims, holds the block, shows the throw arc...).
	local controls = line(164, 28, 0.6, Color3.new(1, 1, 1), 3)
	local function controlsOf(w, touch: boolean): string?
		local A, HA = if touch then "Tap ATTACK" else "Click", if touch then "Hold ATTACK" else "Hold click"
		local M = if touch then "AIM" else "Right click"
		local by = {
			Fists = `{A}: punch · {HA}: keep punching`,
			BoxingGloves = `{HA}: punch · {M}: block · Block + {A}: heavy left`,
			Knife = `{A}: slash · {M} + {A}: throw it`,
			Spear = `{A}: thrust, skewers up to three`,
			Bow = `{HA} to draw, let go to shoot`,
			C4 = `{A}: stick a charge · {M}: BOOM`,
			Landmine = `{A}: put it down · it goes off when they step close`,
			Lasso = `{A}: throw the rope · {M}: let go`,
			Chainsaw = `{HA}: saw`,
			Flamethrower = `{HA}: spray fire · {M}: aim`,
			Minigun = `{HA}: spin up and fire · {M}: aim`,
		}
		if by[w.id] then
			return by[w.id]
		elseif w.kind == "melee" and w.aimSwing then
			return if touch then `{A}: swing` else "Hold click and move the mouse to aim the swing, let go to hit"
		elseif w.kind == "melee" then
			return if w.auto then `{HA}: keep going` else `{A}: swing`
		elseif w.kind == "gun" or w.kind == "rocket" then
			return `{if w.auto then HA else A}: fire · {M}: aim`
		elseif w.kind == "thrown" then
			return `{A}: throw · {M}: see where it lands`
		end
		return nil
	end
	local controlsToken = 0
	local controlsShown = {} -- weapon id -> its controls were already shown
	local function showControls()
		local char = player.Character
		local id = char and char:GetAttribute("EquippedWeapon")
		local w
		for _, each in Weapons do
			if each.id == id then
				w = each
			end
		end
		-- not under the menu (client/Menu): its PLAY walk-off runs with the character already on the map
		local menuUp = player.PlayerGui:FindFirstChild("Menu") ~= nil
		local text = w and not controlsShown[w.id] and player:GetAttribute("Map") and not menuUp and controlsOf(w, TouchControls.active())
		if text then
			controlsShown[w.id] = true -- each weapon's controls once a session
		end
		controlsToken += 1
		local token = controlsToken
		setLine(controls, text or nil)
		task.delay(if player:GetAttribute("TutorialStep") then 4 else 2, function() -- longer for a first-timer
			if controlsToken == token then
				setLine(controls, nil)
			end
		end)
	end
	local function watchCharacter(char: Model)
		char:GetAttributeChangedSignal("EquippedWeapon"):Connect(showControls)
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	player:GetAttributeChangedSignal("Map"):Connect(showControls) -- into a map from the menu: what is in hand
	player.PlayerGui.ChildRemoved:Connect(function(child) -- the menu's cut to the game
		if child.Name == "Menu" then
			showControls()
		end
	end)

	-- Stickers (shared/Stickers): the current challenge, the first one not earned, under the goal bar;
	-- and a pop in the middle of the screen when one is earned (its cash is already in, server/Progress).
	local challenge = line(136, 22, 0.34, Color3.fromRGB(150, 230, 255), 3)
	challenge.AnchorPoint, challenge.Position = Vector2.new(1, 0), UDim2.new(1, -16, 0, 136)
	challenge.TextXAlignment = Enum.TextXAlignment.Right
	local earned = line(210, 40, 0.6, Color3.fromRGB(120, 240, 110), 4)
	local function wording(sticker): string
		return if TouchControls.active() and sticker.touch then sticker.touch else sticker.text
	end
	local function showChallenge()
		local text
		if player:GetAttribute("Tutorial") == false then
			local touch = TouchControls.active()
			for _, sticker in Stickers.LIST do
				if not player:GetAttribute(Stickers.attribute(sticker.id)) and not (touch and sticker.keys) then
					text = `CHALLENGE: {wording(sticker)} +{sticker.cash}$`
					break
				end
			end
		end
		setLine(challenge, text)
	end
	UserInputService.LastInputTypeChanged:Connect(function()
		task.defer(showChallenge) -- after TouchControls has judged it (as the tutorial lines above)
	end)
	-- several at once (a rocket: the blast and a limb) are shown one after another, not over each other
	local queue, showing = {}, false
	local function nextEarned()
		local text = table.remove(queue, 1)
		showing = text ~= nil
		if not text then
			setLine(earned, nil)
			return
		end
		Sfx.ui(Sfx.TUTORIAL_STEP, 0.8)
		setLine(earned, text)
		task.delay(if #queue > 0 then 2 else 3.5, nextEarned)
	end
	local function announce(text: string)
		table.insert(queue, text)
		if not showing then
			nextEarned()
		end
	end
	-- the daily reward (server/Progress.daily), once in a map: paid while still in the menu, it waits
	local dailyShown = false
	local function showDaily()
		local cash = player:GetAttribute("DailyCash")
		if dailyShown or not cash or not player:GetAttribute("Map") then
			return
		end
		dailyShown = true
		announce(`DAY {player:GetAttribute("DailyStreak") or 1} REWARD +{cash}$ · TOMORROW +{player:GetAttribute("DailyNext") or cash}$`)
	end
	player:GetAttributeChangedSignal("DailyCash"):Connect(showDaily)
	player:GetAttributeChangedSignal("Map"):Connect(showDaily)
	showDaily()
	-- the ones the save brought, known once it is in: only stickers earned after that pop up (the save's
	-- attributes and ProgressLoaded can reach the client in one batch, so that flag alone is no guard)
	local known: { [string]: boolean }? = nil
	task.spawn(function()
		while not player:GetAttribute("ProgressLoaded") do
			player:GetAttributeChangedSignal("ProgressLoaded"):Wait()
		end
		task.wait(1) -- the rest of the batch
		local seen = {}
		for _, sticker in Stickers.LIST do
			seen[sticker.id] = player:GetAttribute(Stickers.attribute(sticker.id)) == true
		end
		known = seen
	end)
	player.AttributeChanged:Connect(function(attribute)
		if attribute == "Tutorial" then
			showChallenge()
		elseif attribute:sub(1, 7) == "Sticker" then
			local sticker = Stickers.get(attribute:sub(8))
			if sticker and known and not known[sticker.id] and player:GetAttribute(attribute) then
				known[sticker.id] = true
				announce(`STICKER! {wording(sticker)} +{sticker.cash}$`)
			end
			showChallenge()
		end
	end)
	showChallenge()

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
