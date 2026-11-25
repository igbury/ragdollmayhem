-- Game pass ownership (shared/Shop has the list): checked on joining and after each purchase in the
-- game, then kept on the player as attributes the server and the client both read.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage.Shared.Shop)
local Funnels = require(script.Parent.Funnels)
local Progress = require(script.Parent.Progress)

local ShopServer = {}

local byPass = {} -- [pass id] = key
for _, item in Shop.PASSES do
	if item.pass > 0 then
		byPass[item.pass] = item.key
	end
end

local packs = {} -- [product id] = cash it pays
for _, pack in Shop.CASH_PACKS do
	packs[pack.product] = pack.cash
end

-- The cash packs (shared/Shop): paid only once Progress has saved them, else Roblox retries later.
local function processReceipt(info): Enum.ProductPurchaseDecision
	local cash = packs[info.ProductId]
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if cash and player and Progress.grantCash(player, cash, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not cash then
		warn("Shop: unknown product", info.ProductId)
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function check(player: Player)
	if game:GetService("RunService"):IsStudio() then
		return -- a Studio play is a first visit: the owner's passes stay off (a purchase in the session still counts)
	end
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
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		local key = byPass[passId]
		if bought and key then
			player:SetAttribute(Shop.attribute(key), true)
		end
		if key then
			Funnels.pass(player, key, bought) -- the Shop funnel
		end
	end)
end

return ShopServer
