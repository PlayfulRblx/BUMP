--!nonstrict
--[[
	Top centre while a game is on: which game it is, the time left, and how many are still in.
	The time turns to the alert tone in the last seconds. A game without a clock (NoClock, Bomber
	Bloxians) leaves the middle empty; its Note shows under the bar (HudNote).

	props: Source, Layout (a whole Tokens.Layout entry), Shown (state).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local ROOM = 10

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return function(scope, props)
	local source = props.Source
	local layout = props.Layout.Status
	local minigame = Source.Value(scope, source, "Minigame", false)
	local index = Source.Value(scope, source, "GameIndex", 1)
	local count = Source.Value(scope, source, "GameCount", 1)
	local timeLeft = Source.Value(scope, source, "TimeLeft", 0)
	local alive = Source.Value(scope, source, "Alive", 0)
	local total = Source.Value(scope, source, "Total", 0)
	local hasClock = scope:Computed(function(use)
		local game = use(minigame)
		return not (game and game.NoClock)
	end)
	local urgent = scope:Computed(function(use)
		return use(timeLeft) <= Tokens.Timing.UrgentSeconds
	end)
	local width = layout.Width
	local height = layout.Compact and 44 or 56
	return scope:UiReveal({
		Name = "Status",
		Shown = props.Shown,
		From = Vector2.new(0, -16),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(width + ROOM * 2, height + ROOM * 2),
		Children = {
			scope:UiPlate({
				Radius = "Pill",
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.fromOffset(width, height),
				Children = {
					-- left: the game and where it is in the playlist
					scope:UiText({
						Text = scope:Computed(function(use)
							local game = use(minigame)
							return game and game.Title or ""
						end),
						Type = layout.Compact and "Label" or "Title",
						Role = "Accent",
						Align = "Left",
						Position = UDim2.new(0, 22, 0, layout.Compact and 4 or 6),
						Size = UDim2.new(0.38, 0, 0, layout.Compact and 20 or 26),
						Fit = true,
					}),
					scope:UiText({
						Text = scope:Computed(function(use)
							return Tokens.Set(string.format("Game %d of %d", use(index), use(count)), "Micro")
						end),
						Type = "Micro",
						Role = "Muted",
						Align = "Left",
						Position = UDim2.new(0, 22, 1, layout.Compact and -18 or -22),
						Size = UDim2.new(0.38, 0, 0, 14),
					}),
					-- middle: the clock (not every game has one)
					scope:New("Frame")({
						Name = "Clock",
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Visible = hasClock,
						[Fusion.Children] = {
							scope:UiCounter({
								Value = timeLeft,
								Format = clock,
								Type = layout.Compact and "DataLarge" or "DataLarge",
								Role = scope:Computed(function(use)
									return use(urgent) and "Alert" or "Primary"
								end),
								Flash = scope:Computed(function(use)
									return use(urgent) and "Alert" or "White"
								end),
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromScale(0.5, 0.5),
								Size = UDim2.new(0.26, 0, 0, 32),
							}),
						},
					}),
					-- right: how many are still in
					scope:UiCounter({
						Value = alive,
						Format = function(value)
							return tostring(math.floor(value))
						end,
						Type = "DataLarge",
						Flash = "Alert",
						Align = "Right",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -22, 0, layout.Compact and 2 or 4),
						Size = UDim2.new(0.3, 0, 0, 30),
					}),
					scope:UiText({
						Text = scope:Computed(function(use)
							return Tokens.Set(string.format("left of %d", use(total)), "Micro")
						end),
						Type = "Micro",
						Role = "Muted",
						Align = "Right",
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -22, 1, layout.Compact and -18 or -22),
						Size = UDim2.new(0.3, 0, 0, 14),
					}),
				},
			}),
		},
	})
end
