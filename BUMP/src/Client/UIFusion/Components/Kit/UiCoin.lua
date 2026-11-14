--!nonstrict
--[[
	A gold coin, drawn rather than imported: a round disc lit from the top, a darker rim and a
	stamped B. Sits beside every amount of gold.

	props: Side (its size, 18), plus Name, Position, AnchorPoint, LayoutOrder, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local side = props.Side or 18
	return scope:New("Frame")({
		Name = props.Name or "Coin",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(side, side),
		BackgroundColor3 = Tokens.Color("Gold"),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
			scope:New("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Tokens.Color("Gold"):Lerp(Color3.new(1, 1, 1), 0.35), Tokens.Color("GoldDeep")),
			}),
			scope:New("UIStroke")({
				Thickness = math.max(side / 12, 1),
				Color = Tokens.Color("GoldDeep"),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			scope:New("TextLabel")({
				Name = "Stamp",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "B",
				FontFace = Tokens.Font("Display"),
				TextSize = math.floor(side * 0.62),
				TextColor3 = Tokens.Color("GoldDeep"),
				ZIndex = 2,
			}),
		},
	})
end
