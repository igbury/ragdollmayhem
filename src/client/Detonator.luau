-- C4's detonator: while a player has charges out (their C4Out attribute, set by server/Specials) and
-- holds C4, a little remote sits in their LEFT hand. Drawn locally for every player: our own goes in
-- the first-person viewmodel's left fist (viewLeft, a grip CFrame: +Y up out of the fist), everyone
-- else's (and ours in third person) in their LeftHand's grip.
local Players = game:GetService("Players")

local Detonator = {}

local GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0) -- the R15 grip attachment
local PIECES = { -- { size, offset from the grip, colour, shape }
	{ Vector3.new(0.28, 0.42, 0.16), CFrame.new(0, 0.12, 0), Color3.fromRGB(35, 35, 38), Enum.PartType.Block },
	{ Vector3.one * 0.13, CFrame.new(0, 0.36, 0), Color3.fromRGB(230, 30, 25), Enum.PartType.Ball }, -- the button
	{ Vector3.new(0.04, 0.4, 0.04), CFrame.new(0.09, 0.5, 0.03), Color3.fromRGB(20, 20, 20), Enum.PartType.Block }, -- antenna
	{ Vector3.one * 0.07, CFrame.new(0.09, 0.71, 0.03), Color3.fromRGB(230, 30, 25), Enum.PartType.Ball },
}

local built = {} -- [Player] = { BasePart }

local function build(): { BasePart }
	local parts = {}
	for _, spec in PIECES do
		local p = Instance.new("Part")
		p.Size, p.Color, p.Shape = spec[1], spec[3], spec[4]
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Parent = workspace.CurrentCamera
		table.insert(parts, p)
	end
	return parts
end

-- Once a frame. firstPerson: ours is drawn in the viewmodel, at viewLeft (nil: hidden this frame).
function Detonator.update(firstPerson: boolean, viewLeft: CFrame?)
	local me = Players.LocalPlayer
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local at: CFrame? = nil
		if (plr:GetAttribute("C4Out") or 0) > 0 and char and char:GetAttribute("EquippedWeapon") == "C4" then
			if plr == me and firstPerson then
				at = viewLeft
			else
				local hand = char:FindFirstChild("LeftHand") :: BasePart?
				at = hand and hand.CFrame * GRIP
			end
		end
		local parts = built[plr]
		if at and not parts then
			parts = build()
			built[plr] = parts
		end
		if parts then
			for i, p in parts do
				p.Transparency = if at then 0 else 1
				if at then
					p.CFrame = at * PIECES[i][2]
				end
			end
		end
	end
	for plr, parts in built do
		if not plr.Parent then
			for _, p in parts do
				p:Destroy()
			end
			built[plr] = nil
		end
	end
end

return Detonator
