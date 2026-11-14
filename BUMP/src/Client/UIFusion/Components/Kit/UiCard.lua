--!nonstrict
--[[
	A card in the middle of the screen: the intro to a game, its results, the standings, the
	lobby's count. A plate that pops in, with a small kicker line, a big title and whatever goes
	under it.

	props: Shown (state), Kicker (may be state), Title (may be state), TitleType ("Hero"),
	TitleRole ("Accent"), Width (620), Height (the whole card's height), Tone ("Plate"), Children
	(the body, laid out by the caller in the space under the title), plus Name, Position (its
	centre), ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local ROOM = 10 -- left round the plate for its shadow and pop: a reveal clips to its box

return function(scope, props)
	local width = props.Width or 620
	local height = props.Height or 300
	local titleKind = props.TitleType or "Hero"
	local titleHeight = Tokens.Type[titleKind].Size + 10
	local top = Tokens.Space.L + (props.Kicker ~= nil and 20 or 0)
	return scope:UiReveal({
		Name = props.Name or "Card",
		Shown = props.Shown,
		Pop = true,
		From = Vector2.new(0, 18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position or UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width + ROOM * 2, height + ROOM * 2),
		ZIndex = props.ZIndex,
		Children = {
			scope:UiPlate({
				Tone = props.Tone or "Plate",
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.fromOffset(width, height),
				Children = {
					props.Kicker ~= nil and scope:UiText({
						Name = "Kicker",
						Text = props.Kicker,
						Type = "Caption",
						Role = "Soft",
						Position = UDim2.fromOffset(0, Tokens.Space.L),
						Size = UDim2.new(1, 0, 0, 16),
					}) or nil,
					scope:UiText({
						Name = "Title",
						Text = props.Title,
						Type = titleKind,
						Role = props.TitleRole or "Accent",
						Position = UDim2.fromOffset(0, top),
						Size = UDim2.new(1, 0, 0, titleHeight),
					}),
					scope:New("Frame")({
						Name = "Body",
						Position = UDim2.fromOffset(Tokens.Space.XL, top + titleHeight + Tokens.Space.S),
						Size = UDim2.new(1, -Tokens.Space.XL * 2, 1, -(top + titleHeight + Tokens.Space.S + Tokens.Space.L)),
						BackgroundTransparency = 1,
						[Children] = props.Children,
					}),
				},
			}),
		},
	})
end
