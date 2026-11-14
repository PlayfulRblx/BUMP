--!nonstrict
--[[
	Top centre while a game is on: a small pill with how many are still in and, for a game with a
	clock, the time left (it turns to the alert tone in the last seconds). The user picked the
	minimal layout (2026-11-14: "we should also change that UI in the middle"): the game's name
	and where it is in the session sit small in the corner (HudRound), the game's line of the
	moment under this as bare text (HudNote).

	props: Source, Layout (a whole Tokens.Layout entry), Shown (state).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local ROOM = 10

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return function(scope, props)
	local source = props.Source
	local layout = props.Layout.Status
	local compact = layout.Compact
	local minigame = Source.Value(scope, source, "Minigame", false)
	local timeLeft = Source.Value(scope, source, "TimeLeft", 0)
	local alive = Source.Value(scope, source, "Alive", 0)
	local hasClock = scope:Computed(function(use)
		local game = use(minigame)
		return not (game and game.NoClock)
	end)
	local urgent = scope:Computed(function(use)
		return use(timeLeft) <= Tokens.Timing.UrgentSeconds
	end)
	local height = compact and 38 or 48
	local half = compact and 66 or 84 -- one side of the pill: the clock or the count
	local width = scope:Computed(function(use)
		return use(hasClock) and half * 2 or half
	end)
	local count = scope:New("Frame")({
		Name = "Count",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, half, 1, 0),
		[Children] = {
			scope:UiCounter({
				Value = alive,
				Format = function(value)
					return tostring(math.floor(value))
				end,
				Type = "DataLarge",
				Flash = "Alert",
				Align = "Right",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, compact and 8 or 12, 0.5, 0),
				Size = UDim2.new(0, compact and 24 or 30, 0, 30),
			}),
			scope:UiText({
				Text = Tokens.Set("left\nin", "Micro"),
				Type = "Micro",
				Role = "Muted",
				Align = "Left",
				Wrap = true,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, compact and 36 or 48, 0.5, 0),
				Size = UDim2.new(0, 30, 0, 26),
			}),
		},
	})
	return scope:UiReveal({
		Name = "Status",
		Shown = props.Shown,
		From = Vector2.new(0, -16),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = scope:Computed(function(use)
			return UDim2.fromOffset(use(width) + ROOM * 2, height + ROOM * 2)
		end),
		Children = {
			scope:UiPlate({
				Radius = "Pill",
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = scope:Computed(function(use)
					return UDim2.fromOffset(use(width), height)
				end),
				Children = {
					-- left: the clock (not every game has one)
					scope:New("Frame")({
						Name = "Clock",
						BackgroundTransparency = 1,
						Size = UDim2.new(0, half, 1, 0),
						Visible = hasClock,
						[Children] = {
							scope:UiCounter({
								Value = timeLeft,
								Format = clock,
								Type = "DataLarge",
								Role = scope:Computed(function(use)
									return use(urgent) and "Alert" or "Primary"
								end),
								Flash = scope:Computed(function(use)
									return use(urgent) and "Alert" or "White"
								end),
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.new(0.5, 4, 0.5, 0),
								Size = UDim2.new(1, -12, 0, 30),
							}),
						},
					}),
					scope:UiLine({
						Vertical = true,
						Visible = hasClock,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(0, half, 0.5, 0),
						Size = UDim2.new(0, 1, 0, height - 18),
					}),
					count,
				},
			}),
		},
	})
end
