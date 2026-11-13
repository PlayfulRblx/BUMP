--!nonstrict
--[[
	Client entry point. Merges game enums and constants into the engine's, then boots the
	engine's core client systems followed by the game systems in loadOrder (each exports
	start()). The engine's UIFusion host mounts src/Client/UIFusion/Root/FusionApp.lua.

	Game systems come from Shared/SystemList.lua, in list order.
]]

local EngineConfigBootstrap = require("@Engine/Shared/Utils/ConfigBootstrap")
EngineConfigBootstrap.RegisterUpdatedEnums(require("@Shared/Utils/Enums"))
EngineConfigBootstrap.RegisterUpdatedConstants(require("@Shared/Utils/Constants"))

local EngineClientMasterLoader = require("@Engine/Client/ClientMasterLoader")
local EngineDirectories = require("@Engine/Shared/EngineDirectories")
local print, warn = EngineDirectories.Print, EngineDirectories.Warn

local DEBUG_MODE = true

-- Game systems started during the loading cover.
local loadOrder = table.clone(require("@Shared/SystemList").Client)

-- Systems loaded before loadOrder. The engine UI host goes here so the game root mounts early.
local preloadList = {
	"StarterPlayer/StarterPlayerScripts/BACKEND/@Engine/EngineSystems/UIFusion",
}

-- Game systems that can wait until the first frame is visible.
local postVisibleLoadOrder = {}

-- Add Injections
for _, directory in pairs(require("@Shared/Injections")) do
	EngineClientMasterLoader.AddInjectionDirectory(directory)
end

-- The engine holds its core client systems, and the first spawn, until an intro fires
-- IntroCompleteEvent. This game has no intro yet, so release it once data has loaded
-- instead of waiting for the engine's 20 second watchdog. Bootstrap creates the event.
task.spawn(function()
	local localPlayer = game:GetService("Players").LocalPlayer
	while localPlayer:GetAttribute("PlayerDataLoaded") ~= true do
		task.wait(0.1)
	end
	local introComplete = localPlayer:WaitForChild("IntroCompleteEvent", 30)
	if introComplete then
		introComplete:Fire()
	end
end)

EngineClientMasterLoader.Bootstrap(loadOrder, DEBUG_MODE, preloadList, postVisibleLoadOrder)
	:andThen(function()
		print("Client initialized successfully.")
	end)
	:catch(warn)
