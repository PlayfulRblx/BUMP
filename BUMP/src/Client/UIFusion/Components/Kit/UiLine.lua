--!nonstrict
--[[
	A rule with round ends: dividers and underlines.

	props: Draw (0 to 1 or state: how much of it is drawn, default 1), From ("Center" | "Left" |
	"Right": where it grows from), Tone (colour name, "White"), Transparency (0.6), Weight (units
	thick, Tokens.Line.Rule), Vertical, plus Name, Position, Size (the full line's box),
	AnchorPoint, ZIndex, LayoutOrder, Visible.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local ANCHORS = {
	Center = Vector2.new(0.5, 0.5),
	Left = Vector2.new(0, 0.5),
	Right = Vector2.new(1, 0.5),
}

return function(scope, props)
	local weight = props.Weight or Tokens.Line.Rule
	local vertical = props.Vertical == true
	local anchor = ANCHORS[props.From or "Center"]
	if vertical then
		anchor = Vector2.new(anchor.Y, anchor.X)
	end
	return scope:New("Frame")({
		Name = props.Name or "Line",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or (vertical and UDim2.new(0, weight, 1, 0) or UDim2.new(1, 0, 0, weight)),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("Frame")({
				Name = "Ink",
				AnchorPoint = anchor,
				Position = UDim2.fromScale(anchor.X, anchor.Y),
				Size = scope:Computed(function(use)
					local drawn = math.clamp(use(props.Draw) or 1, 0, 1)
					return vertical and UDim2.fromScale(1, drawn) or UDim2.fromScale(drawn, 1)
				end),
				BackgroundColor3 = Tokens.Color(props.Tone or "White"),
				BackgroundTransparency = props.Transparency or 0.6,
				BorderSizePixel = 0,
				[Children] = {
					scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
				},
			}),
		},
	})
end
