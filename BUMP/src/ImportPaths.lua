--!nonstrict

-- Game-local ImportPaths for runtime safety.
-- Keep this module static and acyclic so server/client bootstrap never depends
-- on dynamic datamodel scans.

local CACHE_KEY = "__BUMPImportPathsV1"

if type(_G[CACHE_KEY]) == "table" then
	return _G[CACHE_KEY]
end

local paths = {
	["@GameServer"] = "ServerScriptService/BACKEND/Server/@Game",
	["@GameClient"] = "StarterPlayer/StarterPlayerScripts/BACKEND/@Game",
	["@GameShared"] = "ReplicatedStorage/BACKEND/Shared/@Game",

	["@EngineServer"] = "ServerScriptService/BACKEND/Server/@Engine",
	["@EngineClient"] = "StarterPlayer/StarterPlayerScripts/BACKEND/@Engine",
	["@EngineShared"] = "ReplicatedStorage/BACKEND/Shared/@Engine",

	UIFusion = "StarterPlayer/StarterPlayerScripts/BACKEND/@Game/UIFusion",
	EngineUIFusion = "StarterPlayer/StarterPlayerScripts/BACKEND/@Engine/UIFusion",

	Client = "StarterPlayer/StarterPlayerScripts/BACKEND",
	Lib = "ReplicatedStorage/BACKEND/Lib",
	Server = "ServerScriptService/BACKEND/@Code",
	Shared = "ReplicatedStorage/BACKEND/Shared",

	Actions = "ReplicatedStorage/BACKEND/Shared/Actions",
	Data = "ReplicatedStorage/BACKEND/Shared/Data",
	GameUtils = "ReplicatedStorage/BACKEND/Shared/GameUtils",
	ItemBehaviors = "ReplicatedStorage/BACKEND/Shared/ItemBehaviors",
	Reducers = "ReplicatedStorage/BACKEND/Shared/@Engine/Reducers",
	State = "ReplicatedStorage/BACKEND/Shared/@Engine/State",
	Thunks = "ReplicatedStorage/BACKEND/Shared/Thunks",
	Utils = "ReplicatedStorage/BACKEND/Shared/Utils",

	Assets = "ReplicatedStorage/Assets",
	Storage = "ReplicatedStorage/Storage",

	Cmdr = "ReplicatedStorage/BACKEND/Lib/Cmdr",
	Cryo = "ReplicatedStorage/BACKEND/Lib/Cryo",
	DataStore2 = "ReplicatedStorage/BACKEND/Lib/DataStore2",
	Immutable = "ReplicatedStorage/BACKEND/Lib/Immutable",
	Inspect = "ReplicatedStorage/BACKEND/Lib/Inspect",
	Network = "ReplicatedStorage/BACKEND/Lib/Network",
	Promise = "ReplicatedStorage/BACKEND/Lib/Promise",
	Roact = "ReplicatedStorage/BACKEND/Lib/Roact",
	RoactRodux = "ReplicatedStorage/BACKEND/Lib/RoactRodux",
	Rodux = "ReplicatedStorage/BACKEND/Lib/Rodux",
	t = "ReplicatedStorage/BACKEND/Lib/t",
	TestEZ = "ReplicatedStorage/BACKEND/Lib/TestEZ",

	Action = "ReplicatedStorage/BACKEND/Shared/Utils/Action",

	print = "ReplicatedStorage/BACKEND/Shared/@Engine/Utils/Print",
	warn = "ReplicatedStorage/BACKEND/Shared/@Engine/Utils/Warn",
}

_G[CACHE_KEY] = paths
return paths
