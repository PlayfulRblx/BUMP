--!nonstrict
--[[
	The pieces BUMP's effects are made of, shared by every effect module (Client/Fx/*, BumpFx,
	PowerUpFx, RoundIntro): particle emitters built from recipe tables in Sunshine Valley's
	storybook look (VFX IKEA's cloud puff, ring flipbook, stars, sparkles, dust), one-shot bursts,
	where on a body to put them, glowing parts and streaks, the comic words that pop over hits, a
	sound at a place, and the camera's shake (Humanoid.CameraOffset, your own camera only).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local TEXTURES = {
	Cloud = "rbxassetid://290833005", -- IKEA Teleport.Wind cloud puff
	RingBurst = "rbxassetid://75804565349970", -- IKEA circleboom2, 4x4 flipbook
	Star = "rbxassetid://15580440964",
	Sparkle = "rbxassetid://128453777673840",
	Dust = "rbxassetid://619393574",
}

local DUST = Color3.fromRGB(255, 246, 228)
local GOLD = Color3.fromRGB(255, 211, 111)
local WHITE = Color3.fromRGB(255, 255, 255)

-- ═══ building emitters ════════════════════════════════════════════════════════════

local function numbers(points)
	if type(points) == "number" then
		return NumberSequence.new(points)
	end
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function range(value)
	if type(value) == "table" then
		return NumberRange.new(value[1], value[2])
	end
	return NumberRange.new(value)
end

-- A ParticleEmitter from a recipe table. Count is how many one burst emits.
local function emitter(recipe): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEXTURES[recipe.Texture] or recipe.Texture
	e.Color = ColorSequence.new(recipe.Color or WHITE)
	e.Size = numbers(recipe.Size or 1)
	e.Transparency = numbers(recipe.Transparency or { { 0, 0.2 }, { 1, 1 } })
	e.Speed = range(recipe.Speed or { 3, 6 })
	e.Lifetime = range(recipe.Life or { 0.35, 0.6 })
	e.Acceleration = recipe.Acceleration or Vector3.zero
	e.Drag = recipe.Drag or 0
	e.SpreadAngle = recipe.Spread or Vector2.new(30, 30)
	e.EmissionDirection = recipe.Direction or Enum.NormalId.Top
	e.Rotation = range(recipe.Rotation or { 0, 360 })
	e.RotSpeed = range(recipe.RotSpeed or 0)
	e.LightEmission = recipe.Glow or 0
	e.LightInfluence = recipe.LightInfluence or 0.5
	e.Orientation = recipe.Orientation or Enum.ParticleOrientation.FacingCamera
	e.Rate = recipe.Rate or 0
	e.ZOffset = recipe.ZOffset or 0
	if recipe.Flipbook then
		e.FlipbookLayout = recipe.Flipbook
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	end
	if recipe.Locked then
		e.LockedToPart = true
	end
	e.Enabled = recipe.Rate ~= nil
	return e
end

-- Cloud puffs that ring out flat round a point (the attachment's up is the ground's up).
local function puff(count: number, speed, size: number, color: Color3?)
	return {
		Texture = "Cloud", Color = color or DUST, Count = count, Speed = speed, Life = { 0.35, 0.6 },
		Direction = Enum.NormalId.Front, Spread = Vector2.new(0, 180),
		Size = { { 0, size * 0.35 }, { 0.35, size * 0.8 }, { 1, size } },
		Transparency = { { 0, 0.45 }, { 0.5, 0.65 }, { 1, 1 } },
		Acceleration = Vector3.new(0, 0.6, 0), Drag = 6, RotSpeed = { -40, 40 }, LightInfluence = 0.55, Glow = 0.1,
	}
end

-- The expanding ring flipbook, lying flat (perpendicular to the attachment's up).
local function ring(size: number, color: Color3?)
	return {
		Texture = "RingBurst", Color = color or DUST, Count = 1, Speed = 0.01, Life = 0.45,
		Flipbook = Enum.ParticleFlipbookLayout.Grid4x4, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Size = { { 0, size * 0.2 }, { 0.3, size * 0.75 }, { 1, size } },
		Transparency = { { 0, 0.15 }, { 0.6, 0.35 }, { 1, 1 } }, Rotation = 0, Glow = 0.4, Spread = Vector2.zero,
	}
end

local function stars(count: number, speed, size: number)
	return {
		Texture = "Star", Color = GOLD, Count = count, Speed = speed, Life = { 0.4, 0.65 },
		Size = { { 0, size }, { 0.7, size }, { 1, 0 } }, Transparency = { { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } },
		Acceleration = Vector3.new(0, -10, 0), Drag = 2, Spread = Vector2.new(60, 60), RotSpeed = { -180, 180 }, Glow = 0.6,
	}
end

local function sparkles(count: number, size: number)
	return {
		Texture = "Sparkle", Color = WHITE, Count = count, Speed = { 2, 5 }, Life = { 0.4, 0.7 },
		Size = { { 0, size * 0.35 }, { 0.18, size }, { 1, 0 } }, Transparency = { { 0, 0 }, { 1, 1 } },
		Acceleration = Vector3.new(0, 1, 0), Drag = 5, Spread = Vector2.new(180, 180), Glow = 0.5,
	}
end

-- Plays every recipe once at `at` (a CFrame whose up is "up" for the effect), then cleans up.
local function burst(at: CFrame, recipes)
	local holder = Instance.new("Attachment")
	holder.WorldCFrame = at
	holder.Parent = Workspace.Terrain
	local longest = 0
	for _, recipe in recipes do
		local e = emitter(recipe)
		e.Parent = holder
		e:Emit(recipe.Count or 1)
		longest = math.max(longest, e.Lifetime.Max)
	end
	Debris:AddItem(holder, longest + 0.3)
end

-- ═══ where on a body ══════════════════════════════════════════════════════════════

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

-- Flat at the feet, unrotated, so rings lie on the ground and puffs fan along it.
local function feet(model: Model): CFrame?
	local root = rootOf(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	return CFrame.new(root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2 - 0.2, 0))
end

-- On the wall in front of the body, its up pointing out of the wall.
local function wallPoint(model: Model, height: number): CFrame?
	local root = rootOf(model)
	if not root then
		return nil
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local spot = root.Position + look * 1.3 + Vector3.new(0, height, 0)
	-- an attachment's up (its Y) out of the wall, toward the body
	return CFrame.fromMatrix(spot, look:Cross(Vector3.yAxis), -look)
end

-- ═══ camera ═══════════════════════════════════════════════════════════════════════

local shake = 0
local shakeConnection = nil

local function kick(amount: number)
	shake = math.max(shake, amount)
	if shakeConnection then
		return
	end
	shakeConnection = RunService.RenderStepped:Connect(function(dt)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		shake = math.max(0, shake - dt * 3.5)
		if humanoid then
			if shake <= 0 then
				humanoid.CameraOffset = Vector3.zero
			else
				local s = shake * shake
				humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
			end
		end
		if shake <= 0 then
			shakeConnection:Disconnect()
			shakeConnection = nil
		end
	end)
end

-- A sound at a place, heard from up to `distance` studs away.
local function sound(id: string, volume: number, parent: Instance, distance: number?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = distance or 220
	s.Parent = parent
	return s
end

-- A glowing part that touches nothing, for flashes and rings.
local function glowPart(size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	if shape then
		p.Shape = shape
	end
	p.Parent = Workspace
	return p
end

-- A streak along `dir` from `origin`: grows out to `length`, thins and fades.
local function streak(origin: Vector3, dir: Vector3, length: number, width: number, color: Color3, seconds: number)
	local function at(l: number): CFrame
		return CFrame.lookAt(origin + dir * (l / 2), origin + dir * l) * CFrame.Angles(0, math.rad(90), 0)
	end
	local p = glowPart(Vector3.new(1, width, width), at(1), color, Enum.PartType.Cylinder)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(p, info, { Size = Vector3.new(length, width * 0.15, width * 0.15), CFrame = at(length) }):Play()
	TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(p, seconds + 0.1)
end

-- A comic "BUMP!" where a shove lands: it pops up big, tilted, then rises and fades.
local COMIC_FONT = Font.new("rbxasset://fonts/families/LuckiestGuy.json")
local COMIC_YELLOW = Color3.fromRGB(255, 214, 54)
local COMIC_INK = Color3.fromRGB(24, 20, 40)

local function comicPop(position: Vector3, text: string, size: number?)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position + Vector3.new(0, 1.5, 0)
	holder.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220 * (size or 1), 90 * (size or 1))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	gui.Adornee = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.FontFace = COMIC_FONT
	label.TextScaled = true
	label.TextColor3 = COMIC_YELLOW
	label.TextStrokeColor3 = COMIC_INK
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-14, 14)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = COMIC_INK
	stroke.Thickness = 3
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	gui.Parent = holder
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0),
	}):Play()
	task.delay(0.42, function()
		TweenService:Create(label, TweenInfo.new(0.28), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.28), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(holder, 0.8)
end

local FxKit = {
	Emitter = emitter, Puff = puff, Ring = ring, Stars = stars, Sparkles = sparkles, Burst = burst,
	RootOf = rootOf, Feet = feet, WallPoint = wallPoint, Kick = kick, Sound = sound,
	GlowPart = glowPart, Streak = streak, ComicPop = comicPop,
	Dust = DUST, Gold = GOLD, White = WHITE,
}

return FxKit
