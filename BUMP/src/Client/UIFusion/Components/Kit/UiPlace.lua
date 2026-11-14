--!nonstrict
--[[
	A finishing place: a round medal in gold, silver or bronze with "1st" stamped on it; fourth
	and below are plain.

	props: Place (number, may be state), Side (its size, 30), plus Name, Position, AnchorPoint,
	LayoutOrder, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local side = props.Side or 30
	local place = scope:Computed(function(use)
		return use(props.Place) or 0
	end)
	local medal = scope:Computed(function(use)
		return use(place) >= 1 and use(place) <= 3
	end)
	return scope:New("Frame")({
		Name = props.Name or "Place",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(side, side),
		BackgroundColor3 = scope:Computed(function(use)
			return use(medal) and Tokens.Color(Tokens.PlaceColor(use(place))) or Tokens.Color("PlateLift")
		end),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
			scope:New("UIGradient")({
				Rotation = 90,
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
			}),
			scope:New("UIStroke")({
				Thickness = 1.5,
				Color = Tokens.Color("Ink"),
				Transparency = 0.6,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			scope:New("TextLabel")({
				Name = "Ordinal",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = scope:Computed(function(use)
					return use(place) > 0 and Tokens.Ordinal(use(place)) or "-"
				end),
				FontFace = Tokens.Font("Display"),
				TextSize = math.floor(side * 0.4),
				TextColor3 = scope:Computed(function(use)
					return use(medal) and Tokens.Color("Ink") or Tokens.Color("White")
				end),
				ZIndex = 2,
			}),
		},
	})
end
