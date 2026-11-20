-- Weapon progression, shared by the server (server/Progress: it counts kills and unlocks) and the client
-- (WeaponBar / Arsenal: locks and what each lock still needs). A player starts with START; every other
-- weapon unlocks once one of three kill counters reaches its number:
--  * kills: any dummy killed;
--  * ranged: killed with a gun, the bow, a thrown knife or the rocket (Weapons kind gun / bow / knife / rocket);
--  * thrown: killed with a grenade, a molotov or a tomato (kind thrown).
local Weapons = require(script.Parent:WaitForChild("Weapons"))
local Shop = require(script.Parent:WaitForChild("Shop")) -- ALL WEAPONS and STARTER PACK unlock too

local Progression = {}

Progression.START = { Fists = true, Bat = true }
-- [weapon id] = { counter, kills needed }
Progression.UNLOCK = {
	Handgun = { "kills", 1 }, -- the tutorial's one kill (server/Tutorial)
	Axe = { "kills", 10 },
	BoxingGloves = { "kills", 20 },
	Pan = { "kills", 25 },
	Grenade = { "kills", 50 },
	Katana = { "kills", 100 },
	Bow = { "ranged", 15 },
	Knife = { "ranged", 25 },
	Revolver = { "ranged", 30 },
	Rifle = { "ranged", 50 },
	Shotgun = { "ranged", 100 },
	Sniper = { "ranged", 150 },
	Rocket = { "ranged", 250 },
	Tomato = { "thrown", 10 },
	Molotov = { "thrown", 25 },
	Crowbar = { "kills", 5 },
	Sledgehammer = { "kills", 15 },
	Lasso = { "kills", 20 },
	Spear = { "kills", 40 },
	Lightsaber = { "kills", 60 },
	Chainsaw = { "kills", 80 },
	Taser = { "ranged", 40 },
	Harpoon = { "ranged", 60 },
	Frostgun = { "ranged", 80 },
	Boilgun = { "ranged", 120 },
	Flamethrower = { "ranged", 150 },
	Minigun = { "ranged", 200 },
	TNT = { "thrown", 30 },
	C4 = { "thrown", 40 },
	Landmine = { "thrown", 45 },
}
-- the player attribute each counter is kept in, and how a lock names it
Progression.ATTRIBUTE = { kills = "Kills", ranged = "RangedKills", thrown = "ThrownKills" }
Progression.LABEL = { kills = "kills", ranged = "ranged kills", thrown = "thrown kills" }

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

-- nil when `player` may use weapon `id`, else what is still missing ("12 / 25 ranged kills").
function Progression.missing(player: Player, id: string): string?
	local pass = tagOf[id] and Shop.UNLOCKS[tagOf[id]]
	if Progression.START[id] or Shop.owns(player, "AllWeapons") or (pass and Shop.owns(player, pass)) then
		return nil
	end
	local rule = Progression.UNLOCK[id]
	if not rule then
		return nil -- not part of the progression (abilities)
	end
	local have = player:GetAttribute(Progression.ATTRIBUTE[rule[1]]) or 0
	if have >= rule[2] then
		return nil
	end
	return `{have} / {rule[2]} {Progression.LABEL[rule[1]]}`
end

return Progression
