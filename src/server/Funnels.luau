-- Analytics funnels (Creator Hub > Analytics > Funnels). Nine of the experience's ten slots:
--  Onboarding (the tutorial, server/Tutorial): 1 joined, 2 in the arena, 3 first kill, 4 took the pistol.
--  MeleeKills / RangedKills / ExplosiveKills: lifetime kills with that group's weapons, a step per
--    KILL_STEPS milestone. Group = the weapon's hotbar tag (shared/Weapons): melee (and a thrown body),
--    gun, thrown + heavy (the rocket). Real kills: 2X KO does not double them.
--  MeleeWeapons / RangedWeapons / ExplosiveWeapons: the group's unlockable weapons in unlock order
--    (shared/Progression); step N = the first N of them all unlocked, so a weapon unlocked out of order
--    (another counter, a pass) waits until the ones before it are in too.
--  Movement / Menus: a step per move / menu, named after it, in MOVE_ORDER / MENU_ORDER; like the
--    weapons, step N = the first N of them all used / opened. The order players really take them in:
--    the MoveUsed / MenuOpened custom events, once per player per name, the name in CustomField01.
-- All lifetime (no session id); only a step's first time counts on Roblox's side, so this sends a step
-- only when it is newly reached. Counts and sets are saved with the progress (server/Progress).
-- AnalyticsService sends only from published servers; in Studio each event is printed instead.
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Progression = require(ReplicatedStorage.Shared.Progression)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

local Funnels = {}
Funnels.changed = function(_: Player) end -- set by Progress: something to save

local STUDIO = RunService:IsStudio()
local KILL_STEPS = { 1, 5, 10, 25, 50, 100, 250, 500, 1000 }
local GROUP_OF_TAG = { melee = "Melee", gun = "Ranged", thrown = "Explosive", heavy = "Explosive" }
local GROUPS = { "Melee", "Ranged", "Explosive" }
-- Move remote reports (main server script, MOVE_NAMES) = the ability they mean
local MOVES = {
	sprint = "Sprint", wall1 = "Wall run", ["wall-1"] = "Wall run", cling = "Wall cling",
	slide = "Slide", slideEnter = "Slide", crouch = "Crouch", crouchIdle = "Crouch",
	dive = "Superman dive", diveEnter = "Superman dive", roll = "Roll", flip = "Wall flip",
	kick = "Kick", jump = "Double jump", slam = "Ground slam", dash = "Dash", mantle = "Mantle", vault = "Vault",
}
-- the Movement funnel's steps, roughly easiest first (append new ones at the end, never reorder)
local MOVE_ORDER = { "Sprint", "Double jump", "Crouch", "Slide", "Roll", "Kick", "Dash", "Wall run",
	"Wall cling", "Wall flip", "Mantle", "Vault", "Superman dive", "Ground slam" }
-- the Menus funnel's steps = what the clients may report as opened (their FireServer("opened", name))
local MENU_ORDER = { "Toolbox", "WeaponWheel", "Stats", "Shop", "Arsenal", "Settings", "Build", "World",
	"Wardrobe", "Menu" }
local MENUS = {}
for _, name in MENU_ORDER do
	MENUS[name] = true
end

local groupOf = { Body = "Melee" } -- [weapon id, its slash / heavy too] = group; a thrown body is hand-to-hand
local unlockOrder = { Melee = {}, Ranged = {}, Explosive = {} } -- [group] = { weapon id } in unlock order
for i, w in Weapons do
	local group = GROUP_OF_TAG[w.tag]
	groupOf[w.id] = group
	for _, sub in { w.slash, w.heavy } do
		if sub then
			groupOf[sub.id] = group
		end
	end
	local rule = Progression.UNLOCK[w.id]
	if group and rule and rule[1] ~= "group" then -- the group one is not a step
		table.insert(unlockOrder[group], { id = w.id, need = rule[2], at = i })
	end
end
for group, list in unlockOrder do
	table.sort(list, function(a, b)
		return if a.need ~= b.need then a.need < b.need else a.at < b.at
	end)
	for i, entry in list do
		list[i] = entry.id
	end
end

local data = {} -- [player] = { kills = { [group] = n }, moves = { [name] = true }, menus = { [name] = true } }
local weaponStep = {} -- [player] = { [group] = steps sent this session }

local function send(player: Player, funnel: string, step: number, name: string)
	if STUDIO then
		print(`Funnel {funnel} {step} {name} ({player.Name})`)
		return
	end
	local ok, err = pcall(function()
		if funnel == "Onboarding" then
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
		else
			AnalyticsService:LogFunnelStepEvent(player, funnel, nil, step, name)
		end
	end)
	if not ok then
		warn("Funnels:", funnel, step, err)
	end
end

local function custom(player: Player, event: string, value: string)
	if STUDIO then
		print(`Event {event} {value} ({player.Name})`)
		return
	end
	pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, event, 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = value,
	})
end

-- how many of `order` from the start are all in `set`
local function prefix(order: { string }, set): number
	local n = 0
	while order[n + 1] and set[order[n + 1]] do
		n += 1
	end
	return n
end

-- puts `name` in `set` and sends the steps it completes (only a step's first time counts)
local function reach(player: Player, funnel: string, order: { string }, set, name: string)
	local before = prefix(order, set)
	set[name] = true
	local after = prefix(order, set)
	if after > before then
		send(player, funnel, after, order[after])
	end
end

local function killStep(n: number): number
	local step = 0
	for i, need in KILL_STEPS do
		if n >= need then
			step = i
		end
	end
	return step
end

local function checkWeapons(player: Player)
	local sent = weaponStep[player]
	if not sent then
		return
	end
	for group, list in unlockOrder do
		local step = 0
		while list[step + 1] and Progression.missing(player, list[step + 1]) == nil do
			step += 1
		end
		if step > (sent[group] or 0) then
			sent[group] = step
			send(player, group .. "Weapons", step, list[step])
		end
	end
end

-- Onboarding step `step` (1..4, see the top) for `player`.
function Funnels.tutorial(player: Player, step: number)
	local names = { "Joined", "Entered arena", "First kill", "Took pistol" }
	send(player, "Onboarding", step, names[step])
end

-- `player` killed a dummy with `weapon` (as Progress.credit gets it).
function Funnels.kill(player: Player, weapon: string?)
	local d = data[player]
	local group = d and weapon and groupOf[weapon]
	if not group then
		return -- not loaded yet, an ability, nobody knows what
	end
	local before = d.kills[group] or 0
	d.kills[group] = before + 1
	local step = killStep(before + 1)
	if step > killStep(before) then
		send(player, group .. "Kills", step, if step == 1 then "1 kill" else `{KILL_STEPS[step]} kills`)
	end
	Funnels.changed(player)
end

-- A Move remote report from `player` (already checked against MOVE_NAMES).
function Funnels.move(player: Player, name: string)
	local d = data[player]
	local move = d and MOVES[name]
	if not move or d.moves[move] then
		return
	end
	reach(player, "Movement", MOVE_ORDER, d.moves, move)
	custom(player, "MoveUsed", "Move - " .. move)
	Funnels.changed(player)
end

-- `player`'s client says it opened menu `name` (anything outside MENUS is ignored).
function Funnels.menu(player: Player, name: any)
	local d = data[player]
	if not d or typeof(name) ~= "string" or not MENUS[name] or d.menus[name] then
		return
	end
	reach(player, "Menus", MENU_ORDER, d.menus, name)
	custom(player, "MenuOpened", "Menu - " .. name)
	Funnels.changed(player)
end

-- `saved` is what Funnels.save gave last time (nil: nothing saved). Called once the progress is in.
function Funnels.load(player: Player, saved: any)
	saved = type(saved) == "table" and saved or {}
	local d = { kills = {}, moves = {}, menus = {} }
	for _, group in GROUPS do
		d.kills[group] = type(saved.kills) == "table" and tonumber(saved.kills[group]) or 0
	end
	for _, key in { "moves", "menus" } do
		if type(saved[key]) == "table" then
			for _, name in saved[key] do
				if type(name) == "string" then
					d[key][name] = true
				end
			end
		end
	end
	data[player] = d
	weaponStep[player] = {}
	checkWeapons(player)
	player.AttributeChanged:Connect(function(attribute)
		-- a kill counter (shared/Progression) or a pass (shared/Shop) can unlock weapons
		if attribute == "Kills" or attribute == "RangedKills" or attribute == "ThrownKills" or attribute == Progression.GROUP_ATTRIBUTE or attribute:sub(1, 4) == "Pass" then
			checkWeapons(player)
		end
	end)
	if player:GetAttribute("Tutorial") then
		Funnels.tutorial(player, 1)
	end
end

-- What to keep in `player`'s save (nil before Funnels.load).
function Funnels.save(player: Player)
	local d = data[player]
	if not d then
		return nil
	end
	local out = { kills = d.kills, moves = {}, menus = {} }
	for _, key in { "moves", "menus" } do
		for name in d[key] do
			table.insert(out[key], name)
		end
	end
	return out
end

function Funnels.forget(player: Player)
	data[player], weaponStep[player] = nil, nil
end

return Funnels
