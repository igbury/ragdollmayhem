-- Attack list shared by server (cooldowns) and client (keys, HUD, effect colors).
return {
	{ id = "Barrage", key = Enum.KeyCode.One, name = "RAPID BARRAGE", cd = 3, color = Color3.fromRGB(255, 200, 60) },
	{ id = "Fist", key = Enum.KeyCode.Two, name = "TITAN FIST", cd = 5, color = Color3.fromRGB(255, 95, 50) },
	{ id = "Flip", key = Enum.KeyCode.Three, name = "GROUND FLIP", cd = 6, color = Color3.fromRGB(255, 150, 40) },
	{ id = "Slash", key = Enum.KeyCode.Four, name = "CRESCENT RUSH", cd = 5, color = Color3.fromRGB(60, 210, 255) },
	{ id = "Nova", key = Enum.KeyCode.Five, name = "NOVA BURST", cd = 8, color = Color3.fromRGB(70, 255, 200) },
	{ id = "Ult", key = Enum.KeyCode.Six, name = "CATACLYSM", cd = 15, color = Color3.fromRGB(255, 235, 120) },
}
