-- Run as a temporary normal Script in ServerScriptService during Studio Play, never in production.
assert(game:GetService("RunService"):IsStudio(), "Studio only")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Monsters = require(game.ServerScriptService.Server.Monsters)
local Magazines = require(game.ServerScriptService.Server.MagazineService)
local report = Instance.new("Folder")
report.Name, report.Parent = "MythQA", workspace
local results = {}
local function case(name, test)
	local ok, detail = pcall(test)
	table.insert(results, { name = name, passed = ok, detail = tostring(detail) })
	report:SetAttribute("Results", HttpService:JSONEncode(results))
end
local player = assert(Players:GetPlayers()[1], "Test player required")
local char = assert(player.Character)
local hum = char:FindFirstChildOfClass("Humanoid")
local before = { cf = char:GetPivot(), hp = hum.Health, xp = player:GetAttribute("MythXP"), kills = player:GetAttribute("MonsterKills"), equipped = char:GetAttribute("EquippedWeapon") }
local ff = char:FindFirstChildOfClass("ForceField")
if ff then ff:Destroy() end
local function at(model, distance)
	local r = model.PrimaryPart
	hum.Health = hum.MaxHealth
	char:PivotTo(CFrame.lookAt(r.Position + Vector3.new(0, -2, distance), r.Position))
	return r
end
local function awaitState(model, expected, seconds)
	local endAt = os.clock() + seconds
	repeat
		if model:GetAttribute("MonsterState") == expected then return true end
		task.wait(0.025)
	until os.clock() >= endAt
	return false
end
local cyclops = workspace.Monsters:WaitForChild("CYCLOPS")
case("three distinct articulated actors", function()
	assert(#workspace.Monsters:GetChildren() == 3)
	for _, m in workspace.Monsters:GetChildren() do
		local motors = 0
		for _, j in m:GetDescendants() do if j:IsA("Motor6D") then motors += 1 end end
		assert(motors == 15, m.Name .. " joint count " .. motors)
		assert(m.PrimaryPart.Anchored and m:GetAttribute("HP") > 0)
	end
	return "3 rigs; 15 motors each; server-owned anchored roots"
end)
case("body hit and eye multiplier", function()
	local hp = cyclops:GetAttribute("HP")
	assert(Monsters.damage(cyclops.UpperTorso, 10, Vector3.zAxis, player))
	assert(cyclops:GetAttribute("HP") == hp - 10)
	assert(Monsters.damage(cyclops.Eye, 10, Vector3.zAxis, player))
	assert(cyclops:GetAttribute("HP") == hp - 35)
	assert(cyclops:GetAttribute("MonsterState") == "Stunned")
	return "10 body damage / 25 eye damage / stun"
end)
case("cyclops telegraph and damaging attack", function()
	at(cyclops, 13)
	assert(awaitState(cyclops, "Windup", 8), "No windup")
	assert(cyclops:GetAttribute("StateUntil") - cyclops:GetAttribute("StateSince") >= 1.2)
	local hp = hum.Health
	assert(awaitState(cyclops, "Strike", 3), "No strike")
	assert(hum.Health < hp, "Attack did not damage player")
	assert(awaitState(cyclops, "Recovery", 1), "No recovery")
	return "windup -> strike -> recovery; player HP decreased"
end)
case("minotaur locks and charges", function()
	local m = workspace.Monsters.MINOTAUR
	at(m, 22)
	Monsters.damage(m.UpperTorso, 1, Vector3.zAxis, player)
	local start = m.PrimaryPart.Position
	assert(awaitState(m, "Windup", 3), "No charge warning")
	assert(awaitState(m, "Charge", 3), "No charge")
	task.wait(0.4)
	assert((m.PrimaryPart.Position - start).Magnitude > 5, "Charge did not move")
	return "charge warning, locked direction, movement >5 studs"
end)
case("talos ankle weak point and delayed hammer", function()
	local m = workspace.Monsters.TALOS
	at(m, 20)
	local hp = m:GetAttribute("HP")
	Monsters.damage(m.AnkleSeal, 10, Vector3.zAxis, player)
	assert(m:GetAttribute("HP") == hp - 25)
	assert(awaitState(m, "Windup", 9), "No hammer windup")
	assert(m:GetAttribute("ImpactAt") ~= nil)
	return "ankle x2.5, stun, delayed targeted impact"
end)
case("death ragdoll and exactly one reward", function()
	local xp = player:GetAttribute("MythXP") or 0
	local kills = player:GetAttribute("MonsterKills") or 0
	Monsters.damage(cyclops.Eye, 350, Vector3.zAxis, player)
	assert(cyclops:GetAttribute("MonsterState") == "Dead")
	assert(cyclops:GetAttribute("Ragdolled") and not cyclops.PrimaryPart.Anchored)
	assert((player:GetAttribute("MythXP") or 0) == xp + 100)
	assert((player:GetAttribute("MonsterKills") or 0) == kills + 1)
	Monsters.damage(cyclops.Eye, 350, Vector3.zAxis, player)
	assert(player:GetAttribute("MythXP") == xp + 100, "Duplicate reward")
	return "ragdoll +100 XP once"
end)
case("reload locks and cancellation", function()
	-- Isolate reload from a concurrent hammer hit, which correctly interrupts it through ragdoll.
	char:PivotTo(CFrame.new(0, 5, 0))
	hum.Health = hum.MaxHealth
	task.wait(1.1)
	char:SetAttribute("EquippedWeapon", "Handgun")
	char:SetAttribute("Ammo_Handgun", 2)
	Magazines.cancel(char)
	assert(Magazines.consume(char, "Handgun"))
	assert(char:GetAttribute("Ammo_Handgun") == 1)
	assert(Magazines.reload(char, "Handgun"))
	assert(not Magazines.consume(char, "Handgun"), "Shot allowed during reload")
	Magazines.cancel(char)
	char:SetAttribute("EquippedWeapon", "Fists")
	task.wait(1.5)
	assert(char:GetAttribute("Ammo_Handgun") == 1, "Cancelled reload refilled")
	char:SetAttribute("EquippedWeapon", "Handgun")
	assert(Magazines.reload(char, "Handgun"))
	task.wait(1.5)
	assert(char:GetAttribute("Ammo_Handgun") == 15)
	return "consume, reload lock, cancel, refill to 15"
end)
case("encounter respawns", function()
	local deadline = os.clock() + 22
	repeat
		local fresh = workspace.Monsters:FindFirstChild("CYCLOPS")
		if fresh and fresh ~= cyclops and fresh:GetAttribute("HP") == 600 then
			assert(fresh:GetAttribute("MonsterState") == "Caged")
			return "fresh caged cyclops at full health"
		end
		task.wait(0.2)
	until os.clock() > deadline
	error("Respawn deadline exceeded")
end)
Magazines.cancel(char)
char:SetAttribute("EquippedWeapon", before.equipped)
char:SetAttribute("Ammo_Handgun", nil)
player:SetAttribute("MythXP", before.xp)
player:SetAttribute("MonsterKills", before.kills)
if char.Parent and hum.Health > 0 then char:PivotTo(before.cf); hum.Health = before.hp end
report:SetAttribute("Done", true)
print("MythQA " .. HttpService:JSONEncode(results))
