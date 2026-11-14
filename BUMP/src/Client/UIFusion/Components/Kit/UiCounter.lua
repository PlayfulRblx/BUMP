--!nonstrict
--[[
	A number that is watched: players left, seconds, gold. When it changes it pops a little
	bigger in the flash colour and settles back, the way an input chip does when its key is
	pressed.

	props: Value (number or state), Format (function(number) -> string), Type ("DataLarge"), Role
	("Primary", may be state), Flash (colour name it lights up in, "Accent", may be state), Align, plus Name,
	Position, Size, AnchorPoint, AutoWidth, LayoutOrder, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local kindName = props.Type or "DataLarge"
	local kind = Tokens.Type[kindName]
	local reduced = Motion.Reduced(scope, props)
	local flash = Motion.Flash(scope, reduced, Motion.Presets.Ease)
	local pop = Motion.Pop(scope, reduced)
	local value = scope:Computed(function(use)
		return use(props.Value)
	end)
	scope:Observer(value):onChange(function()
		flash.Fire(1)
		pop.Fire(Tokens.Timing.Pop)
	end)
	local format = props.Format or tostring
	local height = kind.Size + 6
	local stroke = Tokens.TextStroke
	return scope:New("TextLabel")({
		Name = props.Name or "Counter",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or (props.AutoWidth and UDim2.fromOffset(0, height) or UDim2.new(1, 0, 0, height)),
		AutomaticSize = props.AutoWidth and Enum.AutomaticSize.X or Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		FontFace = Tokens.Font(kind.Font),
		Text = scope:Computed(function(use)
			return Tokens.Set(format(use(value)), kindName)
		end),
		TextSize = kind.Size,
		TextColor3 = scope:Computed(function(use)
			local rest = Tokens.Color(Tokens.Text[use(props.Role) or "Primary"])
			return rest:Lerp(Tokens.Color(use(props.Flash) or "Accent"), math.clamp(use(flash.Value), 0, 1))
		end),
		TextXAlignment = Enum.TextXAlignment[props.Align or "Center"],
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New("UIScale")({ Scale = pop.Scale }),
			scope:New("UIStroke")({
				Thickness = math.clamp(stroke.Thickness * kind.Size / stroke.FullAtSize, stroke.Thinnest, stroke.Thickness),
				Color = Tokens.Color(stroke.Color),
				Transparency = stroke.Transparency,
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		},
	})
end
