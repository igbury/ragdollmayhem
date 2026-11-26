-- The attacker's side of a fight, on this client only and purely for show: a combo counter by the
-- crosshair for blows that land in quick succession, and the KO moment (Fx.ko) when a dummy we just
-- hit goes out cold or dies (its "State", server hit()), or when a kill pays us (the Fx remote's
-- "Cash", server kill()) with no KO seen. Fx.ourHit reports each of our blows here (Fx.onOurHit).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fx = require(script.Parent:WaitForChild("Fx"))
local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))

local player = Players.LocalPlayer

local COMBO_WINDOW = 1.4 -- s between blows that still count as one combo
local KO_AFTER = 1.5 -- s after our blow in which the body going down is our KO
local KO_ONCE = 10 -- s a body's KO stands (out cold, then dead, is one KO)
local INK = Color3.fromRGB(20, 18, 26)
-- the counter's colour as the combo grows: x2 white .. x8+ red
local HEAT = {
	{ 2, Color3.fromRGB(255, 255, 255) },
	{ 3, Color3.fromRGB(255, 225, 70) },
	{ 5, Color3.fromRGB(255, 150, 40) },
	{ 8, Color3.fromRGB(255, 60, 50) },
}

local recent = setmetatable({}, { __mode = "k" }) -- [Model] = os.clock() of our last blow on it
local koAt = setmetatable({}, { __mode = "k" }) -- [Model] = os.clock() its KO played
local lastKo = -math.huge

-- Combo counter ---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name, gui.IgnoreGuiInset, gui.ResetOnSpawn, gui.DisplayOrder = "HitCombo", true, false, 6
local label = Instance.new("TextLabel")
label.AnchorPoint, label.Position, label.Size = Vector2.new(0, 0.5), UDim2.new(0.5, 30, 0.5, 30), UDim2.fromOffset(150, 46)
label.BackgroundTransparency, label.Font, label.TextSize = 1, Enum.Font.Bangers, 40
label.TextXAlignment, label.Rotation, label.Visible = Enum.TextXAlignment.Left, -7, false
local stroke = Instance.new("UIStroke")
stroke.Thickness, stroke.Color, stroke.LineJoinMode = 3, INK, Enum.LineJoinMode.Round
stroke.Parent = label
local pop = Instance.new("UIScale")
pop.Parent = label
label.Parent = gui
gui.Parent = player:WaitForChild("PlayerGui")

local POP = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local combo, lastHit, comboToken = 0, -math.huge, 0
local fadeTween: Tween? = nil

local function fadeOut(token: number)
	if token ~= comboToken then
		return -- another blow since: the combo goes on
	end
	combo = 0
	local tween = TweenService:Create(label, FADE, { TextTransparency = 1 })
	tween.Completed:Once(function()
		if token == comboToken then
			label.Visible = false
		end
	end)
	tween:Play()
	fadeTween = tween
end

local function count()
	local now = os.clock()
	combo = if now - lastHit <= COMBO_WINDOW then combo + 1 else 1
	lastHit = now
	comboToken += 1
	if combo < 2 then
		return
	end
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
	local color = HEAT[1][2]
	for _, h in HEAT do
		if combo >= h[1] then
			color = h[2]
		end
	end
	label.Text = `x{combo}`
	label.TextColor3, label.TextTransparency, stroke.Transparency, label.Visible = color, 0, 0, true
	label.Rotation = -7 + (combo % 2) * 4 -- a little tilt each step, so a new number reads as new
	pop.Scale = 1.35 + math.min(combo, 10) * 0.03
	TweenService:Create(pop, POP, { Scale = 1 }):Play()
	task.delay(COMBO_WINDOW, fadeOut, comboToken)
end

-- KO --------------------------------------------------------------------------------
local function ko(position: Vector3, victim: Model?, quiet: boolean?)
	lastKo = os.clock()
	Fx.ko(position, victim, quiet)
	-- a heavy, low thump under the comic word (existing clips only: Sfx.VARY keeps them from repeating)
	Sfx.playLocal({ Sfx.BODY_THUD, 0.75, 1 }, position)
	Sfx.playLocal({ Sfx.PUNCH, 0.6, 0.9 }, position)
end

local function middle(model: Model): Vector3?
	local part = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Head") or model.PrimaryPart) :: BasePart?
	return part and part.Position
end

local function stateChanged(model: Model)
	local state = model:GetAttribute("State")
	if state ~= "Out cold" and state ~= "Dead" then
		return
	end
	local now = os.clock()
	local hitAt = recent[model]
	if not hitAt or now - hitAt > KO_AFTER or (koAt[model] and now - koAt[model] < KO_ONCE) then
		return
	end
	local at = middle(model)
	if at then
		koAt[model] = now
		ko(at, model)
	end
end

Fx.onOurHit = function(_, _, victim: Model)
	recent[victim] = os.clock()
	count()
end

local dummies = workspace:WaitForChild("Dummies")
local function watch(model: Instance)
	if model:IsA("Model") then
		model:GetAttributeChangedSignal("State"):Connect(function()
			stateChanged(model)
		end)
	end
end
for _, model in dummies:GetChildren() do
	watch(model)
end
dummies.ChildAdded:Connect(watch)

-- A kill that paid us with no KO of ours on that body (a throw, a fall, a bleed-out): the word and the
-- stars. The server pays before the body's "Dead" state reaches us, so wait a moment for that KO first.
local function paid(position: Vector3)
	local now = os.clock()
	if now - lastKo < 0.5 or (workspace.CurrentCamera.CFrame.Position - position).Magnitude > 150 then
		return
	end
	for model, at in koAt do
		local p = now - at < KO_ONCE and middle(model)
		if p and (p - position).Magnitude < 6 then
			return -- the body we already knocked out: no second KO for finishing it
		end
	end
	ko(position, nil, true)
end
ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Fx").OnClientEvent:Connect(function(id: string, _, position: Vector3)
	if id == "Cash" and typeof(position) == "Vector3" then
		task.delay(0.3, paid, position)
	end
end)

return {}
