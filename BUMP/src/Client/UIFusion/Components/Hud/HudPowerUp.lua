--!nonstrict
--[[
	The power-up you brought into this game: its icon, its name and how to fire it. Greys out
	once it's used. Second Chance says it works by itself.

	The slot is a button too (a phone's thumb, or a click): the same as the key.

	props: Source, Layout, Shown (state: the game's intro and play).
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local OnEvent = Fusion.OnEvent

local HEIGHT = 56
local ROOM = 10

return function(scope, props)
	local layout = props.Layout.PowerUp
	local source = props.Source
	local power = Source.Value(scope, source, "Power", false)
	local players = Source.Value(scope, source, "Players", {})
	-- knocked out, you're watching: the shop button has this corner back
	local out = scope:Computed(function(use)
		for _, entry in use(players) do
			if entry.You then
				return entry.Out == true
			end
		end
		return false
	end)
	local catalogue = Source.Value(scope, source, "Catalogue", {})
	local item = scope:Computed(function(use)
		local held = use(power)
		for _, entry in use(catalogue) do
			if held and entry.Id == held.Id then
				return entry
			end
		end
		return false
	end)
	local used = scope:Computed(function(use)
		local held = use(power)
		return held and held.Used == true or false
	end)
	local auto = scope:Computed(function(use)
		local entry = use(item)
		return entry and entry.Automatic or false
	end)
	local icon = HEIGHT - 14
	local textLeft = icon + Tokens.Space.M
	local keyRoom = layout.Key and 30 or 0
	return scope:UiReveal({
		Name = "PowerUp",
		Shown = scope:Computed(function(use)
			return use(props.Shown) and use(item) ~= false and not use(out)
		end),
		From = Vector2.new(0, 10),
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width + ROOM * 2, HEIGHT + ROOM * 2),
		Children = {
			scope:UiPlate({
				Radius = "Pill",
				Tone = scope:Computed(function(use)
					return use(used) and "Hollow" or "Plate"
				end),
				Position = UDim2.fromOffset(ROOM, ROOM),
				Size = UDim2.fromOffset(layout.Width, HEIGHT),
				Children = {
					scope:UiPowerIcon({
						Id = scope:Computed(function(use)
							local entry = use(item)
							return entry and entry.Id or nil
						end),
						Glyph = scope:Computed(function(use)
							local entry = use(item)
							return entry and entry.Glyph or ""
						end),
						Dim = used,
						Side = icon,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 7, 0.5, 0),
					}),
					scope:UiText({
						Text = scope:Computed(function(use)
							local entry = use(item)
							local held = use(power)
							return entry and string.format("%s  %s", entry.Name, string.rep("•", held and held.Level or 1)) or ""
						end),
						Type = layout.Compact and "Body" or "Label",
						Role = scope:Computed(function(use)
							return use(used) and "Faint" or "Primary"
						end),
						Align = "Left",
						Position = UDim2.fromOffset(textLeft, 8),
						Size = UDim2.new(1, -(textLeft + keyRoom + 12), 0, 20),
						Fit = true,
					}),
					scope:UiText({
						Text = scope:Computed(function(use)
							if use(used) then
								return Tokens.Set("Used", "Micro")
							elseif use(auto) then
								return Tokens.Set("Works by itself", "Micro")
							end
							return Tokens.Set(layout.Key and "Ready" or "Tap here to use", "Micro")
						end),
						Type = "Micro",
						Role = scope:Computed(function(use)
							return use(used) and "Faint" or (use(auto) and "Soft" or "Accent")
						end),
						Align = "Left",
						Position = UDim2.fromOffset(textLeft, 30),
						Size = UDim2.new(1, -(textLeft + keyRoom + 12), 0, 14),
					}),
					scope:New("TextButton")({
						Name = "Press",
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = "",
						ZIndex = 3,
						[OnEvent("Activated")] = function()
							if source.Do then
								source.Do("PowerUse")
							end
						end,
					}),
					layout.Key and scope:UiKeyHint({
						Key = layout.Key,
						Side = 22,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -16, 0.5, 0),
						Visible = scope:Computed(function(use)
							return not use(used) and not use(auto)
						end),
					}) or nil,
				},
			}),
		},
	})
end
