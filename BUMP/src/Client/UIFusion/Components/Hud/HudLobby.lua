--!nonstrict
--[[
	The count to the next thing, as a small pill at the top, in the status bar's place (the user,
	2026-11-14: "move this countdown title card towards the top of the screen. It doesn't need to
	cover the player"; it was a big card in the middle):

	    Lobby         NEXT ROUND IN | 4      and under it "1 player here · 7 bots will fill in"
	    Intermission  UP NEXT  MELTDOWN | 12  and under it "Game 3 of 6 · the shop's open"

	The bots fill every seat players don't (Tokens.SeatCount, 8; it said 4 from before the seats
	went to 8).

	props: Source, Layout (a whole Tokens.Layout entry; its Status slot), Shown (state).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local ROOM = 10

return function(scope, props)
	local source = props.Source
	local layout = props.Layout.Status
	local compact = layout.Compact
	local phase = Source.Value(scope, source, "Phase", "Practice")
	local countdown = Source.Value(scope, source, "Countdown", 0)
	local players = Source.Value(scope, source, "Players", {})
	local coming = Source.Value(scope, source, "NextMinigame", false)
	local index = Source.Value(scope, source, "GameIndex", 1)
	local count = Source.Value(scope, source, "GameCount", 1)
	local between = scope:Computed(function(use)
		return use(phase) == "Intermission"
	end)
	local height = compact and 38 or 48
	local width = compact and 230 or 300
	local count_ = compact and 54 or 66 -- the countdown's end of the pill

	local kicker = scope:Computed(function(use)
		return Tokens.Set(use(between) and "Up next" or "Next round in", "Caption")
	end)
	local title = scope:Computed(function(use)
		local game = use(coming)
		return use(between) and game and string.upper(game.Title) or ""
	end)
	local titleRole = scope:Computed(function(use)
		local game = use(coming)
		return Tokens.GameColor(game and game.Id or nil)
	end)
	local line = scope:Computed(function(use)
		if use(between) then
			return string.format("Game %d of %d · the shop's open", use(index) + 1, use(count))
		end
		local humans = 0
		for _, entry in ipairs(use(players)) do
			if not entry.Bot then
				humans += 1
			end
		end
		local bots = math.max(0, Tokens.SeatCount - humans)
		if bots == 0 then
			return "Every seat's taken"
		end
		return string.format("%d %s here · %d %s will fill in", humans, humans == 1 and "player" or "players", bots, bots == 1 and "bot" or "bots")
	end)

	return scope:UiReveal({
		Name = "Lobby",
		Shown = props.Shown,
		From = Vector2.new(0, -16),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(width + ROOM * 2, height + ROOM * 2 + 26),
		Children = {
			scope:UiPlate({
				Radius = "Pill",
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.fromOffset(width, height),
				Children = {
					-- left: what's coming (in the lobby just the kicker, centred in its space)
					scope:UiText({
						Text = kicker,
						Type = "Caption",
						Role = "Muted",
						Align = "Left",
						AnchorPoint = Vector2.new(0, 0.5),
						Position = scope:Computed(function(use)
							return use(between) and UDim2.new(0, 18, 0.5, compact and -7 or -9) or UDim2.new(0, 18, 0.5, 0)
						end),
						Size = UDim2.new(1, -(count_ + 24), 0, 16),
					}),
					scope:UiText({
						Text = title,
						Type = compact and "Label" or "Title",
						Role = titleRole,
						Align = "Left",
						Fit = true,
						Visible = between,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 18, 0.5, compact and 7 or 9),
						Size = UDim2.new(1, -(count_ + 24), 0, compact and 18 or 22),
					}),
					scope:UiLine({
						Vertical = true,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(1, -count_, 0.5, 0),
						Size = UDim2.new(0, 1, 0, height - 18),
					}),
					-- right: the count
					scope:New("Frame")({
						Name = "Count",
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.new(0, count_, 1, 0),
						[Children] = {
							scope:UiCounter({
								Value = countdown,
								Format = function(value)
									return tostring(math.max(0, math.ceil(value)))
								end,
								Type = "DataLarge",
								Flash = "White",
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.new(0.5, -3, 0.5, 0),
								Size = UDim2.new(1, -10, 0, 30),
							}),
						},
					}),
				},
			}),
			-- under the pill: who's in, or which game of the session it'll be
			scope:UiText({
				Text = line,
				Type = "Small",
				Role = "Soft",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, ROOM + height + 6),
				Size = UDim2.new(1, 0, 0, 18),
			}),
		},
	})
end
