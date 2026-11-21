-- The player settings (the toolbox SETTINGS page, client/Toolbox + client/Music), kept as player
-- attributes and saved with the progress (server/Progress). One list for client and server.
-- DEFAULTS: what an attribute that was never set means. RANGE: a number setting's min and max.
-- World settings (GRAVITY, RAGDOLL DAMAGE, GRAVE ZOMBIES, BURNING DUMMIES) follow the host: the player who joined
-- the server first (Settings.host). DAMAGE and BONES follow whoever lands the blow.
local Players = game:GetService("Players")

local Settings = {}

Settings.DEFAULTS = {
	MusicOff = false,
	MusicVolume = 1,
	SfxVolume = 1,
	NeverWanted = true, -- WANTED STARS off (server/Wanted): off unless the player turns them on
	RagdollDamage = true, -- falls, throws and slams hurt (server landImpact)
	GraveZombies = true, -- an unbroken grave lets a zombie out after a minute (server/Graves)
	BurningDummies = true, -- fire sets dummies alight and it spreads between them (server/Specials)
	BoneScale = 1, -- how easily bones break
	Gravity = 1, -- times the normal workspace gravity
	DamageScale = 1, -- times the HP a blow takes
	Wardrobe = "", -- the Toolbox WARDROBE style (shared/Wardrobe)
	PerfMode = "auto", -- performance mode (client/PerfMode): "auto" = on for phones and tablets, "on", "off"
	TouchSimple = true, -- touch screens: EASY controls (aim assist, fewer moves) or PRO (client/TouchControls)
}

Settings.RANGE = {
	MusicVolume = { 0, 1 },
	SfxVolume = { 0, 1 },
	BoneScale = { 0.5, 5 },
	Gravity = { 0.5, 2 },
	DamageScale = { 0.5, 10 },
}

function Settings.get(player: Player?, name: string): any
	local v = player and player:GetAttribute(name)
	if v == nil then
		v = Settings.DEFAULTS[name]
	end
	return v
end

-- The player whose world settings apply: the first one still here (GetPlayers is in join order).
function Settings.host(): Player?
	return Players:GetPlayers()[1]
end

return Settings
