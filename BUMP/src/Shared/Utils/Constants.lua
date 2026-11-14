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

-- BUMP's place is the user's Team Create, placeId 105611532229008. A local file's PlaceId is 0: the engine resolves its
-- environment (and the UI waits on it) from the PlaceId, and an unpublished file can't reach
-- DataStores, so it gets in-memory profiles.
Constants.GamePlaces = {
	Gameplay = { 105611532229008 },
}

-- The Team Create has Studio access to API services switched off, so a real DataStore kicks the
-- player ("Saves can't be reached"). In Studio, profiles are in memory. Turning that setting on is
-- the user's call; set this back to `game.PlaceId == 0` when there is something worth saving.
Constants.DataStores = {
	USE_MOCK_DATASTORE_IN_STUDIO = true,
}

-- The engine's demo switches (ArcEngine Constants.DEMO). MailDemo is on by default there: it posts
-- a "Goodbye!" letter with a free item (6007) to everyone who leaves, and on joining, any mail at
-- all brings up "You have new mail!" (the user, 2026-11-14: "Why when I join is there a "You have
-- mail" notice?" — every Studio Play stop had added one, 50 by then). BUMP has no mailbox, so off,
-- as Sunshine Valley has it.
Constants.DEMO = {
	MailDemo = false,
}

return Constants
