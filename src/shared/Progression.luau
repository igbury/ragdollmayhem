-- Weapon progression, shared by the server (server/Progress: it pays for kills and sells weapons) and
-- the client (WeaponBar / Arsenal: locks, prices, buying). A player starts with START; every kill pays
-- KILL_CASH by kind (2X CASH doubles it), and every other weapon is bought for its PRICE, in any order. Bought
-- weapons are kept as "Own<id>" attributes, the balance as "Cash", both saved by server/Progress.
-- GROUP weapons are not for sale: only joining the game's group unlocks them (InGroup, server/Progress).
-- The kill counters below (Kills, RangedKills, ThrownKills) stay as stats and for the analytics funnels.
local Weapons = require(script.Parent:WaitForChild("Weapons"))
local Shop = require(script.Parent:WaitForChild("Shop")) -- ALL WEAPONS and the other passes unlock too

local Progression = {}

Progression.START = { Fists = true, Bat = true }
Progression.CASH = "Cash"
-- cash a kill pays, by what it took (counters below): melee is the hardest, an explosive can take several
Progression.KILL_CASH = { kills = 12, ranged = 10, thrown = 6 }
-- [weapon id] = cash. A pacing sim (cheapest first, 3 kills/min with fists up to 8 with the top weapons,
-- ~11$ a kill) gave: a buy every 1-4 min for the first 20 min, everything in ~5 h, ~2.5 h with 2X CASH.
-- ponytail: kill rates are guesses; retune once Analytics shows real kills per minute
Progression.PRICE = {
	Handgun = 10,
	Crowbar = 30,
	Axe = 50,
	Tomato = 60,
	Sledgehammer = 80,
	BoxingGloves = 100,
	Lasso = 120,
	Pan = 150,
	Bow = 180,
	Grenade = 200,
	Spear = 250,
	Knife = 280,
	Revolver = 320,
	Molotov = 350,
	Lightsaber = 420,
	TNT = 450,
	Taser = 500,
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

local RANGED = { gun = true, bow = true, knife = true, rocket = true }
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
	elseif kind == "thrown" then
		table.insert(out, "thrown")
	end
	return out
end

-- What a kill with `weapon` pays (2X CASH aside): the counter it adds to besides "kills".
function Progression.cash(weapon: string?): number
	local counters = Progression.counters(weapon)
	return Progression.KILL_CASH[counters[2] or "kills"]
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
