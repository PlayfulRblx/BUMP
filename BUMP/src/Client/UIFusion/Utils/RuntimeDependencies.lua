--!nonstrict

-- UIFusion is hot-reloaded from a cloned DataModel. Dependencies listed here
-- must keep using their original runtime ModuleScripts so stateful client
-- systems are not cloned and initialized a second time.
--
-- Add a client system here, then read it from UI with RuntimeDependencies.Get("Name")
-- (or GetOptional). The engine root calls Configure before mounting the game root.

local DEPENDENCY_PATHS = {}

local persistentImport = nil
local dependencyCache = {}

local RuntimeDependencies = {}

function RuntimeDependencies.Configure(resolver)
	assert(type(resolver) == "function", "RuntimeDependencies.Configure requires a persistent import function")
	persistentImport = resolver
	dependencyCache = {}
end

function RuntimeDependencies.Get(name)
	local cached = dependencyCache[name]
	if cached ~= nil then
		return cached
	end

	local path = DEPENDENCY_PATHS[name]
	assert(path ~= nil, "Unknown UIFusion runtime dependency: " .. tostring(name))
	assert(persistentImport ~= nil, "UIFusion runtime dependencies were used before configuration")

	local dependency = persistentImport(path)
	assert(dependency ~= nil, "UIFusion runtime dependency returned nil: " .. tostring(name))
	dependencyCache[name] = dependency
	return dependency
end

function RuntimeDependencies.GetOptional(name)
	local success, dependency = pcall(RuntimeDependencies.Get, name)
	if success then
		return dependency
	end
	return nil
end

return RuntimeDependencies
