-- The asks, each a comic card top centre, gone after SHOW_TIME (or on OK):
--  * like: "like the game?" Nothing is locked behind it and nothing is given for it (Roblox forbids
--    rewarding likes, and cannot check one anyway). Shown when the saved play time (StatPlaytime,
--    server/Progress) passes one of LIKE_AT and the player has a few stickers.
--  * favorite: Roblox's own favorite prompt, so the game is in their Favorites tomorrow. Nothing
--    given for it either. Asked once, ever (the marks below).
--  * group: Roblox's join prompt for the game's group, whose members get the FROST GUN
--    (shared/Progression GROUP, server/Progress polls membership). Skipped for members.
-- Favorite and group come at whichever is first: a play time mark, or a bought weapon (after a buy
-- the Arsenal is open, a calm moment with a free cursor). Both count what is saved (StatPlaytime, the
-- Own<id> weapons), so each player crosses each one once, ever, with no extra save; the native prompt
-- is clickable even in first person, the card only says why.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local AvatarEditorService = game:GetService("AvatarEditorService")
local GroupService = game:GetService("GroupService")
local Sfx = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Sfx"))

local player = Players.LocalPlayer
local LIKE_AT = { 600, 3600 } -- seconds played
local SHOW_TIME = 12
local INK = Color3.fromRGB(16, 15, 20)
local PAPER = Color3.fromRGB(255, 248, 228)
local CAPTION = Color3.fromRGB(252, 200, 50)
local COMIC = Enum.Font.LuckiestGuy

local gui = Instance.new("ScreenGui")
gui.Name = "LikePrompt"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local function inked(parent: Instance, thickness: number)
	local line = Instance.new("UIStroke")
	line.Thickness, line.Color, line.LineJoinMode = thickness, INK, Enum.LineJoinMode.Miter
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = parent
end

local function label(parent: Instance, text: string, y: number, h: number, font: Enum.Font, color: Color3)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position, t.Size = UDim2.fromOffset(16, y), UDim2.new(1, -32, 0, h)
	t.Font, t.Text, t.TextColor3, t.TextScaled = font, text, color, true
	t.Parent = parent
	return t
end

-- A card with `title` and `body`; `ok` adds an OK button. Returns its close().
local function show(title: string, body: string, ok: boolean): () -> ()
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Size = UDim2.fromOffset(360, if ok then 150 else 104)
	card.Position = UDim2.new(0.5, 0, 0, -170)
	card.BackgroundTransparency = 1
	card.Rotation = -1.5
	card.Parent = gui
	local shadow = Instance.new("Frame")
	shadow.Size, shadow.Position = UDim2.fromScale(1, 1), UDim2.fromOffset(7, 8)
	shadow.BackgroundColor3, shadow.BorderSizePixel = INK, 0
	shadow.Parent = card
	local paper = Instance.new("Frame")
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3, paper.BorderSizePixel = PAPER, 0
	paper.Parent = card
	inked(paper, 4)
	label(paper, title, 10, 36, COMIC, INK)
	label(paper, body, 50, 40, Enum.Font.GothamBold, INK)

	Sfx.ui(Sfx.UI_NOTIFICATION, 0.6)
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(card, info, { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		local away = TweenService:Create(card, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -170) })
		away.Completed:Once(function()
			card:Destroy()
		end)
		away:Play()
	end
	if ok then
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.Position, button.Size = UDim2.new(0.5, 0, 0, 100), UDim2.fromOffset(120, 36)
		button.BackgroundColor3, button.BorderSizePixel = CAPTION, 0
		button.Font, button.Text, button.TextColor3, button.TextSize = COMIC, "OK!", INK, 26
		button.Parent = paper
		inked(button, 3)
		button.Activated:Connect(close)
	end
	task.delay(SHOW_TIME, close)
	return close
end

local function like()
	show("HAVING FUN? 👍", "A like on the game page really helps us keep adding weapons!", true)
end

local function favorite()
	-- (no GetFavorite check: it needs PromptAllowInventoryReadAccess, a scarier prompt than this one)
	local close = show("ADD US TO FAVORITES ⭐", "Find Ragdoll Mayhem in one tap next time you play!", false)
	pcall(AvatarEditorService.PromptSetFavorite, AvatarEditorService, game.PlaceId, Enum.AvatarItemType.Asset, true)
	AvatarEditorService.PromptSetFavoriteCompleted:Once(close)
end

local function group()
	if game.CreatorType ~= Enum.CreatorType.Group or player:GetAttribute("InGroup") then
		return
	end
	local close = show("FREE FROST GUN! ❄️", "Join Cadabula Studios and the FROST GUN is yours.", false)
	task.spawn(function()
		pcall(GroupService.PromptJoinAsync, GroupService, game.CreatorId)
		close()
	end)
end

-- the saved play time and weapons arrive with ProgressLoaded; only what changes after that counts
if not player:GetAttribute("ProgressLoaded") then
	player:GetAttributeChangedSignal("ProgressLoaded"):Wait()
end

-- [ask] = { seconds played, weapons owned (the tutorial's pistol is the first) }, whichever comes first
local ASKS = {
	{ run = favorite, at = 180, owned = 2 },
	{ run = group, at = 420, owned = 3 },
}
local function owned(): number
	local n = 0
	for name, value in player:GetAttributes() do
		if name:sub(1, 3) == "Own" and value == true then
			n += 1
		end
	end
	return n
end
local done = {}
local lastPlayed, lastOwned = player:GetAttribute("StatPlaytime") or 0, owned()
local function check(played: number, have: number)
	for _, ask in ASKS do
		local crossed = (lastPlayed < ask.at and played >= ask.at) or (lastOwned < ask.owned and have >= ask.owned)
		if crossed and not done[ask] then
			done[ask] = true
			task.delay(1, function() -- after the buy's own pop, and never over the tutorial's lines
				while player:GetAttribute("Tutorial") ~= false do
					player:GetAttributeChangedSignal("Tutorial"):Wait()
				end
				ask.run()
			end)
			break -- one at a time; a later one waits for its own mark
		end
	end
	lastPlayed, lastOwned = played, have
end

-- Like: asked after a good moment, not just after time: a mark reached with fewer than MIN_STICKERS
-- stickers (shared/Stickers) waits for the one that makes it, and comes up once its pop (client/TutorialHud) is over.
local MIN_STICKERS = 3
local pending = false
local function stickers(): number
	local n = 0
	for name, value in player:GetAttributes() do
		if name:sub(1, 7) == "Sticker" and value == true then
			n += 1
		end
	end
	return n
end
local lastLike = lastPlayed
player:GetAttributeChangedSignal("StatPlaytime"):Connect(function()
	local now = player:GetAttribute("StatPlaytime") or 0
	for _, mark in LIKE_AT do
		if lastLike < mark and now >= mark then
			if stickers() >= MIN_STICKERS then
				like()
			else
				pending = true
			end
			break
		end
	end
	lastLike = now
	check(now, lastOwned)
end)
player.AttributeChanged:Connect(function(name)
	if pending and name:sub(1, 7) == "Sticker" and stickers() >= MIN_STICKERS then
		pending = false
		task.delay(4, like)
	elseif name:sub(1, 3) == "Own" then
		check(lastPlayed, owned())
	end
end)

return nil
