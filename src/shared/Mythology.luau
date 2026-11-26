-- Original mythological actors. Seconds are on the shared server clock, not client timers.
-- scale: the rig's size (1 = 12 studs tall; players are 5). radius: the attack's blast. reach: how close a
-- dummy on its feet has to be before it attacks. lunge: how far ahead of it the blow lands (none: on the dummy).
return {
	Cyclops = { name = "CYCLOPS", speed = 14, radius = 18, reach = 24, lunge = 18, windup = 1.25, recovery = 2.1, scale = 3, color = Color3.fromRGB(163, 137, 101), accent = Color3.fromRGB(236, 181, 68), hint = "Slams the ground flat. Throw it a dummy.", attack = "SLAM" },
	Minotaur = { name = "MINOTAUR", speed = 16, radius = 12, reach = 34, lunge = 30, windup = 1.1, recovery = 2.6, scale = 2.8, color = Color3.fromRGB(101, 63, 48), accent = Color3.fromRGB(234, 108, 73), hint = "Charges through anything. Throw it a dummy.", attack = "CHARGE" },
	Talos = { name = "TALOS", speed = 10, radius = 22, reach = 34, windup = 1.6, recovery = 2.4, scale = 3.1, color = Color3.fromRGB(128, 92, 52), accent = Color3.fromRGB(92, 210, 190), hint = "Hammers what it sees. Throw it a dummy.", attack = "HAMMER" },
}
