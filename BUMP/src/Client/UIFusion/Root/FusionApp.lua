--!nonstrict
--[[
	The game's UI root. The engine's UIFusion host (RootFusionApp) imports this module,
	calls it with a fresh scope and remounts it on hot reload.

	Contract with the engine root:
	- Called as (outerScope, target, directories). directories carries the engine's
	  shortcuts, components, util/style folders and the configured RuntimeDependencies.
	- Returns a table of root ScreenGuis. The engine destroys them on reload only when their
	  name is one it tracks (GAME_ROOT_GUI_NAMES in RootFusionApp: "TheBestBattlegrounds" and
	  "LoadingGUI"), so keep those names.

	The root is empty for now: the game's HUD and menus go here.
]]

local Fusion = require("@Lib/Fusion")
-- A direct path, not an alias: UI modules are hot-reloaded from a cloned DataModel.
local EngineUIFusion = require(game.StarterPlayer.StarterPlayerScripts.BACKEND["@Engine"].EngineSystems.UIFusion)
local EngineComponents = require("@Engine/Client/UIFusion/EngineComponents")

return function(
	outerScope,
	target,
	directories: {
		engineComponents: { ModuleScript },
		engineUtilModules: Instance,
		engineStyleModules: Instance,
		engineShortcuts: any,
		runtimeDependencies: any,
	}
)
	local shortcuts = {}
	for name, value in pairs(directories.engineShortcuts) do
		if typeof(name) == "string" then
			shortcuts[name] = value
		end
	end
	shortcuts.RuntimeDependencies = directories.runtimeDependencies

	local components = {}
	for componentName, componentModule in pairs(directories.engineComponents) do
		components[componentName] = require(componentModule)
	end
	for componentName, component in pairs(EngineComponents.Flat) do
		components[componentName] = component
	end

	local scope = Fusion.scoped(Fusion, shortcuts, components)
	Fusion.setProfileLabel(scope, "UI.GameRoot")
	EngineUIFusion:SetWindowScope(scope)
	table.insert(outerScope, scope)
	table.insert(scope, function()
		if EngineUIFusion:GetWindowScope() == scope then
			EngineUIFusion:SetWindowScope(nil)
		end
	end)

	return {
		GameGUI = scope:New("ScreenGui")({
			Name = "TheBestBattlegrounds",
			Parent = target,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			ResetOnSpawn = false,
			ScreenInsets = Enum.ScreenInsets.None,
			DisplayOrder = 60,
		}),
	}
end
