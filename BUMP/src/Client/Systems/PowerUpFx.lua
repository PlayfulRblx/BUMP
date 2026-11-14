--!nonstrict
--[[
	What a power-up looks and sounds like, on every client (Server/Rounds/PowerUps fires Fx
	"PowerUp" { Id, Level, Holder, Position } on every use).

	- Every use: the power-up's name pops up over its holder in its colour, so the whole arena
	  (and the plaza watching) can read what just happened.
	- Shield: a bubble round the body for as long as its ShieldAttr says, blinking in its last
	  moments and popping when it drops.
	- Turbo: a whoosh, dust and speed streaks thrown back; on foot a trail while the boost lasts
	  (on a ball the dash's own launch effects play, BumpFx's chargeFx).
	- Shockwave: a ring of light racing out across the floor to its reach, with a low boom and a
	  shake if you're in it (the tiles' ripple is BumpFx's "Ripple").
	- Second Chance: a column of light where it puts you back, stars and a slide whistle.

	Built from BumpFx's pieces (Burst, Recipes, GlowPart, Streak, Sound, Kick).
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")
local Remotes = require("@Shared/Movement/Remotes")
local BumpFx = require("@Client/Systems/BumpFx")

local PowerUpFx = {}

local BUBBLE_SIZE = 9
local BLINK_FROM = 0.9 -- seconds left when a shield starts to blink
local CALLOUT_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
local INK = Color3.fromRGB(24, 22, 30)

local player = Players.LocalPlayer
local bubbles = {} -- [Model] = { part, connection }

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

local function colorOf(id: string): Color3
	local item = PowerUpInfo.Get(id)
	return item and item.Color or Color3.new(1, 1, 1)
end

local function playAt(id: string, position: Vector3, volume: number, speed: number)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = Workspace.Terrain
	local s = BumpFx.Sound(id, volume, holder)
	s.PlaybackSpeed = speed
	s:Play()
	Debris:AddItem(holder, 4)
end

-- ═══ the name over the holder ═════════════════════════════════════════════════════

local function callout(model: Model, text: string, color: Color3)
	local root = rootOf(model)
	if not root then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BumpPowerCallout"
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.upper(text) .. "!"
	label.FontFace = CALLOUT_FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	gui.Parent = root
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 8, 0),
	}):Play()
	task.delay(0.8, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(gui, 1.4)
end

-- ═══ shield bubbles ═══════════════════════════════════════════════════════════════

local function popBubble(model: Model)
	local bubble = bubbles[model]
	if not bubble then
		return
	end
	bubbles[model] = nil
	bubble.connection:Disconnect()
	local at = bubble.part.Position
	bubble.part:Destroy()
	local recipes = BumpFx.Recipes
	BumpFx.Burst(CFrame.new(at), { recipes.Ring(10, colorOf("Shield")), recipes.Sparkles(10, 0.7) })
end

local function showBubble(model: Model)
	if bubbles[model] then
		return
	end
	local part = Instance.new("Part")
	part.Name = "BumpShieldBubble"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * BUBBLE_SIZE
	part.Material = Enum.Material.ForceField
	part.Color = colorOf("Shield")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = Workspace
	local bubble = { part = part }
	local born = os.clock()
	bubble.connection = RunService.RenderStepped:Connect(function()
		local root = rootOf(model)
		local left = (model:GetAttribute(PowerUpInfo.ShieldAttr) or 0) - now()
		if not root or not model.Parent or left <= 0 then
			popBubble(model)
			return
		end
		local t = os.clock() - born
		-- swells in, breathes, and blinks when it's about to drop
		local grow = math.min(1, t / 0.18)
		local breathe = 1 + math.sin(t * 6) * 0.03
		part.Size = Vector3.one * BUBBLE_SIZE * grow * breathe
		part.CFrame = CFrame.new(root.Position + Vector3.new(0, 0.4, 0))
		part.Transparency = left < BLINK_FROM and ((math.floor(t * 12) % 2 == 0) and 0.2 or 0.75) or 0.15
	end)
	bubbles[model] = bubble
end

local function watchShield(model: Model)
	local function check()
		if (model:GetAttribute(PowerUpInfo.ShieldAttr) or 0) > now() then
			showBubble(model)
		end
	end
	model:GetAttributeChangedSignal(PowerUpInfo.ShieldAttr):Connect(check)
	check()
end

-- ═══ each power-up going off ══════════════════════════════════════════════════════

local function turbo(model: Model, root: BasePart, color: Color3)
	local recipes = BumpFx.Recipes
	local back = -root.CFrame.LookVector
	BumpFx.Burst(CFrame.new(root.Position - Vector3.new(0, 2.4, 0)), { recipes.Puff(10, { 10, 18 }, 2), recipes.Ring(7, color) })
	for _ = 1, 6 do
		local spread = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.6, math.random() - 0.5) * 0.6
		local dir = (back + spread).Unit
		local origin = root.Position + Vector3.new(0, math.random() * 2 - 1, 0)
		BumpFx.Streak(origin, dir, 7 + math.random() * 5, 0.35, color, 0.4)
	end
	playAt(BumpSounds.PowerTurbo, root.Position, BumpSounds.PowerVolume, 1.1)
	-- on foot, a trail while the boost lasts
	local untilTime = model:GetAttribute(PowerUpInfo.BoostAttr) or 0
	local seconds = untilTime - now()
	if seconds > 0 then
		local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
		top.Position = Vector3.new(0, 1.2, 0)
		bottom.Position = Vector3.new(0, -1.6, 0)
		top.Parent, bottom.Parent = root, root
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = top, bottom
		trail.Color = ColorSequence.new(color)
		trail.Transparency = NumberSequence.new(0.25, 1)
		trail.Lifetime = 0.28
		trail.LightEmission = 0.6
		trail.FaceCamera = true
		trail.Parent = root
		Debris:AddItem(trail, seconds)
		Debris:AddItem(top, seconds + 0.3)
		Debris:AddItem(bottom, seconds + 0.3)
	end
end

local function shockwave(position: Vector3, reach: number, color: Color3)
	local floor = Vector3.new(position.X, position.Y - 2.8, position.Z)
	-- a flat ring of light racing out to the reach
	local disc = BumpFx.GlowPart(Vector3.new(0.3, 2, 2), CFrame.new(floor) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
	disc.Transparency = 0.2
	local info = TweenInfo.new(reach / 70, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(disc, info, { Size = Vector3.new(0.3, reach * 2, reach * 2), Transparency = 1 }):Play()
	Debris:AddItem(disc, reach / 70 + 0.1)
	local recipes = BumpFx.Recipes
	BumpFx.Burst(CFrame.new(floor), { recipes.Puff(14, { 14, 24 }, 2.4), recipes.Stars(6, { 10, 16 }, 0.6) })
	playAt(BumpSounds.PowerShockwave, position, BumpSounds.PowerVolume, 0.7)
	local root = player.Character and rootOf(player.Character)
	if root and (root.Position - position).Magnitude < reach then
		BumpFx.Kick(1)
	end
end

local function rescue(position: Vector3, color: Color3)
	local column = BumpFx.GlowPart(Vector3.new(30, 5, 5), CFrame.new(position + Vector3.new(0, 10, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
	column.Transparency = 0.25
	TweenService:Create(column, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(34, 0.4, 0.4),
		Transparency = 1,
	}):Play()
	Debris:AddItem(column, 0.8)
	local recipes = BumpFx.Recipes
	BumpFx.Burst(CFrame.new(position - Vector3.new(0, 2, 0)), { recipes.Ring(12, color), recipes.Stars(10, { 10, 16 }, 0.7), recipes.Sparkles(12, 0.8) })
	playAt(BumpSounds.PowerRescue, position, BumpSounds.PowerVolume, 1)
end

local function onPowerUp(data)
	local id = data.Id
	local item = PowerUpInfo.Get(id)
	if not item then
		return
	end
	local model = typeof(data.Holder) == "Instance" and data.Holder or nil
	local root = rootOf(model)
	local position = typeof(data.Position) == "Vector3" and data.Position or (root and root.Position)
	local color = item.Color
	if model then
		callout(model, item.Name, color)
	end
	if not position then
		return
	end
	if id == "Shield" then
		local recipes = BumpFx.Recipes
		BumpFx.Burst(CFrame.new(position), { recipes.Ring(10, color), recipes.Sparkles(12, 0.7) })
		playAt(BumpSounds.PowerShield, position, BumpSounds.PowerVolume, 1.5)
		if model then
			showBubble(model)
		end
	elseif id == "Turbo" and root then
		turbo(model, root, color)
	elseif id == "Shockwave" then
		local stats = PowerUpInfo.Stats(id, data.Level or 1)
		shockwave(position, stats and stats.Radius or 20, color)
	elseif id == "SecondChance" then
		rescue(position, color)
	end
end

function PowerUpFx.start()
	CollectionService:GetInstanceAddedSignal(Remotes.BodyTag):Connect(function(model)
		if model:IsA("Model") then
			watchShield(model)
		end
	end)
	for _, model in CollectionService:GetTagged(Remotes.BodyTag) do
		if model:IsA("Model") then
			watchShield(model)
		end
	end
	Remotes.HookFx(function(name, data)
		if name == "PowerUp" and type(data) == "table" then
			onPowerUp(data)
		end
	end)
end

return PowerUpFx
