--!nonstrict
--[[
	The whole HUD. One root, laid out in layout units and scaled to the screen, showing what the
	round's phase calls for:

	    Practice   your gold only: no round is running (the test yard)
	    Lobby      the count to the next session and who's in
	    Intro      the next game's title card over the camera's flyover (cinema bars), then
	               3, 2, 1 and GO! as play starts
	    Play       the game's status bar, the seats, the dash charge
	    Results    the game's results, and the seats
	    Standings  the session's final standings

	Your gold and level sit top right throughout; being knocked out or levelling up shows over
	any of them. The shop button sits bottom right whenever you're not in a game, and the
	power-up you brought takes its place while you are; the shop opens over everything.

	props: Source (see Kit/Source), Device ("Desktop" | "Phone", may be state), Viewport (the
	size in pixels, Vector2, may be state; left out, the HUD measures itself).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

return function(scope, props)
	local source = props.Source
	local phase = Source.Value(scope, source, "Phase", "Practice")
	local measured = scope:Value(Vector2.new(1280, 720))
	local viewportState = props.Viewport or measured

	local root = scope:New("Frame")({
		Name = "BumpHud",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		[Children] = {
			scope:Computed(function(use, inner)
				local device = use(props.Device) or "Desktop"
				local layout = Tokens.Layout[device] or Tokens.Layout.Desktop
				Tokens.SetShadows(layout.Shadows)
				local function phaseIs(...)
					local wanted = { ... }
					return inner:Computed(function(useInner)
						return table.find(wanted, useInner(phase)) ~= nil
					end)
				end
				return inner:New("Frame")({
					Name = "Layout",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = inner:Computed(function(useInner)
						local viewport = useInner(viewportState) or Vector2.new(1280, 720)
						local scale = viewport.Y / layout.Base
						return UDim2.fromOffset(viewport.X / scale, layout.Base)
					end),
					BackgroundTransparency = 1,
					[Children] = {
						inner:New("UIScale")({
							Scale = inner:Computed(function(useInner)
								local viewport = useInner(viewportState) or Vector2.new(1280, 720)
								return viewport.Y / layout.Base
							end),
						}),
						inner:HudLetterbox({ Source = source, Layout = layout, Shown = phaseIs("Intro") }),
						inner:HudGold({ Source = source, Layout = layout }),
						inner:HudLevel({ Source = source, Layout = layout }),
						inner:HudStatus({ Source = source, Layout = layout, Shown = phaseIs("Play") }),
						inner:HudNote({ Source = source, Layout = layout, Shown = phaseIs("Play") }),
						inner:HudRound({ Source = source, Layout = layout, Shown = phaseIs("Play") }),
						inner:HudPlayers({ Source = source, Layout = layout, Shown = phaseIs("Play", "Results", "Intro") }),
						inner:HudCharge({ Source = source, Layout = layout }),
						inner:HudLobby({ Source = source, Layout = layout, Shown = phaseIs("Lobby") }),
						inner:HudIntro({ Source = source, Layout = layout, Shown = phaseIs("Intro") }),
						inner:HudHero({ Source = source, Layout = layout }),
						inner:HudResults({ Source = source, Layout = layout, Shown = phaseIs("Results") }),
						inner:HudStandings({ Source = source, Layout = layout, Shown = phaseIs("Standings") }),
						inner:HudCountdown({ Source = source, Layout = layout }),
						inner:HudKnockout({ Source = source, Layout = layout }),
						inner:HudFeed({ Source = source, Layout = layout }),
						inner:HudPowerUp({ Source = source, Layout = layout, Shown = phaseIs("Intro", "Play") }),
						inner:HudShopButton({ Source = source, Layout = layout }),
						inner:HudLevelUp({ Source = source, Layout = layout }),
						inner:HudShop({ Source = source, Layout = layout }),
					},
				})
			end),
		},
	})
	if not props.Viewport then
		local function measure()
			local size = root.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				measured:set(size)
			end
		end
		local connection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure)
		table.insert(scope, function()
			connection:Disconnect()
		end)
		task.defer(measure)
	end
	return root
end
