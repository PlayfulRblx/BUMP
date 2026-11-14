--!nonstrict
--[[
	A power-up's icon: a lit disc in the power-up's colour with its glyph, drawn like the coin.
	Dim greys it out (used, or not yours yet).

	props: Id (a power-up id, may be state), Glyph (may be state), Side (40), Dim (may be state),
	plus Name, Position, AnchorPoint, LayoutOrder, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local side = props.Side or 40
	local color = scope:Computed(function(use)
		local base = Tokens.Color(Tokens.PowerColor(use(props.Id)))
		if use(props.Dim) then
			return base:Lerp(Tokens.Color("Faint"), 0.75)
		end
		return base
	end)
	return scope:New("Frame")({
		Name = props.Name or "PowerIcon",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(side, side),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
			scope:New("UIGradient")({
				Rotation = 90,
				Color = Tokens.PlateLight.Color,
			}),
			scope:New("UIStroke")({
				Thickness = math.max(side / 14, 1),
				Color = Tokens.Color("Ink"),
				Transparency = 0.35,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			scope:New("TextLabel")({
				Name = "Glyph",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = props.Glyph or "",
				FontFace = Tokens.Font("Display"),
				TextSize = math.floor(side * 0.56),
				TextColor3 = Tokens.Color("White"),
				TextTransparency = scope:Computed(function(use)
					return use(props.Dim) and 0.5 or 0
				end),
				ZIndex = 2,
			}),
		},
	})
end
