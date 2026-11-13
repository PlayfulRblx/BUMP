--!nonstrict
--[[
	BUMP's ResourceManager: the game's data, served to ArcEngine and the game.

	Mounted at ReplicatedStorage.BACKEND.Shared.Resources. ArcEngine requires this module
	directly (NPCHandler, quests, dialogue, cutscenes, Cmdr item types), so it must keep the
	functions below even while the game has no data for them: return an empty table, never
	nil. The engine falls back to its own Sunshine Valley-era data when a getter is missing,
	and that data is not shipped in the runtime tree.

	Data lives in Database/*.lua as plain tables. Add a getter here for each new database.
]]

local Database = script.Database

local ResourceManager = {}

local itemDefinitions = nil

local function requireItemDefinitions()
	if itemDefinitions == nil then
		itemDefinitions = require(Database.ItemDefinitions)
	end
	return itemDefinitions
end

function ResourceManager.bootstrap(_options: any?) end

function ResourceManager.start() end

-- Items --------------------------------------------------------------------------------

function ResourceManager.getItem(id)
	return requireItemDefinitions()[id]
end

function ResourceManager.getAllItems()
	return requireItemDefinitions()
end

function ResourceManager.forEachItem(callback)
	for id, itemData in pairs(requireItemDefinitions()) do
		callback(id, itemData)
	end
end

function ResourceManager.findItemByName(name: string)
	for _, itemData in pairs(requireItemDefinitions()) do
		if itemData.Name == name then
			return itemData
		end
	end
	return nil
end

function ResourceManager.getSellPrice(idOrData: any): number
	local itemData = if type(idOrData) == "table" then idOrData else ResourceManager.getItem(idOrData)
	return if itemData and type(itemData.SellPrice) == "number" then itemData.SellPrice else 0
end

-- Placeables and stores ---------------------------------------------------------------

function ResourceManager.getPlaceable(_id)
	return nil
end

function ResourceManager.getAllPlaceables()
	return {}
end

function ResourceManager.getMerchantStores()
	return {}
end

-- NPCs ---------------------------------------------------------------------------------

function ResourceManager.getNPCDefinitions()
	return {}
end

function ResourceManager.getNPCDefinition(_npcId: string)
	return nil
end

function ResourceManager.getNPCSchedules()
	return {}
end

function ResourceManager.getNPCStationTags()
	return {}
end

function ResourceManager.getNPCDialogueGraphs()
	return {}
end

function ResourceManager.getNPCBarkSets()
	return {}
end

-- Cutscenes and world ------------------------------------------------------------------

function ResourceManager.getCutsceneDefinitions()
	return {}
end

function ResourceManager.getCutsceneDefinitionIds()
	return {}
end

function ResourceManager.getCutsceneDefinitionById(_cutsceneId)
	return nil
end

function ResourceManager.getMapWaypointDefinitions()
	return {}
end

function ResourceManager.getLocationDefinitions()
	return {}
end

function ResourceManager.getWarpLocations()
	return {}
end

return ResourceManager
