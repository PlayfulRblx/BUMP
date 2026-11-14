--!nonstrict
--[[
	One player in a list: their face ringed in their seat's colour, their name, and a number
	beside it (gold, or a place). Knocked out of the game, the row greys and the face is struck
	through. Your own row wears the accent bar.

	props: Entry ({ Name, UserId?, Seat, Gold?, Out?, You?, Place?, Bot? }, may be state), Show
	("Gold" | "Place" | "Earned": what the number on the right is), Height (40), Compact (smaller
	face, no plate), plus Name, Position, Size (default full width), AnchorPoint, LayoutOrder,
	ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local entry = props.Entry
	local function read(use)
		return use(entry) or {}
	end
	local data = Fusion.peek(entry) or {}
	local height = props.Height or 40
	local face = props.Compact and height - 8 or height - 12
	local show = props.Show or "Gold"
	local out = scope:Computed(function(use)
		return read(use).Out == true
	end)
	local fade = scope:Computed(function(use)
		return use(out) and 0.5 or 0
	end)

	local right
	if show == "Place" then
		right = scope:UiPlace({
			Place = scope:Computed(function(use)
				return read(use).Place
			end),
			Side = height - 12,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
		})
	else
		right = scope:UiGold({
			Value = scope:Computed(function(use)
				return read(use).Gold or 0
			end),
			Gain = show == "Earned",
			Plate = false,
			Type = props.Compact and "DataSmall" or "Data",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
		})
	end

	return scope:UiPlate({
		Name = props.Name or ("Seat" .. tostring(data.Seat or "")),
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, height),
		Tone = props.Compact and "Clear" or "Plate",
		Radius = "Pill",
		Shadow = not props.Compact,
		Bar = scope:Computed(function(use)
			return read(use).You and "Accent" or false
		end),
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Children = {
			scope:UiPortrait({
				UserId = data.UserId,
				Label = data.Name,
				Out = out,
				You = data.You,
				Ring = Tokens.SeatColor(data.Seat),
				Side = face,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, data.You and 18 or 6, 0.5, 0),
			}),
			scope:UiText({
				Text = scope:Computed(function(use)
					return read(use).Name or ""
				end),
				Type = props.Compact and "Small" or "Label",
				Role = scope:Computed(function(use)
					return use(out) and "Muted" or "Primary"
				end),
				Transparency = fade,
				Align = "Left",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, (data.You and 18 or 6) + face + 8, 0.5, 0),
				Size = UDim2.new(1, -((data.You and 18 or 6) + face + 8) - 70, 0, height),
				Fit = true,
			}),
			right,
		},
	})
end
