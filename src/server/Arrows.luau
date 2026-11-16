-- Swept ballistic arrows. One scheduler; damage queries never depend on a cosmetic Touched event.
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Arrows = {}
local flying = {}
function Arrows.fire(origin, direction, speed, ownerCharacter, onHit)
	local arrow = Instance.new("Part")
	arrow.Name, arrow.Size, arrow.Color = "HunterArrow", Vector3.new(0.11, 0.11, 2.5), Color3.fromRGB(176, 142, 87)
	arrow.Anchored, arrow.CanCollide, arrow.CanQuery, arrow.CanTouch = true, false, false, false
	arrow.CFrame, arrow.Parent = CFrame.lookAlong(origin, direction), workspace
	local params = RaycastParams.new(); params.FilterDescendantsInstances = { ownerCharacter, arrow }
	flying[arrow] = { position = origin, velocity = direction * speed, time = 0, distance = 0, params = params, hit = onHit }
	Debris:AddItem(arrow, 5)
end
RunService.Heartbeat:Connect(function(delta)
	for arrow, data in flying do
		if not arrow.Parent then flying[arrow] = nil; continue end
		local remaining = math.min(delta, 0.25)
		while remaining > 0 do
			local dt = math.min(remaining, 1 / 30)
			remaining -= dt
			local nextVelocity = data.velocity - Vector3.yAxis * workspace.Gravity * 0.42 * dt
			local step = (data.velocity + nextVelocity) * (dt / 2)
			local result = workspace:Spherecast(data.position, 0.12, step, data.params)
			data.time += dt; data.distance += step.Magnitude
			if result then
				arrow.CFrame = CFrame.lookAlong(result.Position, data.velocity.Unit)
				flying[arrow] = nil
				data.hit(result, data.velocity.Unit)
				Debris:AddItem(arrow, 2)
				break
			end
			data.position += step; data.velocity = nextVelocity
			arrow.CFrame = CFrame.lookAlong(data.position, data.velocity.Unit)
			if data.time > 4 or data.distance > 300 then arrow:Destroy(); flying[arrow] = nil; break end
		end
	end
end)
return Arrows
