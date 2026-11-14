--!nonstrict
--[[
	The dash's charge while you hold to charge it (BUMP): a meter that fills, gold when full.

	props: Source, Layout.
]]

local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local ROOM = 10

return function(scope, props)
	local layout = props.Layout.Charge
	local charge = Source.Value(scope, props.Source, "Charge", 0)
	local shown = scope:Computed(function(use)
		return use(charge) > 0.02
	end)
	return scope:UiReveal({
		Name = "Charge",
		Shown = shown,
		From = Vector2.new(0, 10),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width + ROOM * 2, 52 + ROOM * 2),
		Children = {
			scope:UiPlate({
				Radius = "Pill",
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.fromOffset(layout.Width, 52),
				Padding = 10,
				Children = {
					scope:UiText({
						Text = scope:Computed(function(use)
							return Tokens.Set(use(charge) >= 0.999 and "Full dash!" or "Charging dash", "Micro")
						end),
						Type = "Micro",
						Role = scope:Computed(function(use)
							return use(charge) >= 0.999 and "Accent" or "Soft"
						end),
						Size = UDim2.new(1, 0, 0, 14),
					}),
					scope:UiMeter({
						Value = charge,
						Tone = scope:Computed(function(use)
							return use(charge) >= 0.999 and "Gold" or "White"
						end),
						Trail = false,
						Position = UDim2.fromOffset(0, 20),
						Size = UDim2.new(1, 0, 0, 10),
					}),
				},
			}),
		},
	})
end
