--!nonstrict
--[[
	Brings its children in when Shown turns true and takes them out when it turns false, so
	pieces arrive instead of blinking on: a fade, a short slide, and optionally the small swell
	the engine's chips arrive with. It fills its parent unless given a Size, so children keep
	their own positions.

	Leave room inside for anything that draws past its own edge (a plate's shadow): a reveal
	clips to its box.

	props: Shown (state), From (Vector2: where it rests when hidden, relative to its place), Pop
	(true to swell in from a little smaller), Preset (a Motion preset, Glide), Children, plus
	Name, Position, Size, AnchorPoint, ZIndex, LayoutOrder.
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")

local Children = Fusion.Children

local GONE = 0.01
local SMALL = 0.9

return function(scope, props)
	local reduced = Motion.Reduced(scope, props)
	local reveal = Motion.Shown(scope, props.Shown, props.Preset or Motion.Presets.Glide, reduced)
	local base = props.Position or UDim2.new()
	local from = props.From or Vector2.zero
	return scope:New("CanvasGroup")({
		Name = props.Name or "Reveal",
		AnchorPoint = props.AnchorPoint,
		Position = scope:Computed(function(use)
			local away = from * (1 - use(reveal))
			return base + UDim2.fromOffset(away.X, away.Y)
		end),
		Size = props.Size or UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = scope:Computed(function(use)
			return 1 - math.clamp(use(reveal), 0, 1)
		end),
		Visible = scope:Computed(function(use)
			return use(reveal) > GONE
		end),
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			props.Pop and scope:New("UIScale")({
				Scale = scope:Computed(function(use)
					return Motion.Mix(SMALL, 1, use(reveal))
				end),
			}) or nil,
			props.Children,
		},
	})
end
