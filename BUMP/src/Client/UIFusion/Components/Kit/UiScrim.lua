--!nonstrict
--[[
	Darkens the whole screen behind something that has to be read: an elimination, the victor.

	props: Shown (state), Strength (0 to 1, how dark at full, 0.55), plus Name, ZIndex.
]]

local Motion = require("@UIFusion/Kit/Motion")
local Tokens = require("@UIFusion/Kit/Tokens")

return function(scope, props)
	local reduced = Motion.Reduced(scope, props)
	local shown = Motion.Shown(scope, props.Shown, Motion.Presets.Ease, reduced)
	local strength = props.Strength or 0.55
	return scope:New("Frame")({
		Name = props.Name or "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Tokens.Color("Ink"),
		BackgroundTransparency = scope:Computed(function(use)
			return 1 - strength * math.clamp(use(shown), 0, 1)
		end),
		BorderSizePixel = 0,
		Visible = scope:Computed(function(use)
			return use(shown) > 0.01
		end),
		ZIndex = props.ZIndex,
	})
end
