--!nonstrict
--[[
	Directories the engine loaders scan for injection modules
	(EngineServerMasterLoader/EngineClientMasterLoader.AddInjectionDirectory). A module in a
	listed directory whose name matches an engine module listed in
	ArcEngine/src/Shared/Configs/ModulesAvailableForInjections.lua extends that module.
]]

return {
	script,
}
