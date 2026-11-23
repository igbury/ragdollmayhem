-- Weapon progression, shared by the server (server/Progress: it pays for kills and sells weapons) and
-- the client (WeaponBar / Arsenal: locks, prices, buying). A player starts with START; every kill pays
-- KILL_CASH by kind (2X CASH doubles it), and every other weapon is bought for its PRICE, in any order. Bought
-- weapons are kept as "Own<id>" attributes, the balance as "Cash", both saved by server/Progress.
-- GROUP weapons are not for sale: only joining the game's group unlocks them (InGroup, server/Progress).
-- The kill counters below (Kills, RangedKills, ThrownKills) stay as stats and for the analytics funnels.
local Weapons = require(script.Parent:WaitForChild("Weapons"))
local Shop = require(script.Parent:WaitForChild("Shop")) -- ALL WEAPONS and the other passes unlock too

local Progression = {}

-- the bat and the tomato too, so the first minutes have more than fists to play with (2026-11-23);
-- everything else is bought, the pistol too (the tutorial's kill pays for it and teaches buying)
Progression.START = { Fists = true, Bat = true, Tomato = true }
Progression.CASH = "Cash"
-- cash a kill pays, by what it took (counters below): melee is the hardest, an explosive can take several;
-- anime: an ability (the Anime Pack; its kills come in as "Ability", main server script)
Progression.KILL_CASH = { kills = 15, ranged = 10, thrown = 5, anime = 10 }
-- times that for a dummy of this Kind (the hooligans fight back with a bat); paid rounded to whole cash
Progression.KIND_CASH = { Hooligan = 1.1 }
-- (a dummy put down with the Toolbox pays only a share of it, Shop.SANDBOX.spawnCash: Progression.cash)
-- [weapon id] = cash. A pacing sim (cheapest first, 3 kills/min with fists up to 8 with the top weapons,
-- ~11$ a kill) gave: a buy every 1-4 min for the first 20 min, everything in ~5 h, ~2.5 h with 2X CASH.
-- The cheap melee weapons were then pushed up between the early guns and explosives, so the first buys
-- alternate ranged / melee / explosive (2026-11-22; the sim not rerun: the first buys take about twice as long).
-- ponytail: kill rates are guesses; retune once Analytics shows real kills per minute
Progression.PRICE = {
	Handgun = 5,
	Bat = 30,
	Tomato = 60,
	Crowbar = 100,
	Bow = 180,
	Axe = 190,
	Grenade = 200,
	Spear = 250,
	Knife = 280,
	Revolver = 320,
	Sledgehammer = 330,
	Molotov = 350,
	BoxingGloves = 380,
	Lightsaber = 420,
	TNT = 450,
	Lasso = 470,
	Taser = 500,
	Pan = 520,
	Chainsaw = 550,
	C4 = 600,
	Landmine = 650,
	Katana = 700,
	Rifle = 750,
	Harpoon = 800,
	Shotgun = 950,
	Boilgun = 1050,
	Sniper = 1250,
	Flamethrower = 1250,
	Minigun = 1700,
	Rocket = 2000,
}
Progression.GROUP = { Frostgun = true } -- only for joining the group

function Progression.own(id: string): string
	return "Own" .. id
end

-- the player attribute each counter is kept in, and how a lock names it
Progression.ATTRIBUTE = { kills = "Kills", ranged = "RangedKills", thrown = "ThrownKills" }
Progression.GROUP_ATTRIBUTE = "InGroup"
Progression.GROUP_NEED = "JOIN THE GROUP"

local RANGED = { gun = true, bow = true, knife = true }
local EXPLOSIVE = { thrown = true, rocket = true } -- the rocket launcher is an explosive, as in the Arsenal
local kindOf = {} -- [weapon id, its slash / heavy too] = kind
local tagOf = {} -- [weapon id] = its shop tag (Shop.UNLOCKS)
for _, w in Weapons do
	kindOf[w.id] = w.kind
	tagOf[w.id] = w.tag
	for _, sub in { w.slash, w.heavy } do
		if sub then
			kindOf[sub.id] = sub.kind
		end
	end
end

-- The counters a kill with `weapon` (a Weapons id, or nil / "Body" / an ability) adds to.
function Progression.counters(weapon: string?): { string }
	local kind = weapon and kindOf[weapon]
	local out = { "kills" }
	if kind and RANGED[kind] then
		table.insert(out, "ranged")
	elseif kind and EXPLOSIVE[kind] then
		table.insert(out, "thrown")
	end
	return out
end

-- What a kill with `weapon` of a dummy of `kind` (its Kind attribute) pays, 2X CASH aside and unrounded:
-- by the counter it adds to besides "kills", an ability by its own rate; `share`: the part a Toolbox one pays.
function Progression.cash(weapon: string?, kind: string?, share: number?): number
	local counters = Progression.counters(weapon)
	local base = if weapon == "Ability" then Progression.KILL_CASH.anime else Progression.KILL_CASH[counters[2] or "kills"]
	return base * (Progression.KIND_CASH[kind or ""] or 1) * (share or 1)
end

-- nil when `player` may use weapon `id`, else what it still takes ("1000$" or GROUP_NEED).
function Progression.missing(player: Player, id: string): string?
	if Progression.GROUP[id] then
		return if player:GetAttribute(Progression.GROUP_ATTRIBUTE) then nil else Progression.GROUP_NEED
	end
	local price = Progression.PRICE[id]
	if not price or Progression.START[id] or player:GetAttribute(Progression.own(id)) then
		return nil -- not part of the progression (abilities), or theirs
	end
	local pass = tagOf[id] and Shop.UNLOCKS[tagOf[id]]
	if Shop.owns(player, "AllWeapons") or (pass and Shop.owns(player, pass)) then
		return nil
	end
	return `{price}$`
end

return Progression
