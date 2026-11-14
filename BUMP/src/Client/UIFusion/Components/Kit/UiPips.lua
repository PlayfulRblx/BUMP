--!nonstrict
--[[
	A row of dots for a handful of charges: lit ones are what you have. A charge coming back
	pops.

	props: Count (how many are lit, may be state), Max (how many there are), Tone (colour name,
	"Accent"), Pip (size of one, 9), Gap (5), plus Name, Position, AnchorPoint, LayoutOrder.
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local reduced = Motion.Reduced(scope, props)
	local size = props.Pip or 9
	local gap = props.Gap or 5
	local max = props.Max or 2
	local pips = {}
	for index = 1, max do
		local lit = Motion.Shown(scope, scope:Computed(function(use)
			return (tonumber(use(props.Count)) or 0) >= index
		end), Motion.Presets.Pop, reduced)
		table.insert(pips, scope:New("Frame")({
			Name = "Pip" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((index - 1) * (size + gap) + size / 2, size / 2),
			Size = scope:Computed(function(use)
				local grown = size * Motion.Mix(0.7, 1, use(lit))
				return UDim2.fromOffset(grown, grown)
			end),
			BackgroundColor3 = scope:Computed(function(use)
				return Tokens.Color("Faint"):Lerp(Tokens.Color(props.Tone or "Accent"), math.clamp(use(lit), 0, 1))
			end),
			BackgroundTransparency = scope:Computed(function(use)
				return Motion.Mix(0.25, 0, math.clamp(use(lit), 0, 1))
			end),
			BorderSizePixel = 0,
			[Children] = { scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }) },
		}))
	end
	return scope:New("Frame")({
		Name = props.Name or "Pips",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(max * size + (max - 1) * gap, size),
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
		[Children] = pips,
	})
end
