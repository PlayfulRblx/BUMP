--!nonstrict
--[[
	Bots: stand-ins for empty seats, moved by the server. A bot dealt one of the players' friends
	(Server/Rounds/Friends) wears that friend's avatar; any other is a plain body in its seat's
	colour. Each minigame drives them itself (BumpGame's bot brain); this only makes and
	clears them. They wear the same tags as players' characters, so they can be bumped, are
	animated by every client's Animator, and ragdoll the same way.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")

local Bots = {}

Bots.Names = {
	"Pipsqueak", "Wobbles", "Bonkers", "Zippy", "Doodle", "Noodle", "Tumble", "Fizz",
	"Biscuit", "Sprocket", "Pogo", "Mochi", "Waffles", "Jellybean",
}

function Bots.SeatColor(seat: number): Color3
	return RoundInfo.SeatColors[seat] or Color3.fromRGB(200, 200, 200)
end

local SKIN = Color3.fromRGB(240, 210, 180)

-- Paints a body part by part: colours on a HumanoidDescription don't reach a body built from
-- it here (bots and dummies came out black).
function Bots.Paint(model: Model, shirt: Color3, trousers: Color3)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local name = part.Name
			if name == "UpperTorso" or name == "LowerTorso" or name == "Torso" then
				part.Color = shirt
			elseif name:find("Leg") or name:find("Foot") then
				part.Color = trousers
			else
				part.Color = SKIN
			end
		end
	end
end

-- A friend's body colours, part by part, from their avatar (the colours on a description don't
-- reach a body built from it here, so they're painted on as Paint does).
local PART_COLOURS = {
	Head = "HeadColor", UpperTorso = "TorsoColor", LowerTorso = "TorsoColor",
	LeftUpperArm = "LeftArmColor", LeftLowerArm = "LeftArmColor", LeftHand = "LeftArmColor",
	RightUpperArm = "RightArmColor", RightLowerArm = "RightArmColor", RightHand = "RightArmColor",
	LeftUpperLeg = "LeftLegColor", LeftLowerLeg = "LeftLegColor", LeftFoot = "LeftLegColor",
	RightUpperLeg = "RightLegColor", RightLowerLeg = "RightLegColor", RightFoot = "RightLegColor",
}
local function paintFrom(model: Model, description: HumanoidDescription)
	for _, part in model:GetChildren() do
		local property = part:IsA("BasePart") and PART_COLOURS[part.Name]
		if property then
			part.Color = description[property]
		end
	end
end

-- The plain body: skin, a shirt in the seat's colour, darker trousers.
local function plainBody(color: Color3): Model
	local description = Instance.new("HumanoidDescription")
	description.TorsoColor = color
	description.LeftArmColor = SKIN
	description.RightArmColor = SKIN
	description.HeadColor = SKIN
	description.LeftLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	description.RightLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	Bots.Paint(model, color, color:Lerp(Color3.new(0, 0, 0), 0.4))
	return model
end

-- `look`: a friend's avatar (Friends.Look) to wear, or nil for the plain seat-coloured body. The
-- seat's colour still marks a friend's bot everywhere else (its ball, spotlight, name and ring).
function Bots.Spawn(id: string, name: string, seat: number, cframe: CFrame, look: HumanoidDescription?): Model
	local color = Bots.SeatColor(seat)
	local model
	if look then
		local ok, built = pcall(Players.CreateHumanoidModelFromDescription, Players, look:Clone(), Enum.HumanoidRigType.R15)
		if ok and built then
			model = built
			paintFrom(model, look)
		else
			warn("[Bots] couldn't build " .. name .. "'s look: " .. tostring(built))
		end
	end
	model = model or plainBody(color)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayName = name
	humanoid.WalkSpeed = 24
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 45
	model:SetAttribute(RoundInfo.IdAttr, id)
	model:SetAttribute(Remotes.MoveAttr, "Run")
	model:PivotTo(cframe)
	model.Parent = Workspace
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetNetworkOwner(nil)
		end
	end
	CollectionService:AddTag(model, Remotes.BodyTag)
	CollectionService:AddTag(model, RoundInfo.BotTag)
	return model
end

function Bots.Remove(model: Model?)
	if model then
		model:Destroy()
	end
end

return Bots
