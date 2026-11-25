-- Touch screen controls: round buttons around Roblox's jump button (ATTACK held like the mouse, AIM a
-- toggle, DASH, GRAB, VIEW), and a mode pill on top of them:
--  * EASY (the default, the TouchSimple setting): aim assist (shots bend to a dummy just off the
--    crosshair, the view drifts onto it while attacking or aiming), always running, and the plain
--    jump only: no double jump, wall run, cling, slide or slam (init.client asks mv.simple()).
--  * PRO: every move, with RUN / SLIDE buttons of their own (SLAM is cut for now, init.client mv.cut).
-- The buttons press init.client's own input handlers (mv.began / mv.ended) with a stand-in input,
-- so a touch does exactly what the mouse and keys do. Roblox's own action buttons for those moves
-- (ContextActionService) are hidden: these take their place.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Music = require(script.Parent:WaitForChild("Music")) -- the settings (shared/Settings)
local Menu = require(script.Parent:WaitForChild("Menu"))

local TouchControls = {}

-- Playing by touch: a phone or tablet, or a hybrid laptop whose last input was the screen. Only a
-- touch, the keyboard, the mouse or a gamepad decide; anything else (window focus, the gyro) keeps it.
local touching = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local function judge(kind: Enum.UserInputType)
	local name = kind.Name
	if name == "Touch" then
		touching = true
	elseif name == "Keyboard" or name:find("Mouse") or name:find("Gamepad") then
		touching = false
	end
end
judge(UserInputService:GetLastInputType())
UserInputService.LastInputTypeChanged:Connect(judge)
function TouchControls.active(): boolean
	return touching
end
-- The ATTACK button's left edge in screen pixels while it shows, else nil (client/WeaponBar keeps the
-- hotbar left of it: on a narrow phone the Anime Pack's bar would run under it). Set by start().
function TouchControls.attackLeft(): number?
	return nil
end

local INK = Color3.fromRGB(16, 15, 20)
local ASSIST_CONE = math.cos(math.rad(7)) -- a shot bends to a dummy this close to the crosshair
local MAGNET_CONE = math.cos(math.rad(12)) -- the view drifts onto one this close
local MAGNET_RANGE = 120
local MAGNET_PULL = 3 -- share of the gap closed per second
local JUMP_SIZE = 70 -- the phone's jump button: the layout below is drawn for it and scales with it
-- name = { x, y from the jump button's centre, size, label, PRO only }. At most 184 px above it: a
-- 381 px tall phone has the jump centre ~210 px under Roblox's top bar.
local LAYOUT = {
	Attack = { -90, -15, 80, "ATTACK" },
	Aim = { -10, -95, 56, "AIM" },
	Dash = { -95, -100, 54, "DASH" },
	Grab = { 22, -160, 48, "GRAB" },
	View = { -35, -160, 48, "VIEW" },
	Run = { -160, -100, 50, "RUN", true },
	-- Slam = { -220, -100, 50, "SLAM", true }, -- cut for now (init.client mv.cut.slam)
}
local CAS_ACTIONS = { "Sprint", "Dash", "Slam" } -- init.client's bind()

local function fake(kind: Enum.UserInputType, key: Enum.KeyCode?): any
	return { UserInputType = kind, KeyCode = key or Enum.KeyCode.Unknown }
end
local M1 = fake(Enum.UserInputType.MouseButton1)
local M2 = fake(Enum.UserInputType.MouseButton2)
local E = fake(Enum.UserInputType.Keyboard, Enum.KeyCode.E)
local V = fake(Enum.UserInputType.Keyboard, Enum.KeyCode.V)

-- mv: init.client's movement table (began, ended, dash, armSlam, sprintToggle, crouchHeld, and the
-- hooks this fills: simple, assist, magnet). aiming(): the right mouse is down.
function TouchControls.start(mv, dummyFolder: Folder, aiming: () -> boolean)
	if not UserInputService.TouchEnabled then
		return
	end
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("RagdollHud") :: ScreenGui
	local function simple(): boolean
		return touching and Music.get("TouchSimple") == true
	end
	mv.simple = simple

	-- the dummy nearest the line `dir` from `origin` within `cone` and `range`, seen from there
	local params = RaycastParams.new()
	local function target(origin: Vector3, dir: Vector3, cone: number, range: number): Vector3?
		params.FilterDescendantsInstances = { player.Character, camera }
		local best, bestDot = nil, cone
		for _, m in dummyFolder:GetChildren() do
			local p = m:FindFirstChild("UpperTorso") or (m:IsA("Model") and m.PrimaryPart)
			local to = p and p.Position - origin
			if to and to.Magnitude <= range and to.Unit:Dot(dir) > bestDot then
				local hit = workspace:Raycast(origin, to, params)
				if not hit or hit.Instance:IsDescendantOf(m) then
					best, bestDot = to.Unit, to.Unit:Dot(dir)
				end
			end
		end
		return best
	end
	local attackHeld = false
	mv.assist = function(origin: Vector3, dir: Vector3, range: number): Vector3?
		return simple() and target(origin, dir.Unit, ASSIST_CONE, range) or nil
	end
	mv.magnet = function(dt: number)
		if not (simple() and (attackHeld or aiming())) then
			return
		end
		local cf = camera.CFrame
		local to = target(cf.Position, cf.LookVector, MAGNET_CONE, MAGNET_RANGE)
		if to then
			local look = cf.LookVector:Lerp(to, math.min(dt * MAGNET_PULL, 1))
			camera.CFrame = CFrame.lookAt(cf.Position, cf.Position + look)
		end
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player.PlayerGui
	local root = Instance.new("Frame") -- sits on the jump button's centre; UIScale follows its size
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(0, 0)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local buttons = {}
	local function button(name: string): TextButton
		local spec = LAYOUT[name]
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromOffset(spec[1], spec[2])
		b.Size = UDim2.fromOffset(spec[3], spec[3])
		b.BackgroundColor3 = INK
		b.BackgroundTransparency = 0.35
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBlack
		b.Text = spec[4]
		b.TextSize = spec[3] >= 70 and 15 or 12
		b.TextColor3 = Color3.new(1, 1, 1)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = b
		local s = Instance.new("UIStroke")
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color, s.Thickness, s.Transparency = Color3.new(1, 1, 1), 2, 0.4
		s.Parent = b
		b.Parent = root
		buttons[name] = { button = b, stroke = s, pro = spec[5] }
		return b
	end
	local function lit(name: string, on: boolean)
		local s = buttons[name].stroke
		s.Color = on and Color3.fromRGB(255, 200, 60) or Color3.new(1, 1, 1)
		s.Transparency = on and 0 or 0.4
	end

	-- ATTACK: held like the left mouse button, let go when that finger leaves the screen
	local attackTouch: InputObject? = nil
	local attack = button("Attack")
	function TouchControls.attackLeft(): number?
		return if root.Visible then attack.AbsolutePosition.X else nil
	end
	attack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not attackTouch then
			attackTouch, attackHeld = input, true
			lit("Attack", true)
			mv.began(M1, false)
		end
	end)
	-- that finger dragged while held draws an aimed swing's line (init.client swingUi), as the mouse does
	UserInputService.InputChanged:Connect(function(input)
		if input == attackTouch then
			mv.swingDrag(input.Delta)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == attackTouch then
			attackTouch, attackHeld = nil, false
			lit("Attack", false)
			mv.ended(M1)
		end
	end)
	local aimOn = false
	local function setAim(on: boolean)
		if on == aimOn then
			return
		end
		aimOn = on
		lit("Aim", on)
		if on then mv.began(M2, false) else mv.ended(M2) end
	end
	button("Aim").Activated:Connect(function()
		setAim(not aimOn)
	end)
	button("Dash").Activated:Connect(function()
		mv.dash()
	end)
	button("Grab").Activated:Connect(function()
		mv.began(E, false)
	end)
	button("View").Activated:Connect(function()
		mv.began(V, false)
	end)
	button("Run").Activated:Connect(function()
		mv.sprintToggle = not mv.sprintToggle
	end)

	local mode = Instance.new("TextButton") -- EASY / PRO
	mode.AnchorPoint = Vector2.new(0.5, 0.5)
	mode.Position = UDim2.fromOffset(-100, -160)
	mode.Size = UDim2.fromOffset(64, 44) -- a finger-sized target
	mode.BackgroundColor3 = INK
	mode.BackgroundTransparency = 0.2
	mode.Font = Enum.Font.GothamBlack
	mode.TextSize = 13
	mode.TextColor3 = Color3.new(1, 1, 1)
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0.5, 0)
	mc.Parent = mode
	mode.Parent = root
	mode.Activated:Connect(function()
		Music.set("TouchSimple", not simple())
	end)
	local function showMode()
		local on = simple()
		mode.Text = on and "EASY" or "PRO"
		mode.TextColor3 = on and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(255, 160, 70)
		for _, b in buttons do
			b.button.Visible = not (b.pro and on)
		end
	end
	Music.changed:Connect(function(name)
		if name == "TouchSimple" then
			showMode()
		end
	end)
	showMode()

	-- placed on Roblox's jump button (bigger on a tablet: the layout scales with it); Roblox's own
	-- move buttons kept hidden (it can make them again on a respawn)
	local function place()
		local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true) :: GuiObject?
		local centre, size
		if jump and jump.AbsoluteSize.X > 0 then
			centre, size = jump.AbsolutePosition + jump.AbsoluteSize / 2, jump.AbsoluteSize.X
		else
			centre, size = gui.AbsoluteSize - Vector2.new(60, 55), JUMP_SIZE
		end
		centre -= gui.AbsolutePosition
		root.Position = UDim2.fromOffset(centre.X, centre.Y)
		scale.Scale = size / JUMP_SIZE
		for _, name in CAS_ACTIONS do
			local b = ContextActionService:GetButton(name)
			if b then
				b.Visible = false
			end
		end
	end
	task.spawn(function()
		while gui.Parent do
			place()
			task.wait(0.5)
		end
	end)
	RunService.RenderStepped:Connect(function()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local show = touching and not Menu.active
			and not hud:GetAttribute("WeaponPickerOpen") and hum ~= nil and hum.Health > 0
		root.Visible = show
		if not show then
			if attackTouch then
				attackTouch, attackHeld = nil, false
				lit("Attack", false)
				mv.ended(M1)
			end
			setAim(false)
		end
	end)
end

return TouchControls
