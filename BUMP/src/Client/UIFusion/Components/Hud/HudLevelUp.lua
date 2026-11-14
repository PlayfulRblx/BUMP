--!nonstrict
--[[
	A level up: the new level, and if it opens a power-up level in the shop, that.

	props: Source, Layout.
]]

local Source = require("@UIFusion/Kit/Source")
local Tokens = require("@UIFusion/Kit/Tokens")

return function(scope, props)
	local layout = props.Layout.Banner
	local source = props.Source
	local shown = scope:Value(false)
	local data = scope:Value({ Level = 1 })
	local serial = 0
	Source.On(scope, source, "XpEarned", function(info)
		if not info or not info.LeveledUp then
			return
		end
		serial += 1
		local mine = serial
		data:set(info)
		shown:set(true)
		task.delay(Tokens.Timing.BannerSeconds, function()
			if serial == mine then
				shown:set(false)
			end
		end)
	end)
	return scope:UiBanner({
		Name = "LevelUp",
		Shown = shown,
		Tone = "Accent",
		Size = "Hero",
		Width = layout.Width,
		Position = layout.Position,
		Kicker = Tokens.Set("Level up!", "Caption"),
		Title = scope:Computed(function(use)
			return "Level " .. tostring(use(data).Level or 1)
		end),
		Subtitle = scope:Computed(function(use)
			local reached = use(data).Level or 1
			local entry = (source.Get("Catalogue") or {})[1]
			for powerLevel, gate in entry and entry.Gates or {} do
				if gate == reached and powerLevel > 1 then
					return string.format("Level %d power-ups are open in the shop", powerLevel)
				end
			end
			return string.format("+%d XP", use(data).Amount or 0)
		end),
	})
end
