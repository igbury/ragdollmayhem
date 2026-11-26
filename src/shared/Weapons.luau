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
	{ id = "Handgun", name = "HANDGUN", tag = "gun", short = "PSTL", kind = "gun", hurt = "bullet", cd = 0.2, range = 300, dmg = 1.5, push = 22, chip = 1 },
	{ id = "Bow", name = "HUNTER BOW", tag = "gun", short = "BOW", kind = "bow", hurt = "blade", cd = 0.7, range = 260, dmg = 4, push = 35, speed = 190 },
	{ id = "Revolver", name = "REVOLVER", tag = "gun", short = "REV", kind = "gun", hurt = "bullet", cd = 0.75, range = 300, dmg = 4.5, push = 75, chip = 2.2 },
	{ id = "Shotgun", name = "SHOTGUN", tag = "gun", short = "SHTG", kind = "gun", hurt = "bullet", cd = 0.95, range = 110, dmg = 1.3, push = 34, chip = 1.2, pellets = 8, spread = 0.09 },
	{ id = "Rifle", name = "RIFLE", tag = "gun", short = "RFL", kind = "gun", hurt = "bullet", auto = true, cd = 0.09, range = 400, dmg = 1, push = 16, chip = 1 },
	{ id = "Sniper", name = "HEAVY SNIPER", tag = "gun", short = "SNPR", kind = "gun", hurt = "bullet", cd = 1.6, range = 700, dmg = 21, push = 390, chip = 2.5, torsoKill = true }, -- the head bursts (dmg >= 4), the chest or stomach kills outright
	{ id = "Taser", name = "TASER", tag = "gun", short = "TSR", kind = "gun", hurt = "blunt", cd = 1.2, range = 35, dmg = 1, push = 5 },
	{ id = "Frostgun", name = "FROST GUN", tag = "gun", short = "FRST", kind = "gun", cd = 0.8, range = 120, dmg = 1 },
	{ id = "Boilgun", name = "BOIL GUN", tag = "gun", short = "BOIL", kind = "gun", cd = 0.9, range = 30, dmg = 1, push = 35 },
	{ id = "Flamethrower", name = "FLAMETHROWER", tag = "gun", short = "FLAM", kind = "gun", auto = true, cd = 0.1, range = 18, dmg = 2.5 },
	{ id = "Minigun", name = "MINIGUN", tag = "gun", short = "MINI", kind = "gun", auto = true, spinUp = 0.5, hurt = "bullet", cd = 0.06, range = 350, dmg = 0.9, push = 12, chip = 0.8 },
	{ id = "Harpoon", name = "HARPOON", tag = "gun", short = "HARP", kind = "gun", cd = 1.4, range = 120, dmg = 4, speed = 160 },
	-- grapple: the hook bites and reels the shooter in; on a dummy the ride ends in a flying kick (dmg, push)
	{ id = "Grapple", name = "GRAPPLE GUN", tag = "gun", short = "GRPL", kind = "gun", cd = 1.0, range = 160, dmg = 2.5, push = 85, speed = 200 },
	-- gravity gun: click punts what is in front (range, push); right click pulls a body in from `reach` and
	-- holds it at the claws; a click then launches it at `launch` studs/s (server/Specials, client gravity)
	{ id = "Gravgun", name = "GRAVITY GUN", tag = "gun", short = "GRAV", kind = "gun", cd = 0.5, range = 24, dmg = 1.2, push = 120, reach = 70, launch = 170 },
	-- balloon gun: each hit ties a balloon to the limb it struck (server/Specials): one slows a fall,
	-- two hold the body where it is, three and more carry it up
	{ id = "BalloonGun", name = "BALLOON GUN", tag = "gun", short = "BLN", kind = "gun", cd = 0.45, range = 220 },
	-- leaf blower: held, a wind cone out to `range` that topples dummies and blows them away at up to
	-- `push` studs/s (server/Specials blow); aimed down, `thrust` studs/s a tick lifts you (client useWeapon)
	{ id = "LeafBlower", name = "LEAF BLOWER", tag = "gun", short = "BLOW", kind = "gun", auto = true, cd = 0.1, range = 24, push = 60, thrust = 24 },
	-- cosmic power: an ability, no weapon in hand: held, a beam of comic cosmic energy from the palm that
	-- holds on the dummy under the crosshair (server/Specials cosmic, client Fx Cosmic)
	{ id = "CosmicPower", name = "COSMIC POWER", tag = "gun", short = "CSMC", kind = "gun", auto = true, cd = 0.1, range = 70, dmg = 0.5, push = 20 },
	-- web shot: an ability, no weapon in hand: the web sticks the dummy to the wall behind it (server/Specials web, client Fx Web)
	{ id = "WebShot", name = "WEB SHOT", tag = "gun", short = "WEB", kind = "gun", cd = 0.6, range = 90, dmg = 1, push = 0 },
	-- ground slam: an ability: a leap and a hard landing that throws everyone round it (client useWeapon leap, server/Specials groundSlam, client Fx GroundSlam)
	{ id = "GroundSlam", name = "GROUND SLAM", tag = "gun", short = "SLAM", kind = "gun", cd = 1.6, range = 14, dmg = 20, push = 55, leap = 75 },
	-- EXPLOSIVES
	{ id = "Grenade", name = "GRENADE", tag = "thrown", short = "GRND", kind = "thrown", cd = 1.5, speed = 70 },
	{ id = "Molotov", name = "MOLOTOV", tag = "thrown", short = "MOLO", kind = "thrown", cd = 1.5, speed = 60 },
	{ id = "Tomato", name = "TOMATO", tag = "thrown", short = "TMT", kind = "thrown", cd = 0.35, speed = 95 },
	{ id = "TNT", name = "TNT", tag = "thrown", short = "TNT", kind = "thrown", cd = 2.5, speed = 45 },
	{ id = "C4", name = "C4", tag = "thrown", short = "C4", kind = "thrown", cd = 0.6, speed = 45 },
	{ id = "Landmine", name = "LANDMINE", tag = "thrown", short = "MINE", kind = "thrown", cd = 1.0 },
	{ id = "Rocket", name = "ROCKET LAUNCHER", tag = "heavy", short = "RPG", kind = "rocket", cd = 2.2, range = 500, speed = 140 },
	-- TOOLS
	-- bandage: aim at the stump of a torn-off limb (within `range`) and click: it is dressed and stops
	-- bleeding (server Body.playerBandage; client MedicAim shows which stump the click would take)
	{ id = "Bandage", name = "BANDAGE", tag = "tool", short = "BNDG", kind = "bandage", cd = 0.8, range = 10 },
	-- cast: aim at an arm or a leg with a broken bone and click: it goes in a plaster cast (server
	-- Body.playerCast; client MedicAim lights up the limb)
	{ id = "Cast", name = "PLASTER CAST", tag = "tool", short = "CAST", kind = "cast", cd = 1.2, range = 10 },
	-- balloons: aim at a dummy's limb within `range` and click: a balloon is tied to it, the Balloon Gun's
	-- (server Specials tieByHand): 1 slows a fall, 2 hover, 3+ lift
	{ id = "Balloon", name = "BALLOONS", tag = "tool", short = "BLNS", kind = "balloon", cd = 0.5, range = 10 },
	-- syringes: aim at a dummy within `range` and click (server Body.playerSyringe); one mesh, the serum's
	-- colour set per id (client/WeaponMeshes VARIANTS)
	{ id = "DeathSyringe", name = "DEATH SYRINGE", tag = "tool", short = "DTH", kind = "syringe", cd = 1.5, range = 9 },
	{ id = "HealSyringe", name = "HEALING SYRINGE", tag = "tool", short = "HEAL", kind = "syringe", cd = 1.5, range = 9 },
}
