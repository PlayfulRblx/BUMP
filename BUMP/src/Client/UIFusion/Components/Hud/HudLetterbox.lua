--!nonstrict
--[[
	Cinema bars across the top and bottom while a game's intro flies the camera round (until the
	countdown starts), sliding in and out.

	props: Source, Layout, Shown (state: the Intro phase).
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local height = props.Layout.Letterbox.Height
	local countdown = Source.Value(scope, props.Source, "Countdown", 0)
	local reduced = Motion.Reduced(scope, props)
	local up = scope:Computed(function(use)
		return use(props.Shown) == true and (tonumber(use(countdown)) or 0) > Tokens.Timing.CountdownFrom
	end)
	local slide = Motion.Shown(scope, up, Motion.Presets.Glide, reduced)
	local function bar(top: boolean)
		return scope:New("Frame")({
			Name = top and "Top" or "Bottom",
			AnchorPoint = Vector2.new(0, top and 0 or 1),
			Position = scope:Computed(function(use)
				local away = (1 - math.clamp(use(slide), 0, 1)) * height
				return top and UDim2.new(0, 0, 0, -away) or UDim2.new(0, 0, 1, away)
			end),
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = Tokens.Color("Ink"),
			BorderSizePixel = 0,
		})
	end
	return scope:New("Frame")({
		Name = "Letterbox",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = scope:Computed(function(use)
			return use(slide) > 0.01
		end),
		[Children] = { bar(true), bar(false) },
	})
end
