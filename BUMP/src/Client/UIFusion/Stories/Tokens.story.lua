--!nonstrict
--[[
	What everything is made of: the colours, the type, the plates and the shapes. The colours
	and the plate's lighting are the engine's input chip tokens, read live, so this page is also
	a check that the HUD and the chips beside it agree.
]]

local StoryDeps = require("@Client/UIFusion/Stories/StoryDeps")
local StoryKit = require("@Client/UIFusion/Stories/StoryKit")
local Tokens = require("@UIFusion/Kit/Tokens")

local Fusion = StoryDeps.Fusion

local Children = Fusion.Children

local TYPE_ORDER = { "Mega", "Hero", "Heading", "Title", "Label", "Body", "Small", "Caption", "Micro", "DataHero", "DataLarge", "Data", "DataSmall" }
local SAMPLES = {
	Mega = "Bump", Hero = "You win!", Heading = "Starting in 3", Title = "Builderman", Label = "Charge dash",
	Body = "Jump on a ball and roll everyone else off the platform.", Small = "3 players here · 1 bot will fill in",
	Caption = "Game 2 of 5", Micro = "Left of 4",
	DataHero = "07", DataLarge = "1:04", Data = "148", DataSmall = "+6",
}
local COLOR_ORDER = { "Plate", "PlateLift", "Ink", "White", "Soft", "Muted", "Faint", "Accent", "Alert", "Positive", "Warning", "Info" }
local BUMP_COLOR_ORDER = { "Gold", "GoldDeep", "Silver", "Bronze", "Seat1", "Seat2", "Seat3", "Seat4", "Seat5", "Seat6", "Seat7", "Seat8" }
local PLATE_ORDER = { "Plate", "Lifted", "Accent", "Alert", "Hollow" }

local function swatch(scope, order: number, name: string, color: Color3)
	return StoryKit.Specimen(scope, order, name, Vector2.new(96, 56), scope:New("Frame")({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Slot }),
		},
	}))
end

return {
	name = "Tokens",
	summary = "Colours, type, plates and shapes: what every piece of the kit is made of, taken from the engine's input chips.",
	fusion = Fusion,
	controls = StoryKit.Controls(),
	story = function(props)
		StoryKit.Stage(props, function(scope)
			local rows = {}
			local y = 0
			for _, kindName in ipairs(TYPE_ORDER) do
				local kind = Tokens.Type[kindName]
				table.insert(rows, scope:UiText({
					Text = SAMPLES[kindName],
					Type = kindName,
					Align = "Left",
					Position = UDim2.fromOffset(18, y + 12),
					Size = UDim2.new(1, -36, 0, kind.Size + 8),
				}))
				table.insert(rows, scope:UiText({
					Text = string.format("%s · %d", kindName, kind.Size),
					Type = "Micro",
					Role = "Muted",
					Align = "Right",
					Position = UDim2.new(0, 18, 0, y + 12),
					Size = UDim2.new(1, -36, 0, kind.Size + 8),
				}))
				y += kind.Size + 14
			end
			local typeBlock = {
				StoryKit.Specimen(scope, 1, "On a plate", Vector2.new(560, y + 24), scope:UiPlate({
					Size = UDim2.fromScale(1, 1),
					Children = rows,
				})),
			}

			local colours = {}
			for index, name in ipairs(COLOR_ORDER) do
				table.insert(colours, swatch(scope, index, name, Tokens.Colors[name]))
			end

			local bumpColours = {}
			for index, name in ipairs(BUMP_COLOR_ORDER) do
				table.insert(bumpColours, swatch(scope, index, name, Tokens.Colors[name]))
			end

			local plates = {}
			for index, name in ipairs(PLATE_ORDER) do
				table.insert(plates, StoryKit.Specimen(scope, index, name, Vector2.new(170, 86), scope:UiPlate({
					Size = UDim2.fromScale(1, 1),
					Tone = name,
					Bar = (name == "Accent" or name == "Alert") and name or nil,
					Padding = Tokens.Space.M,
					Children = {
						scope:UiText({ Text = "Players left", Type = "Caption", Role = "Soft", Align = "Left", Size = UDim2.new(1, 0, 0, 14) }),
						scope:UiText({ Text = "3", Type = "DataLarge", Align = "Left", Position = UDim2.fromOffset(0, 16) }),
					},
				})))
			end

			local shapes = {}
			for index, name in ipairs({ "Pill", "Panel", "Slot", "Small" }) do
				table.insert(shapes, StoryKit.Specimen(scope, index, name, Vector2.new(120, 48), scope:UiPlate({
					Size = UDim2.fromScale(1, 1),
					Radius = name,
				})))
			end

			local floating = {
				StoryKit.Specimen(scope, 1, "Words straight on the world keep their outline", Vector2.new(420, 60), {
					scope:UiText({ Text = "Players left", Type = "Caption", Role = "Soft", Align = "Left", Size = UDim2.new(1, 0, 0, 14) }),
					scope:UiText({ Text = "Wobbles", Type = "Title", Align = "Left", Position = UDim2.fromOffset(0, 16) }),
					scope:UiText({ Text = "Knocked out", Type = "Label", Role = "Alert", Align = "Left", Position = UDim2.fromOffset(120, 18) }),
					scope:UiText({ Text = "+10 gold", Type = "Label", Role = "Accent", Align = "Left", Position = UDim2.fromOffset(250, 18) }),
				}),
			}

			return StoryKit.Page(scope, {
				StoryKit.Section(scope, 1, "Colour", "The engine's chip palette. Amber is what is yours or matters now; coral is being knocked out.", colours),
				StoryKit.Section(scope, 2, "BUMP's colours", "Gold for what you earn and the medals; one bright colour per seat so four players tell apart.", bumpColours),
				StoryKit.Section(scope, 3, "Plates", "Warm near-black, lit from the top, with a drop shadow instead of an outline. Try the Backdrop control.", plates),
				StoryKit.Section(scope, 4, "Shapes", "Chips are round at both ends; panels and slots are soft.", shapes),
				StoryKit.Section(scope, 5, "Type", "Gotham, as on the chips: Medium for words, Bold for names and numbers, Heavy capitals for announcements.", typeBlock),
				StoryKit.Section(scope, 6, "On the world", nil, floating),
			})
		end)
	end,
}
