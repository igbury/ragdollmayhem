-- The comic set's own mechanics (shared/Weapons, after the Rocket). The weapon handler (init.server)
-- asks fire() before its generic gun / melee / thrown paths, and afterHit() once a generic blow has
-- landed on a dummy. Every helper of the server's it needs comes in through init() (K below).
--  * Flamethrower: a cone of fire; whoever is in it burns (harm "fire"), the floor it licks catches.
--  * Frostgun: an ice ray; a dummy it hits freezes solid (anchored, ice shells) for FREEZE seconds.
--  * Boilgun: a short spray of boiling water: knocks back and scalds for a while after (burns).
--  * Taser: two wires; the dummy drops and twitches.
--  * Lasso / Harpoon: a rope to the dummy that yanks it in; the lasso then drags it along behind.
--  * C4: click sticks a charge to what it hits (MAX_C4), right click sets all of them off.
--  * Landmine: placed on the floor ahead; armed after a moment, it blows when a dummy steps close.
--  * Spear: a long thrust that runs through up to SPEAR_PIERCE dummies in a line.
--  * Minigun: needs weapon.spinUp seconds of the trigger held before the first round (spinning()).
--  * Crowbar knocks a dummy's weapon out of its hands; the Sledgehammer's blow sends out a shockwave.
--  * Burning (alight): any fire (flamethrower, molotov, burning floor) sets a dummy alight: flames on
--    its body (client Fx, the "Burning" attribute), burns on for BURN s and catches the ones close by.
--    The BURNING DUMMIES setting (shared/Settings, the host's) turns it off.
--  * Boilgun: its water boils the blood in the body (boilBlood): the blood gauge drains, steam and
--    bubbles come off it, and boiled dry it dies.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Shared.Settings)

local Specials = {}

local K -- the server's helpers (init)

local UP = Vector3.yAxis
local FLAME_CONE = math.cos(math.rad(22))
local FREEZE = 4
local MAX_C4 = 3
local MAX_MINES = 4
local MINE_ARM = 1.5
local MINE_REACH = 4
local SPEAR_PIERCE = 3
local LASSO_DRAG = 4 -- s the lassoed dummy stays tied
local LASSO_LENGTH = 7 -- studs of rope it is dragged on
local ICE = Color3.fromRGB(170, 220, 255)
local ROPE = BrickColor.new("Brown")
local DISARM_LINES = { "Hey! That was mine!", "My weapon!", "Ow, my hand!", "Give that back!" }
local BURN = 6 -- s a dummy burns once alight; every new flame on it starts the count again
local BURN_TICK, BURN_DAMAGE = 0.5, 2.5
local SPREAD_REACH, SPREAD_CHANCE = 4.5, 0.3 -- a burning body catches a neighbour this close, per tick
local BOIL_TICKS, BOIL_TICK = 10, 0.3 -- one blast boils for 3 s
local BOIL_BLOOD = 8 -- blood (of 100) boiled off per tick: one blast leaves it pale, two boil it dry
local BOIL_DEAD = 10 -- blood left at which it dies of it
-- The crowbar's limb rip: a hit on an arm or a leg has a RIP_CHANCE of hooking the claw into the top of
-- that limb, tugging RIP_TUG s against the body, tearing it off and carrying it on the claw RIP_HANG s
-- before it drops. A hit on the torso or the head hooks the limb nearest the blow.
local RIP_CHANCE = 0.8
local RIP_TUG, RIP_HANG = 3, 1.4
-- where the claw is, from the right hand: the grip attachment (init.client DEFAULT_GRIP when there is
-- none), HOLD.Crowbar.grip, then the claw's tip in the crowbar mesh (assets/weapons/comic_weapons.py)
local DEFAULT_GRIP = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
local CROWBAR_GRIP = CFrame.new(0, 0.05, 0)
local CLAW_TIP = CFrame.new(0, 1.37, -0.37) -- the hook's point, measured on src/client/WeaponMeshes/Crowbar (Fx.CLAW too)

local charges = {} -- [Player] = { BasePart }: stuck C4
local mines = {} -- [Player] = { BasePart }
local spin = {} -- [Player] = { since, last }: the minigun's spin-up
local nextPatch = {} -- [Player] = when the flamethrower may light the floor again
local lastSound = {} -- [Player] = { [weapon id] = os.clock() } (HUSH)

function Specials.init(deps)
	K = deps
	Players.PlayerRemoving:Connect(function(player)
		for _, list in { charges[player], mines[player] } do
			for _, p in list do
				p:Destroy()
			end
		end
		charges[player], mines[player], spin[player], nextPatch[player], lastSound[player] = nil, nil, nil, nil, nil
	end)
end

-- A clip of shared/Sfx by name, at `position`; nothing while that clip is not uploaded / approved yet.
local function play(name: string, position: Vector3, pitch: number?, volume: number?)
	local id = K.Sfx[name]
	if id then
		K.Sfx.play({ id, pitch or 1, volume or 1 }, position)
	end
end

-- true while the weapon's fire sound would play again too soon (the flamethrower and the chainsaw
-- fire many times a second: one clip every Sfx.HUSH s instead). The client keeps the same rule (useWeapon).
function Specials.hushed(weapon, player: Player): boolean
	local every = K.Sfx.HUSH[weapon.id]
	if not every then
		return false
	end
	local mine = lastSound[player] or {}
	lastSound[player] = mine
	local now = os.clock()
	if now - (mine[weapon.id] or 0) < every then
		return true
	end
	mine[weapon.id] = now
	return false
end

-- Fire on a dummy: it burns for BURN s (each new flame restarts the count), takes BURN_DAMAGE every
-- BURN_TICK (harm "fire": chars the skin, floors it), and may set the ones next to it alight.
function Specials.alight(d)
	if d.burnTick or not d.model.Parent or not Settings.get(Settings.host(), "BurningDummies") then
		return
	end
	local now = os.clock()
	local already = d.burningUntil and d.burningUntil > now
	d.burningUntil = now + BURN
	if already then
		return
	end
	d.model:SetAttribute("Burning", true)
	local torso = d.model:FindFirstChild("UpperTorso")
	local crackle = torso and K.Sfx.FIRE_BURNING_LOOP and K.Sfx.loop(torso, K.Sfx.FIRE_BURNING_LOOP, 0.45, 120)
	task.spawn(function()
		while d.model.Parent and d.burningUntil and os.clock() < d.burningUntil do
			task.wait(BURN_TICK)
			d.burnTick = true -- its own burning does not restart the count (harm "fire" calls alight)
			K.harm(d, BURN_DAMAGE, "fire", nil)
			d.burnTick = nil
			local t = d.model:FindFirstChild("UpperTorso") :: BasePart?
			if t then
				for model, other in K.dummies do
					local ot = other ~= d and model:FindFirstChild("UpperTorso") :: BasePart?
					if ot and not (other.burningUntil and other.burningUntil > os.clock())
						and (ot.Position - t.Position).Magnitude < SPREAD_REACH and math.random() < SPREAD_CHANCE then
						Specials.alight(other)
					end
				end
			end
		end
		d.burningUntil = nil
		if crackle then
			crackle:Destroy()
		end
		if d.model.Parent then
			d.model:SetAttribute("Burning", nil)
		end
	end)
end

-- The boilgun's water boils the blood in the body: BOIL_BLOOD of it goes every tick for BOIL_TICKS
-- (another blast adds more), steam and bubbles come off (client "Boil"), and once it is down to
-- BOIL_DEAD the dummy dies of it. A zombie has no blood to lose.
local function boilBlood(d, origin: Vector3)
	if d.zombie then
		return
	end
	if d.boiling then
		d.boiling += BOIL_TICKS // 2 -- hit again: it boils on longer
		return
	end
	d.boiling = BOIL_TICKS
	K.addInjury(d, "boiling blood")
	local torso = d.model:FindFirstChild("UpperTorso")
	local sizzle = torso and K.Sfx.BOIL_SIZZLE and K.Sfx.loop(torso, K.Sfx.BOIL_SIZZLE, 0.6, 100)
	task.spawn(function()
		while d.boiling and d.boiling > 0 and d.model.Parent do
			d.boiling -= 1
			d.blood = math.max(0, d.blood - BOIL_BLOOD)
			K.fx:FireAllClients("Boil", nil, d.model)
			if d.state ~= "Dead" then
				if d.blood <= BOIL_DEAD then
					K.kill(d, "Dead: blood boiled")
				else
					K.harm(d, 2, "boil", origin) -- writhing on the floor while it boils
				end
			end
			K.sync(d)
			task.wait(BOIL_TICK)
		end
		d.boiling = nil
		if sizzle then
			sizzle:Destroy()
		end
	end)
end

local function exclude(...): RaycastParams
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ... }
	return params
end

local function bodyParts(d): { BasePart }
	local out = {}
	for _, part in d.model:GetChildren() do
		if part:IsA("BasePart") then
			table.insert(out, part)
		end
	end
	return out
end

-- Free the body for the server to move: nobody holding it, nobody else simulating it.
local function takeOver(d)
	if d.heldBy or d.looseOwner then
		K.release(d, Vector3.zero)
	end
end

local function setVelocity(d, velocity: Vector3, spinBy: number?)
	local spinV = spinBy and Random.new():NextUnitVector() * spinBy
	for _, part in bodyParts(d) do
		part.AssemblyLinearVelocity = velocity
		if spinV then
			part.AssemblyAngularVelocity = spinV
		end
	end
end

-- A rope between the shooter's hand and the dummy's torso, `length` studs at most.
local function rope(char: Model, d, length: number): RopeConstraint?
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("HumanoidRootPart")
	local torso = d.model:FindFirstChild("UpperTorso")
	if not hand or not torso then
		return nil
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "RopeEnd"
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Name = "RopeEnd"
	a1.Parent = torso
	local r = Instance.new("RopeConstraint")
	r.Attachment0, r.Attachment1 = a0, a1
	r.Visible, r.Thickness, r.Color = true, 0.12, ROPE
	r.Length = length
	r.Parent = torso
	r.Destroying:Once(function()
		a0:Destroy()
		a1:Destroy()
	end)
	return r
end

-- Yank the dummy towards the shooter for `seconds`.
local function reel(d, char: Model, speed: number, seconds: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local t0 = os.clock()
	while os.clock() - t0 < seconds and root and root.Parent and d.model.Parent do
		local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
		if not torso then
			break
		end
		local to = root.Position - torso.Position
		if to.Magnitude < 4 then
			break
		end
		setVelocity(d, to.Unit * speed + UP * 8)
		task.wait(0.05)
	end
end

-- One ray; a monster takes it on its own, a dummy is returned with the part and the point.
local function shoot(char: Model, origin: Vector3, dir: Vector3, range: number, weapon, player: Player)
	local result = workspace:Raycast(origin, dir * range, exclude(char))
	local target = result and result.Position or origin + dir * range
	local d = result and K.dummyOf(result.Instance)
	if result and not d and K.Monsters.damage(result.Instance, (weapon.dmg or 1) * 10, dir, player) then
		return nil, result, target
	end
	return d, result, target
end

-- ---- the weapons ----

local function flame(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	K.fx:FireAllClients("Flame", char, origin, dir, weapon.range)
	local params = exclude(char)
	for model, d in K.dummies do
		local torso = model:FindFirstChild("UpperTorso") :: BasePart?
		local to = torso and torso.Position - origin
		if to and to.Magnitude < weapon.range and to.Unit:Dot(dir) > FLAME_CONE then
			local seen = workspace:Raycast(origin, to, params)
			if not seen or seen.Instance:IsDescendantOf(model) then
				K.harm(d, weapon.dmg, "fire", origin)
			end
		end
	end
	local ray = workspace:Raycast(origin, dir * weapon.range, params)
	local tip = ray and ray.Position or origin + dir * weapon.range
	K.Monsters.blast(tip, 5, weapon.dmg * 3, player)
	if ray and not K.dummyOf(ray.Instance) and os.clock() > (nextPatch[player] or 0) then
		nextPatch[player] = os.clock() + 0.8
		task.spawn(function() -- the floor it licks burns for a few seconds (no holes: not a molotov)
			K.fx:FireAllClients("Fire", nil, ray.Position, 4, 3)
			for _ = 1, 6 do
				K.smash(ray.Position, 5, 3, Vector3.zero, 0, "fire")
				task.wait(0.5)
			end
		end)
	end
end

local function thaw(d, ice, anchored)
	d.frozenUntil = nil
	for _, shell in ice do
		shell:Destroy()
	end
	for _, part in anchored do
		if part.Parent then
			part.Anchored = false
		end
	end
	if d.model.Parent then
		d.model:SetAttribute("Frozen", nil)
		K.fx:FireAllClients("Thaw", nil, d.model:GetPivot().Position)
		play("ICE_SHATTER", d.model:GetPivot().Position)
	end
end

local function freeze(d)
	local now = os.clock()
	if d.frozenUntil then
		d.frozenUntil = now + FREEZE -- frozen again: longer
		return
	end
	takeOver(d)
	d.frozenUntil = now + FREEZE
	local ice, anchored = {}, {}
	for _, part in bodyParts(d) do
		if part.Transparency < 1 then
			local shell = Instance.new("Part")
			shell.Name = "Ice"
			shell.Size = part.Size + Vector3.one * 0.35
			shell.CFrame = part.CFrame
			shell.Material = Enum.Material.Ice
			shell.Color = ICE
			shell.Transparency = 0.35
			shell.Anchored, shell.CanCollide, shell.CanQuery, shell.CanTouch = true, false, false, false
			shell.Parent = workspace
			table.insert(ice, shell)
		end
		if not part.Anchored then
			part.AssemblyLinearVelocity = Vector3.zero
			part.Anchored = true
			table.insert(anchored, part)
		end
	end
	d.model:SetAttribute("Frozen", true)
	play("ICE_FREEZE", d.model:GetPivot().Position)
	d.burningUntil = nil -- ice puts the fire out
	task.spawn(function()
		while d.frozenUntil and os.clock() < d.frozenUntil and d.model.Parent do
			task.wait(0.2)
		end
		thaw(d, ice, anchored)
	end)
end

local function frost(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	local d, result, target = shoot(char, origin, dir, weapon.range, weapon, player)
	K.fx:FireAllClients("Shot", char, weapon.id, origin, target, result ~= nil, true)
	if d and result and result.Instance.Parent then
		K.hit(d, result.Instance, dir, weapon.dmg, 0, "blunt", target, origin)
		if d.state ~= "Dead" then
			freeze(d)
		end
	end
end

local function boil(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	local rng = Random.new()
	local scalded = {}
	local right = dir:Cross(UP)
	right = right.Magnitude > 0.01 and right.Unit or Vector3.xAxis
	local up = right:Cross(dir).Unit
	for pellet = 1, 7 do
		local aim = (dir + right * rng:NextNumber(-1, 1) * 0.13 + up * rng:NextNumber(-1, 1) * 0.13).Unit
		local d, result, target = shoot(char, origin, aim, weapon.range, weapon, player)
		K.fx:FireAllClients("Shot", char, weapon.id, origin, target, result ~= nil, pellet == 1)
		if d and result and result.Instance.Parent and not scalded[d] then
			scalded[d] = true
			K.hit(d, result.Instance, aim, weapon.dmg, weapon.push, "blunt", target, origin)
		end
	end
	for d in scalded do -- the blood in it starts to boil
		boilBlood(d, origin)
	end
end

local function tase(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	local d, result, target = shoot(char, origin, dir, weapon.range, weapon, player)
	K.fx:FireAllClients("Shot", char, weapon.id, origin, target, result ~= nil, true)
	if not (d and result and result.Instance.Parent) then
		return
	end
	takeOver(d)
	K.hit(d, result.Instance, dir, weapon.dmg, weapon.push, "blunt", target, origin)
	if d.state == "Dead" then
		return
	end
	K.knockDown(d, 3.5, "Knocked down")
	K.fx:FireAllClients("Tase", char, result.Instance, 1.6)
	task.spawn(function() -- twitching on the floor while the current runs
		for _ = 1, 10 do
			task.wait(0.15)
			if not d.model.Parent or d.heldBy then
				return
			end
			for _, part in bodyParts(d) do
				part.AssemblyAngularVelocity = Random.new():NextUnitVector() * 6 -- a twitch, not a roll away
			end
		end
	end)
end

-- Each player's lassoed dummies, oldest first: { d, rope }. A tie comes off when its time is up or
-- when the right mouse lets it go (Specials.lassoCut), whichever is first.
local tied = {} :: { [Player]: { { d: any, rope: Instance } } }
local function untie(player: Player, tie)
	local list = tied[player]
	local i = list and table.find(list, tie)
	if not i then return end -- already let go
	table.remove(list, i)
	if #list == 0 then tied[player] = nil end
	tie.rope:Destroy()
	local d = tie.d
	d.lassoed = nil
	if d.model.Parent and not d.heldBy then
		K.release(d, Vector3.zero, player) -- the thrower keeps it until it settles, then the server
	end
end
game:GetService("Players").PlayerRemoving:Connect(function(player)
	for _, tie in table.clone(tied[player] or {}) do untie(player, tie) end
end)

local function lasso(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	local result = workspace:Spherecast(origin, 1.2, dir * weapon.range, exclude(char))
	local target = result and result.Position or origin + dir * weapon.range
	local d = result and K.dummyOf(result.Instance)
	K.fx:FireAllClients("Shot", char, weapon.id, origin, target, d ~= nil, true)
	if not d or d.lassoed or d.state == "Dead" then
		return
	end
	d.lassoed = true
	takeOver(d)
	K.knockDown(d, LASSO_DRAG + 1, "Knocked down")
	local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
	local r = torso and rope(char, d, (torso.Position - origin).Magnitude + 1)
	if not r then
		d.lassoed = nil
		return
	end
	K.say(d, "Whoa, whoa!")
	play("HARPOON_REEL", origin, 0.8, 0.7)
	reel(d, char, 50, 0.6)
	r.Length = LASSO_LENGTH -- now it trails behind on the rope; the thrower simulates it, so it drags smoothly
	K.setOwner(d.model, player)
	local tie = { d = d, rope = r }
	local list = tied[player] or {}
	tied[player] = list
	table.insert(list, tie)
	task.delay(LASSO_DRAG, untie, player, tie)
end

-- Right mouse with the lasso: lets go of the dummy caught last (the next one before it on the next click).
function Specials.lassoCut(player: Player)
	local list = tied[player]
	local tie = list and list[#list]
	if tie then untie(player, tie) end
end

local function harpoon(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	local d, result, target = shoot(char, origin, dir, weapon.range, weapon, player)
	K.fx:FireAllClients("Shot", char, weapon.id, origin, target, result ~= nil, d ~= nil)
	task.wait((target - origin).Magnitude / weapon.speed) -- the spear's flight (the client draws it)
	if not (d and result and result.Instance.Parent) then
		if result and not d then
			K.Map.blast(target, 1.2, 25)
		end
		return
	end
	K.hit(d, result.Instance, dir, weapon.dmg, 0, "blade", target, origin)
	if d.state == "Dead" or d.lassoed then
		return
	end
	takeOver(d)
	K.knockDown(d, 2.5, "Knocked down")
	local r = rope(char, d, (target - origin).Magnitude + 2)
	play("HARPOON_REEL", origin)
	reel(d, char, 75, 0.8)
	if r then
		r:Destroy()
	end
end

local function placeC4(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3, aimed: boolean)
	local list = charges[player] or {}
	charges[player] = list
	if aimed then -- the detonator: every charge of ours goes off
		charges[player] = {}
		player:SetAttribute("C4Out", nil) -- clients drop the detonator from the left hand
		play("C4_BEEP", origin)
		for i, p in list do
			if p.Parent then
				local position = p.Position
				p:Destroy()
				task.delay(i * 0.12, K.explode, position, K.Sfx.GRENADE_BOOM, 1.2)
			end
		end
		return
	end
	if #list >= MAX_C4 then
		table.remove(list, 1):Destroy() -- the oldest fizzles out
	end
	local p = Instance.new("Part")
	p.Name = weapon.id
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * 0.7
	p.Color = Color3.fromRGB(220, 210, 180)
	p.Position = origin + dir * 2.5
	p:SetAttribute("Projectile", true) -- clients dress it in the C4 mesh
	p.Parent = workspace
	p:SetNetworkOwner(nil)
	p.AssemblyLinearVelocity = dir * weapon.speed + UP * 10
	table.insert(list, p)
	player:SetAttribute("C4Out", #list) -- clients put the detonator in the left hand
	p.Destroying:Once(function() -- fizzled out, timed out or set off
		local now = charges[player]
		local i = now and table.find(now, p)
		if i then
			table.remove(now, i)
			player:SetAttribute("C4Out", if #now > 0 then #now else nil)
		end
	end)
	local stuck = false
	p.Touched:Connect(function(other)
		if stuck or other:IsDescendantOf(char) or not other.CanCollide and not K.dummyOf(other) then
			return
		end
		-- the real surface it hit, back along the flight: the charge goes flat on it, putty side down
		-- (the mesh's base is 0.13 under its origin), not left hanging where the ball first touched
		local v = p.AssemblyLinearVelocity
		local along = if v.Magnitude > 1 then v.Unit else (other.Position - p.Position).Unit
		local params = exclude(char, p, table.unpack(list))
		local hit = workspace:Raycast(p.Position - along * 1.5, along * 3, params)
			or workspace:Raycast(p.Position + UP, -UP * 3, params)
		if not hit then
			return -- brushed something the rays can't find (an invisible trigger): keep flying
		end
		other = hit.Instance
		stuck = true
		local n = hit.Normal
		local side = n:Cross(along)
		side = if side.Magnitude > 0.05 then side.Unit else n:Cross(Vector3.xAxis).Unit
		p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		p.CFrame = CFrame.fromMatrix(hit.Position + n * 0.13, side, n)
		play("C4_STICK", p.Position)
		if other.Anchored then
			p.Anchored = true
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = p, other
			weld.Parent = p
		end
		p.CanCollide = false
	end)
	Debris:AddItem(p, 90)
end

local function placeMine(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	local flatDir = dir * Vector3.new(1, 0, 1)
	flatDir = flatDir.Magnitude > 0.05 and flatDir.Unit or Vector3.zAxis
	local down = workspace:Raycast(origin + flatDir * 4 + UP, -UP * 12, exclude(char))
	if not down then
		return
	end
	local list = mines[player] or {}
	mines[player] = list
	if #list >= MAX_MINES then
		table.remove(list, 1):Destroy()
	end
	local p = Instance.new("Part")
	p.Name = weapon.id
	p.Size = Vector3.new(1, 0.3, 1)
	p.Transparency = 1
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CFrame = CFrame.lookAlong(down.Position + UP * 0.08, flatDir)
	p:SetAttribute("Projectile", true) -- clients dress it in the landmine mesh
	p.Parent = workspace
	table.insert(list, p)
	if K.Sfx.LANDMINE_ARM then
		play("LANDMINE_ARM", p.Position)
	else
		K.Sfx.play({ K.Sfx.UI_CLICK, 0.6, 1 }, p.Position)
	end
	task.spawn(function()
		task.wait(MINE_ARM)
		local placed = os.clock()
		while p.Parent and os.clock() - placed < 180 do
			for model in K.dummies do
				local torso = model:FindFirstChild("UpperTorso") :: BasePart?
				local off = torso and torso.Position - p.Position
				if off and Vector3.new(off.X, 0, off.Z).Magnitude < MINE_REACH and math.abs(off.Y) < 6 then
					local position = p.Position
					p:Destroy()
					K.explode(position, K.Sfx.GRENADE_BOOM, 1)
					return
				end
			end
			task.wait(0.1)
		end
		p:Destroy()
	end)
end

local function spear(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3)
	local skip = { char }
	local first, landed = nil, 0
	local from = origin
	local left = weapon.range
	while landed < SPEAR_PIERCE and left > 0 do
		local result = workspace:Raycast(from, dir * left, exclude(table.unpack(skip)))
		if not result then
			break
		end
		first = first or result.Position
		local d = K.dummyOf(result.Instance)
		if not d then
			K.Monsters.damage(result.Instance, weapon.dmg * 10, dir, player)
			break -- a wall or a monster stops it
		end
		K.hit(d, result.Instance, dir, weapon.dmg, weapon.push, "blade", result.Position, origin)
		landed += 1
		table.insert(skip, d.model)
		left -= (result.Position - from).Magnitude
		from = result.Position
	end
	local to = first or origin + dir * weapon.range
	K.fx:FireAllClients("Shot", char, weapon.id, origin, to, landed > 0, true)
	local sounds = K.Sfx.WEAPON[weapon.id] or {}
	if landed > 0 and sounds.hit then
		K.Sfx.play(sounds.hit, to, player)
	elseif landed == 0 and sounds.swing then
		K.Sfx.play(sounds.swing, origin, player)
	end
end

local HANDLERS = {
	Flamethrower = flame,
	Frostgun = frost,
	Boilgun = boil,
	Taser = tase,
	Lasso = lasso,
	Harpoon = harpoon,
	C4 = placeC4,
	Landmine = placeMine,
	Spear = spear,
}

-- The minigun: true while its barrels are still spinning up (no round yet). A trigger let go for
-- more than 0.3 s starts the count again; the client sends a use every cd while it is held.
function Specials.spinning(weapon, player: Player): boolean
	if not weapon.spinUp then
		return false
	end
	local now = os.clock()
	local s = spin[player]
	if not s or now - s.last > 0.3 then
		s = { since = now, last = now }
		spin[player] = s
		local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
		if head then
			play("MINIGUN_SPIN_UP", head.Position)
		end
	end
	s.last = now
	return now - s.since < weapon.spinUp
end

-- true: the weapon was used here (the caller stops), false: on to the generic paths.
function Specials.fire(weapon, player: Player, char: Model, origin: Vector3, dir: Vector3, aimed: boolean): boolean
	local handler = HANDLERS[weapon.id]
	if not handler then
		return false
	end
	handler(weapon, player, char, origin, dir, aimed)
	return true
end

-- The crowbar's claw in the world (the attacker's right hand, the crowbar as it is held).
local function clawOf(char: Model): (BasePart?, CFrame?)
	local hand = char:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return nil, nil
	end
	local grip = hand:FindFirstChild("RightGripAttachment") :: Attachment?
	return hand, hand.CFrame * (grip and grip.CFrame or DEFAULT_GRIP) * CROWBAR_GRIP * CLAW_TIP
end

-- Where the torn arm hangs: its top (the shoulder end) speared on the claw's point, hanging straight
-- down, turned the way the crowbar faces. Fx keeps the same rule for the attacker's own view.
local function hangCF(claw: CFrame, arm: BasePart): CFrame
	local look = claw.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.05 and look.Unit or Vector3.zAxis
	return CFrame.lookAlong(claw.Position, look) * CFrame.new(0, -arm.Size.Y * 0.4, 0)
end

-- The claw hooks the shoulder nearest the blow, pulls on it while the body fights it (RIP_TUG), the
-- arm tears off at the shoulder and hangs on the claw's point RIP_HANG s, then drops.
-- The attacker's client simulates the body meanwhile (setOwner), so the tug follows its hand smoothly.
local RIP_LINES = { "AAH! Let go!", "Not the arm! NOT THE ARM!", "Hey, that's attached!" }
-- the limb a body part belongs to, by the part it tears off from (nil: the torso or the head)
local LIMB_ROOT = {
	LeftHand = "LeftUpperArm", LeftLowerArm = "LeftUpperArm", LeftUpperArm = "LeftUpperArm",
	RightHand = "RightUpperArm", RightLowerArm = "RightUpperArm", RightUpperArm = "RightUpperArm",
	LeftFoot = "LeftUpperLeg", LeftLowerLeg = "LeftUpperLeg", LeftUpperLeg = "LeftUpperLeg",
	RightFoot = "RightUpperLeg", RightLowerLeg = "RightUpperLeg", RightUpperLeg = "RightUpperLeg",
}
local function ripArm(d, player: Player, char: Model, hitPart: Instance)
	if d.ripping or d.frozenUntil then
		return
	end
	local rootName = LIMB_ROOT[hitPart.Name]
	local arm = rootName and not d.lost[rootName] and d.model:FindFirstChild(rootName) :: BasePart?
	if not arm and hitPart:IsA("BasePart") then -- the torso or the head: the limb nearest the blow
		local best = math.huge
		for _, name in { "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" } do
			local limb = not d.lost[name] and d.model:FindFirstChild(name) :: BasePart?
			local gap = limb and (limb.Position - hitPart.Position).Magnitude
			if gap and gap < best then
				arm, best = limb, gap
			end
		end
	end
	local hand, claw = clawOf(char)
	if not arm or not hand or not claw then
		return
	end
	d.ripping = true
	takeOver(d)
	setVelocity(d, Vector3.zero) -- the claw holds it: no flying off with the blow's shove
	K.knockDown(d, RIP_TUG + 3, "Knocked down")
	K.setOwner(d.model, player)
	-- The claw is IN the limb: the top of it (where the claw went in) is pinned to the claw's point and
	-- turned with it, stiffly, so the limb rides the crowbar and the body hangs off the limb. Only the
	-- limb is driven (no reaction force), so the attacker's arm feels none of the body's weight.
	local tip = Instance.new("Attachment")
	tip.Name = "Claw"
	tip.CFrame = hand.CFrame:ToObjectSpace(claw)
	tip.Parent = hand
	local hook = Instance.new("Attachment")
	hook.Name = "Claw"
	-- the limb keeps the angle it had to the claw as it went in
	hook.CFrame = CFrame.new(0, arm.Size.Y * 0.4, 0) * arm.CFrame.Rotation:ToObjectSpace(claw.Rotation)
	hook.Parent = arm
	local pull = Instance.new("AlignPosition")
	pull.Attachment0, pull.Attachment1 = hook, tip
	pull.MaxForce, pull.MaxVelocity, pull.Responsiveness = math.huge, math.huge, 200
	pull.Parent = arm
	local turn = Instance.new("AlignOrientation")
	turn.Attachment0, turn.Attachment1 = hook, tip
	turn.MaxTorque, turn.MaxAngularVelocity, turn.Responsiveness = math.huge, math.huge, 200
	turn.Parent = arm
	K.fx:FireAllClients("Hook", char, hook.WorldPosition)
	play("CROWBAR_HIT", hook.WorldPosition, 0.8)
	K.say(d, RIP_LINES[math.random(#RIP_LINES)])
	task.spawn(function()
		-- the tug: the body hangs off the pinned limb and swings with the crowbar's heaves (the attacker's
		-- client plays them and owns the body, so it moves smoothly); nothing spins it any more (that was
		-- the flailing)
		local t0 = os.clock()
		while os.clock() - t0 < RIP_TUG and arm.Parent == d.model do
			task.wait(0.1)
		end
		turn:Destroy()
		pull:Destroy()
		hook:Destroy()
		if arm.Parent ~= d.model or not hand.Parent then
			tip:Destroy()
			d.ripping = nil
			return
		end
		local left = arm.Name:find("Left") ~= nil
		local torso = d.model:FindFirstChild("UpperTorso") :: BasePart?
		local gib = K.sever(d, arm, UP)
		K.Body.lost(d, arm)
		K.addInjury(d, (left and "left" or "right") .. (arm.Name:find("Leg") and " leg" or " arm") .. " torn off")
		K.sync(d)
		if torso then
			K.fx:FireAllClients("Wound", nil, torso, arm.Position, UP, 3, nil, "cut")
		end
		K.fx:FireAllClients("Rip", char, arm.Position)
		play("ARM_RIP", arm.Position)
		K.release(d, Vector3.zero, player) -- the body drops off the claw; the attacker settles it, then the server
		-- the arm on the claw: the server holds it on the third-person crowbar's point for everyone; the
		-- attacker's client draws it on the crowbar it actually sees (Fx "Hang", first person too)
		local parts, rel = {}, {}
		for _, p in gib:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, p)
				rel[p] = arm.CFrame:ToObjectSpace(p.CFrame)
				p.Anchored, p.CanCollide = true, false
			end
		end
		K.fx:FireAllClients("Hang", char, gib, arm, RIP_HANG)
		local hung = os.clock()
		while os.clock() - hung < RIP_HANG and hand.Parent and arm.Parent do
			local _, now = clawOf(char)
			if now then
				local at = hangCF(now, arm)
				for _, p in parts do
					p.CFrame = at * rel[p]
				end
			end
			task.wait()
		end
		tip:Destroy()
		for _, p in parts do
			if p.Parent then
				p.Anchored, p.CanCollide = false, true
			end
		end
		if arm.Parent then -- it slides off the claw and drops
			pcall(arm.SetNetworkOwner, arm, nil)
			arm.AssemblyLinearVelocity = Vector3.new(0, -6, 0)
		end
		d.ripping = nil
	end)
end

-- A generic blow (init.server's ray loop) has just landed on dummy `d` at `target`; `swing` is the
-- aimed swing (x, y on the circle, z the charge) when there was one.
function Specials.afterHit(weapon, d, target: Vector3, swing: Vector3?, player: Player?, char: Model?, hitPart: Instance?)
	if weapon.id == "Crowbar" and player and char and hitPart and math.random() < RIP_CHANCE then
		ripArm(d, player, char, hitPart) -- the limb it landed on (or the nearest one) comes off
	end
	if weapon.id == "Crowbar" and d.gear and d.state ~= "Dead" then
		K.setGear(d, nil)
		K.say(d, DISARM_LINES[math.random(#DISARM_LINES)])
	elseif weapon.id == "Sledgehammer" then
		K.fx:FireAllClients("Slam", nil, target, 7)
		K.smash(target, 7, 12, Vector3.zero, 35)
	end
end

return Specials
