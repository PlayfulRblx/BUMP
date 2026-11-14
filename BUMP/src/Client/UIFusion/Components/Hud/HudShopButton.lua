--!nonstrict
--[[
	The shop button, whenever you're not playing a game (the user: "a shop button anywhere").

	props: Source, Layout.
]]

local Source = require("@UIFusion/Kit/Source")
local Fusion = require("@Lib/Fusion")

local Children = Fusion.Children

-- Whether you're a contestant in a game under way (intro or play).
local function playing(phase, players): boolean
	if phase ~= "Intro" and phase ~= "Play" then
		return false
	end
	for _, entry in players or {} do
		if entry.You then
			return not entry.Out
		end
	end
	return false
end

return function(scope, props)
	local layout = props.Layout.ShopButton
	local source = props.Source
	local phase = Source.Value(scope, source, "Phase", "Practice")
	local players = Source.Value(scope, source, "Players", {})
	local open = Source.Value(scope, source, "ShopOpen", false)
	return scope:New("Frame")({
		Name = "ShopButton",
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width, 38),
		BackgroundTransparency = 1,
		Visible = scope:Computed(function(use)
			return not use(open) and not playing(use(phase), use(players))
		end),
		[Children] = {
			scope:UiButton({
				Name = "Shop",
				Text = "Shop",
				Variant = "Primary",
				Key = layout.Key,
				Size = UDim2.fromScale(1, 1),
				OnPress = function()
					if source.Do then
						source.Do("ShopToggle")
					end
				end,
			}),
		},
	})
end
