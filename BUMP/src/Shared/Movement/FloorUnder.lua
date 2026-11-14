--!nonstrict
--[[
	The part a standing body's feet are on (Humanoid has no FloorPart to read: only FloorMaterial),
	found with a short ray straight down from its root. MELTDOWN's moving platforms and bounce pads
	need to know which part it is.

	    local part = FloorUnder(character, root)   -- nil in the air
]]

local Workspace = game:GetService("Workspace")

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

return function(character: Model, root: BasePart): BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local reach = (humanoid and humanoid.HipHeight or 2) + root.Size.Y / 2 + 1.2
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params)
	return hit and hit.Instance or nil
end
