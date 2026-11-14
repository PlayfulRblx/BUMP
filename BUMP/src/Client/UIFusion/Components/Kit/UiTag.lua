--!nonstrict
--[[
	A small chip: a weapon's name, a zone, "You". As wide as its text, round at both ends.

	props: Text (may be state), Tone ("Quiet" | "Solid" | "Accent" | "Alert", may be state), Height
	(18), plus Name, Position, AnchorPoint, LayoutOrder, Visible, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

-- Fill and Text are colour names. A bright fill takes dark text with no outline.
local TONES = {
	Quiet = { Fill = "PlateLift", Transparency = 0.1, Text = "Soft", Outline = true },
	Solid = { Fill = "Plate", Transparency = 0.15, Text = "Primary", Outline = true },
	Accent = { Fill = "Accent", Transparency = 0, Text = "OnLight", Outline = false },
	Alert = { Fill = "Alert", Transparency = 0, Text = "OnLight", Outline = false },
}

return function(scope, props)
	local function tone(use)
		return TONES[use(props.Tone) or "Quiet"] or TONES.Quiet
	end
	local height = props.Height or 18
	return scope:New("Frame")({
		Name = props.Name or "Tag",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = scope:Computed(function(use)
			return Tokens.Color(tone(use).Fill)
		end),
		BackgroundTransparency = scope:Computed(function(use)
			return tone(use).Transparency
		end),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
			scope:New("UIPadding")({
				PaddingLeft = UDim.new(0, Tokens.Space.S),
				PaddingRight = UDim.new(0, Tokens.Space.S),
			}),
			-- Rebuilt with the tone: whether the text is outlined is fixed when it is made.
			scope:Computed(function(use, inner)
				local current = tone(use)
				return inner:UiText({
					Text = props.Text,
					Type = "Micro",
					Role = current.Text,
					Outline = current.Outline,
					AutoWidth = true,
					Size = UDim2.new(0, 0, 1, 0),
				})
			end),
		},
	})
end
