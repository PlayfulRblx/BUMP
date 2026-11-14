--!nonstrict
-- Fusion and UI Labs for stories, found by instance rather than an "@Lib" string require:
-- UI Labs' hot reloader doesn't accept those paths.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local libRoot = ReplicatedStorage:WaitForChild("BACKEND"):WaitForChild("Lib")

local function requireLibModule(candidateNames)
	for _, name in ipairs(candidateNames) do
		local module = libRoot:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			return require(module)
		end
	end
	error("StoryDeps could not resolve required library module: " .. table.concat(candidateNames, ", "))
end

return {
	Fusion = requireLibModule({ "Fusion" }),
	UILabs = requireLibModule({ "ui-labs", "UILabs", "uilabs" }),
}
