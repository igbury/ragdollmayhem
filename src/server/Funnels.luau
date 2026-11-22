-- Analytics funnels (Creator Hub > Analytics > Funnels) and custom events. An experience gets 10
-- funnels; this is the registry of what each one asks. All are lifetime (saved with the progress,
-- server/Progress) except Shop, one session per shop visit. Only a step's first time counts on Roblox's
-- side and a later step completes the earlier ones, so a step is sent only when it is newly reached.
-- Steps are only ever appended, never inserted or reordered: a changed sequence is a new funnel name.
--
--  #  Funnel          Question                                   Steps
--  1  Onboarding      where do new players drop in the tutorial  Joined, Entered arena, First kill, Took pistol
--  2  MeleeKills      how far do players get killing             1 / 5 / 10 / 25 / 50 / 100 / 250 / 500 / 1000 kills
--  3  RangedKills       ... with each weapon group               (same steps; a thrown body counts as melee,
--  4  ExplosiveKills    (2X CASH does not double them)            the rocket as explosive)
--  5  Arsenal         does the cash loop land: earn, look, buy   First paid kill, Opened Arsenal, Can afford a weapon,
--                                                                Bought 1st weapon, Equipped a bought weapon,
--                                                                Bought 3 / 10 / 20 weapons, Owns every weapon
--  6  Playtime        when do players stop coming back           1 / 3 / 5 / 10 / 15 / 30 min, 1 / 2 / 5 h in a map
--  7  Shop            does a shop visit turn into a purchase     Opened shop, Saw a pass prompt, Bought a pass
--  8  Moves           how much of the movement kit gets used     1 / 2 / 3 / 5 / 8 / 11 moves (all not cut)
--  9  Sandbox         is the Toolbox found and used              Opened Toolbox, Spawned a character, Built a block
-- 10  (free)
-- Retired 2026-11-21 (their meaning changed; never reuse the names): MeleeWeapons, RangedWeapons,
-- ExplosiveWeapons (kill-count unlock order, now weapons are bought), Movement (stuck at the cut Wall
-- flip), Menus (stuck at the WeaponWheel, which the Arsenal replaced).
--
-- Custom events (CustomField01 = the value): MoveUsed "Move - <name>", MenuOpened "Menu - <name>"
-- (once per player each), WeaponBought "Weapon - <id>" (value: its price), PassPrompt
-- "Pass - <key> - Bought" / "Pass - <key> - Closed".
-- AnalyticsService sends only from published servers; in Studio each event is printed instead.
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
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
local ARSENAL = { "First paid kill", "Opened Arsenal", "Can afford a weapon", "Bought 1st weapon",
	"Equipped a bought weapon", "Bought 3 weapons", "Bought 10 weapons", "Bought 20 weapons", "Owns every weapon" }
local BOUGHT_STEPS = { [1] = 4, [3] = 6, [10] = 7, [20] = 8 } -- weapons bought = the Arsenal step it reaches
local PLAYTIME_MINUTES = { 1, 3, 5, 10, 15, 30, 60, 120, 300 }
local SHOP = { "Opened shop", "Saw a pass prompt", "Bought a pass" }
local MOVE_STEPS = { 1, 2, 3, 5, 8, 11 } -- 11 = every move not cut (client/init mv.cut: slam, flip, vault)
local SANDBOX = { "Opened Toolbox", "Spawned a character", "Built a block" }
-- Move remote reports (main server script, MOVE_NAMES) = the ability they mean
local MOVES = {
	sprint = "Sprint", wall1 = "Wall run", ["wall-1"] = "Wall run", cling = "Wall cling",
	slide = "Slide", slideEnter = "Slide", crouch = "Crouch", crouchIdle = "Crouch",
	dive = "Superman dive", diveEnter = "Superman dive", roll = "Roll", flip = "Wall flip",
	kick = "Kick", jump = "Double jump", slam = "Ground slam", dash = "Dash", mantle = "Mantle", vault = "Vault",
}
-- what the clients may report as opened (their FireServer("opened", name))
local MENUS = { Toolbox = true, WeaponWheel = true, Stats = true, Shop = true, Arsenal = true, Settings = true,
	Build = true, World = true, Wardrobe = true, Menu = true }

local groupOf = { Body = "Melee" } -- [weapon id, its slash / heavy too] = group; a thrown body is hand-to-hand
for _, w in Weapons do
	groupOf[w.id] = GROUP_OF_TAG[w.tag]
	for _, sub in { w.slash, w.heavy } do
		if sub then
			groupOf[sub.id] = GROUP_OF_TAG[w.tag]
		end
	end
end
local FOR_SALE = 0
for _ in Progression.PRICE do
	FOR_SALE += 1
end

-- [player] = { kills = { [group] = n }, moves = { [name] = true }, menus = { [name] = true },
--   steps = { [funnel] = highest step sent }, bought = weapons bought with cash }
local data = {}
local shopVisit = {} -- [player] = the Shop funnel's session id for this visit

local function send(player: Player, funnel: string, step: number, name: string, session: string?)
	if STUDIO then
		print(`Funnel {funnel} {step} {name} ({player.Name})`)
		return
	end
	local ok, err = pcall(function()
		if funnel == "Onboarding" then
			AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
		else
			AnalyticsService:LogFunnelStepEvent(player, funnel, session, step, name)
		end
	end)
	if not ok then
		warn("Funnels:", funnel, step, err)
	end
end

local function custom(player: Player, event: string, value: string, amount: number?)
	if STUDIO then
		print(`Event {event} {value} ({player.Name})`)
		return
	end
	pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, event, amount or 1, {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = value,
	})
end

-- Sends lifetime funnel `funnel` up to `step` (named from `names`) if it is past what was sent.
local function reach(player: Player, funnel: string, step: number, names: { string })
	local d = data[player]
	if not d or step <= (d.steps[funnel] or 0) then
		return
	end
	d.steps[funnel] = step
	send(player, funnel, step, names[step])
	Funnels.changed(player)
end

-- The milestone step a count reaches in `steps` (0 below the first).
local function milestone(steps: { number }, n: number): number
	local step = 0
	for i, need in steps do
		if n >= need then
			step = i
		end
	end
	return step
end

local function countNames(steps: { number }, one: string, many: string): { string }
	local names = {}
	for i, n in steps do
		names[i] = if n == 1 then `1 {one}` else `{n} {many}`
	end
	return names
end
local KILL_NAMES = countNames(KILL_STEPS, "kill", "kills")
local MOVE_NAMES = countNames(MOVE_STEPS, "move", "moves")
local PLAYTIME_NAMES = {}
for i, m in PLAYTIME_MINUTES do
	PLAYTIME_NAMES[i] = if m < 60 then `{m} min` else `{m // 60} h`
end

-- Arsenal step 3: the cash covers a weapon not owned yet.
local function checkAfford(player: Player)
	local cash = player:GetAttribute(Progression.CASH) or 0
	for id, price in Progression.PRICE do
		if cash >= price and Progression.missing(player, id) then
			reach(player, "Arsenal", 3, ARSENAL)
			return
		end
	end
end

-- Onboarding step `step` (1..4, see the top) for `player`.
function Funnels.tutorial(player: Player, step: number)
	local names = { "Joined", "Entered arena", "First kill", "Took pistol" }
	send(player, "Onboarding", step, names[step])
end

-- `player` killed a dummy with `weapon` (as Progress.credit gets it; every kill pays cash).
function Funnels.kill(player: Player, weapon: string?)
	local d = data[player]
	if not d then
		return -- not loaded yet
	end
	reach(player, "Arsenal", 1, ARSENAL)
	local group = weapon and groupOf[weapon]
	if not group then
		return -- an ability, nobody knows what: no kill group
	end
	d.kills[group] = (d.kills[group] or 0) + 1
	reach(player, group .. "Kills", milestone(KILL_STEPS, d.kills[group]), KILL_NAMES)
	Funnels.changed(player)
end

-- `player` bought weapon `id` for `price` cash (server/Progress.buy, after it went through).
function Funnels.bought(player: Player, id: string, price: number)
	local d = data[player]
	if not d then
		return
	end
	d.bought += 1
	custom(player, "WeaponBought", "Weapon - " .. id, price)
	local step = 0
	for n, s in BOUGHT_STEPS do
		if d.bought >= n then
			step = math.max(step, s)
		end
	end
	local owned = 0
	for weapon in Progression.PRICE do
		if player:GetAttribute(Progression.own(weapon)) then
			owned += 1
		end
	end
	if owned >= FOR_SALE then
		step = #ARSENAL
	end
	reach(player, "Arsenal", step, ARSENAL)
	Funnels.changed(player)
end

-- `player` equipped weapon `id` (main server script, after the equip went through).
function Funnels.equipped(player: Player, id: string)
	if Progression.PRICE[id] and not Progression.START[id] and id ~= "Handgun" and player:GetAttribute(Progression.own(id)) then
		reach(player, "Arsenal", 5, ARSENAL) -- the pistol is the tutorial's gift, not a buy
	end
end

-- A Move remote report from `player` (already checked against MOVE_NAMES).
function Funnels.move(player: Player, name: string)
	local d = data[player]
	local move = d and MOVES[name]
	if not move or d.moves[move] then
		return
	end
	d.moves[move] = true
	custom(player, "MoveUsed", "Move - " .. move)
	local n = 0
	for _ in d.moves do
		n += 1
	end
	reach(player, "Moves", milestone(MOVE_STEPS, n), MOVE_NAMES)
	Funnels.changed(player)
end

-- `player`'s client says it opened menu `name` (anything outside MENUS is ignored).
function Funnels.menu(player: Player, name: any)
	local d = data[player]
	if not d or typeof(name) ~= "string" or not MENUS[name] then
		return
	end
	if name == "Shop" then -- every visit is a new Shop session
		shopVisit[player] = HttpService:GenerateGUID(false)
		send(player, "Shop", 1, SHOP[1], shopVisit[player])
	elseif name == "Arsenal" then
		reach(player, "Arsenal", 2, ARSENAL)
	elseif name == "Toolbox" then
		reach(player, "Sandbox", 1, SANDBOX)
	end
	if not d.menus[name] then
		d.menus[name] = true
		custom(player, "MenuOpened", "Menu - " .. name)
		Funnels.changed(player)
	end
end

-- A game pass prompt for `key` (shared/Shop) closed for `player`, `bought` or not (server/Shop).
function Funnels.pass(player: Player, key: string, bought: boolean)
	local session = shopVisit[player] or HttpService:GenerateGUID(false) -- a prompt from outside the shop
	shopVisit[player] = session
	send(player, "Shop", 2, SHOP[2], session)
	if bought then
		send(player, "Shop", 3, SHOP[3], session)
	end
	custom(player, "PassPrompt", `Pass - {key} - {if bought then "Bought" else "Closed"}`)
end

-- `player` spawned a character / built a block with the Toolbox (main server script, after it worked).
function Funnels.spawned(player: Player)
	reach(player, "Sandbox", 2, SANDBOX)
end
function Funnels.built(player: Player)
	reach(player, "Sandbox", 3, SANDBOX)
end

-- `saved` is what Funnels.save gave last time (nil: nothing saved). Called once the progress is in.
function Funnels.load(player: Player, saved: any)
	saved = type(saved) == "table" and saved or {}
	local d = { kills = {}, moves = {}, menus = {}, steps = {}, bought = tonumber(saved.bought) or 0 }
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
	if type(saved.steps) == "table" then
		for funnel, step in saved.steps do
			if type(funnel) == "string" and type(step) == "number" then
				d.steps[funnel] = step
			end
		end
	end
	data[player] = d
	checkAfford(player)
	reach(player, "Playtime", milestone(PLAYTIME_MINUTES, (player:GetAttribute("StatPlaytime") or 0) / 60), PLAYTIME_NAMES)
	player.AttributeChanged:Connect(function(attribute)
		if attribute == Progression.CASH or attribute:sub(1, 3) == "Own" or attribute:sub(1, 4) == "Pass" then
			checkAfford(player)
		elseif attribute == "StatPlaytime" then -- in a map only (server/Progress)
			reach(player, "Playtime", milestone(PLAYTIME_MINUTES, (player:GetAttribute("StatPlaytime") or 0) / 60), PLAYTIME_NAMES)
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
	local out = { kills = d.kills, moves = {}, menus = {}, steps = d.steps, bought = d.bought }
	for _, key in { "moves", "menus" } do
		for name in d[key] do
			table.insert(out[key], name)
		end
	end
	return out
end

function Funnels.forget(player: Player)
	data[player], shopVisit[player] = nil, nil
end

return Funnels
