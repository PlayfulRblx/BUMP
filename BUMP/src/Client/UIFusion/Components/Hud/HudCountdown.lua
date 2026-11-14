--!nonstrict
--[[
	The end of a game's intro: 3 ... 2 ... 1 ... GO! (the user, 2026-11-13: an intro "into a 3 - 2 -
	1 countdown"; then "The 3 2 1 Go should be a lot more tasteful. No background on it"). Bare
	text, no plate: each number in plain white with the kit's dark outline, swelling a touch as it
	lands; when play starts GO! in the game's colour, a touch bigger, fading out after
	Tokens.Timing.GoSeconds. The beeps and the GO sound are BumpMusic's.

	props: Source, Layout.
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children
local peek = Fusion.peek

return function(scope, props)
	local layout = props.Layout.Countdown
	local source = props.Source
	local reduced = Motion.Reduced(scope, props)
	local phase = Source.Value(scope, source, "Phase", "Practice")
	local countdown = Source.Value(scope, source, "Countdown", 0)
	local minigame = Source.Value(scope, source, "Minigame", false)
	local pop = Motion.Pop(scope, reduced)
	local going = scope:Value(false)

	local number = scope:Computed(function(use)
		if use(phase) ~= "Intro" then
			return 0
		end
		local left = tonumber(use(countdown)) or 0
		return left >= 1 and left <= Tokens.Timing.CountdownFrom and left or 0
	end)
	scope:Observer(number):onChange(function()
		if peek(number) > 0 then
			pop.Fire(0.18)
		end
	end)
	-- GO! the moment play starts after an intro
	local lastPhase = peek(phase)
	local serial = 0
	scope:Observer(phase):onChange(function()
		local now = peek(phase)
		if lastPhase == "Intro" and now == "Play" then
			serial += 1
			local mine = serial
			going:set(true)
			pop.Fire(0.25)
			task.delay(Tokens.Timing.GoSeconds, function()
				if serial == mine then
					going:set(false)
				end
			end)
		elseif now ~= "Play" then
			going:set(false)
		end
		lastPhase = now
	end)

	local shown = scope:Computed(function(use)
		-- the 1 stays up through the moment between the intro's clock running out and play starting
		local waiting = use(phase) == "Intro" and (tonumber(use(countdown)) or 0) <= 0
		return use(number) > 0 or use(going) or waiting
	end)
	-- fades in and out rather than snapping, keeping the last word up while it fades
	local fade = Motion.Shown(scope, shown, Motion.Presets.Glide, reduced)
	local label = scope:Value("")
	local labelGo = scope:Value(false)
	local function relabel()
		if peek(going) then
			label:set("GO!")
			labelGo:set(true)
		elseif peek(number) > 0 then
			label:set(tostring(peek(number)))
			labelGo:set(false)
		end
	end
	scope:Observer(number):onBind(relabel)
	scope:Observer(going):onBind(relabel)
	local side = layout.Compact and 130 or 210
	return scope:New("Frame")({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = layout.Position,
		Size = UDim2.fromOffset(side * 2, side),
		BackgroundTransparency = 1,
		Visible = scope:Computed(function(use)
			return use(fade) > 0.02
		end),
		[Children] = {
			scope:New("UIScale")({
				Scale = scope:Computed(function(use)
					return use(pop.Scale) * (layout.Compact and 0.62 or 1)
				end),
			}),
			scope:UiText({
				Name = "Number",
				Text = label,
				Type = "Giant",
				Role = scope:Computed(function(use)
					if use(labelGo) then
						local game = use(minigame)
						return Tokens.GameColor(game and game.Id or nil)
					end
					return "Primary"
				end),
				Transparency = scope:Computed(function(use)
					return 1 - math.clamp(use(fade), 0, 1)
				end),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
			}),
		},
	})
end
