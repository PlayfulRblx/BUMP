--!nonstrict
--[[
	A player's face in a round frame. Shows the player's headshot, or their initial on a plate
	when there is no player behind the name (a bot, a zone).

	props: UserId (number, optional), Label (the name, for the initial), Out (true once knocked
	out of the game, may be state: greyed and struck through), Ring (a colour name for the ring,
	a seat's colour; Ink by default), You (a thicker ring), Side (its size, 28), plus Name,
	Position, AnchorPoint, LayoutOrder, ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local side = props.Side or 28
	local dead = scope:Computed(function(use)
		return use(props.Out) == true
	end)
	local hasFace = type(props.UserId) == "number" and props.UserId > 0
	local initial = string.upper(string.sub(tostring(props.Label or "?"), 1, 1))
	local function round()
		return scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill })
	end
	return scope:New("Frame")({
		Name = props.Name or "Portrait",
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(side, side),
		BackgroundColor3 = Tokens.Color("PlateLift"),
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			round(),
			scope:New("UIStroke")({
				Thickness = math.max(side / (props.You and 10 or 14), 1.5),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = scope:Computed(function(use)
					return Tokens.Color(use(dead) and "Faint" or (use(props.Ring) or "Ink"))
				end),
				Transparency = scope:Computed(function(use)
					return (props.Ring or props.You) and 0 or 0.35
				end),
			}),
			hasFace and scope:New("ImageLabel")({
				Name = "Face",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", props.UserId),
				ImageColor3 = scope:Computed(function(use)
					return use(dead) and Tokens.Color("Muted") or Color3.new(1, 1, 1)
				end),
				ImageTransparency = scope:Computed(function(use)
					return use(dead) and 0.5 or 0
				end),
				[Children] = { round() },
			}) or scope:UiText({
				Name = "Initial",
				Text = initial,
				Type = side >= 40 and "Title" or (side >= 26 and "Label" or "Micro"),
				Role = "Soft",
				Size = UDim2.fromScale(1, 1),
				Transparency = scope:Computed(function(use)
					return use(dead) and 0.6 or 0
				end),
			}),
			-- Struck through: knocked out of this game.
			scope:New("Frame")({
				Name = "Strike",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, math.max(side / 12, 2)),
				Rotation = -45,
				BackgroundColor3 = Tokens.Color("Alert"),
				BorderSizePixel = 0,
				Visible = dead,
				ZIndex = 3,
				[Children] = { round() },
			}),
		},
	})
end
