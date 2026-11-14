--!nonstrict
--[[
	Fields every new player profile starts with. Passed to
	EngineServerMasterLoader.AddDefaultProfileData by ServerMaster and merged with the
	engine's own defaults (profile:Reconcile adds new keys to existing profiles).

	Money.Soft is BUMP's gold (starting at 0 rather than the engine's 500). Bump is the game's own
	progress (Server/Systems/Progress): Xp (the player level comes from it), PowerUps (id -> level
	bought, 1 to 3), Equipped (the power-up they bring into each game, "" for none) and Daily (the
	day number and streak of their last daily reward).
]]

return {
	Bump = {
		Xp = 0,
		PowerUps = {},
		Equipped = "",
		Daily = { Day = 0, Streak = 0 },
	},
	SubProfilesData = {
		DEFAULT_SCOPE_KEY = {
			Money = {
				Soft = 0,
			},
		},
	},
}
