--!nonstrict
--[[
	After each game: everyone by where they finished, with the gold each earned, and the XP you
	earned under it.

	props: Source, Layout, Shown (state).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local layout = props.Layout.Card
	local source = props.Source
	local minigame = Source.Value(scope, source, "Minigame", false)
	local results = Source.Value(scope, source, "Results", {})
	local row = layout.Width > 500 and 34 or 24
	local gap = layout.Width > 500 and 6 or 4
	return scope:UiCard({
		Name = "Results",
		Shown = props.Shown,
		Kicker = scope:Computed(function(use)
			local game = use(minigame)
			return Tokens.Set((game and game.Title or "") .. " · results", "Caption")
		end),
		Title = scope:Computed(function(use)
			local first = use(results)[1]
			if not first then
				return ""
			end
			return first.You and "You win!" or (first.Name .. " wins!")
		end),
		TitleType = "Heading",
		Width = math.min(layout.Width, 520),
		Height = 110 + (row + gap) * Tokens.SeatCount + 26,
		Position = layout.Position,
		Children = {
			scope:New("UIListLayout")({
				Padding = UDim.new(0, gap),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			scope:Computed(function(use, inner)
				local rows = {}
				for order, entry in ipairs(use(results)) do
					table.insert(rows, inner:New("Frame")({
						Name = "Row" .. order,
						Size = UDim2.new(1, 0, 0, row),
						BackgroundTransparency = 1,
						LayoutOrder = order,
						[Children] = {
							inner:UiPlace({ Place = entry.Place, Side = row - 6, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }),
							inner:UiSeat({
								Entry = entry,
								Show = "Earned",
								Height = row,
								Position = UDim2.fromOffset(row + 4, 0),
								Size = UDim2.new(1, -(row + 4), 0, row),
							}),
						},
					}))
				end
				return rows
			end),
			scope:UiText({
				Name = "Xp",
				Text = scope:Computed(function(use)
					for _, entry in ipairs(use(results)) do
						if entry.You and (entry.Xp or 0) > 0 then
							return Tokens.Set(string.format("+%d XP", entry.Xp), "Caption")
						end
					end
					return ""
				end),
				Type = "Caption",
				Role = "Accent",
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = 99,
			}),
		},
	})
end
