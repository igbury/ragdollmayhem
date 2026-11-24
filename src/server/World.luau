-- The host's world settings (shared/Settings: the first player on the server decides):
--  * GRAVITY: workspace gravity times the setting (it replicates, so clients fall the same way).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage.Shared.Settings)

local World = {}

function World.start()
	local baseGravity = workspace.Gravity
	task.spawn(function()
		while true do
			task.wait(1)
			workspace.Gravity = baseGravity * Settings.get(Settings.host(), "Gravity")
		end
	end)
end

return World
