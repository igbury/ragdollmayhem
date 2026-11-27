-- The shop: game passes, bought once and kept for good (Roblox remembers who owns what, nothing to
-- save). The server (server/Shop) puts each owned pass on the player as an attribute "Pass<key>",
-- the client draws the shop from this list (client/Menu) and reads the attributes for the perks.
--
-- `pass`: the game pass id from Creator Hub (Monetization > Passes). 0 = not on sale yet: the shop
-- shows SOON! and nobody owns it. `price` is only shown until Roblox answers with the real one.
local Shop = {}

-- in shop order: the menu's shop panels left to right, top to bottom, BACK in the bottom-left
Shop.PASSES = {
	{ key = "AllGuns", name = "ALL GUNS", price = 65, pass = 2093482820 },
	{ key = "AllMelee", name = "ALL MELEE", price = 55, pass = 2092594925 },
	{ key = "AllExplosives", name = "ALL EXPLOSIVES", price = 100, pass = 2092612886 },
	{ key = "AllWeapons", name = "ALL WEAPONS", price = 200, pass = 2093656889 },
	{ key = "DoubleKO", name = "2X CASH", price = 150, pass = 2096772828 }, -- each kill pays double cash (shared/Progression)
	{ key = "Anime", name = "ANIME ATTACKS", price = 150, pass = 2093668861 }, -- the abilities (shared/Attacks)
	{ key = "SandboxPlus", name = "SANDBOX +", price = 100, pass = 2094442786 }, -- every Toolbox kind, teams, spawning more than 1, higher caps
	{ key = "Doomsday", name = "DOOMSDAY PACK", price = 200, pass = 2099725192 }, -- the powers in Shop.DOOMSDAY
}

-- Cash packs: developer products, bought again and again (server/Shop's ProcessReceipt pays them,
-- client/WeaponBar's buy opens one when short of cash). Kept well under ALL WEAPONS' worth (~86$ per R$) so the pass stays
-- the best deal; `price` is only shown until Roblox answers with the real one.
Shop.CASH_PACKS = {
	{ product = 3736190763, cash = 1000, price = 49 },
	{ product = 3736190836, cash = 2500, price = 99 },
	{ product = 3736190967, cash = 6000, price = 199 },
}

-- The cash pack for someone `short` cash: the smallest that covers it, else the biggest.
function Shop.packFor(short: number)
	for _, pack in Shop.CASH_PACKS do
		if pack.cash >= short then
			return pack
		end
	end
	return Shop.CASH_PACKS[#Shop.CASH_PACKS]
end

-- [weapon tag (shared/Weapons)] = the pass that unlocks every weapon with it
Shop.UNLOCKS = { gun = "AllGuns", melee = "AllMelee", thrown = "AllExplosives", heavy = "AllExplosives" }
-- DOOMSDAY PACK: the powers (shared/Weapons ids) only its pass unlocks (shared/Progression.missing)
Shop.DOOMSDAY = { CosmicPower = true, WebShot = true, GroundSlam = true }
-- 2X CASH (key DoubleKO): each kill pays this many times the cash
Shop.KO_WORTH = 2
-- SANDBOX +: what the Toolbox (client/Toolbox, server "spawn" / "build") keeps for the pass, and the
-- caps without it / with it (blocks per player, living dummies, seconds between one player's SPAWNs,
-- the share of a kill's cash a dummy they spawned pays: spammed spawns farmed 760$/min at 10x DAMAGE)
Shop.SANDBOX = {
	kinds = { Soldier = true, Heavy = true, Worker = true, Zombie = true },
	materials = { Metal = true, Slate = true },
	blocks = { 100, 300 },
	dummies = { 20, 30 },
	spawnCooldown = { 3, 1.5 },
	spawnCash = { 0.1, 0.4 },
}

function Shop.attribute(key: string): string
	return "Pass" .. key
end

function Shop.owns(player: Player, key: string): boolean
	return player:GetAttribute(Shop.attribute(key)) == true
end

-- For what was free before the shop (the anime attacks): locked only once its pass is on sale and
-- the player does not own it, so nothing is taken away while the pass id is still 0.
local byKey = {}
for _, item in Shop.PASSES do
	byKey[item.key] = item
end
function Shop.locked(player: Player, key: string): boolean
	return byKey[key].pass > 0 and not Shop.owns(player, key)
end

-- The PASSES entry for `key`.
function Shop.item(key: string)
	return byKey[key]
end

return Shop
