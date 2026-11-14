--!nonstrict
--[[
	Top right, always: your saved gold. Gold you earn pops in.

	props: Source, Layout.
]]

local Source = require("@UIFusion/Kit/Source")

return function(scope, props)
	local layout = props.Layout.Gold
	return scope:UiGold({
		Name = "MyGold",
		Value = Source.Value(scope, props.Source, "MyGold", 0),
		Type = layout.Compact and "Data" or "DataLarge",
		AnchorPoint = layout.Anchor,
		Position = layout.Position,
	})
end
