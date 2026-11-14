--!nonstrict
--[[
	MELTDOWN on every client: the lava, the moving platforms, and telling the server the moment
	you touch the lava (its copy of a falling body lags behind yours).

	- The lava: the server only says where it is and how fast it's rising (the tower folder's
	  "LavaY" / "LavaAt" / "LavaRate", Server/Rounds/Tower); each client moves the "Lava" part
	  itself every frame, smoothly, and dresses it: a shimmering crust, embers and bubbles off its
	  surface, a bubbling that gets louder the closer you are. It glows hotter in a surge, and
	  sinks away when the tower leaves.
	- Moving platforms (RoundInfo.MoverAttr): every client moves its own copy from the same server
	  time (Shared/Minigames/MeltLayout.MoverOffset), so they glide instead of stepping with the
	  network; the Platformer carries you with them.
	- The heat: the closer the lava is below you, the warmer the picture.
	- "Melted": your root under the lava's top and you still in the game, sent to the server
	  (MeltdownGame believes it if its copy of you is anywhere near).
]]

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local MeltFx = require("@Client/Fx/MeltFx")
local Platformer = require("@Client/Systems/Platformer")
local MeltLayout = require("@Shared/Minigames/MeltLayout")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")

local MeltClient = {}

local LAVA_THICK = 60 -- as Tower's
local LAVA_COLOR = Color3.fromRGB(235, 62, 18) -- deep enough not to wash out to yellow under the bloom
local SURGE_COLOR = Color3.fromRGB(255, 150, 50)
local MELT_ABOVE = 1.2 -- your root this little above the lava's top and you've touched it
local MELT_RESEND = 0.5
local HEAT_RANGE = 28

local player = Players.LocalPlayer
local tower = nil -- the MeltTower folder being shown
local dressing = nil -- { crust, surface, sound }
local shownY = nil
local sinkFrom = nil -- { at, y } once the tower is leaving
local surgeUntil = 0
local meltSentAt = 0
local heat = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Where the server says the lava's top is right now.
local function lavaY(folder: Instance): number?
	local y, at, rate = folder:GetAttribute("LavaY"), folder:GetAttribute("LavaAt"), folder:GetAttribute("LavaRate")
	if type(y) ~= "number" then
		return nil
	end
	return y + (rate or 0) * (serverNow() - (at or serverNow()))
end

function MeltClient.LavaY(): number?
	return shownY
end

-- Surging: the lava glows hotter for this long (MeltFx's "Surge").
function MeltClient.Surge(seconds: number)
	surgeUntil = os.clock() + seconds
end

local function inGame(): boolean
	local round = ReplicatedStorage:FindFirstChild(RoundInfo.Folder)
	if not round or round:GetAttribute("Phase") ~= "Play" or round:GetAttribute("Minigame") ~= "Meltdown" then
		return false
	end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, round:GetAttribute("Players") or "[]")
	if not ok or type(list) ~= "table" then
		return false
	end
	for _, entry in list do
		if type(entry) == "table" and entry.UserId == player.UserId then
			return not entry.Out
		end
	end
	return false
end

local function emitterOn(parent: Instance, props)
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		e[key] = value
	end
	e.Parent = parent
	return e
end

local function dress(folder: Instance, lava: BasePart)
	local crust = lava:Clone()
	crust.Name = "LavaCrust"
	crust.Material = Enum.Material.ForceField -- it shimmers and crawls on its own
	crust.Color = Color3.fromRGB(255, 140, 50)
	crust.Transparency = 0
	crust.Size = Vector3.new(0.6, lava.Size.Y, lava.Size.Z)
	crust.Parent = folder
	-- a flat box just under the top to throw embers and bubbles off
	local surface = Instance.new("Part")
	surface.Name = "LavaSurface"
	surface.Anchored = true
	surface.CanCollide = false
	surface.CanQuery = false
	surface.CanTouch = false
	surface.Transparency = 1
	surface.Size = Vector3.new(lava.Size.Y * 0.9, 0.4, lava.Size.Y * 0.9)
	surface.Parent = folder
	emitterOn(surface, {
		Name = "Embers",
		Texture = "rbxassetid://128453777673840",
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 80, 30)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1),
		Lifetime = NumberRange.new(1.6, 3),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 3, 0),
		Drag = 0.6,
		Rate = 60,
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Top,
	})
	emitterOn(surface, {
		Name = "Bubbles",
		Texture = "rbxassetid://290833005",
		Color = ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(120, 40, 30)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 4), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(1, 3),
		Rate = 25,
		LightEmission = 0.6,
		RotSpeed = NumberRange.new(-40, 40),
		EmissionDirection = Enum.NormalId.Top,
	})
	local sound = Instance.new("Sound")
	sound.Name = "LavaBubble"
	sound.SoundId = BumpSounds.LavaBubble
	sound.Looped = true
	sound.PlaybackSpeed = 0.55
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	dressing = { crust = crust, surface = surface, sound = sound }
end

local function undress()
	if dressing then
		dressing.sound:Destroy()
		dressing.crust:Destroy()
		dressing.surface:Destroy()
	end
	dressing = nil
end

local function setHeat(amount: number)
	if not heat or not heat.Parent then
		heat = Instance.new("ColorCorrectionEffect")
		heat.Name = "MeltHeat"
		heat.Parent = Lighting
	end
	heat.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 205, 175), amount)
	heat.Saturation = 0.15 * amount
	heat.Contrast = 0.06 * amount
end

local function placeLava(lava: BasePart, y: number)
	local centre = Vector3.new(lava.Position.X, y - LAVA_THICK / 2, lava.Position.Z)
	lava.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90))
	if dressing then
		dressing.crust.CFrame = CFrame.new(centre.X, y + 0.05, centre.Z) * CFrame.Angles(0, 0, math.rad(90))
		dressing.surface.CFrame = CFrame.new(centre.X, y - 0.3, centre.Z)
	end
end

local function step(dt: number)
	if tower and not tower.Parent then
		tower = nil
	end
	if not tower then
		if dressing then
			undress()
		end
		shownY = nil
		if heat and heat.Parent then
			setHeat(0)
		end
		return
	end
	local lava = tower:FindFirstChild("Lava")
	if not lava then
		return
	end
	if not dressing then
		dress(tower, lava)
	end
	local target = lavaY(tower) or lava.Position.Y + LAVA_THICK / 2
	-- leaving: it sinks away and goes dark
	if tower:GetAttribute("Leaving") then
		sinkFrom = sinkFrom or { at = os.clock(), y = shownY or target }
		local u = math.clamp((os.clock() - sinkFrom.at) / 1.4, 0, 1)
		target = sinkFrom.y - 30 * u * u
	else
		sinkFrom = nil
	end
	shownY = shownY and shownY + (target - shownY) * math.min(1, dt * 12) or target
	placeLava(lava, shownY)
	local surging = os.clock() < surgeUntil
	lava.Color = lava.Color:Lerp(surging and SURGE_COLOR or LAVA_COLOR, math.min(1, dt * 6))

	-- the movers, from server time (the server moves its own copy the same way)
	local t = serverNow()
	for _, model in tower:GetChildren() do
		if model:IsA("Model") and model:GetAttribute(RoundInfo.MoverAttr) and not model:GetAttribute("Falling") then
			local home = model:GetAttribute("MoverHome")
			local axis = model:GetAttribute("MoverAxis")
			if typeof(home) == "CFrame" and typeof(axis) == "Vector3" then
				local mover = { Axis = axis, Amp = model:GetAttribute("MoverAmp") or 0, Period = model:GetAttribute("MoverPeriod") or 5, Phase = model:GetAttribute("MoverPhase") or 0 }
				model:PivotTo(home + MeltLayout.MoverOffset(mover, t))
			end
		end
	end

	-- you, against it
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local above = root.Position.Y - shownY
		local actual = root.Position.Y - target
		if dressing then
			dressing.sound.Volume = 0.15 + 0.55 * math.clamp(1 - above / 45, 0, 1)
		end
		setHeat(math.clamp(1 - above / HEAT_RANGE, 0, 1) * (surging and 1 or 0.8))
		if actual < MELT_ABOVE and not tower:GetAttribute("Leaving") and os.clock() - meltSentAt > MELT_RESEND
			and not character:GetAttribute(RoundInfo.KnockoutHoldAttr) and inGame() then
			meltSentAt = os.clock()
			Remotes.Act("Melted")
		end
	end
end

local function watch(child: Instance)
	if child.Name == "MeltTower" and child:IsA("Folder") then
		tower = child
		shownY = nil
		sinkFrom = nil
		if dressing then
			undress()
		end
	end
end

function MeltClient.start()
	MeltFx.Watch(MeltClient.Surge)
	-- a bounce pad's boing (a pound's own jump comes from PoundLand)
	Platformer.OnMove(function(move, previous)
		if move == "PoundJump" and previous ~= "PoundLand" then
			local sound = Instance.new("Sound")
			sound.SoundId = BumpSounds.Bounce
			sound.Volume = 0.6
			sound.PlaybackSpeed = 1.5
			sound.Parent = SoundService
			sound:Play()
			task.delay(1.5, function()
				sound:Destroy()
			end)
		end
	end)
	Workspace.ChildAdded:Connect(watch)
	for _, child in Workspace:GetChildren() do
		watch(child)
	end
	RunService.RenderStepped:Connect(step)
end

return MeltClient
