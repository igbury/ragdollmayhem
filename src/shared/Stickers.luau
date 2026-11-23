-- Stickers: small challenges that each pay cash once, ever. LIST's order is the order they are
-- offered in (client/TutorialHud shows the first one not earned as the current challenge, under the
-- next-weapon goal), but any of them is earned whenever it happens. The server awards them
-- (server/Progress.sticker, called from the main script's hit / kill / throw / revive / harm / tomato
-- and from Progress itself for kills and buying); earned ones are "Sticker<id>" player attributes,
-- saved with the progress. Not during the tutorial.
local Stickers = {}

-- touch: the wording on a phone; keys: only doable with a keyboard (no drag or revive button on
-- touch, client/TouchControls), so a phone player is never offered it as the challenge
Stickers.LIST = {
	{ id = "bones", text = "Break a dummy's bone", cash = 15 },
	{ id = "wall", text = "F to drag, click to kick it into a wall", cash = 20, keys = true },
	{ id = "buy", text = "Buy a weapon in the Arsenal", cash = 20 },
	{ id = "throw", text = "E to grab, click to throw a dummy", touch = "GRAB a dummy, ATTACK to throw it", cash = 25 },
	{ id = "ko10", text = "Knock out 10 dummies", cash = 40 },
	{ id = "revive", text = "Revive a downed dummy with R", cash = 20, keys = true },
	{ id = "headshot", text = "Pop a dummy's head", cash = 30 },
	{ id = "limb", text = "Take a dummy's limb off", cash = 30 },
	{ id = "tomato", text = "Hit a dummy with a tomato", cash = 15 },
	{ id = "fire", text = "Set a dummy on fire", cash = 30 },
	{ id = "boom", text = "Catch a dummy in an explosion", cash = 35 },
	{ id = "ko100", text = "Knock out 100 dummies", cash = 150 },
}
-- studs a throw has to carry a dummy for "throw" (as the STATS page measures it): a level throw at
-- spawn went 27, so this is any real throw, not a drop
Stickers.THROW = 20

local byId = {}
for _, sticker in Stickers.LIST do
	byId[sticker.id] = sticker
end

function Stickers.get(id: string)
	return byId[id]
end

function Stickers.attribute(id: string): string
	return "Sticker" .. id
end

return Stickers
