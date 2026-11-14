--!nonstrict
--[[
	The game's UI root. The engine's UIFusion host (RootFusionApp) imports this module,
	calls it with a fresh scope and remounts it on hot reload.

	Contract with the engine root:
	- Called as (outerScope, target, directories). directories carries the engine's
	  shortcuts, components, util/style folders and the configured RuntimeDependencies.
	- Returns a table of root ScreenGuis. The engine destroys them on reload only when their
	  name is one it tracks (GAME_ROOT_GUI_NAMES in RootFusionApp: "TheBestBattlegrounds" and
	  "LoadingGUI"), so everything the game draws is a Frame inside that one ScreenGui. A
	  second ScreenGui returned from here would be left behind on every reload.

	Components are rescanned here on every mount. The engine root scans them once at boot, so
	without this a hot reload keeps serving the old copy of an edited component. Name game
	components with a prefix (Ui*, Hud*): the engine's scan drops one whose name matches an
	engine component.
]]

local Fusion = require("@Lib/Fusion")
-- A direct path, not an alias: UI modules are hot-reloaded from a cloned DataModel.
local EngineUIFusion = require(game.StarterPlayer.StarterPlayerScripts.BACKEND["@Engine"].EngineSystems.UIFusion)
local EngineComponents = require("@Engine/Client/UIFusion/EngineComponents")

local Components = script.Parent.Parent.Components

-- Above the camera's screen effects, below the engine's windows and notifications.
local HUD_DISPLAY_ORDER = 60

local function shouldSkipComponentModule(moduleScript: ModuleScript): boolean
	local moduleName = moduleScript.Name
	return moduleName == "init"
		or moduleName:match("%.spec$") ~= nil
		or moduleName:match("%.story$") ~= nil
		or moduleName:match("%.storybook$") ~= nil
end

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
	assert(
		type(directories.runtimeDependencies) == "table",
		"FusionApp requires configured runtime dependencies from the engine root"
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
	for _, moduleScript in ipairs(Components:GetDescendants()) do
		if moduleScript:IsA("ModuleScript") and not shouldSkipComponentModule(moduleScript) then
			local component = require(moduleScript)
			if component then
				components[moduleScript.Name] = component
			end
		end
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
			DisplayOrder = HUD_DISPLAY_ORDER,
			[Fusion.Children] = {
				scope:New("Frame")({
					Name = "Hud",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					-- The engine clears the HUD for cutscenes and menus.
					Visible = scope.HUDContentEnabled,
					[Fusion.Children] = {
						scope:BumpHud({
							Source = directories.runtimeDependencies.Get("RoundClient"),
							Device = scope:Computed(function(use)
								return use(scope.IsMobile) and "Phone" or "Desktop"
							end),
						}),
					},
				}),
			},
		}),
	}
end
