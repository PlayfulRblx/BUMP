--!nonstrict
--[[
	A plate: the dark, top-lit, soft-cornered surface everything in the HUD sits on, the same
	surface the engine's input chips are made of. Children go in a "Content" frame.

	Colour is carried two ways, as on the chips: Bar draws a small rounded bar of a tone at the
	left edge, and the emphasised tones (Accent, Alert) tint the fill and outline the plate.

	props: Tone (a Tokens.Plates name, "Plate", may be state), Radius (a Tokens.Radius name,
	"Panel"), Bar (a colour name or nil, may be state), Shadow (false to drop it), Padding (units
	of space inside), Children, plus Name, Position, Size, AnchorPoint, Visible, ZIndex,
	LayoutOrder.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local function tone(use)
		return Tokens.Plates[use(props.Tone) or "Plate"] or Tokens.Plates.Plate
	end
	local radius = Tokens.Radius[props.Radius or "Panel"] or Tokens.Radius.Panel
	local padding = props.Padding
	local bar = scope:Computed(function(use)
		return use(props.Bar) or false
	end)
	local hasBar = props.Bar ~= nil
	return scope:New("Frame")({
		Name = props.Name or "Plate",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = scope:Computed(function(use)
			local current = tone(use)
			if current.Tone then
				return Tokens.Color("Plate"):Lerp(Tokens.Color(current.Tone), current.Tint)
			end
			return Tokens.Color("Plate")
		end),
		BackgroundTransparency = scope:Computed(function(use)
			return tone(use).Transparency
		end),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = radius }),
			scope:New("UIGradient")({
				Rotation = 90,
				Color = Tokens.PlateLight.Color,
				Transparency = Tokens.PlateLight.Transparency,
			}),
			(Tokens.Shadows() and props.Shadow ~= false) and scope:New("UIShadow")({
				BlurRadius = UDim.new(0, Tokens.Shadow.Blur),
				Offset = UDim2.fromOffset(0, Tokens.Shadow.OffsetY),
				Transparency = Tokens.Shadow.Transparency,
			}) or nil,
			scope:New("UIStroke")({
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = scope:Computed(function(use)
					return Tokens.Color(tone(use).Tone or "White")
				end),
				Transparency = scope:Computed(function(use)
					return tone(use).Stroke and Tokens.StrokeTransparency or 1
				end),
			}),
			hasBar and scope:New("Frame")({
				Name = "Bar",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 7, 0.5, 0),
				Size = UDim2.new(0, Tokens.Line.Bar, 1, -18),
				BackgroundColor3 = scope:Computed(function(use)
					return Tokens.Color(use(bar) or "Neutral")
				end),
				BorderSizePixel = 0,
				Visible = scope:Computed(function(use)
					return use(bar) ~= false
				end),
				ZIndex = 2,
				[Children] = { scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }) },
			}) or nil,
			scope:New("Frame")({
				Name = "Content",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 2,
				[Children] = {
					padding and scope:New("UIPadding")({
						PaddingTop = UDim.new(0, padding),
						PaddingBottom = UDim.new(0, padding),
						PaddingLeft = UDim.new(0, padding + (hasBar and Tokens.Line.Bar + 6 or 0)),
						PaddingRight = UDim.new(0, padding),
					}) or nil,
					props.Children,
				},
			}),
		},
	})
end
