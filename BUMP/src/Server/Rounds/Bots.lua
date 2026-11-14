--!nonstrict
--[[
	Bots: stand-ins for empty seats, built from a plain avatar in their seat's colour and moved by
	the server. Each minigame drives them itself (BumpGame's bot brain); this only makes and
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

function Bots.Spawn(id: string, name: string, seat: number, cframe: CFrame): Model
	local description = Instance.new("HumanoidDescription")
	local color = Bots.SeatColor(seat)
	description.TorsoColor = color
	description.LeftArmColor = Color3.fromRGB(240, 210, 180)
	description.RightArmColor = Color3.fromRGB(240, 210, 180)
	description.HeadColor = Color3.fromRGB(240, 210, 180)
	description.LeftLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	description.RightLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	local model = Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
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
	Bots.Paint(model, color, color:Lerp(Color3.new(0, 0, 0), 0.4))
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
