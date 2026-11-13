--!nonstrict
--[[
	Server entry point. Registers game data with ArcEngine, then boots the engine's core
	systems followed by the game's server systems (Shared/SystemList.lua).

	Order matters: enums and constants are merged into the engine's before any engine
	system is required, and every registration happens before Bootstrap.
]]
--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EngineConfigBootstrap = require("@Engine/Shared/Utils/ConfigBootstrap")
local GameEnums = require("@Shared/Utils/Enums")
EngineConfigBootstrap.RegisterUpdatedEnums(GameEnums)
local GameConstants = require("@Shared/Utils/Constants")
EngineConfigBootstrap.RegisterUpdatedConstants(GameConstants)
for _, featureFlags in pairs(GameConstants.FeatureFlagGroups or {}) do
	for flagName, fallbackEnabled in pairs(featureFlags) do
		if ReplicatedStorage:GetAttribute(flagName) == nil then
			ReplicatedStorage:SetAttribute(flagName, fallbackEnabled == true)
		end
	end
end

local EngineServerMasterLoader = require("@Engine/Server/ServerMasterLoader")
local EngineDirectories = require("@Engine/Shared/EngineDirectories")
local print, warn = EngineDirectories.Print, EngineDirectories.Warn

local DEBUG_MODE = true

-- The game's server systems, in list order.
local loadOrder = table.clone(require("@Shared/SystemList").Server)

-- Game systems that can start after the first players are in.
local deferredLoadOrder = {}

-- Inject Default Profile Data
EngineServerMasterLoader.AddDefaultProfileData(require(script.Parent.DefaultProfileData))

-- Add Injections
for _, directory in pairs(require("@Shared/Injections")) do
	EngineServerMasterLoader.AddInjectionDirectory(directory)
end

EngineServerMasterLoader.Bootstrap(loadOrder, DEBUG_MODE, {
	deferredLoadOrder = deferredLoadOrder,
})
	:andThen(function()
		print("Server critical systems initialized successfully.")
	end)
	:catch(warn)
