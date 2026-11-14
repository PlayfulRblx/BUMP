--!nonstrict
--[[
	A button: a chip you can press. It swells a touch under the pointer and gives when pressed.
	Primary is the one thing to press on a screen and wears the accent.

	props: Text, Variant ("Quiet" | "Primary" | "Alert"), OnPress, Key (a key cap drawn before the
	text, optional), Enabled (may be state, default true), plus Name, Position, Size (default
	140 by 34), AnchorPoint, LayoutOrder, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local UiMotion = require("@Engine/Client/UIFusion/EngineUtils/UiMotion")
local Motion = require("@UIFusion/Kit/Motion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children
local OnEvent = Fusion.OnEvent

local VARIANTS = {
	Quiet = { Plate = "Plate", Text = "Primary" },
	Primary = { Plate = "Accent", Text = "Accent" },
	Alert = { Plate = "Alert", Text = "Alert" },
}

return function(scope, props)
	local variant = VARIANTS[props.Variant or "Quiet"] or VARIANTS.Quiet
	local reduced = Motion.Reduced(scope, props)
	local enabled = scope:Computed(function(use)
		return use(props.Enabled) ~= false
	end)
	local touch = UiMotion.Interaction(scope, {
		Reduced = reduced,
		Disabled = scope:Computed(function(use)
			return not use(enabled)
		end),
		HoverScale = 1.04,
		PressScale = 0.95,
		Lift = 0,
	})
	return scope:New("TextButton")({
		Name = props.Name or "Button",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(140, 34),
		AutoButtonColor = false,
		Text = "",
		BackgroundTransparency = 1,
		Active = enabled,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[OnEvent("MouseEnter")] = touch.OnEnter,
		[OnEvent("MouseLeave")] = touch.OnLeave,
		[OnEvent("MouseButton1Down")] = touch.OnDown,
		[OnEvent("MouseButton1Up")] = touch.OnUp,
		[OnEvent("Activated")] = function()
			if Fusion.peek(enabled) and props.OnPress then
				props.OnPress()
			end
		end,
		[Children] = {
			scope:New("UIScale")({ Scale = touch.Scale }),
			scope:UiPlate({
				Size = UDim2.fromScale(1, 1),
				Radius = "Pill",
				Tone = scope:Computed(function(use)
					return use(enabled) and variant.Plate or "Hollow"
				end),
				Children = {
					scope:New("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, Tokens.Space.S),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					props.Key and scope:UiKeyHint({ Key = props.Key, LayoutOrder = 1 }) or nil,
					scope:UiText({
						Text = props.Text,
						Type = "Label",
						Role = scope:Computed(function(use)
							return use(enabled) and variant.Text or "Faint"
						end),
						AutoWidth = true,
						LayoutOrder = 2,
					}),
				},
			}),
		},
	})
end
