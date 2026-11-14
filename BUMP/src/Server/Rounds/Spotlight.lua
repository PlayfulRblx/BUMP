--!nonstrict
--[[
	A spotlight on everyone still in the game (the user, 2026-11-13: "add a bright spotlight onto
	each of the players so people can see them as the centre of attention"): a warm light, tinted
	a little by their seat colour, shining down from above their head. Just the light: a visible
	beam cone was tried and turned down ("get rid of the cone spotlight").

	    Spotlight.Add(model, seatColor)   -- RoundServer, when a game is set up
	    Spotlight.Remove(model)           -- when they're knocked out, and when the game ends

	Everything hangs off the HumanoidRootPart (named Bump*), so it follows the body and goes when
	the body goes.
]]

local Spotlight = {}

local HEIGHT = 18 -- the light's height above the root
local NAMES = { "BumpSpotTop" }

function Spotlight.Remove(model: Model?)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in NAMES do
		local thing = root:FindFirstChild(name)
		if thing then
			thing:Destroy()
		end
	end
end

function Spotlight.Add(model: Model?, color: Color3)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	Spotlight.Remove(model)
	local top = Instance.new("Attachment")
	top.Name = "BumpSpotTop"
	top.Position = Vector3.new(0, HEIGHT, 0)
	top.Parent = root

	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 46
	light.Range = HEIGHT + 10
	light.Brightness = 7
	light.Color = Color3.new(1, 0.97, 0.9):Lerp(color, 0.2)
	light.Shadows = true
	light.Parent = top
end

return Spotlight
