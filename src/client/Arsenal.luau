-- The weapon picker (Q, the backpack, or J): a searchable category grid sorted by price, the anime
-- abilities on a tab of their own, sharing the hotbar's selection and loadout (client/WeaponBar).
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local player = Players.LocalPlayer
local Arsenal = {}
local function textButton(parent, text, size, position)
	local b = Instance.new("TextButton")
	b.Text, b.Size, b.Position = text, size, position
	b.Font, b.TextSize, b.TextColor3 = Enum.Font.GothamBold, 13, Color3.new(1, 1, 1)
	b.BackgroundColor3, b.BorderSizePixel = Color3.fromRGB(45, 48, 57), 0
	b.ZIndex, b.Parent = 43, parent
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 7); c.Parent = b
	return b
end
function Arsenal.start(gui, weapons, models, fist, icon, about, api, choose, closeWheel)
	local cover = Instance.new("Frame")
	cover.Name, cover.Size = "Arsenal", UDim2.fromScale(1, 1)
	cover.BackgroundColor3, cover.BackgroundTransparency = Color3.new(0, 0, 0), 0.35
	cover.ZIndex, cover.Visible, cover.Active, cover.Parent = 40, false, true, gui
	local panel = Instance.new("Frame")
	panel.Name, panel.Size, panel.Position, panel.AnchorPoint = "Panel", UDim2.fromScale(0.92, 0.72), UDim2.fromScale(0.5, 0.49), Vector2.new(0.5, 0.5)
	panel.BackgroundColor3, panel.BorderSizePixel, panel.ZIndex, panel.Parent = Color3.fromRGB(22, 24, 30), 0, 41, cover
	local max = Instance.new("UISizeConstraint"); max.MaxSize, max.Parent = Vector2.new(840, 630), panel
	local c = Instance.new("UICorner"); c.CornerRadius, c.Parent = UDim.new(0, 12), panel
	local title = textButton(panel, "ARSENAL", UDim2.new(1, -62, 0, 42), UDim2.fromOffset(8, 8))
	title.BackgroundColor3, title.AutoButtonColor, title.TextXAlignment = Color3.fromRGB(143, 46, 44), false, Enum.TextXAlignment.Left
	local padding = Instance.new("UIPadding"); padding.PaddingLeft, padding.Parent = UDim.new(0, 12), title
	local x = textButton(panel, "X", UDim2.fromOffset(38, 42), UDim2.new(1, -46, 0, 8))
	local tabs = Instance.new("Frame")
	tabs.Name, tabs.Position, tabs.Size = "Categories", UDim2.fromOffset(8, 58), UDim2.new(1, -16, 0, 34)
	tabs.BackgroundTransparency, tabs.ZIndex, tabs.Parent = 1, 42, panel
	local list = Instance.new("UIListLayout"); list.FillDirection, list.Padding, list.Parent = Enum.FillDirection.Horizontal, UDim.new(0, 5), tabs
	local search = Instance.new("TextBox")
	search.Name, search.PlaceholderText, search.Text = "Search", "Search weapons...", ""
	search.Size, search.Position = UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 100)
	search.BackgroundColor3, search.TextColor3, search.PlaceholderColor3 = Color3.fromRGB(36, 39, 48), Color3.new(1, 1, 1), Color3.fromRGB(171, 178, 188)
	search.Font, search.TextSize, search.ClearTextOnFocus, search.ZIndex, search.Parent = Enum.Font.Gotham, 14, false, 43, panel
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name, scroll.Position, scroll.Size = "Weapons", UDim2.fromOffset(8, 140), UDim2.new(1, -16, 1, -148)
	scroll.BackgroundTransparency, scroll.BorderSizePixel, scroll.ScrollBarThickness, scroll.ZIndex = 1, 0, 5, 42
	scroll.CanvasSize, scroll.AutomaticCanvasSize, scroll.Parent = UDim2.new(), Enum.AutomaticSize.Y, panel
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding, grid.SortOrder, grid.Parent = UDim2.fromOffset(8, 8), Enum.SortOrder.LayoutOrder, scroll
	local selectedCategory, cards, buttons = "all", {}, {}
	local function refresh()
		local columns = scroll.AbsoluteSize.X < 550 and 2 or 4
		grid.CellSize = UDim2.new(1 / columns, -10, 0, 150)
		title.Text = `ARSENAL   /   KILL FOR CASH   /   {player:GetAttribute(Progression.CASH) or 0}$`
		local query = search.Text:lower()
		for i, card in cards do
			local w = card.w
			local group = if w.tag == "heavy" then "thrown" else w.tag -- EXPLOSIVES holds both
			card.frame.Visible = (selectedCategory == "all" or group == selectedCategory) and w.name:lower():find(query, 1, true) ~= nil
			local equipped = api.get() == i
			local lock = api.locked and api.locked(i) -- weapon progression: what it still needs
			local price = lock and i <= #weapons and Progression.PRICE[w.id]
			local afford = price and (player:GetAttribute(Progression.CASH) or 0) >= price
			card.button.Text = afford and `BUY {lock}` or lock and `🔒 {lock}` or equipped and "EQUIPPED" or "EQUIP"
			card.button.BackgroundColor3 = afford and Color3.fromRGB(196, 140, 30) or lock and Color3.fromRGB(70, 70, 78) or equipped and Color3.fromRGB(56, 111, 83) or Color3.fromRGB(43, 128, 76)
		end
		for category, b in buttons do b.BackgroundColor3 = category == selectedCategory and Color3.fromRGB(132, 83, 50) or Color3.fromRGB(45, 48, 57) end
	end
	for _, entry in { {"all", "ALL"}, {"melee", "MELEE"}, {"gun", "RANGED"}, {"thrown", "EXPLOSIVES"}, {"ability", "ABILITIES"} } do
		local b = textButton(tabs, entry[2], UDim2.new(0.2, -4, 1, 0), UDim2.new())
		buttons[entry[1]] = b
		b.Activated:Connect(function() selectedCategory = entry[1]; scroll.CanvasPosition = Vector2.zero; refresh() end)
	end
	local function setOpen(on)
		if on and api.blocked() then return end
		if on then closeWheel() end
		if on and not cover.Visible then
			game:GetService("ReplicatedStorage").Remotes.Action:FireServer("opened", "Arsenal") -- the Menus funnel (server/Funnels)
		end
		cover.Visible = on
		gui:SetAttribute("WeaponPickerOpen", on)
		api.freeze(on)
		UIS.MouseIconEnabled = on
		if on then refresh() else search:ReleaseFocus() end
	end
	-- cards: the weapons cheapest first (free ones first, the group's Frostgun last), then the abilities
	local entries = {}
	for i, w in weapons do
		local price = Progression.PRICE[w.id] or (if Progression.GROUP[w.id] then math.huge else 0)
		table.insert(entries, { i = i, w = w, price = price })
	end
	table.sort(entries, function(a, b)
		return if a.price ~= b.price then a.price < b.price else a.i < b.i
	end)
	for k, a in api.attacks or {} do
		table.insert(entries, { i = api.attackFrom + k, w = { id = a.id, name = a.name, tag = "ability", color = a.color, cd = a.cd } })
	end
	for order, e in entries do
		local i, w = e.i, e.w
		local frame = Instance.new("Frame")
		frame.Name, frame.LayoutOrder, frame.BackgroundColor3, frame.ZIndex, frame.Parent = w.id, order, Color3.fromRGB(35, 37, 46), 42, scroll
		local holder = Instance.new("Frame"); holder.Size, holder.Position, holder.BackgroundTransparency, holder.ZIndex, holder.Parent = UDim2.new(1, -12, 0, 75), UDim2.fromOffset(6, 22), 1, 43, frame
		if w.tag == "ability" then -- an orb in its colour, as on the hotbar
			local orb = Instance.new("Frame")
			orb.AnchorPoint, orb.Position, orb.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(52, 52)
			orb.BackgroundColor3, orb.ZIndex, orb.Parent = w.color, 43, holder
			local oc = Instance.new("UICorner"); oc.CornerRadius, oc.Parent = UDim.new(0.5, 0), orb
		else
			local vp = icon(models[w.id] or fist, holder, w.id); vp.ZIndex = 43
		end
		local name = textButton(frame, w.name, UDim2.new(1, -8, 0, 20), UDim2.fromOffset(4, 2))
		name.TextSize, name.TextScaled, name.BackgroundTransparency, name.AutoButtonColor = 11, true, 1, false
		local tc = Instance.new("UITextSizeConstraint"); tc.MaxTextSize, tc.MinTextSize, tc.Parent = 11, 8, name
		local detail = textButton(frame, if w.cd then `Ability · {w.cd} s cooldown` else about[w.id] or w.tag, UDim2.new(1, -8, 0, 20), UDim2.fromOffset(4, 94))
		detail.TextSize, detail.TextScaled, detail.BackgroundTransparency, detail.AutoButtonColor = 9, true, 1, false
		local dc = Instance.new("UITextSizeConstraint"); dc.MaxTextSize, dc.MinTextSize, dc.Parent = 10, 8, detail
		local equip = textButton(frame, "EQUIP", UDim2.new(1, -12, 0, 27), UDim2.new(0, 6, 1, -31))
		equip.Activated:Connect(function()
			if i <= #weapons and api.locked(i) and Progression.PRICE[w.id] then
				api.buy(i) -- stays open: the card turns to EQUIP once it is theirs (refresh below)
				return
			end
			choose(i); setOpen(false)
		end)
		cards[i] = { frame = frame, button = equip, w = w }
	end
	search:GetPropertyChangedSignal("Text"):Connect(refresh)
	player.AttributeChanged:Connect(function(attribute) -- cash in, a weapon bought
		if cover.Visible and (attribute == Progression.CASH or attribute:sub(1, 3) == "Own") then refresh() end
	end)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	x.Activated:Connect(function() setOpen(false) end)
	UIS.InputBegan:Connect(function(input, processed)
		if processed or UIS:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.J then setOpen(not cover.Visible)
		elseif cover.Visible and input.KeyCode == Enum.KeyCode.Escape then setOpen(false) end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.15 then return end
		elapsed = 0
		if cover.Visible and (api.blocked() or not gui.Enabled) then setOpen(false) end
	end)
	-- (on): open / close, (nil): toggle, (nil, true): only ask. Returns whether it is open.
	return function(on: boolean?, query: boolean?): boolean
		if not query then
			setOpen(if on == nil then not cover.Visible else on)
		end
		return cover.Visible
	end
end
return Arsenal
