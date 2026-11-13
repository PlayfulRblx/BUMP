--!nonstrict
--[[
	Game UI components: the engine's UI root loads every module in this folder and offers it to
	Fusion scopes by name (scope:BUMPComponents). The game has no components of its own
	yet; this placeholder is the first.

	Keep a module here. The engine's root waits for UIFusion/Components before it mounts, and the
	build only carries .lua files, so an empty folder vanishes and the engine's whole UI never
	appears.
]]

return function(scope, props)
	return scope:New("Folder")({ Name = props and props.Name or "BUMPComponents" })
end
