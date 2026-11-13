--!nonstrict
--[[
	Game constants. Merged into the engine's Constants (ArcEngine/src/Shared/Utils/Constants.lua)
	by EngineConfigBootstrap.RegisterUpdatedConstants in both master scripts; engine systems also
	read this module directly as "@GameShared/Utils/Constants".

	FeatureFlagGroups: { [GroupName] = { [AttributeName] = defaultEnabled } }. ServerMaster
	publishes each flag as a ReplicatedStorage attribute unless one is already set, so a flag
	can be flipped in Studio without a code change.
]]

local Constants = {}

Constants.FeatureFlagGroups = {}

-- BUMP has no published place yet. An unpublished file's PlaceId is 0: the engine resolves its
-- environment (and the UI waits on it) from the PlaceId, and an unpublished file can't reach
-- DataStores, so it gets in-memory profiles. Add the real place id here once it is published.
Constants.GamePlaces = {
	Gameplay = { 0 },
}

Constants.DataStores = {
	USE_MOCK_DATASTORE_IN_STUDIO = game.PlaceId == 0,
}

return Constants
