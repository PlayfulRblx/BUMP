--!nonstrict
--[[
	Small, in the corner while a game is on: which game it is, in its own colour, and where it is
	in the session: a pip for each game of the session, lit up to this one, and "2 of 6 games"
	(the user asked what "Game 2 of 6" meant: a session plays six minigames back to back before
	the final standings). Bare text, no plate: the minimal layout they picked (HudStatus).

	props: Source, Layout (a whole Tokens.Layout entry; its Round entry), Shown (state).
]]

local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

return function(scope, props)
	local source = props.Source
	local layout = props.Layout.Round
	local compact = layout.Compact
	local minigame = Source.Value(scope, source, "Minigame", false)
	local index = Source.Value(scope, source, "GameIndex", 1)
	local count = Source.Value(scope, source, "GameCount", 1)
	local role = scope:Computed(function(use)
		local game = use(minigame)
		return Tokens.GameColor(game and game.Id or nil)
	end)
	local align = layout.Align or "Left"
	local x = align == "Center" and 0.5 or 0
	local width = layout.Width
	local pip, gap = compact and 7 or 9, compact and 4 or 5
	return scope:UiReveal({
		Name = "Round",
		Shown = props.Shown,
		From = Vector2.new(0, -10),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(width, compact and 34 or 46),
		Children = {
			scope:UiText({
				Text = scope:Computed(function(use)
					local game = use(minigame)
					return game and string.upper(game.Title) or ""
				end),
				Type = compact and "Label" or "Title",
				Role = role,
				Align = align,
				Visible = not compact,
				AnchorPoint = Vector2.new(x, 0),
				Position = UDim2.fromScale(x, 0),
				Size = UDim2.new(1, 0, 0, compact and 18 or 24),
			}),
			-- rebuilt if the session's length or the game changes (the pips take a fixed count and tone)
			scope:Computed(function(use, inner)
				return inner:UiPips({
					Count = index,
					Max = math.max(1, use(count)),
					Tone = use(role),
					Pip = pip,
					Gap = gap,
					AnchorPoint = Vector2.new(x, 0),
					Position = compact and UDim2.new(x, 0, 0, 2) or UDim2.new(x, 0, 0, 28),
				})
			end),
			scope:UiText({
				Text = scope:Computed(function(use)
					return Tokens.Set(string.format("%d of %d games", use(index), use(count)), "Caption")
				end),
				Type = "Caption", -- (Micro ran the words together)
				Role = "Muted",
				Align = compact and "Center" or "Left",
				AutoWidth = true,
				AnchorPoint = compact and Vector2.new(0.5, 0) or Vector2.new(0, 0),
				Position = scope:Computed(function(use)
					if compact then
						return UDim2.new(0.5, 0, 0, 12)
					end
					return UDim2.new(0, use(count) * (pip + gap) + 8, 0, 24)
				end),
			}),
		},
	})
end
