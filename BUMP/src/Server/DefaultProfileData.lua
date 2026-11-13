--!nonstrict
--[[
	Fields every new player profile starts with. Passed to
	EngineServerMasterLoader.AddDefaultProfileData by ServerMaster and merged with the
	engine's own defaults (profile:Reconcile adds new keys to existing profiles).

	The game saves nothing of its own yet, so this only zeroes the engine's Soft currency
	(the engine defaults it to 500).
]]

return {
	SubProfilesData = {
		DEFAULT_SCOPE_KEY = {
			Money = {
				Soft = 0,
			},
		},
	},
}
