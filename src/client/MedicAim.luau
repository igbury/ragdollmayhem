-- The medical items in hand (shared/Weapons), showing what a click would treat; the click itself is the
-- ordinary weapon use and the server picks the same thing by the same rule:
--  * Bandage (server Body.playerBandage): the stump of a torn-off limb that the line from the head toward
--    what the crosshair is on passes closest to, at most AIM studs off it and the item's range out.
--  * Cast (server Body.playerCast): the arm or leg the crosshair is on, within range, when a bone in it is
--    broken ("Broken" on a part) and it is not in a cast yet ("Cast"): its upper part, lower part and
--    hand / foot all light up.
--  * Balloon (server Specials tieByHand): the body part the crosshair is on, within range (a hat or hair:
--    the head), where the balloon would be tied.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons"))

local MedicAim = {}

local AIM = 1.4 -- studs off the line (server Body.BANDAGE_AIM)
local RANGE = {}
for _, w in Weapons do
	if w.kind == "bandage" or w.kind == "cast" or w.kind == "balloon" then
		RANGE[w.id] = w.range
	end
end
local LIMB = { Arm = { "UpperArm", "LowerArm", "Hand" }, Leg = { "UpperLeg", "LowerLeg", "Foot" } } -- server Body.LIMB_PARTS

function MedicAim.start(dummyFolder: Instance)
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local lights = {}
	for i = 1, 3 do
		local h = Instance.new("Highlight")
		h.Name = "MedicAim"
		h.FillColor, h.FillTransparency = Color3.fromRGB(120, 255, 140), 0.25
		h.OutlineColor, h.OutlineTransparency = Color3.new(1, 1, 1), 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		lights[i] = h
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = "MedicAimTag"
	tag.Size, tag.StudsOffsetWorldSpace, tag.AlwaysOnTop = UDim2.fromOffset(220, 34), Vector3.new(0, 1.4, 0), true
	local label = Instance.new("TextLabel")
	label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	label.Font, label.TextScaled = Enum.Font.LuckiestGuy, true
	label.TextColor3, label.TextStrokeTransparency = Color3.new(1, 1, 1), 0
	label.Parent = tag
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- the stump nearest the line, or nil
	local function stumpOn(head: BasePart, dir: Vector3, range: number): BasePart?
		local best, bestOff = nil, AIM
		for _, model in dummyFolder:GetChildren() do
			local torso = model:FindFirstChild("UpperTorso") :: BasePart?
			if not torso or (torso.Position - head.Position).Magnitude > range + 6 then
				continue
			end
			for _, cap in model:GetDescendants() do
				if cap.Name == "Stump" and cap:IsA("BasePart") and not cap:GetAttribute("Bandaged") then
					local to = cap.Position - head.Position
					local along = to:Dot(dir)
					local off = (to - dir * along).Magnitude
					if along > 0 and along <= range and off < bestOff then
						best, bestOff = cap, off
					end
				end
			end
		end
		return best
	end
	-- the parts of the broken, uncast limb `hit` belongs to, or nil
	local function limbOf(hit: Instance): { BasePart }?
		local model = hit.Parent
		local side, part = hit.Name:match("^(%u%l+)(%u.+)$")
		if not (model and model.Parent == dummyFolder and side) then
			return nil
		end
		for _, names in LIMB do
			if table.find(names, part) then
				local parts, broken = {}, false
				for _, name in names do
					local p = model:FindFirstChild(side .. name)
					if p then
						if p:GetAttribute("Cast") then
							return nil
						end
						broken = broken or p:GetAttribute("Broken") == true
						table.insert(parts, p)
					end
				end
				return if broken then parts else nil
			end
		end
		return nil
	end

	-- the body part a balloon would be tied to (server Specials limbOf), or nil
	local function partOf(hit: Instance): BasePart?
		local inst = hit
		while inst.Parent and inst.Parent.Parent ~= dummyFolder do
			inst = inst.Parent
		end
		local model = inst.Parent
		if not model then
			return nil
		end
		if inst:IsA("BasePart") and inst.Name ~= "HumanoidRootPart" then
			return inst
		end
		return model:FindFirstChild(if inst:IsA("Accessory") then "Head" else "UpperTorso") :: BasePart?
	end

	RunService.RenderStepped:Connect(function()
		local char = player.Character
		local head = char and char:FindFirstChild("Head") :: BasePart?
		local item = char and char:GetAttribute("EquippedWeapon")
		local range = item and RANGE[item]
		local show: { BasePart } = {}
		if head and range and not char:GetAttribute("Ragdolled") then
			-- the crosshair as client useWeapon aims: the mouse, or the screen's middle on touch
			local mouse = if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			params.FilterDescendantsInstances = { char, camera }
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
			local dir = ((if hit then hit.Position else ray.Origin + ray.Direction * 300) - head.Position).Unit
			if dir:Dot(ray.Direction) < 0.5 then
				dir = (ray.Origin + ray.Direction * 300 - head.Position).Unit
			end
			if item == "Bandage" then
				local cap = stumpOn(head, dir, range)
				show = if cap then { cap } else {}
				label.Text = "CLICK TO BANDAGE"
			elseif item == "Balloon" then
				local part = hit and (hit.Position - head.Position).Magnitude <= range and partOf(hit.Instance)
				show = if part then { part } else {}
				label.Text = "CLICK TO TIE A BALLOON"
			elseif hit and (hit.Position - head.Position).Magnitude <= range then
				show = limbOf(hit.Instance) or {}
				label.Text = "CLICK TO PUT IN A CAST"
			end
		end
		for i, h in lights do
			h.Adornee = show[i]
			h.Parent = if show[i] then camera else nil
		end
		tag.Adornee = show[1]
		tag.Parent = if show[1] then player:FindFirstChildOfClass("PlayerGui") else nil
	end)
end

return MedicAim
