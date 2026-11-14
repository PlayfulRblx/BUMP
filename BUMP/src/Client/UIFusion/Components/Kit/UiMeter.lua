--!nonstrict
--[[
	A round-ended bar for any 0 to 1 amount. A loss snaps the bar down at once and leaves a
	ghost of what was lost, which then drains away, so a hit reads as a hit; a gain eases up.

	props: Value (0 to 1, may be state), Tone (colour name, "White", may be state), Trail (false to
	drop the ghost), Ticks (split into this many equal parts), plus Name, Position, Size
	(default full width, 8 high), AnchorPoint, LayoutOrder, Visible.
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local reduced = Motion.Reduced(scope, props)
	local value = scope:Computed(function(use)
		return math.clamp(tonumber(use(props.Value)) or 0, 0, 1)
	end)
	local fill = Motion.Spring(scope, value, Motion.Presets.Snap, reduced)

	-- The ghost holds where the bar was, waits, then follows it down. It never trails a gain.
	local ghostGoal = scope:Value(Fusion.peek(value))
	local serial = 0
	scope:Observer(value):onChange(function()
		local now = Fusion.peek(value)
		serial += 1
		local mine = serial
		if now >= Fusion.peek(ghostGoal) then
			ghostGoal:set(now)
			return
		end
		task.delay(Tokens.Timing.DamageTrailSeconds, function()
			if serial == mine then
				ghostGoal:set(now)
			end
		end)
	end)
	table.insert(scope, function()
		serial += 1
	end)
	local ghost = Motion.Spring(scope, ghostGoal, Motion.Presets.Drift, reduced)

	local function pill()
		return scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill })
	end

	local ticks = {}
	for index = 1, (props.Ticks or 1) - 1 do
		table.insert(ticks, scope:New("Frame")({
			Name = "Tick",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(index / props.Ticks, 0),
			Size = UDim2.new(0, 1.5, 1, 0),
			BackgroundColor3 = Tokens.Color("Ink"),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 4,
		}))
	end

	return scope:New("Frame")({
		Name = props.Name or "Meter",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Tokens.Color("Ink"),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		[Children] = {
			pill(),
			props.Trail ~= false and scope:New("Frame")({
				Name = "Ghost",
				Size = scope:Computed(function(use)
					return UDim2.fromScale(math.clamp(use(ghost), 0, 1), 1)
				end),
				BackgroundColor3 = Tokens.Color("Alert"),
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				ZIndex = 2,
				[Children] = { pill() },
			}) or nil,
			scope:New("Frame")({
				Name = "Fill",
				Size = scope:Computed(function(use)
					return UDim2.fromScale(math.clamp(use(fill), 0, 1), 1)
				end),
				BackgroundColor3 = scope:Computed(function(use)
					return Tokens.Color(use(props.Tone) or "White")
				end),
				BorderSizePixel = 0,
				ZIndex = 3,
				[Children] = { pill() },
			}),
			ticks,
		},
	})
end
