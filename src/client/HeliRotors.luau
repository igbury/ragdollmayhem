-- Spins the army helicopters' rotors (server: Helicopter) every frame here, so they turn smoothly
-- whatever the server's update rate. Each rotor piece has "Spin" (turns per second), "Axis" ("Y"
-- main rotor, "X" tail rotor), "Pivot" (the rotor's centre in the Body's space) and "Offset" (the
-- piece's rest pose from that pivot): blades, grips and tips all turn about the same mast.
local RunService = game:GetService("RunService")

local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Sfx"))

local folder = workspace:WaitForChild("Helicopters")

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, heli in folder:GetChildren() do
		local body = heli:FindFirstChild("Body") :: BasePart?
		if not body then
			continue
		end
		if not body:FindFirstChild("RotorSound") then -- the rotors' thump, heard from afar
			Sfx.loop(body, Sfx.HELICOPTER_ROTOR_LOOP, 0.7, 400).Name = "RotorSound"
		end
		for _, p in heli:GetChildren() do
			local spin = p:IsA("BasePart") and p:GetAttribute("Spin")
			local pivot, offset = spin and p:GetAttribute("Pivot"), spin and p:GetAttribute("Offset")
			if pivot and offset then
				local a = t * spin * math.pi * 2
				local turn = p:GetAttribute("Axis") == "X" and CFrame.Angles(a, 0, 0) or CFrame.Angles(0, a, 0)
				p.CFrame = body.CFrame * pivot * turn * offset
			end
		end
	end
end)

return nil
