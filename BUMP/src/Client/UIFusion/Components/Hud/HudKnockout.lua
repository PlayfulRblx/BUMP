--!nonstrict
--[[
	Your knockout card (the user, 2026-11-14: "show "ELIMINATED BY X"", "Can we polish it
	massively?" (the card and the sound, punchy cartoon), then "We can make it look MUCHHHH better
	than that", choosing "cartoon broadcast bars" from three mockups). Chunky angled bars sweep in
	from the left edge like a cartoon sports show, low on the screen so the knockout camera's shot
	(Client/Systems/KnockoutCam) keeps the middle:

	    at once                a yellow bar whips in with an overshoot; ELIMINATED! pops onto it a
	                           letter at a time, each tipped a little
	    KnockoutReveal in      as the camera swings to whoever did it: a bar in their seat colour
	                           whips in under it, their face bursts out of it (a player's headshot,
	                           a bot's initial) spinning upright, then BY and their name, then a
	                           pill saying how ("WITH A DIVE"); when nobody did it, the bar is red
	                           and says why (FELL OFF!, BLEW UP!)
	    a beat later           your place and gold over the top bar
	    KnockoutSeconds in     the bars whip back out to the left, top one first

	The bars are flat cartoon slabs: a face, a thick ink outline and a hard ink shadow, each a
	CanvasGroup so the angled right end clips clean. The sounds are BumpMusic's. Tokens only.

	props: Source, Layout.
]]

local Fusion = require("@Lib/Fusion")
local Motion = require("@UIFusion/Kit/Motion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children

local WHY = {
	["blew up"] = "Blew up!", ["fell alone"] = "Fell off!", fell = "Fell off!", ["knocked off"] = "Knocked off!",
}
local HOW = {
	ram = "With a ram", runover = "Ran you over", dive = "With a dive", shove = "With a shove",
	pound = "With a ground pound", shockwave = "With a Shockwave", pass = "With a bomb pass",
	blast = "With the blast", bomb = "With the bomb",
}
local SHOUT = "ELIMINATED!"
-- layout units
local TOP_W, TOP_H, TOP_CUT = 470, 66, 34
local LOW_W, LOW_H, LOW_CUT = 580, 62, 28
local GAP = 10
local OUTLINE, SHADOW = 4, 6
local FACE = 92 -- clear of the shout above (104 covered the bottom of its first letters)
local LETTER_STAGGER = 0.035

-- One layer of a slab: a rectangle with its right end cut on a slant (top further out), in one
-- colour. A CanvasGroup, so the rotated piece making the slant is clipped to the bar.
local function slabLayer(scope, width: number, height: number, cut: number, color, transparency, position: UDim2, z: number)
	local angle = math.atan(cut / height)
	local wedgeW = cut + 60
	local wedgeH = height * 2.4
	-- the wedge's right edge lies on the cut, through its middle
	local mid = Vector2.new(width + cut / 2, height / 2)
	local centre = mid - Vector2.new(math.cos(angle), math.sin(angle)) * (wedgeW / 2)
	return scope:New("CanvasGroup")({
		Name = "Layer",
		Position = position,
		Size = UDim2.fromOffset(width + cut, height),
		BackgroundTransparency = 1,
		GroupTransparency = transparency,
		ZIndex = z,
		[Children] = {
			scope:New("Frame")({
				Name = "Body",
				Size = UDim2.fromOffset(width, height),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
			scope:New("Frame")({
				Name = "Cut",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(centre.X, centre.Y),
				Size = UDim2.fromOffset(wedgeW, wedgeH),
				Rotation = math.deg(angle),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}),
		},
	})
end

-- A whole slab: shadow, outline, face, and whatever sits on it. Starts off the left edge.
local function slab(scope, props)
	local w, h, cut = props.Width, props.Height, props.Cut
	local ink = Tokens.Color("Ink")
	return scope:New("Frame")({
		Name = props.Name,
		Position = props.Position,
		Size = UDim2.fromOffset(w + cut, h),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		[Children] = {
			slabLayer(scope, w + OUTLINE * 2, h + OUTLINE * 2, cut, ink, props.Transparency, UDim2.fromOffset(-OUTLINE + SHADOW, -OUTLINE + SHADOW), 1),
			slabLayer(scope, w + OUTLINE * 2, h + OUTLINE * 2, cut, ink, props.Transparency, UDim2.fromOffset(-OUTLINE, -OUTLINE), 2),
			slabLayer(scope, w, h, cut, props.Color, props.Transparency, UDim2.fromOffset(0, 0), 3),
			scope:New("Frame")({
				Name = "Content",
				Size = UDim2.fromOffset(w + cut, h),
				BackgroundTransparency = 1,
				ZIndex = 4,
				[Children] = props.Children,
			}),
		},
	})
end

return function(scope, props)
	local layout = props.Layout.Knockout
	local reduced = Motion.Reduced(scope, props)
	local data = scope:Value({})
	local top = scope:Value(false)
	local low = scope:Value(false)
	local face = scope:Value(false)
	local tag = scope:Value(false)
	local footer = scope:Value(false)
	local letters = {}
	for index = 1, #SHOUT do
		letters[index] = scope:Value(false)
	end
	local serial = 0

	local function at(seconds: number, mine: number, fn)
		task.delay(seconds, function()
			if serial == mine then
				fn()
			end
		end)
	end

	Source.On(scope, props.Source, "KnockedOut", function(info)
		serial += 1
		local mine = serial
		data:set(info or {})
		for _, value in { low, face, tag, footer } do
			value:set(false)
		end
		for _, value in letters do
			value:set(false)
		end
		top:set(true)
		for index, value in letters do
			at(0.12 + index * LETTER_STAGGER, mine, function()
				value:set(true)
			end)
		end
		local reveal = Tokens.Timing.KnockoutReveal
		at(reveal, mine, function()
			low:set(true)
		end)
		at(reveal + 0.12, mine, function()
			face:set(true)
		end)
		at(reveal + 0.3, mine, function()
			tag:set(true)
		end)
		at(reveal + 0.45, mine, function()
			footer:set(true)
		end)
		at(Tokens.Timing.KnockoutSeconds, mine, function()
			top:set(false)
			footer:set(false)
		end)
		at(Tokens.Timing.KnockoutSeconds + 0.08, mine, function()
			low:set(false)
			face:set(false)
			tag:set(false)
		end)
	end)

	local topIn = Motion.Shown(scope, top, Motion.Presets.Pop, reduced)
	local lowIn = Motion.Shown(scope, low, Motion.Presets.Pop, reduced)
	local faceIn = Motion.Shown(scope, face, Motion.Presets.Pop, reduced)
	local tagIn = Motion.Shown(scope, tag, Motion.Presets.Pop, reduced)
	local footerIn = Motion.Shown(scope, footer, Motion.Presets.Glide, reduced)

	local lowColor = scope:Computed(function(use)
		local info = use(data)
		return Tokens.Color(info.By and Tokens.SeatColor(info.BySeat) or "Alert")
	end)
	local function slideX(use, shown, width)
		return Motion.Mix(-(width + 80), 0, use(shown))
	end
	local function hidden(use, shown)
		return use(shown) < 0.02
	end

	-- the shout, a letter at a time
	local shoutLetters = {}
	for index = 1, #SHOUT do
		local char = string.sub(SHOUT, index, index)
		local popped = Motion.Shown(scope, letters[index], Motion.Presets.Pop, reduced)
		local tilt = ((index * 37) % 11 - 5) * 1.4
		table.insert(shoutLetters, scope:New("TextLabel")({
			Name = "Letter" .. index,
			Size = UDim2.fromOffset(0, TOP_H),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Text = char,
			FontFace = Tokens.Font("DisplayItalic"),
			TextSize = 50,
			TextColor3 = Tokens.Color("Ink"),
			Rotation = tilt,
			LayoutOrder = index,
			[Children] = {
				scope:New("UIScale")({
					Scale = scope:Computed(function(use)
						return math.max(use(popped), 0)
					end),
				}),
			},
		}))
	end

	local topBar = slab(scope, {
		Name = "Shout",
		Width = TOP_W,
		Height = TOP_H,
		Cut = TOP_CUT,
		Color = Tokens.Color("Gold"),
		Position = scope:Computed(function(use)
			return UDim2.fromOffset(slideX(use, topIn, TOP_W + TOP_CUT), 0)
		end),
		Visible = scope:Computed(function(use)
			return not hidden(use, topIn)
		end),
		ZIndex = 1,
		Children = {
			scope:New("UIPadding")({ PaddingLeft = UDim.new(0, 36) }),
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 1),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			shoutLetters,
		},
	})

	-- who did it (or why), on their seat colour
	local lowBar = slab(scope, {
		Name = "Who",
		Width = LOW_W,
		Height = LOW_H,
		Cut = LOW_CUT,
		Color = lowColor,
		Position = scope:Computed(function(use)
			return UDim2.fromOffset(slideX(use, lowIn, LOW_W + LOW_CUT), TOP_H + GAP)
		end),
		Visible = scope:Computed(function(use)
			return not hidden(use, lowIn)
		end),
		ZIndex = 2,
		Children = {
			-- room for their face; with nobody to blame, the reason lines up with the shout
			scope:New("UIPadding")({
				PaddingLeft = scope:Computed(function(use)
					return UDim.new(0, use(data).By and 36 + FACE + 14 or 40)
				end),
			}),
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			scope:Computed(function(use, inner)
				local info = use(data)
				local items = {}
				if info.By then
					table.insert(items, inner:New("TextLabel")({
						Name = "By",
						Size = UDim2.fromOffset(0, LOW_H),
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Text = "BY",
						FontFace = Tokens.Font("Display"),
						TextSize = 18,
						TextColor3 = Tokens.Color("Ink"),
						LayoutOrder = 1,
					}))
				end
				table.insert(items, inner:New("TextLabel")({
					Name = "Name",
					Size = UDim2.fromOffset(0, LOW_H),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					Text = string.upper(info.By or WHY[info.Reason or ""] or "Out!"),
					FontFace = Tokens.Font("Display"),
					TextSize = 40,
					TextColor3 = Tokens.Color("White"),
					LayoutOrder = 2,
					[Children] = { inner:New("UIStroke")({ Color = Tokens.Color("Ink"), Thickness = 3.5 }) },
				}))
				return items
			end),
		},
	})

	-- their face, bursting out over the bar's left end
	local faceBadge = scope:New("Frame")({
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(36 + FACE / 2, TOP_H + GAP + LOW_H / 2 + 5),
		Size = UDim2.fromOffset(FACE + 10, FACE + 10),
		BackgroundColor3 = Tokens.Color("Ink"),
		Rotation = scope:Computed(function(use)
			return Motion.Mix(-40, 0, math.clamp(use(faceIn), 0, 1.2))
		end),
		Visible = scope:Computed(function(use)
			return use(faceIn) > 0.02 and use(data).By ~= nil
		end),
		ZIndex = 5,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
			scope:New("UIScale")({
				Scale = scope:Computed(function(use)
					return math.max(use(faceIn), 0)
				end),
			}),
			scope:New("Frame")({
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(FACE + 2, FACE + 2),
				BackgroundColor3 = Tokens.Color("White"),
				[Children] = { scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }) },
			}),
			scope:Computed(function(use, inner)
				local info = use(data)
				if not info.By then
					return {}
				end
				return {
					inner:UiPortrait({
						Name = "Portrait",
						UserId = info.ByUserId,
						Label = info.By,
						Ring = Tokens.SeatColor(info.BySeat),
						Side = FACE - 8,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						ZIndex = 6,
					}),
				}
			end),
		},
	})

	-- how they did it, a pill at the end of the bar
	local howPill = scope:New("Frame")({
		Name = "How",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(LOW_W - 60, TOP_H + GAP + LOW_H + 2),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Tokens.Color("Ink"),
		Rotation = -3,
		Visible = scope:Computed(function(use)
			local info = use(data)
			return use(tagIn) > 0.02 and HOW[info.How or ""] ~= nil
		end),
		ZIndex = 6,
		[Children] = {
			scope:New("UICorner")({ CornerRadius = Tokens.Radius.Pill }),
			scope:New("UIPadding")({ PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
			scope:New("UIScale")({
				Scale = scope:Computed(function(use)
					return math.max(use(tagIn), 0)
				end),
			}),
			scope:New("TextLabel")({
				Name = "Text",
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Text = scope:Computed(function(use)
					return string.upper(HOW[use(data).How or ""] or "")
				end),
				FontFace = Tokens.Font("Display"),
				TextSize = 17,
				TextColor3 = Tokens.Color("Gold"),
			}),
		},
	})

	-- place and gold, over the top bar
	local place = scope:UiText({
		Name = "Place",
		Text = scope:Computed(function(use)
			local info = use(data)
			local placeText = info.Place and info.Place > 0 and Tokens.Ordinal(info.Place) .. " place" or ""
			return string.format("%s · +%d gold", placeText, info.Gold or 0)
		end),
		Type = "Title",
		Role = "Primary",
		Align = "Left",
		Transparency = scope:Computed(function(use)
			return 1 - math.clamp(use(footerIn), 0, 1)
		end),
		Position = scope:Computed(function(use)
			return UDim2.fromOffset(38, -34 + (1 - math.clamp(use(footerIn), 0, 1)) * 10)
		end),
		Size = UDim2.fromOffset(TOP_W, 28),
	})

	local height = TOP_H + GAP + LOW_H + 24
	return scope:New("Frame")({
		Name = "KnockedOut",
		AnchorPoint = Vector2.new(0, 1),
		Position = layout.Position,
		Size = UDim2.fromOffset(LOW_W + LOW_CUT + 80, height),
		BackgroundTransparency = 1,
		Visible = scope:Computed(function(use)
			return use(topIn) > 0.02 or use(lowIn) > 0.02
		end),
		[Children] = {
			scope:New("UIScale")({ Scale = layout.Scale or 1 }),
			place,
			topBar,
			lowBar,
			faceBadge,
			howPill,
		},
	})
end
