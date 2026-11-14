--!nonstrict
--[[
	Under the status bar while a game is on: the game's line of the moment, when it has one
	(Bomber Bloxians: "Zippy has the bomb!"). It pops each time the line changes.

	props: Source, Layout (a whole Tokens.Layout entry), Shown (state).
]]

local Source = require("@UIFusion/Kit/Source")

local ROOM = 10

return function(scope, props)
	local source = props.Source
	local layout = props.Layout.Note
	local note = Source.Value(scope, source, "Note", "")
	local text = scope:Computed(function(use)
		local value = use(note)
		return type(value) == "string" and value or ""
	end)
	local shown = scope:Computed(function(use)
		return use(props.Shown) and use(text) ~= ""
	end)
	local height = layout.Compact and 34 or 42
	return scope:UiReveal({
		Name = "Note",
		Shown = shown,
		From = Vector2.new(0, -10),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width + ROOM * 2, height + ROOM * 2),
		Children = {
			scope:UiPlate({
				Radius = "Pill",
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.fromOffset(layout.Width, height),
				Children = {
					scope:UiText({
						Text = text,
						Type = layout.Compact and "Label" or "Title",
						Role = "Alert",
						Fit = true,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.new(1, -28, 0, layout.Compact and 20 or 26),
					}),
				},
			}),
		},
	})
end
