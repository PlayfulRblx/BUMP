--!nonstrict
--[[
	Every piece of BUMP's kit, in every state it has: the general pieces that came from The
	Scramble's kit (text, plates, tags, counters, meters, key caps, buttons, banners) and
	BUMP's own (coin, gold, places, seats, cards). Animate cycles the values that change, to
	judge how they move.
]]

local StoryDeps = require("@Client/UIFusion/Stories/StoryDeps")
local StoryKit = require("@Client/UIFusion/Stories/StoryKit")
local Tokens = require("@UIFusion/Kit/Tokens")

local Fusion = StoryDeps.Fusion
local UILabs = StoryDeps.UILabs

local controls = StoryKit.Controls({ Animate = UILabs.Boolean(true) })

return {
	name = "Kit",
	summary = "Every piece in every state: seats, gold, places, cards, plus the shared text, plates, tags, meters and buttons.",
	fusion = Fusion,
	controls = controls,
	story = function(props)
		local ticking = true
		StoryKit.Stage(props, function(scope)
			local S = StoryKit.Specimen
			local animate = props.controls.Animate
			local tick = scope:Value(0)
			task.spawn(function()
				while ticking do
					task.wait(1.2)
					if Fusion.peek(animate) then
						tick:set(Fusion.peek(tick) + 1)
					end
				end
			end)
			local function cycle(list)
				return scope:Computed(function(use)
					return list[(use(tick) % #list) + 1]
				end)
			end

			local seats = {
				S(scope, 1, "You", Vector2.new(240, 46), scope:UiSeat({ Entry = { Name = "You", Seat = 1, Gold = 27, You = true }, Height = 46 })),
				S(scope, 2, "A player", Vector2.new(240, 46), scope:UiSeat({ Entry = { Name = "Builderman", UserId = 156, Seat = 3, Gold = 34 }, Height = 46 })),
				S(scope, 3, "A bot", Vector2.new(240, 46), scope:UiSeat({ Entry = { Name = "Pipsqueak", Seat = 2, Gold = 15, Bot = true }, Height = 46 })),
				S(scope, 4, "Knocked out", Vector2.new(240, 46), scope:UiSeat({ Entry = { Name = "Wobbles", Seat = 4, Gold = 12, Out = true }, Height = 46 })),
				S(scope, 5, "Gold changing (Animate)", Vector2.new(240, 46), scope:UiSeat({
					Entry = scope:Computed(function(use)
						return { Name = "Builderman", UserId = 156, Seat = 3, Gold = 10 + (use(tick) % 4) * 6 }
					end),
					Height = 46,
				})),
				S(scope, 6, "Earned this game", Vector2.new(240, 46), scope:UiSeat({ Entry = { Name = "You", Seat = 1, Gold = 6, You = true }, Show = "Earned", Height = 46 })),
				S(scope, 7, "Phone, compact", Vector2.new(150, 34), scope:UiSeat({ Entry = { Name = "Pipsqueak", Seat = 2, Gold = 15 }, Height = 34, Compact = true })),
			}

			local gold = {
				S(scope, 1, "Coin", Vector2.new(40, 40), scope:UiCoin({ Side = 36 })),
				S(scope, 2, "Your gold", Vector2.new(140, 44), scope:UiGold({ Value = 148, Type = "DataLarge" })),
				S(scope, 3, "Growing (Animate)", Vector2.new(140, 44), scope:UiGold({
					Value = scope:Computed(function(use)
						return 148 + use(tick) * 6
					end),
					Type = "DataLarge",
				})),
				S(scope, 4, "Earned", Vector2.new(100, 34), scope:UiGold({ Value = 10, Gain = true })),
				S(scope, 5, "No plate", Vector2.new(80, 24), scope:UiGold({ Value = 34, Plate = false, Type = "DataSmall" })),
			}

			local places = {}
			for place = 1, 4 do
				table.insert(places, S(scope, place, Tokens.Ordinal(place), Vector2.new(44, 44), scope:UiPlace({ Place = place, Side = 40 })))
			end
			table.insert(places, S(scope, 5, "Cycling (Animate)", Vector2.new(44, 44), scope:UiPlace({ Place = cycle({ 1, 2, 3, 4 }), Side = 40 })))

			local portraits = {}
			for seat = 1, 4 do
				table.insert(portraits, S(scope, seat, "Seat " .. seat, Vector2.new(44, 44), scope:UiPortrait({ Label = "Bot", Ring = Tokens.SeatColor(seat), Side = 40 })))
			end
			table.insert(portraits, S(scope, 5, "You, with a face", Vector2.new(44, 44), scope:UiPortrait({ UserId = 156, Label = "B", Ring = "Seat3", You = true, Side = 40 })))
			table.insert(portraits, S(scope, 6, "Knocked out", Vector2.new(44, 44), scope:UiPortrait({ UserId = 156, Label = "B", Ring = "Seat3", Out = true, Side = 40 })))

			local tags = {
				S(scope, 1, "Quiet", Vector2.new(80, 18), scope:UiTag({ Text = "Bot", Tone = "Quiet" })),
				S(scope, 2, "Solid", Vector2.new(80, 18), scope:UiTag({ Text = "3 wins", Tone = "Solid" })),
				S(scope, 3, "Accent", Vector2.new(80, 18), scope:UiTag({ Text = "You", Tone = "Accent" })),
				S(scope, 4, "Alert", Vector2.new(80, 18), scope:UiTag({ Text = "Out", Tone = "Alert" })),
				S(scope, 5, "Key caps", Vector2.new(160, 22), {
					scope:UiKeyHint({ Key = "C", Side = 20 }),
					scope:UiKeyHint({ Key = "Space", Side = 20, Position = UDim2.fromOffset(30, 0) }),
					scope:UiKeyHint({ Key = "WASD", Side = 20, Position = UDim2.fromOffset(92, 0) }),
				}),
			}

			local meters = {
				S(scope, 1, "Dash charge (Animate)", Vector2.new(220, 10), scope:UiMeter({
					Value = cycle({ 0.15, 0.45, 0.8, 1 }),
					Tone = cycle({ "White", "White", "White", "Gold" }),
					Trail = false,
					Size = UDim2.fromOffset(220, 10),
				})),
				S(scope, 2, "Seconds left (Animate)", Vector2.new(120, 34), scope:UiCounter({
					Value = cycle({ 64, 63, 12, 9 }),
					Format = function(value)
						return string.format("%d:%02d", value // 60, value % 60)
					end,
					Role = cycle({ "Primary", "Primary", "Primary", "Alert" }),
					Flash = cycle({ "White", "White", "White", "Alert" }),
				})),
				S(scope, 3, "Buttons", Vector2.new(300, 34), {
					scope:UiButton({ Text = "Play again", Variant = "Primary" }),
					scope:UiButton({ Text = "Leave", Variant = "Quiet", Position = UDim2.fromOffset(152, 0) }),
				}),
			}

			local cards = {
				S(scope, 1, "A card (Animate shows and hides it)", Vector2.new(440, 200), scope:UiCard({
					Shown = scope:Computed(function(use)
						return not Fusion.peek(animate) or use(tick) % 3 ~= 2
					end),
					Kicker = Tokens.Set("Game 2 of 5", "Caption"),
					Title = "Bump",
					TitleType = "Hero",
					Width = 420,
					Height = 180,
					Position = UDim2.fromOffset(220, 100),
					Children = {
						scope:UiText({ Text = "Roll everyone else off the platform.", Type = "Body", Role = "Primary", Size = UDim2.new(1, 0, 0, 20) }),
					},
				})),
				S(scope, 2, "Knocked out banner", Vector2.new(500, 110), scope:UiBanner({
					Shown = scope:Computed(function(use)
						return not Fusion.peek(animate) or use(tick) % 3 ~= 2
					end),
					Tone = "Alert",
					Size = "Hero",
					Width = 480,
					Position = UDim2.fromOffset(250, 55),
					Kicker = Tokens.Set("Knocked out", "Caption"),
					Title = "3rd place",
					Subtitle = "+3 gold · watch the rest",
				})),
			}

			return StoryKit.Page(scope, {
				StoryKit.Section(scope, 1, "Seats", "One player in a list: their face in their seat's colour, their name and their gold. Struck through when knocked out.", seats),
				StoryKit.Section(scope, 2, "Gold", "Everything earned is gold: a drawn coin and the number, popping when it grows.", gold),
				StoryKit.Section(scope, 3, "Places", "Gold, silver and bronze medals, then plain.", places),
				StoryKit.Section(scope, 4, "Faces", "Each seat's ring colour; bots get their initial.", portraits),
				StoryKit.Section(scope, 5, "Tags and keys", nil, tags),
				StoryKit.Section(scope, 6, "Meters, numbers, buttons", nil, meters),
				StoryKit.Section(scope, 7, "Cards and banners", "What pops into the middle of the screen.", cards),
			})
		end)
		return function()
			ticking = false
		end
	end,
}
