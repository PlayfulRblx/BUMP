--!nonstrict
--[[
	An amount of gold: a coin and the number, on a pill. When it grows the number pops in gold.
	A Gain prefix ("+") shows gold being earned rather than held.

	props: Value (number or state), Gain (true to set it as "+10"), Type ("Data"), Plate (false for
	no pill behind it), plus Name, Position, AnchorPoint, LayoutOrder, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local kindName = props.Type or "Data"
	local size = Tokens.Type[kindName].Size
	local coin = math.floor(size * 1.15)
	local height = math.max(coin, size) + (props.Plate == false and 0 or 12)
	local inner = {
		scope:New("UIListLayout")({
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, math.floor(size * 0.35)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		scope:UiCoin({ Side = coin, LayoutOrder = 1 }),
		scope:UiCounter({
			Value = props.Value,
			Format = function(value)
				return (props.Gain and "+" or "") .. tostring(math.floor(value))
			end,
			Type = kindName,
			Role = props.Gain and "Accent" or "Primary",
			Flash = "Gold",
			AutoWidth = true,
			Align = "Left",
			Size = UDim2.fromOffset(0, size + 6),
			LayoutOrder = 2,
		}),
	}
	if props.Plate == false then
		return scope:New("Frame")({
			Name = props.Name or "Gold",
			AnchorPoint = props.AnchorPoint,
			Position = props.Position,
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = props.LayoutOrder,
			ZIndex = props.ZIndex,
			[Children] = inner,
		})
	end
	return scope:New("Frame")({
		Name = props.Name or "Gold",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Tokens.Color("Plate"),
		BackgroundTransparency = Tokens.Plates.Plate.Transparency,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
			scope:New("UIGradient")({ Rotation = 90, Color = Tokens.PlateLight.Color, Transparency = Tokens.PlateLight.Transparency }),
			Tokens.Shadows() and scope:New("UIShadow")({
				BlurRadius = UDim.new(0, Tokens.Shadow.Blur),
				Offset = UDim2.fromOffset(0, Tokens.Shadow.OffsetY),
				Transparency = Tokens.Shadow.Transparency,
			}) or nil,
			scope:New("UIPadding")({
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, math.floor(size * 0.8)),
			}),
			scope:New("Frame")({
				Name = "Row",
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				[Children] = inner,
			}),
		},
	})
end
