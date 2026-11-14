--!nonstrict
--[[
	A game's title card (the user, 2026-11-13: "a nice AAA ADHD nintendo level intro with title card
	and camera pan over ... into a 3 - 2 - 1 countdown"), over the camera's flyover
	(Client/Systems/RoundIntro):

	- the title slams in huge in the game's colour (Tokens.GameColor), from twice its size, tilted,
	  bouncing to rest, with a "GAME 2 OF 5" ribbon sliding in above it a beat later;
	- at the end of the camera's sweep (Tokens.Timing.TitleUntil seconds left) it swells and fades,
	  leaving the lineup of contestants the screen;
	- the blurb and the game's controls (key caps) sit along the bottom until the countdown,
	  stepping away while your name card is up (HudHero).

	props: Source, Layout, Shown (state: the Intro phase).
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local HEIGHT = 240

return function(scope, props)
	local layout = props.Layout.Title
	local controlsLayout = props.Layout.Controls
	local source = props.Source
	local reduced = Motion.Reduced(scope, props)
	local minigame = Source.Value(scope, source, "Minigame", false)
	local index = Source.Value(scope, source, "GameIndex", 1)
	local count = Source.Value(scope, source, "GameCount", 1)
	local countdown = Source.Value(scope, source, "Countdown", 0)
	local hero = Source.Value(scope, source, "IntroHero", false)

	-- the card is up over the camera's sweep, then leaves the lineup the screen
	local up = scope:Computed(function(use)
		return use(props.Shown) == true and (tonumber(use(countdown)) or 0) > Tokens.Timing.TitleUntil
	end)
	-- the blurb and controls stay along the bottom until the countdown, out of the way of your
	-- name card (HudHero) in your moment
	local strip = scope:Computed(function(use)
		return use(props.Shown) == true and use(hero) ~= true and (tonumber(use(countdown)) or 0) > Tokens.Timing.CountdownFrom
	end)
	local slam = Motion.Shown(scope, up, Motion.Presets.Pop, reduced)
	-- the ribbon and blurb come a beat after the title
	local late = scope:Value(false)
	local serial = 0
	scope:Observer(up):onBind(function()
		serial += 1
		local mine = serial
		if Fusion.peek(up) then
			late:set(false)
			task.delay(0.35, function()
				if serial == mine then
					late:set(true)
				end
			end)
		else
			late:set(false)
		end
	end)
	local extra = Motion.Shown(scope, late, Motion.Presets.Glide, reduced)
	local controlsUp = Motion.Shown(scope, strip, Motion.Presets.Glide, reduced)

	local titleRole = scope:Computed(function(use)
		local game = use(minigame)
		return Tokens.GameColor(game and game.Id or nil)
	end)

	local card = scope:New("CanvasGroup")({
		Name = "TitleCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width, HEIGHT),
		BackgroundTransparency = 1,
		-- slamming in it's solid at once; leaving, it fades as it swells
		GroupTransparency = scope:Computed(function(use)
			if use(up) then
				return 0
			end
			return 1 - math.clamp(use(slam) * 1.4, 0, 1)
		end),
		Rotation = scope:Computed(function(use)
			return Motion.Mix(-12, -3, math.clamp(use(slam), 0, 1.2))
		end),
		Visible = scope:Computed(function(use)
			return use(slam) > 0.02
		end),
		[Children] = {
			scope:New("UIScale")({
				Scale = scope:Computed(function(use)
					if use(up) then
						return Motion.Mix(2.2, 1, use(slam))
					end
					return Motion.Mix(1.4, 1, use(slam))
				end),
			}),
			-- the ribbon: which game of how many
			scope:UiPlate({
				Name = "Ribbon",
				Tone = "Accent",
				Radius = "Pill",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = scope:Computed(function(use)
					return UDim2.new(0.5, (1 - use(extra)) * -260, 0, 0)
				end),
				Size = UDim2.fromOffset(layout.Compact and 160 or 200, layout.Compact and 26 or 32),
				Children = {
					scope:UiText({
						Text = scope:Computed(function(use)
							return Tokens.Set(string.format("Game %d of %d", use(index), use(count)), "Caption")
						end),
						Type = "Caption",
						Role = "Accent",
						Size = UDim2.fromScale(1, 1),
					}),
				},
			}),
			scope:UiText({
				Name = "Title",
				Text = scope:Computed(function(use)
					local game = use(minigame)
					return game and game.Title or ""
				end),
				Type = layout.Compact and "Mega" or "Giant",
				Role = titleRole,
				Fit = true,
				Position = UDim2.fromOffset(0, layout.Compact and 28 or 36),
				Size = UDim2.new(1, 0, 0, layout.Compact and 76 or 140),
			}),
		},
	})

	-- the controls, along the bottom for the whole intro
	local controls = scope:New("Frame")({
		Name = "Controls",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = scope:Computed(function(use)
			return controlsLayout.Position + UDim2.fromOffset(0, (1 - use(controlsUp)) * 80)
		end),
		Size = UDim2.fromOffset(0, controlsLayout.Compact and 28 or 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Visible = scope:Computed(function(use)
			return use(controlsUp) > 0.02
		end),
		[Children] = {
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 18),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			scope:Computed(function(use, inner)
				local game = use(minigame)
				local items = {}
				for order, control in ipairs(game and game.Controls or {}) do
					table.insert(items, inner:New("Frame")({
						Name = control.Label,
						Size = UDim2.fromOffset(0, controlsLayout.Compact and 20 or 26),
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						LayoutOrder = order,
						[Children] = {
							inner:New("UIListLayout")({
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 6),
								SortOrder = Enum.SortOrder.LayoutOrder,
							}),
							inner:UiKeyHint({ Key = control.Key, Side = controlsLayout.Compact and 16 or 20, LayoutOrder = 1 }),
							inner:UiText({ Text = control.Label, Type = "Label", Role = "Primary", AutoWidth = true, LayoutOrder = 2 }),
						},
					}))
				end
				return items
			end),
		},
	})

	-- what the game's about, over the controls
	local blurb = scope:UiText({
		Name = "Blurb",
		Text = scope:Computed(function(use)
			local game = use(minigame)
			return game and game.Blurb or ""
		end),
		Type = controlsLayout.Compact and "Small" or "Title",
		Role = "Primary",
		Wrap = true,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = scope:Computed(function(use)
			return controlsLayout.Position + UDim2.fromOffset(0, (1 - use(controlsUp)) * 80 - (controlsLayout.Compact and 18 or 26))
		end),
		Size = UDim2.new(0.6, 0, 0, controlsLayout.Compact and 34 or 52),
		Transparency = scope:Computed(function(use)
			return 1 - math.clamp(use(controlsUp), 0, 1)
		end),
		Visible = scope:Computed(function(use)
			return use(controlsUp) > 0.02
		end),
	})

	return scope:New("Frame")({
		Name = "Intro",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		[Children] = { card, blurb, controls },
	})
end
