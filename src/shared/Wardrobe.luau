-- The Toolbox WARDROBE: catalog items a player dresses dummies in (client/Toolbox, server/Dresser).
-- Ids are the catalog's most favourited Hats, Classic Shirts and Classic Pants (catalog.roblox.com,
-- 2026-11-20); nobody needs to own them, a dummy wears any public item. A style is a player attribute
-- "Wardrobe" (shared/Settings, saved with the progress): "hat,shirt,pants,hatColor,shirtColor,pantsColor",
-- item 0 = none, colour 1 = as it comes.
local Wardrobe = {}

Wardrobe.CATEGORIES = {
	{ key = "hat", name = "HATS", items = {
		{ id = 607702162, name = "Cap" }, { id = 417457461, name = "R Cap" }, { id = 617605556, name = "Hood" },
		{ id = 1365767, name = "Valkyrie" }, { id = 139152472, name = "Crown" }, { id = 4819740796, name = "Robox" },
		{ id = 1374269, name = "Kitty Ears" }, { id = 10476359, name = "Paper Hat" }, { id = 4904891637, name = "Trendy Hat" },
		{ id = 17165040274, name = "Fedora" }, { id = 2646473721, name = "Visor" }, { id = 10159600649, name = "8-Bit Crown" },
		{ id = 96079043, name = "Headphones" }, { id = 63689493, name = "Snow Cap" }, { id = 106012874743955, name = "Cowboy" },
	} },
	{ key = "shirt", name = "SHIRTS", items = {
		{ id = 144076358, name = "Motorcycle" }, { id = 607785314, name = "Jacket" }, { id = 398633584, name = "Denim Hoodie" },
		{ id = 144076436, name = "Striped" }, { id = 398634295, name = "Starburst" }, { id = 3670737444, name = "Pattern" },
		{ id = 382538059, name = "Jersey" }, { id = 398635081, name = "Plaid" }, { id = 382537702, name = "Teal" },
		{ id = 6554200369, name = "Grey Suit" }, { id = 382537085, name = "Pizza" }, { id = 382538295, name = "Guitar Tee" },
		{ id = 4047884939, name = "Fav Pizza" }, { id = 6553589977, name = "White Suit" }, { id = 5134719820, name = "Flannel" },
	} },
	{ key = "pants", name = "PANTS", items = {
		{ id = 144076760, name = "Green Jeans" }, { id = 398634487, name = "Jeans" }, { id = 398633812, name = "Black Jeans" },
		{ id = 398635338, name = "Skater" }, { id = 382537806, name = "Shorts" }, { id = 129459077, name = "Slacks" },
		{ id = 382538503, name = "Sneakers" }, { id = 382537569, name = "Dark Jeans" }, { id = 5197702014, name = "Ripped" },
		{ id = 129458426, name = "Blue Jeans" }, { id = 382537950, name = "Jean Shorts" }, { id = 97118097068276, name = "Dark Pants" },
		{ id = 6960786140, name = "Plaid PJs" }, { id = 6709744935, name = "Vintage" }, { id = 1160488459, name = "Pink" },
	} },
}

-- tints multiplied over the item's own colours; white leaves it as it comes
Wardrobe.COLORS = {
	Color3.new(1, 1, 1),
	Color3.fromRGB(232, 70, 56),
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(252, 220, 60),
	Color3.fromRGB(90, 200, 80),
	Color3.fromRGB(60, 140, 240),
	Color3.fromRGB(150, 90, 220),
	Color3.fromRGB(255, 120, 190),
	Color3.fromRGB(90, 90, 100),
}

export type Style = { items: { number }, colors: { number } } -- per category: item index (0 none), colour index

-- a saved / sent string into a style, every index clamped into range (it comes from a client)
function Wardrobe.parse(text: any): Style
	local n = {}
	for part in (if type(text) == "string" then text else ""):sub(1, 64):gmatch("[^,]+") do
		table.insert(n, math.floor(tonumber(part) or 0))
	end
	local style = { items = {}, colors = {} }
	for i, c in Wardrobe.CATEGORIES do
		local item, color = n[i] or 0, n[i + 3] or 1
		style.items[i] = if item >= 0 and item <= #c.items then item else 0
		style.colors[i] = if color >= 1 and color <= #Wardrobe.COLORS then color else 1
	end
	return style
end

function Wardrobe.format(style: Style): string
	return table.concat(style.items, ",") .. "," .. table.concat(style.colors, ",")
end

-- the catalog id style wears in category i, or nil
function Wardrobe.id(style: Style, i: number): number?
	local item = Wardrobe.CATEGORIES[i].items[style.items[i]]
	return item and item.id
end

return Wardrobe
