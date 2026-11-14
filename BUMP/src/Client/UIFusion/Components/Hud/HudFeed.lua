--!nonstrict
--[[
	Everyone else's eliminations, a line each (the user, 2026-11-14, choosing "only yours" for the
	camera shot, with a small line for the others): "MOCHI eliminated FIZZ", or "FIZZ fell off" /
	"FIZZ blew up" when nobody did it, names in their seat colours, on a small plate. The newest is
	at the top; each fades out after LINE_SECONDS, and at most MAX_LINES show.

	props: Source, Layout.
]]

local Fusion = require("@Lib/Fusion")
local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

local Children = Fusion.Children
local peek = Fusion.peek

local LINE_SECONDS = 4.5
local MAX_LINES = 4
local WHY = { ["blew up"] = "blew up", ["fell alone"] = "fell off", fell = "fell off", ["knocked off"] = "was knocked off" }

return function(scope, props)
	local layout = props.Layout.Feed
	local compact = layout.Compact == true
	local rowHeight = compact and 24 or 30
	local lines = scope:Value({})
	local count = 0

	Source.On(scope, props.Source, "Eliminated", function(news)
		if type(news) ~= "table" or not news.Name then
			return
		end
		count += 1
		local line = { Key = count, News = news, Shown = scope:Value(false) }
		local list = table.clone(peek(lines))
		table.insert(list, 1, line)
		while #list > MAX_LINES do
			table.remove(list)
		end
		lines:set(list)
		task.defer(function()
			line.Shown:set(true)
		end)
		task.delay(LINE_SECONDS, function()
			line.Shown:set(false)
			task.delay(0.4, function()
				local now = table.clone(peek(lines))
				local at = table.find(now, line)
				if at then
					table.remove(now, at)
					lines:set(now)
				end
			end)
		end)
	end)

	local function words(inner, news)
		local parts = {}
		local function add(text, role, order)
			table.insert(parts, inner:UiText({
				Text = text,
				Type = compact and "Small" or "Label",
				Role = role,
				AutoWidth = true,
				LayoutOrder = order,
			}))
		end
		if news.By then
			add(news.By, Tokens.SeatColor(news.BySeat), 1)
			add("eliminated", "Soft", 2)
			add(news.Name, Tokens.SeatColor(news.Seat), 3)
		else
			add(news.Name, Tokens.SeatColor(news.Seat), 1)
			add(WHY[news.Reason or ""] or "is out", "Soft", 2)
		end
		return parts
	end

	return scope:New("Frame")({
		Name = "Feed",
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
		Size = UDim2.fromOffset(layout.Width, (rowHeight + 6) * MAX_LINES),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New("UIListLayout")({
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = layout.Anchor.X > 0.5 and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			scope:ForValues(lines, function(_, inner, line)
				return inner:UiReveal({
					Name = "Line" .. line.Key,
					Shown = line.Shown,
					From = Vector2.new(layout.Anchor.X > 0.5 and 30 or -30, 0),
					Size = UDim2.fromOffset(layout.Width, rowHeight),
					LayoutOrder = -line.Key,
					Children = {
						inner:UiPlate({
							Name = "Plate",
							Tone = "Plate",
							Radius = "Pill",
							Size = UDim2.fromScale(1, 1),
							Children = {
								inner:New("UIPadding")({
									PaddingLeft = UDim.new(0, 12),
									PaddingRight = UDim.new(0, 12),
								}),
								inner:New("UIListLayout")({
									FillDirection = Enum.FillDirection.Horizontal,
									HorizontalAlignment = layout.Anchor.X > 0.5 and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left,
									VerticalAlignment = Enum.VerticalAlignment.Center,
									Padding = UDim.new(0, 6),
									SortOrder = Enum.SortOrder.LayoutOrder,
								}),
								words(inner, line.News),
							},
						}),
					},
				})
			end),
		},
	})
end
