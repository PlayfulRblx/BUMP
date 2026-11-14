--!nonstrict
--[[
	Under your gold, always: your level and how far into it you are.

	props: Source, Layout.
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local HEIGHT = 30

return function(scope, props)
	local layout = props.Layout.Level
	local source = props.Source
	local level = Source.Value(scope, source, "MyLevel", 1)
	local into = Source.Value(scope, source, "MyXpInto", 0)
	local need = Source.Value(scope, source, "MyXpNeed", 1)
	return scope:UiPlate({
		Name = "Level",
		Radius = "Pill",
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width, HEIGHT),
		Children = {
			scope:New("Frame")({
				Name = "Badge",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 3, 0.5, 0),
				Size = UDim2.fromOffset(HEIGHT - 6, HEIGHT - 6),
				BackgroundColor3 = Tokens.Color("Accent"),
				BorderSizePixel = 0,
				[Children] = {
					scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
					scope:UiText({
						Text = level,
						Type = "DataSmall",
						Role = "OnLight",
						Outline = false,
						Size = UDim2.fromScale(1, 1),
					}),
				},
			}),
			scope:UiText({
				Text = Tokens.Set("Level", "Micro"),
				Type = "Micro",
				Role = "Soft",
				Align = "Left",
				Position = UDim2.fromOffset(HEIGHT + 2, 2),
				Size = UDim2.new(1, -(HEIGHT + 12), 0, 12),
			}),
			scope:UiMeter({
				Value = scope:Computed(function(use)
					return use(into) / math.max(use(need), 1)
				end),
				Tone = "Accent",
				Trail = false,
				Position = UDim2.fromOffset(HEIGHT + 2, 17),
				Size = UDim2.new(1, -(HEIGHT + 12), 0, 6),
			}),
		},
	})
end
