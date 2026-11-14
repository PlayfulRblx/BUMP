--!nonstrict
--[[
	The end of a session: everyone by the gold they won across every game, the leader crowned.

	props: Source, Layout, Shown (state).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local layout = props.Layout.Card
	local standings = Source.Value(scope, props.Source, "Standings", {})
	local row = layout.Width > 500 and 36 or 24
	local gap = layout.Width > 500 and 6 or 4
	return scope:UiCard({
		Name = "Standings",
		Shown = props.Shown,
		Kicker = Tokens.Set("Final standings", "Caption"),
		Title = scope:Computed(function(use)
			local first = use(standings)[1]
			if not first then
				return ""
			end
			return first.You and "You're the champion!" or (first.Name .. " is champion!")
		end),
		TitleType = "Heading",
		Tone = "Accent",
		Width = math.min(layout.Width, 540),
		Height = 112 + (row + gap) * Tokens.SeatCount,
		Position = layout.Position,
		Children = {
			scope:New("UIListLayout")({
				Padding = UDim.new(0, gap),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			scope:Computed(function(use, inner)
				local rows = {}
				for order, entry in ipairs(use(standings)) do
					table.insert(rows, inner:New("Frame")({
						Name = "Row" .. order,
						Size = UDim2.new(1, 0, 0, row),
						BackgroundTransparency = 1,
						LayoutOrder = order,
						[Children] = {
							inner:UiPlace({ Place = entry.Rank, Side = row - 6, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }),
							inner:UiSeat({
								Entry = entry,
								Show = "Gold",
								Height = row,
								Position = UDim2.fromOffset(row + 4, 0),
								Size = UDim2.new(1, -(row + 4) - 70, 0, row),
							}),
							inner:UiTag({
								Text = string.format("%d %s", entry.Wins or 0, (entry.Wins or 0) == 1 and "win" or "wins"),
								Tone = (entry.Wins or 0) > 0 and "Solid" or "Quiet",
								AnchorPoint = Vector2.new(1, 0.5),
								Position = UDim2.new(1, 0, 0.5, 0),
							}),
						},
					}))
				end
				return rows
			end),
		},
	})
end
