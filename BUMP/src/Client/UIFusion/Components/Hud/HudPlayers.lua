--!nonstrict
--[[
	The seats down the side (eight: Tokens.SeatCount): each face in its seat's colour with the gold they've won this
	session. Struck through when knocked out of the game being played.

	props: Source, Layout, Shown (state).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local ROOM = 10
local GAP = 4

return function(scope, props)
	local layout = props.Layout.Players
	local players = Source.Value(scope, props.Source, "Players", {})
	return scope:UiReveal({
		Name = "Players",
		Shown = props.Shown,
		From = Vector2.new(layout.Anchor.X > 0.5 and 24 or -24, 0),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width + ROOM * 2, (layout.Row + GAP) * Tokens.SeatCount + ROOM * 2),
		Children = {
			scope:New("Frame")({
				Name = "List",
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.new(1, -ROOM * 2, 1, -ROOM * 2),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New("UIListLayout")({
						Padding = UDim.new(0, GAP),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					scope:Computed(function(use, inner)
						local rows = {}
						for index, entry in ipairs(use(players)) do
							table.insert(rows, inner:UiSeat({
								Entry = entry,
								Show = "Gold",
								Height = layout.Row,
								Compact = layout.Compact,
								LayoutOrder = index,
							}))
						end
						return rows
					end),
				},
			}),
		},
	})
end
