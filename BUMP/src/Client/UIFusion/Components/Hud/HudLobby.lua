--!nonstrict
--[[
	Between sessions: the count to the next one and who's in. Empty seats are filled by bots
	when it starts.

	props: Source, Layout, Shown (state).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local layout = props.Layout.Card
	local countdown = Source.Value(scope, props.Source, "Countdown", 0)
	local players = Source.Value(scope, props.Source, "Players", {})
	local width = math.min(layout.Width, 460)
	return scope:UiCard({
		Name = "Lobby",
		Shown = props.Shown,
		Kicker = Tokens.Set("Next round in", "Caption"),
		Title = scope:Computed(function(use)
			return tostring(math.max(0, math.ceil(use(countdown))))
		end),
		TitleType = "Mega",
		TitleRole = "Primary",
		Width = width,
		Height = 190,
		Position = layout.Position,
		Children = {
			scope:UiText({
				Text = scope:Computed(function(use)
					local humans = 0
					for _, entry in ipairs(use(players)) do
						if not entry.Bot then
							humans += 1
						end
					end
					local bots = math.max(0, 4 - humans)
					if bots == 0 then
						return "Four players ready"
					end
					return string.format("%d %s here · %d %s will fill in", humans, humans == 1 and "player" or "players", bots, bots == 1 and "bot" or "bots")
				end),
				Type = "Body",
				Role = "Soft",
				Size = UDim2.new(1, 0, 0, 20),
			}),
		},
	})
end
