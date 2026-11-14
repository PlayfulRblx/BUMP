--!nonstrict
--[[
	All text in the game. Type says how it is set (size, weight, capitals) and Role what it is
	for (its colour), both from Tokens. Like the engine's chip labels, it wears a dark outline
	so it reads over a bright scene; text on a light fill turns that off.

	props: Text (string, number or state), Type ("Body"), Role ("Primary", may be state),
	Align ("Center" | "Left" | "Right"), VAlign ("Center" | "Top" | "Bottom"), Transparency (may be
	state), Fit (shrink to fit), Wrap, AutoWidth (size to the text's width), Outline (false to
	drop the outline), plus the usual Name, Position, Size, AnchorPoint, Rotation, Visible,
	ZIndex, LayoutOrder.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

return function(scope, props)
	local kindName = props.Type or "Body"
	local kind = Tokens.Type[kindName]
	assert(kind, "UiText: no type called " .. tostring(kindName))
	local height = kind.Size + 6
	local stroke = Tokens.TextStroke
	local thickness = math.clamp(stroke.Thickness * kind.Size / stroke.FullAtSize, stroke.Thinnest, stroke.Thickness)
	return scope:New("TextLabel")({
		Name = props.Name or "Text",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Rotation = props.Rotation,
		Size = props.Size or (props.AutoWidth and UDim2.fromOffset(0, height) or UDim2.new(1, 0, 0, height)),
		AutomaticSize = props.AutoWidth and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		FontFace = Tokens.Font(kind.Font),
		Text = scope:Computed(function(use)
			return Tokens.Set(use(props.Text), kindName)
		end),
		TextSize = kind.Size,
		TextScaled = props.Fit,
		TextColor3 = scope:Computed(function(use)
			local role = use(props.Role) or "Primary"
			return Tokens.Color(Tokens.Text[role] or role)
		end),
		TextTransparency = props.Transparency,
		TextXAlignment = Enum.TextXAlignment[props.Align or "Center"],
		TextYAlignment = Enum.TextYAlignment[props.VAlign or "Center"],
		TextWrapped = props.Wrap,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		[Fusion.Children] = {
			props.Fit and scope:New("UITextSizeConstraint")({ MaxTextSize = kind.Size }) or nil,
			props.Outline ~= false and scope:New("UIStroke")({
				Thickness = thickness,
				Color = Tokens.Color(stroke.Color),
				Transparency = scope:Computed(function(use)
					-- Fades with the text, a little ahead of it.
					local hidden = tonumber(use(props.Transparency)) or 0
					return math.clamp(stroke.Transparency + hidden * (1 - stroke.Transparency), 0, 1)
				end),
				LineJoinMode = Enum.LineJoinMode.Round,
			}) or nil,
		},
	})
end
