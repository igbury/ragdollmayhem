-- Game pass ownership (shared/Shop has the list): checked on joining and after each purchase in the
-- game, then kept on the player as attributes the server and the client both read.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage.Shared.Shop)

local ShopServer = {}

local byPass = {} -- [pass id] = key
for _, item in Shop.PASSES do
	if item.pass > 0 then
		byPass[item.pass] = item.key
	end
end

local function check(player: Player)
	for _, item in Shop.PASSES do
		if item.pass > 0 then
			task.spawn(function()
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, item.pass)
				if ok and owns and player.Parent then
					player:SetAttribute(Shop.attribute(item.key), true)
				elseif not ok then
					warn("Shop: pass check failed for", player.Name, item.key, owns)
				end
			end)
		end
	end
end

function ShopServer.start()
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		check(player)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		local key = byPass[passId]
		if bought and key then
			player:SetAttribute(Shop.attribute(key), true)
		end
	end)
end

return ShopServer
