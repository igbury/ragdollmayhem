-- The serum syringes (shared/Weapons kind "syringe", after the Death and Healing ones, which stay in
-- init.server Body.playerSyringe). Body.playerSyringe finds the dummy the crosshair is on and hands
-- it here with the jab's id; every helper of the server's comes in through init() (K below).
--  * SleepSyringe: out cold for SLEEP s, snoring.
--  * SpeedSyringe (adrenaline): it sprints about at HYPER_SPEED screaming for HYPER s, then collapses.
--  * JellySyringe: its joints lose every limit and all their friction for JELLY s: it flops like jelly.
--  * HeliumSyringe: it floats up at HELIUM_RISE studs/s for HELIUM s, then the gas goes and it drops.
--  * ShrinkSyringe / GiantSyringe: Model:ScaleTo to SHRINK / GIANT for SIZE_TIME s, then back to 1.
--  * FireSyringe: it burns from the inside (Specials.alight) for FIRE s.
--  * ExplosiveSyringe: it beeps faster and faster for BOMB_FUSE s, then blows up (a grenade's blast).
--  * ZombieSyringe: living or dead, it comes back as a zombie (a new Zombie body in its place, same name).
local RunService = game:GetService("RunService")

local Serums = {}

local K -- the server's helpers (init)

local SLEEP = 10
local SNORE_EVERY = 2.5
local HYPER, HYPER_SPEED, HYPER_TIRED = 7, 26, 5
local JELLY = 10
local HELIUM, HELIUM_RISE = 5, 9
local SIZE_TIME, SHRINK, GIANT, SIZE_STEPS = 15, 0.4, 2.2, 8
local FIRE = 12
local BOMB_FUSE = 3
local TURN_TIME = 1.5

local LINES = {
	Speed = { "I CAN SEE SOUNDS!", "WHY IS EVERYTHING SO SLOW?!", "AAAAAAAAAH!", "I FEEL AMAZING!", "CAN'T STOP! WON'T STOP!" },
	Tired = { "So... tired...", "I need... a nap...", "My legs..." },
	Jelly = { "My bones feel funny...", "Wobble wobble...", "I can't... stand..." },
	Helium = { "Why is my voice so high?!", "I'm floating!", "Put me down!", "Wheee!" },
	Pop = { "Uh oh.", "Not good!", "Going down!" },
	Shrink = { "Hey! Down here!", "Everything got huge!", "Don't step on me!" },
	Giant = { "I AM HUGE!", "Who's laughing now?!", "Tiny people everywhere!" },
	Normal = { "Phew, back to normal.", "What just happened?" },
	Fire = { "It burns inside!", "HOT HOT HOT!", "Water! WATER!" },
	Bomb = { "Is that... beeping?", "Why am I ticking?!", "Get it out! GET IT OUT!" },
	Turn = { "I feel... hungry...", "Braaains...", "Something's wrong with me..." },
}

local function pick(list)
	return list[math.random(#list)]
end

local function alive(d): boolean
	return d.model.Parent ~= nil and d.state ~= "Dead"
end

local function torsoOf(d): BasePart?
	return d.model:FindFirstChild("UpperTorso") :: BasePart?
end

local function sleep(d)
	local token = os.clock()
	d.serumSleep = token
	K.say(d, "Zzz...", "think")
	K.knockDown(d, SLEEP, "Out cold")
	task.spawn(function()
		while task.wait(SNORE_EVERY) and d.serumSleep == token and alive(d) and os.clock() - token < SLEEP do
			K.say(d, pick({ "Zzz...", "Zzzzz...", "Snore... mimimi..." }), "think")
		end
	end)
end

local function speed(d)
	if d.model:GetAttribute("Ragdolled") then
		return -- down already: nothing to run with
	end
	local token = os.clock()
	d.hyperUntil = token + HYPER
	K.say(d, pick(LINES.Speed), "shout")
	task.spawn(function()
		while alive(d) and d.hyperUntil == token + HYPER and os.clock() < d.hyperUntil do
			local root = d.model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and not d.model:GetAttribute("Ragdolled") then
				local angle = math.random() * math.pi * 2
				d.speed = HYPER_SPEED
				K.walkTo(d, root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 25)
				if math.random() < 0.35 then
					K.say(d, pick(LINES.Speed), "shout")
				end
			end
			task.wait(0.8)
		end
		if d.hyperUntil == token + HYPER then
			d.hyperUntil = nil
			if alive(d) then
				K.say(d, pick(LINES.Tired), "think")
				K.knockDown(d, HYPER_TIRED, "Out cold")
			end
		end
	end)
end

local function jelly(d)
	local token = os.clock()
	local first = not d.serumJelly
	d.serumJelly = token
	if first then -- a second jab only runs the clock again: the limits are off already
		local saved = {}
		for _, j in d.model:GetDescendants() do
			if j:IsA("BallSocketConstraint") then
				saved[j] = { j.LimitsEnabled, j.TwistLimitsEnabled, j.MaxFrictionTorque }
				j.LimitsEnabled, j.TwistLimitsEnabled, j.MaxFrictionTorque = false, false, 0
			elseif j:IsA("HingeConstraint") then
				saved[j] = { j.LimitsEnabled, j.MotorMaxTorque }
				j.LimitsEnabled, j.MotorMaxTorque = false, 0
			end
		end
		d.jellySaved = saved
	end
	if d.state ~= "Dead" then
		K.say(d, pick(LINES.Jelly))
		K.knockDown(d, JELLY, "Knocked down")
	end
	task.spawn(function()
		local names = { "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg", "Head", "LeftHand", "RightHand" }
		while d.model.Parent and d.serumJelly == token and os.clock() - token < JELLY do
			local limb = d.model:FindFirstChild(names[math.random(#names)]) :: BasePart?
			if limb then -- a wobble now and then, so it keeps jiggling
				limb:ApplyImpulse(Random.new():NextUnitVector() * limb.AssemblyMass * 14)
			end
			task.wait(0.3)
		end
		if d.serumJelly ~= token then
			return -- jabbed again: that one puts the joints back
		end
		d.serumJelly = nil
		for j, s in d.jellySaved or {} do
			if j.Parent then
				if j:IsA("BallSocketConstraint") then
					j.LimitsEnabled, j.TwistLimitsEnabled, j.MaxFrictionTorque = s[1], s[2], s[3]
				else
					j.LimitsEnabled, j.MotorMaxTorque = s[1], s[2]
				end
			end
		end
		d.jellySaved = nil
	end)
end

local function helium(d)
	local torso = torsoOf(d)
	if not torso or d.serumHelium then
		return
	end
	d.serumHelium = true
	if d.state ~= "Dead" then
		K.say(d, pick(LINES.Helium), "shout")
		K.knockDown(d, HELIUM + 3, "Knocked down")
	end
	K.setOwner(d.model, nil) -- the server lifts it: it has to own it
	local mass = 0
	for _, part in d.model:GetDescendants() do
		if part:IsA("BasePart") and not part.Massless then
			mass += part:GetMass()
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "HeliumLift"
	a0.Parent = torso
	local force = Instance.new("VectorForce")
	force.Name = "HeliumLift"
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Attachment0 = a0
	force.Parent = torso
	local start = os.clock()
	local loop
	loop = RunService.Heartbeat:Connect(function()
		local done = not torso.Parent or os.clock() - start > HELIUM
		if done then
			loop:Disconnect()
			force:Destroy()
			a0:Destroy()
			d.serumHelium = nil
			if torso.Parent then
				K.Sfx.play({ K.Sfx.ROCKET_JUMP_POP, 0.6, 1 }, torso.Position)
				if d.state ~= "Dead" then
					K.say(d, pick(LINES.Pop), "shout")
				end
			end
			return
		end
		local v = torso.AssemblyLinearVelocity
		local g = workspace.Gravity
		local up = math.clamp(g + 3 * (HELIUM_RISE - v.Y), 0, 2.5 * g) -- rises at HELIUM_RISE, drifting a little
		force.Force = Vector3.new(-v.X * 0.6, up, -v.Z * 0.6) * mass
		if d.state ~= "Dead" and d.wakeAt < os.clock() + 1 then
			K.knockDown(d, 2, "Knocked down") -- limp the whole ride
		end
	end)
end

local function resize(d, to: number)
	local model = d.model
	local token = os.clock()
	d.serumSize = token
	local from = model:GetScale()
	task.spawn(function()
		for i = 1, SIZE_STEPS do -- grows (or shrinks) over a moment, not in one pop
			if not model.Parent or d.serumSize ~= token then
				return
			end
			model:ScaleTo(from + (to - from) * i / SIZE_STEPS)
			task.wait(0.05)
		end
	end)
	task.delay(SIZE_TIME, function()
		if model.Parent and d.serumSize == token then
			d.serumSize = nil
			local now = model:GetScale()
			for i = 1, SIZE_STEPS do
				if not model.Parent or d.serumSize then
					return -- jabbed again on the way back: that one runs it now
				end
				model:ScaleTo(now + (1 - now) * i / SIZE_STEPS)
				task.wait(0.05)
			end
			if alive(d) then
				K.say(d, pick(LINES.Normal))
			end
		end
	end)
end

local function fire(d)
	K.Specials.alight(d)
	if d.burningUntil then -- alight is off (BURNING DUMMIES setting): no fire, only a scream
		d.burningUntil = math.max(d.burningUntil, os.clock() + FIRE)
	end
	K.say(d, pick(LINES.Fire), "shout")
end

local function bomb(d, player: Player, id: string)
	if d.serumBomb then
		return
	end
	d.serumBomb = true
	K.say(d, pick(LINES.Bomb), "shout")
	task.spawn(function()
		K.Wanted.act(player, id) -- the blast is on whoever jabbed it
		local start = os.clock()
		while d.model.Parent and os.clock() - start < BOMB_FUSE do
			local torso = torsoOf(d)
			if torso then
				K.Sfx.play({ K.Sfx.C4_BEEP, 1 + (os.clock() - start) / BOMB_FUSE, 0.9 }, torso.Position)
			end
			task.wait(math.max(0.08, 0.45 * (1 - (os.clock() - start) / BOMB_FUSE)))
		end
		d.serumBomb = nil
		local torso = torsoOf(d)
		if not torso then
			return
		end
		local at = torso.Position
		if d.state ~= "Dead" then
			d.hp = 0
			K.kill(d, "Exploded")
		end
		K.explode(at, K.Sfx.GRENADE_BOOM, 1.2)
	end)
end

local function zombie(d)
	if d.zombie or d.serumTurning then
		return
	end
	d.serumTurning = true
	if d.state ~= "Dead" then
		K.say(d, pick(LINES.Turn), "think")
		K.knockDown(d, TURN_TIME + 1, "Knocked down")
	end
	task.delay(TURN_TIME, function()
		local model = d.model
		if not model.Parent then
			return
		end
		local cf = CFrame.new(model:GetPivot().Position + Vector3.yAxis * 3)
		local name = model.Name
		local torso = torsoOf(d)
		if torso then
			K.Sfx.play({ K.Sfx.ZOMBIE_GROAN_1, 1, 1 }, torso.Position)
		end
		model:Destroy()
		K.spawn(cf, name, "Zombie") -- same name, the zombie's rags and skin: you can tell what it turned into
	end)
end

local SERUMS = {
	SleepSyringe = sleep,
	SpeedSyringe = speed,
	JellySyringe = jelly,
	HeliumSyringe = helium,
	ShrinkSyringe = function(d)
		K.say(d, pick(LINES.Shrink), "shout")
		resize(d, SHRINK)
	end,
	GiantSyringe = function(d)
		K.say(d, pick(LINES.Giant), "shout")
		resize(d, GIANT)
	end,
	FireSyringe = fire,
	ExplosiveSyringe = bomb,
	ZombieSyringe = zombie,
}
-- the ones that work on a body too (the rest only on the living)
local ON_DEAD = { ZombieSyringe = true, ExplosiveSyringe = true, JellySyringe = true, ShrinkSyringe = true, GiantSyringe = true, HeliumSyringe = true }

function Serums.init(deps)
	K = deps
end

-- true: `id` is a serum and dummy `d` got it (or could not take it); false: not one of these.
function Serums.jab(id: string, d, player: Player): boolean
	local serum = SERUMS[id]
	if not serum then
		return false
	end
	if d.state ~= "Dead" or ON_DEAD[id] then
		d.blame, d.blameAt, d.blameWeapon = player, os.clock(), id
		serum(d, player, id)
	end
	return true
end

-- the walk speed an adrenaline jab gives (init.server pace), nil when none is working
function Serums.pace(d): number?
	return if d.hyperUntil and os.clock() < d.hyperUntil then HYPER_SPEED else nil
end

return Serums
