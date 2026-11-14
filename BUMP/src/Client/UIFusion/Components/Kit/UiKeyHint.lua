--!nonstrict
--[[
	A key cap: the key that does something, drawn small beside it. A pale rounded cap with dark
	lettering, so it reads as a key and not as a label.

	props: Key (string), Side (its height, 16), plus Name, Position, AnchorPoint, LayoutOrder,
	Visible, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local side = props.Side or 16
	local key = tostring(Fusion.peek(props.Key) or "")
	-- Square for a single character; a word gets room for each extra letter.
	local width = side + math.max(#key - 1, 0) * side * 0.5
	return scope:New("Frame")({
		Name = props.Name or "KeyHint",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(width, side),
		BackgroundColor3 = Tokens.Color("White"),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = UDim.new(0, math.max(side * 0.28, 3)) }),
			-- A darker foot, like the lip of a key.
			scope:New("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(0.78, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 184, 176)),
				}),
			}),
			scope:UiText({
				Text = key,
				Type = side < 15 and "Micro" or "DataSmall",
				Role = "OnLight",
				Outline = false,
				Size = UDim2.fromScale(1, 1),
			}),
		},
	})
end
