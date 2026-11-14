--!nonstrict
--[[
	An announcement in the middle of the screen: a zone's warning, an elimination, the victor.
	One big plate in its tone that swells in, holds, and fades.

	props: Shown (state), Kicker (the small line above the title, optional, may be state), Title
	(may be state), Subtitle (optional, may be state), Tone ("Accent" | "Alert" | "Plate"), Size
	("Hero" | "Heading": how big the title is set), Width (560), plus Name, Position (its
	centre), ZIndex.
]]

local Fusion = require("@Lib/Fusion")
local Tokens = require("@UIFusion/Kit/Tokens")

local ROOM = 14

return function(scope, props)
	local tone = props.Tone or "Accent"
	local titleKind = props.Size or "Hero"
	local titleHeight = Tokens.Type[titleKind].Size + 8
	local kicker = props.Kicker ~= nil
	local subtitle = props.Subtitle ~= nil
	local top = Tokens.Space.M + (kicker and 18 or 0)
	local height = top + titleHeight + (subtitle and 20 or 0) + Tokens.Space.M
	local width = props.Width or 560
	local words = tone == "Plate" and "Soft" or tone

	return scope:UiReveal({
		Name = props.Name or "Banner",
		Shown = props.Shown,
		Pop = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.Position or UDim2.fromScale(0.5, 0.4),
		-- Room round the plate for its shadow: a reveal clips to its box.
		Size = UDim2.fromOffset(width + ROOM * 2, height + ROOM * 2),
		ZIndex = props.ZIndex,
		Children = {
			scope:UiPlate({
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.fromOffset(width, height),
				Tone = tone,
				Radius = "Panel",
				Children = {
					kicker and scope:UiText({
						Name = "Kicker",
						Text = props.Kicker,
						Type = "Caption",
						Role = words,
						Position = UDim2.fromOffset(0, Tokens.Space.M - 2),
					}) or nil,
					scope:UiText({
						Name = "Title",
						Text = props.Title,
						Type = titleKind,
						Role = "Primary",
						Position = UDim2.fromOffset(Tokens.Space.L, top),
						Size = UDim2.new(1, -Tokens.Space.L * 2, 0, titleHeight),
						Fit = true,
					}),
					subtitle and scope:UiText({
						Name = "Subtitle",
						Text = props.Subtitle,
						Type = "Body",
						Role = "Soft",
						Position = UDim2.fromOffset(0, top + titleHeight),
					}) or nil,
				},
			}),
		},
	})
end
