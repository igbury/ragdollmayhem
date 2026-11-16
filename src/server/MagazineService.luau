local Magazines = require(game:GetService("ReplicatedStorage").Shared.Magazines)
local Service = {}
local function key(id) return "Ammo_" .. id end
function Service.reload(char, id)
	local spec = Magazines[id]
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not spec or not hum or hum.Health <= 0 or char:GetAttribute("Ragdolled") then return false end
	if char:GetAttribute("ReloadWeapon") or char:GetAttribute("EquippedWeapon") ~= id then return false end
	local ammo = char:GetAttribute(key(id))
	if ammo == nil or ammo >= spec.capacity then return false end
	local token = workspace:GetServerTimeNow() + spec.duration
	char:SetAttribute("ReloadWeapon", id)
	char:SetAttribute("ReloadUntil", token)
	task.delay(spec.duration, function()
		if char.Parent and hum.Health > 0 and char:GetAttribute("ReloadUntil") == token then
			if char:GetAttribute("EquippedWeapon") == id and not char:GetAttribute("Ragdolled") then char:SetAttribute(key(id), spec.capacity) end
			char:SetAttribute("ReloadWeapon", nil)
			char:SetAttribute("ReloadUntil", nil)
		end
	end)
	return true
end
function Service.cancel(char)
	if not char then return end
	char:SetAttribute("ReloadWeapon", nil)
	char:SetAttribute("ReloadUntil", nil)
end
function Service.consume(char, id)
	local spec = Magazines[id]
	if not spec then return true end
	if char:GetAttribute("ReloadWeapon") then return false end
	local ammo = char:GetAttribute(key(id)) or spec.capacity
	if ammo <= 0 then Service.reload(char, id); return false end
	char:SetAttribute(key(id), ammo - 1)
	-- Auto reload also works on touch/controller without a separate input.
	if ammo == 1 then Service.reload(char, id) end
	return true
end
return Service
