--!nonstrict
--[[
	Your name card, in your moment of a game's intro (the user, 2026-11-13: the intro "should take
	a little bit longer when showing the final player, which is the player's character itself";
	they chose a big name card on screen among the extras). While RoundClient's IntroHero is on
	(Client/Systems/RoundIntro, as the camera orbits round you), low on the left:

	- a streak in your seat colour shoots in from the left edge behind where the name goes;
	- your name slams in huge in your seat colour from twice its size, tilted, bouncing to rest;
	- a "YOU" pill drops in over it a beat later;
	- when the camera leaves you it swells and fades.

	props: Source, Layout.
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children
local peek = Fusion.peek

return function(scope, props)
	local layout = props.Layout.Hero
	local compact = layout.Compact == true
	local source = props.Source
	local reduced = Motion.Reduced(scope, props)
	local hero = Source.Value(scope, source, "IntroHero", false)
	local phase = Source.Value(scope, source, "Phase", "Practice")
	local players = Source.Value(scope, source, "Players", {})

	local up = scope:Computed(function(use)
		return use(hero) == true and use(phase) == "Intro"
	end)
	local mine = scope:Computed(function(use)
		for _, entry in use(players) or {} do
			if type(entry) == "table" and entry.You then
				return entry
			end
		end
		return nil
	end)
	local seatRole = scope:Computed(function(use)
		local entry = use(mine)
		return Tokens.SeatColor(entry and entry.Seat or nil)
	end)

	local slam = Motion.Shown(scope, up, Motion.Presets.Pop, reduced)
	local streak = Motion.Shown(scope, up, Motion.Presets.Glide, reduced)
	-- the YOU pill a beat after the name
	local late = scope:Value(false)
	local serial = 0
	scope:Observer(up):onBind(function()
		serial += 1
		local mineSerial = serial
		late:set(false)
		if peek(up) then
			task.delay(0.25, function()
				if serial == mineSerial then
					late:set(true)
				end
			end)
		end
	end)
	local tag = Motion.Shown(scope, late, Motion.Presets.Pop, reduced)

	local width = layout.Width
	local nameHeight = compact and 86 or 150
	local height = nameHeight + (compact and 34 or 52)

	return scope:New("Frame")({
		Name = "Hero",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = layout.Position,
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Visible = scope:Computed(function(use)
			return use(slam) > 0.02 or use(streak) > 0.02
		end),
		[Children] = {
			-- the streak: from off the left edge to just past the name, in your colour
			scope:New("Frame")({
				Name = "Streak",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = scope:Computed(function(use)
					local s = math.clamp(use(streak), 0, 1.2)
					return UDim2.new(0, Motion.Mix(-40, width * 0.78, s), 0, height - nameHeight * 0.5)
				end),
				Size = UDim2.fromOffset(width * 1.3, nameHeight * 0.62),
				Rotation = -3,
				BackgroundColor3 = scope:Computed(function(use)
					return Tokens.Color(use(seatRole))
				end),
				BackgroundTransparency = scope:Computed(function(use)
					if use(up) then
						return 0.15
					end
					return 1 - math.clamp(use(streak), 0, 1) * 0.85
				end),
				BorderSizePixel = 0,
				[Children] = {
					scope:New("UIGradient")({
						-- fading out toward the left, strongest under the name, a soft end past it
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.4, 0.55),
							NumberSequenceKeypoint.new(0.88, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
					}),
				},
			}),
			-- the name and the pill, slamming in together
			scope:New("CanvasGroup")({
				Name = "Card",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.fromOffset(width, height),
				BackgroundTransparency = 1,
				GroupTransparency = scope:Computed(function(use)
					if use(up) then
						return 0
					end
					return 1 - math.clamp(use(slam) * 1.4, 0, 1)
				end),
				Rotation = scope:Computed(function(use)
					return Motion.Mix(-14, -4, math.clamp(use(slam), 0, 1.2))
				end),
				[Children] = {
					scope:New("UIScale")({
						Scale = scope:Computed(function(use)
							if use(up) then
								return Motion.Mix(2.2, 1, use(slam))
							end
							return Motion.Mix(1.35, 1, use(slam))
						end),
					}),
					scope:UiPlate({
						Name = "You",
						Tone = "Accent",
						Radius = "Pill",
						AnchorPoint = Vector2.new(0, 0),
						Position = scope:Computed(function(use)
							return UDim2.fromOffset(compact and 8 or 14, (1 - math.clamp(use(tag), 0, 1)) * -30)
						end),
						Size = UDim2.fromOffset(compact and 70 or 104, compact and 28 or 40),
						Visible = scope:Computed(function(use)
							return use(tag) > 0.02
						end),
						Children = {
							scope:UiText({
								Text = "You",
								Type = compact and "Label" or "Title",
								Role = "Accent",
								Size = UDim2.fromScale(1, 1),
							}),
						},
					}),
					scope:UiText({
						Name = "Name",
						Text = scope:Computed(function(use)
							local entry = use(mine)
							return entry and entry.Name or ""
						end),
						Type = compact and "Mega" or "Giant",
						Role = seatRole,
						Align = "Left",
						Fit = true,
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.fromScale(0, 1),
						Size = UDim2.new(1, 0, 0, nameHeight),
					}),
				},
			}),
		},
	})
end
