-- Weapon list shared by server (rules) and client (HUD, viewmodel, cooldowns). The order is the
-- order on the hotbar and round the weapon wheel (hold Q); Q / F / the mouse wheel step through it.
-- kind: gun/melee = instant ray, knife = ray with travel time, thrown = physical projectile,
-- rocket = a flying warhead that blows up on the first thing it meets.
-- dmg scales the body-zone damage of a punch, push is the knockback speed,
-- chip is the radius of map knocked out where it lands.
-- hurt is the kind of injury it leaves on a dummy (see hit() on the server): blunt = bruises and
-- broken bones, bullet = bleeding wounds and shattered bones, blade = deep cuts; a blade with
-- dmg >= 4 (the axe, the katana) takes limbs off; a bullet with dmg >= 4 is a heavy round.
-- pellets / spread: a shotgun fires that many rays, each turned off the aim by up to `spread`.
-- hip: from the hip a shot leaves within this many radians of the crosshair; aiming (right
-- mouse) takes it away entirely.
-- tag: the group on the hotbar and wheel (colour), short: the word on a small slot.
-- aimSwing: hold the attack button to pick the swing on a circle: the line's direction is where
-- the blow goes, its length the power (the server scales damage and knockback by it).
return {
	{ id = "Fists", name = "FISTS", tag = "melee", short = "FIST" },
	{ id = "BoxingGloves", name = "BOXING GLOVES", tag = "melee", short = "BOX", kind = "melee", hurt = "blunt", auto = true, cd = 0.30, range = 9, dmg = 1.6, push = 48,
		-- left click with the block up (right mouse): a heavy left that floors whatever it lands on
		heavy = { id = "BoxingHeavy", equipId = "BoxingGloves", cooldownGroup = "BoxingHeavy", kind = "melee", hurt = "blunt", cd = 0.9, range = 9, dmg = 2, push = 80, knockdown = 2.5 } },
	{ id = "Bat", name = "BASEBALL BAT", tag = "melee", short = "BAT", kind = "melee", aimSwing = true, hurt = "blunt", cd = 0.55, range = 11, dmg = 2.5, push = 90, chip = 2.5 },
	{ id = "Pan", name = "FRYING PAN", tag = "melee", short = "PAN", kind = "melee", aimSwing = true, hurt = "blunt", cd = 0.6, range = 10, dmg = 2, push = 120, chip = 1.5 },
	{ id = "Katana", name = "KATANA", tag = "melee", short = "KTN", kind = "melee", aimSwing = true, hurt = "blade", cd = 0.45, range = 12, dmg = 4, push = 40, chip = 2.5 },
	{ id = "Axe", name = "AXE", tag = "melee", short = "AXE", kind = "melee", aimSwing = true, hurt = "blade", cd = 0.8, range = 11, dmg = 4, push = 45, chip = 3.5 },
	{ id = "Knife", name = "KNIFE", tag = "melee", short = "KNF", kind = "knife", hurt = "blade", cd = 0.6, range = 140, speed = 160, dmg = 3, push = 30,
		slash = { id = "KnifeSlash", equipId = "Knife", cooldownGroup = "Knife", kind = "melee", hurt = "blade", cd = 0.35, range = 9, dmg = 2, push = 24 } },
	{ id = "Handgun", name = "HANDGUN", tag = "gun", short = "PSTL", kind = "gun", hurt = "bullet", cd = 0.2, range = 300, dmg = 1.5, push = 22, chip = 1, hip = 0.08 },
	{ id = "Bow", name = "HUNTER BOW", tag = "gun", short = "BOW", kind = "bow", hurt = "blade", cd = 0.7, range = 260, dmg = 4, push = 35, speed = 190 },
	{ id = "Revolver", name = "REVOLVER", tag = "gun", short = "REV", kind = "gun", hurt = "bullet", cd = 0.75, range = 300, dmg = 4.5, push = 75, chip = 2.2, hip = 0.1 },
	{ id = "Shotgun", name = "SHOTGUN", tag = "gun", short = "SHTG", kind = "gun", hurt = "bullet", cd = 0.95, range = 110, dmg = 1.3, push = 34, chip = 1.2, pellets = 8, spread = 0.09, hip = 0.1 },
	{ id = "Rifle", name = "RIFLE", tag = "gun", short = "RFL", kind = "gun", hurt = "bullet", auto = true, cd = 0.09, range = 400, dmg = 1, push = 16, chip = 1, hip = 0.045 },
	{ id = "Sniper", name = "SNIPER", tag = "gun", short = "SNPR", kind = "gun", hurt = "bullet", cd = 1.6, range = 700, dmg = 7, push = 130, chip = 2.5, hip = 0.25 },
	{ id = "Grenade", name = "GRENADE", tag = "thrown", short = "GRND", kind = "thrown", cd = 1.5, speed = 70 },
	{ id = "Molotov", name = "MOLOTOV", tag = "thrown", short = "MOLO", kind = "thrown", cd = 1.5, speed = 60 },
	{ id = "Tomato", name = "TOMATO", tag = "thrown", short = "TMT", kind = "thrown", cd = 0.35, speed = 95 },
	{ id = "Rocket", name = "ROCKET LAUNCHER", tag = "heavy", short = "RPG", kind = "rocket", cd = 2.2, range = 500, speed = 140, hip = 0.12 },
}
