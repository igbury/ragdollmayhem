-- Weapon list shared by server (rules) and client (HUD, viewmodel, cooldowns). The order is the
-- order on the hotbar and round the weapon wheel (hold Q), grouped MELEE, RANGED, EXPLOSIVES (keep it so);
-- Q / F / the mouse wheel step through it.
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
	-- the comic set (Crowbar on, in each group): each has its own mechanic in server/Specials (the flamethrower's fire, the
	-- frostgun's freeze, the taser's shock, the lasso's and the harpoon's rope, C4, mines, ...);
	-- knockdown: every blow that lands floors the dummy for that long; spinUp: s of trigger before
	-- the first round; Specials ignores `kind` for the rays it fires itself, the client still uses it.
	-- MELEE
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
	{ id = "Crowbar", name = "CROWBAR", tag = "melee", short = "CRW", kind = "melee", aimSwing = true, hurt = "blunt", cd = 0.45, range = 10, dmg = 2, push = 60, chip = 1.5 },
	{ id = "Sledgehammer", name = "SLEDGEHAMMER", tag = "melee", short = "SLDG", kind = "melee", aimSwing = true, hurt = "blunt", cd = 1.1, range = 11, dmg = 4, push = 130, chip = 3.5, knockdown = 2.5 },
	{ id = "Spear", name = "SPEAR", tag = "melee", short = "SPR", kind = "melee", hurt = "blade", cd = 0.75, range = 15, dmg = 3, push = 45 },
	{ id = "Lightsaber", name = "LIGHTSABER", tag = "melee", short = "LSBR", kind = "melee", aimSwing = true, hurt = "blade", cd = 0.4, range = 12, dmg = 4, push = 30, chip = 1.5 },
	{ id = "Chainsaw", name = "CHAINSAW", tag = "melee", short = "CHNS", kind = "melee", auto = true, hurt = "blade", cd = 0.12, range = 9, dmg = 1.2, push = 6, knockdown = 1 },
	{ id = "Lasso", name = "LASSO", tag = "melee", short = "LSO", kind = "thrown", cd = 1.5, range = 45 },
	-- RANGED
	{ id = "Handgun", name = "HANDGUN", tag = "gun", short = "PSTL", kind = "gun", hurt = "bullet", cd = 0.2, range = 300, dmg = 1.5, push = 22, chip = 1, hip = 0.08 },
	{ id = "Bow", name = "HUNTER BOW", tag = "gun", short = "BOW", kind = "bow", hurt = "blade", cd = 0.7, range = 260, dmg = 4, push = 35, speed = 190 },
	{ id = "Revolver", name = "REVOLVER", tag = "gun", short = "REV", kind = "gun", hurt = "bullet", cd = 0.75, range = 300, dmg = 4.5, push = 75, chip = 2.2, hip = 0.1 },
	{ id = "Shotgun", name = "SHOTGUN", tag = "gun", short = "SHTG", kind = "gun", hurt = "bullet", cd = 0.95, range = 110, dmg = 1.3, push = 34, chip = 1.2, pellets = 8, spread = 0.09, hip = 0.1 },
	{ id = "Rifle", name = "RIFLE", tag = "gun", short = "RFL", kind = "gun", hurt = "bullet", auto = true, cd = 0.09, range = 400, dmg = 1, push = 16, chip = 1, hip = 0.045 },
	{ id = "Sniper", name = "SNIPER", tag = "gun", short = "SNPR", kind = "gun", hurt = "bullet", cd = 1.6, range = 700, dmg = 7, push = 130, chip = 2.5, hip = 0.25 },
	{ id = "Taser", name = "TASER", tag = "gun", short = "TSR", kind = "gun", hurt = "blunt", cd = 1.2, range = 35, dmg = 1, push = 5, hip = 0.06 },
	{ id = "Frostgun", name = "FROST GUN", tag = "gun", short = "FRST", kind = "gun", cd = 0.8, range = 120, dmg = 1, hip = 0.06 },
	{ id = "Boilgun", name = "BOIL GUN", tag = "gun", short = "BOIL", kind = "gun", cd = 0.9, range = 30, dmg = 1, push = 35, hip = 0.1 },
	{ id = "Flamethrower", name = "FLAMETHROWER", tag = "gun", short = "FLAM", kind = "gun", auto = true, cd = 0.1, range = 18, dmg = 2.5, hip = 0.1 },
	{ id = "Minigun", name = "MINIGUN", tag = "gun", short = "MINI", kind = "gun", auto = true, spinUp = 0.5, hurt = "bullet", cd = 0.06, range = 350, dmg = 0.9, push = 12, chip = 0.8, spread = 0.035, hip = 0.06 },
	{ id = "Harpoon", name = "HARPOON", tag = "gun", short = "HARP", kind = "gun", cd = 1.4, range = 120, dmg = 4, speed = 160, hip = 0.05 },
	-- EXPLOSIVES
	{ id = "Grenade", name = "GRENADE", tag = "thrown", short = "GRND", kind = "thrown", cd = 1.5, speed = 70 },
	{ id = "Molotov", name = "MOLOTOV", tag = "thrown", short = "MOLO", kind = "thrown", cd = 1.5, speed = 60 },
	{ id = "Tomato", name = "TOMATO", tag = "thrown", short = "TMT", kind = "thrown", cd = 0.35, speed = 95 },
	{ id = "TNT", name = "TNT", tag = "thrown", short = "TNT", kind = "thrown", cd = 2.5, speed = 45 },
	{ id = "C4", name = "C4", tag = "thrown", short = "C4", kind = "thrown", cd = 0.6, speed = 45 },
	{ id = "Landmine", name = "LANDMINE", tag = "thrown", short = "MINE", kind = "thrown", cd = 1.0 },
	{ id = "Rocket", name = "ROCKET LAUNCHER", tag = "heavy", short = "RPG", kind = "rocket", cd = 2.2, range = 500, speed = 140, hip = 0.12 },
}
