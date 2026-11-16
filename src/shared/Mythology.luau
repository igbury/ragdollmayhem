-- Original mythological actors. Seconds are on the shared server clock, not client timers.
return {
	Cyclops = { name = "CYCLOPS", hp = 600, speed = 10, radius = 12, damage = 28, windup = 1.25, recovery = 2.1, reward = 100, scale = 1, color = Color3.fromRGB(163, 137, 101), accent = Color3.fromRGB(236, 181, 68), hint = "Shoot the eye. Jump or leave the amber circle.", attack = "SLAM", weak = "Eye" },
	Minotaur = { name = "MINOTAUR", hp = 480, speed = 12, radius = 8, damage = 24, windup = 1.1, recovery = 2.6, reward = 85, scale = 0.85, color = Color3.fromRGB(101, 63, 48), accent = Color3.fromRGB(234, 108, 73), hint = "Sidestep the charge. Strike during recovery.", attack = "CHARGE", weak = "Head" },
	Talos = { name = "TALOS", hp = 750, speed = 7, radius = 15, damage = 20, windup = 1.6, recovery = 2.4, reward = 120, scale = 1.08, color = Color3.fromRGB(128, 92, 52), accent = Color3.fromRGB(92, 210, 190), hint = "Hit the glowing ankle. Leave the marked impact.", attack = "HAMMER", weak = "AnkleSeal" },
}
