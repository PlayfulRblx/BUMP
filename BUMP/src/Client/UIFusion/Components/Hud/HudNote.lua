--!nonstrict
--[[
	Under the status pill while a game is on: the game's line of the moment, when it has one
	(Bomber Bloxians: "Zippy has the bomb!"; MELTDOWN: "SURGE!"). Bare text in the game's colour
	with the kit's dark outline, no plate (the minimal layout the user picked, 2026-11-14); it
	pops each time the line changes.

	props: Source, Layout (a whole Tokens.Layout entry), Shown (state).
]]

local Motion = require("@UIFusion/Kit/Motion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

return function(scope, props)
	local source = props.Source
	local layout = props.Layout.Note
	local note = Source.Value(scope, source, "Note", "")
	local minigame = Source.Value(scope, source, "Minigame", false)
	local text = scope:Computed(function(use)
		local value = use(note)
		return type(value) == "string" and value or ""
	end)
	local shown = scope:Computed(function(use)
		return use(props.Shown) and use(text) ~= ""
	end)
	-- a little swell each time the line changes
	local pop = Motion.Pop(scope, Motion.Reduced(scope, props))
	scope:Observer(text):onChange(function()
		pop.Fire(Tokens.Timing.Pop * 2)
	end)
	local height = layout.Compact and 24 or 32
	return scope:UiReveal({
		Name = "Note",
		Shown = shown,
		From = Vector2.new(0, -8),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width, height + 12),
		Children = {
			scope:UiText({
				Text = text,
				Type = layout.Compact and "Label" or "Title",
				Role = scope:Computed(function(use)
					local game = use(minigame)
					return Tokens.GameColor(game and game.Id or nil)
				end),
				Fit = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 0, 0, height),
			}),
			scope:New("UIScale")({ Scale = pop.Scale }),
		},
	})
end
