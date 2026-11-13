-- Weapon list shared by server (rules) and client (HUD, viewmodel, cooldowns). Q cycles through it.
-- kind: gun/melee = instant ray, knife = ray with travel time, thrown = physical projectile.
-- dmg scales the body-zone damage of a punch, push is the knockback speed,
-- chip is the radius of map knocked out where it lands.
return {
	{ id = "Fists", name = "FISTS" },
	{ id = "Bat", name = "BASEBALL BAT", kind = "melee", cd = 0.55, range = 11, dmg = 2.5, push = 90, chip = 2.5 },
	{ id = "Axe", name = "AXE", kind = "melee", cd = 0.8, range = 11, dmg = 4, push = 45, chip = 3.5 },
	{ id = "Knife", name = "THROWING KNIFE", kind = "knife", cd = 0.6, range = 140, speed = 160, dmg = 3, push = 30 },
	{ id = "Handgun", name = "HANDGUN", kind = "gun", cd = 0.2, range = 300, dmg = 1.5, push = 22, chip = 1 },
	{ id = "Revolver", name = "REVOLVER", kind = "gun", cd = 0.75, range = 300, dmg = 4.5, push = 75, chip = 2.2 },
	{ id = "Rifle", name = "RIFLE", kind = "gun", auto = true, cd = 0.09, range = 400, dmg = 1, push = 16, chip = 1 },
	{ id = "Grenade", name = "GRENADE", kind = "thrown", cd = 1.5, speed = 70 },
	{ id = "Molotov", name = "MOLOTOV", kind = "thrown", cd = 1.5, speed = 60 },
}
