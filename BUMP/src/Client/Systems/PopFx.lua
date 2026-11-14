--!nonstrict
--[[
	A bomb holder popping (the user: "When exploded by the bomb, the character should just pop and
	disappear almost instantly. Perhaps a red highlight that fades into a sackboy level pop").

	When a body's RoundInfo.PopAttr turns true (Server/Rounds/BomberGame), every client:
	- floods it red (a Highlight fading in over FLASH seconds);
	- then pops it: the body vanishes (LocalTransparencyModifier on everything, name hidden), a
	  white and red puff bursts out with a ring and sparkles, tufts of stuffing fly out and tumble
	  down, and a balloon pop plays (a kick of the camera if it's you or close);
	- and keeps it hidden until the server clears the attribute, once the body is on the stand.
	Our own take on a cartoon pop, no borrowed art. Built from BumpFx's pieces.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local BumpFx = require("@Client/Systems/BumpFx")

local PopFx = {}

local FLASH = 0.22 -- seconds of red before the pop
local RED = Color3.fromRGB(255, 50, 40)
local WHITE = Color3.fromRGB(255, 255, 255)
local STUFFING = { Color3.fromRGB(255, 250, 240), Color3.fromRGB(255, 226, 214), Color3.fromRGB(255, 90, 70) }
local TUFTS = 16

local player = Players.LocalPlayer
local popping = {} -- [Model] = serial while red or hidden
local serial = 0

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

-- Everything that draws the body, hidden or shown on this client only.
local function setHidden(model: Model, hidden: boolean)
	for _, thing in model:GetDescendants() do
		if thing:IsA("BasePart") or thing:IsA("Decal") or thing:IsA("Texture") then
			thing.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if hidden then
			if humanoid:GetAttribute("BumpPopNames") == nil then
				humanoid:SetAttribute("BumpPopNames", humanoid.DisplayDistanceType.Name)
			end
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		else
			local before = humanoid:GetAttribute("BumpPopNames")
			if before then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType[before]
				humanoid:SetAttribute("BumpPopNames", nil)
			end
		end
	end
end

-- Tufts of stuffing thrown out of the pop, tumbling and shrinking away.
local function stuffing(at: Vector3)
	for _ = 1, TUFTS do
		local tuft = Instance.new("Part")
		tuft.Shape = Enum.PartType.Ball
		tuft.Size = Vector3.one * (0.5 + math.random() * 0.6)
		tuft.Material = Enum.Material.SmoothPlastic
		tuft.Color = STUFFING[math.random(#STUFFING)]
		tuft.CanCollide = false
		tuft.CanQuery = false
		tuft.CanTouch = false
		tuft.CastShadow = false
		tuft.Position = at + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2
		tuft.Parent = Workspace
		local out = Vector3.new(math.random() - 0.5, 0.3 + math.random() * 0.7, math.random() - 0.5).Unit
		tuft.AssemblyLinearVelocity = out * (24 + math.random() * 22)
		tuft.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		local life = 0.8 + math.random() * 0.5
		TweenService:Create(tuft, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.one * 0.05,
			Transparency = 0.6,
		}):Play()
		Debris:AddItem(tuft, life + 0.05)
	end
end

local function pop(model: Model)
	serial += 1
	local mine = serial
	popping[model] = mine
	local root = rootOf(model)
	if not root then
		return
	end
	-- red floods in
	local highlight = Instance.new("Highlight")
	highlight.Name = "BumpPopFlash"
	highlight.FillColor = RED
	highlight.OutlineColor = WHITE
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	local flash = TweenInfo.new(FLASH, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(highlight, flash, { FillTransparency = 0, OutlineTransparency = 0.2 }):Play()
	task.delay(FLASH, function()
		highlight:Destroy()
		if popping[model] ~= mine or not model.Parent then
			return
		end
		local at = (rootOf(model) or root).Position + Vector3.new(0, 0.6, 0)
		setHidden(model, true)
		local recipes = BumpFx.Recipes
		BumpFx.Burst(CFrame.new(at), {
			recipes.Puff(14, { 12, 22 }, 3.4, WHITE),
			recipes.Puff(8, { 8, 16 }, 2.4, RED),
			recipes.Ring(14, WHITE),
			recipes.Sparkles(14, 0.9),
		})
		stuffing(at)
		local holder = Instance.new("Attachment")
		holder.WorldPosition = at
		holder.Parent = Workspace.Terrain
		local s = BumpFx.Sound(BumpSounds.Pop, BumpSounds.PopVolume, holder)
		s.PlaybackSpeed = 0.9 + math.random() * 0.2
		s:Play()
		Debris:AddItem(holder, 2)
		local mineRoot = player.Character and rootOf(player.Character)
		if model == player.Character then
			BumpFx.Kick(1.2)
		elseif mineRoot and (mineRoot.Position - at).Magnitude < 30 then
			BumpFx.Kick(0.6)
		end
	end)
end

local function unpop(model: Model)
	popping[model] = nil
	local flash = model:FindFirstChild("BumpPopFlash")
	if flash then
		flash:Destroy()
	end
	setHidden(model, false)
end

local function watch(model: Model)
	local function check()
		if model:GetAttribute(RoundInfo.PopAttr) == true then
			if not popping[model] then
				pop(model)
			end
		elseif popping[model] then
			unpop(model)
		end
	end
	model:GetAttributeChangedSignal(RoundInfo.PopAttr):Connect(check)
	check()
end

function PopFx.start()
	CollectionService:GetInstanceAddedSignal(Remotes.BodyTag):Connect(function(model)
		if model:IsA("Model") then
			watch(model)
		end
	end)
	for _, model in CollectionService:GetTagged(Remotes.BodyTag) do
		if model:IsA("Model") then
			watch(model)
		end
	end
end

return PopFx
