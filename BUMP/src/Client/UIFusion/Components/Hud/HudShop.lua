--!nonstrict
--[[
	The shop (the user: power-ups "and progression elements that can be purchased with gold"):
	every power-up in a row with what it does, the level you have it at, and a button to unlock
	or upgrade it for gold; the one you own can be equipped to bring into games. Your level and
	gold are along the top: a power-up's higher levels wait for your level (Gates). The server
	has the last word on every purchase; its answer shows along the bottom.

	props: Source, Layout.
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local GAP = 8

return function(scope, props)
	local layout = props.Layout.Shop
	local compact = layout.Compact == true
	local source = props.Source
	local open = Source.Value(scope, source, "ShopOpen", false)
	local catalogue = Source.Value(scope, source, "Catalogue", {})
	local owned = Source.Value(scope, source, "PowerUps", {})
	local equipped = Source.Value(scope, source, "Equipped", "")
	local gold = Source.Value(scope, source, "MyGold", 0)
	local level = Source.Value(scope, source, "MyLevel", 1)
	local into = Source.Value(scope, source, "MyXpInto", 0)
	local need = Source.Value(scope, source, "MyXpNeed", 1)

	local message = scope:Value("")
	local messageOk = scope:Value(true)
	local serial = 0
	Source.On(scope, source, "ShopReply", function(reply)
		serial += 1
		local mine = serial
		message:set(reply and reply.Message or "")
		messageOk:set(reply and reply.Ok == true)
		task.delay(3, function()
			if serial == mine then
				message:set("")
			end
		end)
	end)

	local function act(action: string, id: string?)
		if source.Do then
			source.Do(action, id)
		end
	end

	local row = layout.Row
	local header = compact and 28 or 36
	local footer = compact and 34 or 40
	local count = 4
	local bodyHeight = header + GAP + count * (row + GAP) + footer
	local titleType = compact and "Title" or "Heading"
	local cardHeight = 36 + Tokens.Type[titleType].Size + 10 + Tokens.Space.S + Tokens.Space.L + bodyHeight
	local buyWidth = compact and 112 or 158
	local equipWidth = compact and 76 or 100
	local buttonHeight = compact and 28 or 32
	local buttons = buyWidth + equipWidth + Tokens.Space.S + Tokens.Space.S

	-- One power-up's row.
	local function shopRow(inner, use, entry, order)
		local have = use(owned)[entry.Id] or 0
		local nextLevel = have + 1
		local maxed = nextLevel > #entry.Prices
		local price = entry.Prices[nextLevel]
		local gate = entry.Gates[nextLevel]
		local gated = not maxed and use(level) < gate
		local short = not maxed and not gated and use(gold) < price
		local isEquipped = use(equipped) == entry.Id
		local buyText
		if maxed then
			buyText = "Maxed"
		elseif gated then
			buyText = "Needs level " .. gate
		else
			buyText = string.format("%s · %d%s", have == 0 and "Unlock" or "Upgrade", price, compact and "" or " gold")
		end
		local describe = entry.Describe[math.max(have, 1)] or ""
		local iconSide = row - 16
		local textLeft = iconSide + 16
		return inner:UiPlate({
			Name = entry.Id,
			Tone = isEquipped and "Accent" or "Lifted",
			Bar = Tokens.PowerColor(entry.Id),
			Size = UDim2.new(1, 0, 0, row),
			LayoutOrder = order,
			Shadow = false,
			Children = {
				inner:UiPowerIcon({
					Id = entry.Id,
					Glyph = entry.Glyph,
					Dim = have == 0,
					Side = iconSide,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 10, 0.5, 0),
				}),
				inner:New("Frame")({
					Name = "Heading",
					Position = UDim2.fromOffset(textLeft, compact and 6 or 8),
					Size = UDim2.new(1, -(textLeft + buttons), 0, 20),
					BackgroundTransparency = 1,
					[Children] = {
						inner:New("UIListLayout")({
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, Tokens.Space.S),
							SortOrder = Enum.SortOrder.LayoutOrder,
						}),
						inner:UiText({
							Text = entry.Name,
							Type = compact and "Body" or "Label",
							Role = have > 0 and "Primary" or "Soft",
							AutoWidth = true,
							LayoutOrder = 1,
						}),
						inner:UiPips({
							Count = have,
							Max = #entry.Prices,
							Tone = Tokens.PowerColor(entry.Id),
							Pip = 8,
							Gap = 4,
							LayoutOrder = 2,
						}),
						not compact and inner:UiText({
							Text = Tokens.Set(describe, "Micro"),
							Type = "Micro",
							Role = "Muted",
							AutoWidth = true,
							LayoutOrder = 3,
						}) or nil,
					},
				}),
				inner:UiText({
					Name = "Blurb",
					Text = compact and Tokens.Set(describe, "Micro") or entry.Blurb,
					Type = compact and "Micro" or "Small",
					Role = "Soft",
					Align = "Left",
					VAlign = "Top",
					Wrap = not compact,
					Position = UDim2.fromOffset(textLeft, compact and 28 or 30),
					Size = UDim2.new(1, -(textLeft + buttons), 0, compact and 14 or row - 36),
				}),
				have > 0 and inner:UiButton({
					Name = "Equip",
					Text = isEquipped and "Equipped" or "Equip",
					Variant = "Quiet",
					Enabled = not isEquipped,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -(buyWidth + Tokens.Space.S * 2), 0.5, 0),
					Size = UDim2.fromOffset(equipWidth, buttonHeight),
					OnPress = function()
						act("ShopEquip", entry.Id)
					end,
				}) or nil,
				inner:UiButton({
					Name = "Buy",
					Text = buyText,
					Variant = "Primary",
					Enabled = not maxed and not gated and not short,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -Tokens.Space.S, 0.5, 0),
					Size = UDim2.fromOffset(buyWidth, buttonHeight),
					OnPress = function()
						act("ShopBuy", entry.Id)
					end,
				}),
			},
		})
	end

	local card = scope:UiCard({
		Name = "Shop",
		Shown = open,
		Kicker = Tokens.Set("Spend your gold", "Caption"),
		Title = "Shop",
		TitleType = titleType,
		Width = layout.Width,
		Height = cardHeight,
		Position = layout.Position,
		ZIndex = 6,
		Children = {
			-- your level and gold
			scope:New("Frame")({
				Name = "Header",
				Size = UDim2.new(1, 0, 0, header),
				BackgroundTransparency = 1,
				[Children] = {
					scope:UiText({
						Text = scope:Computed(function(use)
							return string.format("Level %d  ·  %d / %d XP", use(level), use(into), use(need))
						end),
						Type = compact and "DataSmall" or "Data",
						Role = "Accent",
						Align = "Left",
						Size = UDim2.new(0.6, 0, 0, header - 10),
					}),
					scope:UiMeter({
						Value = scope:Computed(function(use)
							return use(into) / math.max(use(need), 1)
						end),
						Tone = "Accent",
						Trail = false,
						Position = UDim2.new(0, 0, 1, -6),
						Size = UDim2.new(0.45, 0, 0, 5),
					}),
					scope:UiGold({
						Value = gold,
						Type = compact and "Data" or "DataLarge",
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, 0, 0.5, 0),
					}),
				},
			}),
			scope:New("Frame")({
				Name = "Rows",
				Position = UDim2.fromOffset(0, header + GAP),
				Size = UDim2.new(1, 0, 0, count * (row + GAP)),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New("UIListLayout")({
						Padding = UDim.new(0, GAP),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					scope:Computed(function(use, inner)
						local rows = {}
						for order, entry in ipairs(use(catalogue)) do
							table.insert(rows, shopRow(inner, use, entry, order))
						end
						return rows
					end),
				},
			}),
			-- the server's answer, and the way out
			scope:UiText({
				Name = "Message",
				Text = message,
				Type = compact and "Small" or "Body",
				Role = scope:Computed(function(use)
					return use(messageOk) and "Positive" or "Alert"
				end),
				Align = "Left",
				Position = UDim2.new(0, 0, 1, -(footer - 4)),
				Size = UDim2.new(1, -150, 0, footer - 8),
			}),
			scope:UiButton({
				Name = "Close",
				Text = "Close",
				Variant = "Quiet",
				Key = props.Layout.ShopButton.Key,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 0, 1, 0),
				Size = UDim2.fromOffset(compact and 90 or 120, buttonHeight),
				OnPress = function()
					act("ShopClose")
				end,
			}),
		},
	})

	return scope:New("Frame")({
		Name = "ShopLayer",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 6,
		[Children] = {
			scope:UiScrim({ Shown = open, Strength = 0.45, ZIndex = 5 }),
			card,
		},
	})
end
