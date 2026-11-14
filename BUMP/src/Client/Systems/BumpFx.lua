--!nonstrict
--[[
	Particles and camera kicks for moving and bumping, on every body.

	The look is Sunshine Valley's storybook dust, made from VFX IKEA's sprites (the IKEA place,
	92733014069261): its "Teleport.Wind" cartoon cloud puff, the "circleboom2" 4x4 expanding-ring
	flipbook, gold stars, sparkles and soft dust. The recipes follow Sunshine Valley's
	VfxPresetRegistry (RollKick, RollLand, RollBonk, PetSkid), retuned here.

	Animator hands every change of move here (OnMove), for your body and everyone else's, so a
	landing kicks dust whoever made it. The server's "Bump" event pops a hit wherever a bump
	lands. Lasting effects (dust off a wall slide or a belly slide, stars round a dazed head) run
	while their move lasts and stop when it changes.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require("@Shared/Movement/Remotes")
local BallSounds = require("@Client/Systems/BallSounds")
local BumpSounds = require("@Shared/Audio/BumpSounds")

local BumpFx = {}

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

local player = Players.LocalPlayer
local lasting = {} -- [Model] = { emitters to stop }

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

-- ═══ lasting effects ══════════════════════════════════════════════════════════════

local function stopLasting(model: Model)
	local list = lasting[model]
	if list then
		-- The list holds the emitters and the attachments they sit on: stop the emitters, and
		-- clear both once the last particles have faded.
		for _, item in list do
			if item.Parent then
				if item:IsA("ParticleEmitter") then
					item.Enabled = false
				end
				Debris:AddItem(item, 1)
			end
		end
		lasting[model] = nil
	end
end

local function startLasting(model: Model, parent: Instance, recipe)
	local e = emitter(recipe)
	e.Enabled = true
	e.Parent = parent
	lasting[model] = lasting[model] or {}
	table.insert(lasting[model], e)
	return e
end

local function onModelPart(model: Model, partName: string, offset: Vector3): Attachment?
	local part = model:FindFirstChild(partName) or rootOf(model)
	if not part then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "BumpFx"
	a.Position = offset
	a.Parent = part
	lasting[model] = lasting[model] or {}
	table.insert(lasting[model], a)
	return a
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

-- ═══ moves ════════════════════════════════════════════════════════════════════════

local LAUNCHES = { Jump = 0.8, AirJump = 1.1, Backflip = 1.2, LongJump = 1.1, PoundJump = 1.4, Rollout = 0.7 }
local AIRBORNE = {
	Jump = true, AirJump = true, Backflip = true, LongJump = true, PoundJump = true, Rollout = true,
	Fall = true, WallJump = true, Dive = true, Knocked = true,
}
local BIG_LANDINGS = { Backflip = true, LongJump = true, PoundJump = true, WallJump = true }

local chargeFx = {} -- the ball dash's charge-up and launch (defined further down)

function BumpFx.OnMove(model: Model, move: string, previous: string)
	BallSounds.OnMove(model, move, previous)
	if move == "RideCharge" then
		chargeFx.Start(model)
	elseif previous == "RideCharge" then
		chargeFx.Stop(model)
	end
	if move == "RideDash" then
		chargeFx.Launch(model)
	end
	stopLasting(model)
	local mine = model == player.Character
	local at = feet(model)
	if not at then
		return
	end

	if LAUNCHES[move] then
		local size = LAUNCHES[move]
		local recipes = { puff(math.round(3 * size), { 3, 5 * size }, size) }
		if move == "PoundJump" or move == "Backflip" or move == "AirJump" then
			table.insert(recipes, ring(2.6 * size))
			table.insert(recipes, sparkles(6, 0.35))
		end
		burst(at, recipes)
	elseif move == "PoundLand" then
		burst(at, { ring(7), puff(10, { 10, 16 }, 1.8), stars(3, { 5, 8 }, 0.35), sparkles(8, 0.4) })
		if mine then
			kick(1.1)
		end
	elseif move == "LandRoll" then
		burst(at, { ring(4), puff(6, { 6, 10 }, 1.4) })
		if mine then
			kick(0.6)
		end
	elseif move == "Roll" then
		burst(at, { puff(3, { 3, 5 }, 1.1) })
	elseif move == "Bonk" then
		local wall = wallPoint(model, 0.5)
		if wall then
			burst(wall, { ring(3.2), puff(6, { 6, 9 }, 1.3), stars(5, { 5, 8 }, 0.4) })
		end
		-- stars round the head while dazed
		local head = onModelPart(model, "Head", Vector3.new(0, 1.1, 0))
		if head then
			startLasting(model, head, {
				Texture = "Star", Color = GOLD, Rate = 7, Speed = { 1.5, 2.5 }, Life = { 0.5, 0.8 },
				Size = { { 0, 0 }, { 0.2, 0.32 }, { 0.8, 0.32 }, { 1, 0 } }, Transparency = 0,
				Direction = Enum.NormalId.Front, Spread = Vector2.new(0, 180), Drag = 3, RotSpeed = { -200, 200 }, Glow = 0.6,
			})
		end
		if mine then
			kick(0.9)
		end
	elseif move == "WallCling" then
		local wall = wallPoint(model, 1.2)
		if wall then
			burst(wall, { puff(4, { 3, 5 }, 0.9) })
		end
	elseif move == "WallSlide" then
		local hands = onModelPart(model, "HumanoidRootPart", Vector3.new(0, 1.2, -1.2))
		local foot = onModelPart(model, "HumanoidRootPart", Vector3.new(0.3, -1.6, -1.1))
		for _, a in { hands, foot } do
			if a then
				startLasting(model, a, {
					Texture = "Cloud", Color = DUST, Rate = 16, Speed = { 1, 2.5 }, Life = { 0.3, 0.5 },
					Size = { { 0, 0.3 }, { 0.4, 0.8 }, { 1, 1.1 } }, Transparency = { { 0, 0.45 }, { 1, 1 } },
					Acceleration = Vector3.new(0, 3, 0), Drag = 4, Spread = Vector2.new(40, 40), RotSpeed = { -40, 40 },
					Direction = Enum.NormalId.Top, LightInfluence = 0.55,
				})
			end
		end
	elseif move == "WallJump" then
		local wall = wallPoint(model, 0)
		-- the body has already turned away from the wall, so the wall is behind it
		local root = rootOf(model)
		if root then
			local back = -Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			back = back.Magnitude > 0.01 and back.Unit or Vector3.zAxis
			local spot = root.Position + back * 1.3
			wall = CFrame.fromMatrix(spot, back:Cross(Vector3.yAxis), -back)
		end
		if wall then
			burst(wall, { ring(3.4), puff(5, { 4, 7 }, 1.1) })
		end
	elseif move == "Slide" then
		burst(at, { ring(3), puff(5, { 5, 8 }, 1.2) })
		local a = onModelPart(model, "HumanoidRootPart", Vector3.new(0, -1.6, 0))
		if a then
			startLasting(model, a, {
				Texture = "Cloud", Color = DUST, Rate = 22, Speed = { 1, 3 }, Life = { 0.3, 0.55 },
				Size = { { 0, 0.4 }, { 0.4, 0.9 }, { 1, 1.2 } }, Transparency = { { 0, 0.5 }, { 1, 1 } },
				Acceleration = Vector3.new(0, 2, 0), Drag = 4, Spread = Vector2.new(60, 60), RotSpeed = { -40, 40 },
				Direction = Enum.NormalId.Top, LightInfluence = 0.55,
			})
		end
	elseif move == "Dive" then
		burst(at + Vector3.new(0, 1.5, 0), { puff(3, { 2, 4 }, 1) })
	elseif move == "Bump" then
		-- the shove going: a whoosh and a kick of dust off the back foot
		burst(at, { puff(4, { 4, 7 }, 1) })
		local root = rootOf(model)
		if root then
			local s = sound(BumpSounds.ShoveWhoosh, 0.45, root, 90)
			s.PlaybackSpeed = 1.35
			s:Play()
			Debris:AddItem(s, 1.5)
		end
	elseif move == "Shoved" then
		-- staggering back from a shove: stars knocked out round the head, dust skidding off the feet
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			burst(head.CFrame + Vector3.new(0, 0.8, 0), { stars(5, { 6, 10 }, 0.5) })
		end
		local a = onModelPart(model, "HumanoidRootPart", Vector3.new(0, -2.6, 0))
		if a then
			startLasting(model, a, {
				Texture = "Cloud", Color = DUST, Rate = 30, Speed = { 1, 3 }, Life = { 0.3, 0.55 },
				Size = { { 0, 0.5 }, { 0.4, 1 }, { 1, 1.3 } }, Transparency = { { 0, 0.45 }, { 1, 1 } },
				Acceleration = Vector3.new(0, 2, 0), Drag = 4, Spread = Vector2.new(70, 70), RotSpeed = { -40, 40 },
				Direction = Enum.NormalId.Top, LightInfluence = 0.55,
			})
		end
	elseif (move == "Run" or move == "Crouch") and AIRBORNE[previous] then
		if BIG_LANDINGS[previous] then
			burst(at, { ring(3), puff(5, { 4, 7 }, 1.2) })
		else
			burst(at, { puff(3, { 2.5, 4 }, 1) })
		end
	end
end

-- A bump landing on someone: a ring, a pop of cloud and stars where they met.
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

local function onBump(position: Vector3, kind: string?)
	if kind == "Bump" then
		-- a shove landing: bigger, with the word, and a thump
		burst(CFrame.new(position), {
			ring(6.5, WHITE), puff(9, { 8, 14 }, 1.6), stars(7, { 8, 13 }, 0.55), sparkles(8, 0.5),
		})
		comicPop(position, "BUMP!")
		local holder = Instance.new("Attachment")
		holder.WorldPosition = position
		holder.Parent = Workspace.Terrain
		local s = sound(BumpSounds.ShoveHit, 0.8, holder, 120)
		s.PlaybackSpeed = 0.7 + math.random() * 0.1
		s:Play()
		Debris:AddItem(holder, 2)
	else
		burst(CFrame.new(position), {
			ring(4.5, WHITE), puff(6, { 6, 10 }, 1.3), stars(4, { 6, 10 }, 0.45), sparkles(6, 0.4),
		})
	end
	local root = player.Character and rootOf(player.Character)
	if root and (root.Position - position).Magnitude < 6 then
		kick(kind == "Bump" and 1 or 0.8)
	end
end

-- A ball hitting a ball (BumpGame's ballImpact), sized by how hard: a white flash swelling, a
-- shockwave ring racing out flat, sparks thrown out round the hit, stars, a comic word (BUMP!,
-- WHAM!, or KAPOW! when it knocked someone off) and a thump; the camera kicks for the riders in
-- it (BallRider freezes their balls a moment and punches their view), less for anyone near.
local function onBallHit(data)
	local at: Vector3 = data.Position
	local strength = math.clamp(tonumber(data.Strength) or 0, 0, 1)
	local off = data.Off == true
	local power = off and 1 or strength
	local flash = glowPart(Vector3.one * 2, CFrame.new(at), WHITE, Enum.PartType.Ball)
	flash.Transparency = 0.1
	TweenService:Create(flash, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * (8 + 10 * power),
		Transparency = 1,
	}):Play()
	Debris:AddItem(flash, 0.25)
	local ringPart = glowPart(Vector3.new(0.3, 3, 3), CFrame.new(at - Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.PartType.Cylinder)
	ringPart.Transparency = 0.25
	TweenService:Create(ringPart, TweenInfo.new(0.38, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 20 + 26 * power, 20 + 26 * power),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ringPart, 0.45)
	for _ = 1, math.floor(6 + 8 * power) do
		local direction = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5)
		if direction.Magnitude < 0.05 then
			direction = Vector3.new(1, 0.2, 0)
		end
		streak(at, direction.Unit, 5 + 9 * power, 0.35 + 0.25 * power, math.random() < 0.5 and WHITE or GOLD, 0.28)
	end
	burst(CFrame.new(at), {
		ring(6 + 6 * power, WHITE), puff(math.floor(6 + 8 * power), { 8, 16 }, 1.6), stars(math.floor(4 + 6 * power), { 8, 14 }, 0.6), sparkles(10, 0.6),
	})
	comicPop(at, off and "KAPOW!" or (strength > 0.55 and "WHAM!" or "BUMP!"), 0.85 + 0.6 * power)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = Workspace.Terrain
	local thump = sound(BumpSounds.KOBoom, 0.35 + 0.45 * power, holder, 260)
	thump.PlaybackSpeed = 1.9 - 0.4 * power
	thump:Play()
	local boing = sound(BumpSounds.Pop, 0.6, holder, 200)
	boing.PlaybackSpeed = 0.55 + 0.15 * (1 - power)
	boing:Play()
	Debris:AddItem(holder, 3)
	local root = player.Character and rootOf(player.Character)
	local involved = false
	for _, ball in { data.Hitter, data.Hit } do
		if typeof(ball) == "Instance" and ball:GetAttribute("Rider") == tostring(player.UserId) then
			involved = true
		end
	end
	if involved then
		kick(1 + 0.8 * power)
	elseif root and (root.Position - at).Magnitude < 40 then
		kick(0.4 + 0.4 * power)
	end
end

-- A ground pound's ripple through BUMP's hex tiles: each tile bobs up and back as the wave
-- reaches it, less the further out. Drawn on this machine only (the tiles stay put for the
-- server), with a ring of dust where it started.
local function onRipple(data)
	-- whichever game's arena is in (BUMP's or Bomber's), not one that's leaving
	local arena = nil
	for _, child in Workspace:GetChildren() do
		if child:GetAttribute("HexArena") ~= nil and not child:GetAttribute("Leaving") then
			arena = child
		end
	end
	if not arena then
		return
	end
	local origin = data.Position
	local radius, speed, height = data.Radius or 28, data.Speed or 70, data.Height or 1.6
	burst(CFrame.new(origin - Vector3.new(0, 2.6, 0)), { ring(radius * 0.6), puff(10, { 10, 18 }, 1.6) })
	for _, tile in arena:GetChildren() do
		if tile:IsA("Model") and tile:GetAttribute("Ring") ~= nil and not tile:GetAttribute("Falling") then
			local pivot = tile:GetPivot().Position
			local distance = Vector3.new(pivot.X - origin.X, 0, pivot.Z - origin.Z).Magnitude
			if distance <= radius then
				local lift = height * (1 - distance / radius) + 0.3
				task.delay(distance / speed, function()
					for _, part in tile:GetChildren() do
						if part:IsA("BasePart") and part.Anchored then
							local base = part:GetAttribute("BumpRippleBase") or part.CFrame
							part:SetAttribute("BumpRippleBase", base)
							local tween = TweenService:Create(part, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
								CFrame = base + Vector3.new(0, lift, 0),
							})
							tween:Play()
						end
					end
				end)
			end
		end
	end
	local root = player.Character and rootOf(player.Character)
	if root and (root.Position - origin).Magnitude < radius then
		kick(0.7)
	end
end

-- ═══ Bomber Bloxians' bomb ═══════════════════════════════════════════════════════

local BOMB_TAG = "BumpBomb"
local BOMB_RED = Color3.fromRGB(255, 60, 40)
local BOMB_DARK = Color3.fromRGB(32, 32, 40)


-- One bomb, while it exists. The server's bomb is welded stiffly to the holder's root; each client
-- hides it and draws its own, sprung to a point between the holder's hands, so it bounces with
-- the run, lags and tilts when they turn or stop, squashes on landings, pulses on each tick, and
-- swings across to the new holder on a pass (the user: "the bomb should wobble with the
-- character ... It doesn't look fun to carry at all"). A spark on its fuse, and a tick with a red
-- flash every "TickEvery" seconds (the server quickens it as the hidden fuse burns down).
local BOMB_SPRING, BOMB_DAMP = 220, 13 -- a bouncy spring: overshoots and settles
local BOMB_SNAP = 40 -- further than this from where it should be, it jumps there

local function holderOf(bomb: BasePart): Model?
	local weld = bomb:FindFirstChild("HoldWeld")
	local root = weld and weld:IsA("Weld") and weld.Part0
	return root and root.Parent and root.Parent:IsA("Model") and root.Parent or nil
end

-- Where the bomb should sit: resting on top of the raised hands (any lower and it swallows the
-- head), or where the server holds it if there are no hands.
local function carryPoint(bomb: BasePart, radius: number): Vector3
	local model = holderOf(bomb)
	if model then
		local left, right = model:FindFirstChild("LeftHand"), model:FindFirstChild("RightHand")
		local torso = model:FindFirstChild("UpperTorso")
		if left and right and torso then
			return (left.Position + right.Position) / 2 + torso.CFrame.UpVector * radius * 1.1
		end
	end
	return bomb.Position
end

local function watchBomb(bomb: BasePart)
	local radius = bomb.Size.Y / 2
	-- hide the server's bomb here; draw this one instead
	local cap = bomb:FindFirstChild("Cap")
	bomb.LocalTransparencyModifier = 1
	if cap and cap:IsA("BasePart") then
		cap.LocalTransparencyModifier = 1
	end
	local function visualPart(name: string, size: Vector3, color: Color3, material: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = true
		p.Size = size
		p.Color = color
		p.Material = material
		p.Parent = Workspace
		return p
	end
	local body = visualPart("BombView", Vector3.one * radius * 2, BOMB_DARK, Enum.Material.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	local capView = visualPart("BombCapView", Vector3.new(0.8, 1.8, 1.8), Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	capView.Shape = Enum.PartType.Cylinder
	local spark = Instance.new("Attachment")
	spark.Position = Vector3.new(0, radius + 0.9, 0)
	spark.Parent = body
	local fizz = emitter({
		Texture = "Sparkle", Color = Color3.fromRGB(255, 200, 90), Rate = 30, Speed = { 2, 5 }, Life = { 0.15, 0.35 },
		Size = { { 0, 0.7 }, { 1, 0 } }, Transparency = { { 0, 0 }, { 1, 1 } }, Spread = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, -6, 0), Glow = 1, LightInfluence = 0,
	})
	fizz.Parent = spark
	local light = Instance.new("PointLight")
	light.Color = BOMB_RED
	light.Range = 14
	light.Brightness = 0
	light.Parent = body
	local tick = sound(BumpSounds.BombTick, BumpSounds.TickVolume, body, 120)

	-- the spring
	local position = carryPoint(bomb, radius)
	local velocity = Vector3.zero
	local pulse = 0
	local born = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not bomb.Parent then
			connection:Disconnect()
			body:Destroy()
			capView:Destroy()
			return
		end
		dt = math.min(dt, 1 / 20)
		local target = carryPoint(bomb, radius)
		if (target - position).Magnitude > BOMB_SNAP then
			position, velocity = target, Vector3.zero
		end
		local accel = (target - position) * BOMB_SPRING - velocity * BOMB_DAMP
		velocity += accel * dt
		position += velocity * dt
		-- tilt away from where it's lagging behind, plus a little idle wobble
		local lag = position - target
		local flatLag = Vector3.new(lag.X, 0, lag.Z)
		local t = os.clock() - born
		local tilt = CFrame.identity
		if flatLag.Magnitude > 1e-3 then
			local axis = Vector3.new(0, 1, 0):Cross(flatLag.Unit)
			tilt = CFrame.fromAxisAngle(axis, math.clamp(flatLag.Magnitude * 0.35, 0, 0.6))
		end
		tilt *= CFrame.Angles(math.sin(t * 7) * 0.05, 0, math.cos(t * 5.3) * 0.05)
		-- squash and stretch with how fast it's moving up or down, and a pulse on each tick
		pulse = math.max(0, pulse - dt * 5)
		local stretch = math.clamp(velocity.Y * 0.006, -0.22, 0.22)
		local grow = 1 + pulse * 0.12
		mesh.Scale = Vector3.new((1 - stretch * 0.5) * grow, (1 + stretch) * grow, (1 - stretch * 0.5) * grow)
		local frame = CFrame.new(position) * tilt
		body.CFrame = frame
		capView.CFrame = frame * CFrame.new(0, radius * (1 + stretch) * grow, 0) * CFrame.Angles(0, 0, math.rad(90))
		spark.Position = Vector3.new(0, radius * (1 + stretch) * grow + 0.9, 0)
	end)

	task.spawn(function()
		while bomb.Parent do
			local every = bomb:GetAttribute("TickEvery") or 1
			tick:Play()
			body.Color = BOMB_RED
			light.Brightness = 3
			pulse = 1
			local flash = math.min(0.12, every * 0.5)
			task.wait(flash)
			if not bomb.Parent then
				break
			end
			body.Color = BOMB_DARK
			light.Brightness = 0
			task.wait(math.max(every - flash, 0.03))
		end
	end)
end

-- The fuse ran out: a flash, a fireball of cloud, a ring along the ground, a bang and a shake.
local function onBoom(data)
	local position = data.Position
	local radius = data.Radius or 20
	burst(CFrame.new(position), {
		ring(radius * 1.6, Color3.fromRGB(255, 190, 120)),
		puff(26, { 18, 34 }, 4, Color3.fromRGB(255, 150, 80)),
		puff(18, { 8, 16 }, 5, Color3.fromRGB(90, 80, 80)),
		stars(10, { 16, 26 }, 0.8),
		sparkles(24, 1.2),
	})
	burst(CFrame.new(position - Vector3.new(0, 4, 0)), { ring(radius * 2.2, DUST), puff(20, { 24, 40 }, 3) })
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = Workspace.Terrain
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 170, 90)
	flash.Range = 40
	flash.Brightness = 8
	flash.Parent = holder
	TweenService:Create(flash, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	sound(BumpSounds.BombBoom, BumpSounds.BoomVolume, holder, 400):Play()
	Debris:AddItem(holder, 3)
	local root = player.Character and rootOf(player.Character)
	if root then
		local distance = (root.Position - position).Magnitude
		kick(math.clamp(1.6 - distance / 60, 0.3, 1.6))
	end
end

-- ═══ knock-outs ═════════════════════════════════════════════════════════════════
-- The user (2026-11-13): "a super smash bros style effect for eliminations". Our own take: where
-- someone went out, a flash, a fan of streaks and one big beam shooting up and out in their
-- seat colour, a shockwave ring, stars, a bang and a shake. The last KO of a game is bigger.



local function onKO(data)
	local origin: Vector3 = data.Position
	local color: Color3 = typeof(data.Color) == "Color3" and data.Color or WHITE
	local out: Vector3 = typeof(data.Out) == "Vector3" and data.Out or Vector3.new(1, 0, 0)
	local scale = data.Final and 1.5 or 1
	local up = (out * 0.55 + Vector3.new(0, 1, 0)).Unit
	local light = color:Lerp(WHITE, 0.55)
	-- the flash
	local flash = glowPart(Vector3.one * 2, CFrame.new(origin), WHITE, Enum.PartType.Ball)
	TweenService:Create(flash, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 40 * scale, Color = light }):Play()
	TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.7)
	-- the big beam, and a fan of streaks round it
	streak(origin, up, 140 * scale, 16 * scale, color, 0.8)
	streak(origin, up, 120 * scale, 7 * scale, WHITE, 0.6)
	local rng = Random.new()
	local side = up:Cross(Vector3.new(0, 1, 0))
	side = side.Magnitude > 0.1 and side.Unit or Vector3.new(1, 0, 0)
	local other = up:Cross(side).Unit
	for index = 1, math.floor(20 * scale) do
		local spread = rng:NextNumber(0.15, 0.75)
		local turn = rng:NextNumber(0, math.pi * 2)
		local dir = (up + (side * math.cos(turn) + other * math.sin(turn)) * spread).Unit
		local c = index % 4 == 0 and WHITE or (index % 4 == 1 and light or color)
		streak(origin, dir, rng:NextNumber(50, 100) * scale, rng:NextNumber(2.5, 4.5) * scale, c, rng:NextNumber(0.6, 0.9))
	end
	-- a shockwave ring, flat
	local ringPart = glowPart(Vector3.new(0.4, 4, 4), CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
	ringPart.Transparency = 0.2
	TweenService:Create(ringPart, TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 95 * scale, 95 * scale), Transparency = 1 }):Play()
	Debris:AddItem(ringPart, 0.8)
	burst(CFrame.lookAt(origin, origin + up), {
		stars(math.floor(12 * scale), { 25, 45 }, 1.2), sparkles(math.floor(24 * scale), 1.4), puff(12, { 20, 35 }, 4, light),
	})
	-- the bang
	local holder = Instance.new("Attachment")
	holder.WorldPosition = origin
	holder.Parent = Workspace.Terrain
	local boom = sound(BumpSounds.KOBoom, BumpSounds.KOVolume, holder, 500)
	boom.PlaybackSpeed = 1.3
	boom:Play()
	local ping = sound(BumpSounds.KOPing, BumpSounds.KOVolume * 0.7, holder, 500)
	ping.PlaybackSpeed = 0.75
	ping:Play()
	Debris:AddItem(holder, 3)
	local root = player.Character and rootOf(player.Character)
	if root then
		kick(math.clamp(2 - (root.Position - origin).Magnitude / 90, 0.5, 1.8) * scale)
	end
end

-- ═══ the ball dash: charging up, then the launch ══════════════════════════════════
-- The user (2026-11-13): "the dash on the ball should charge up like the player's running in spot
-- on the ball, VFX on the ground and around the ball to indicate the player's building up power,
-- and then a launch". While a rider charges (move RideCharge, on every body): a glowing ring on the
-- ground under the ball that grows and pulses faster, rings rippling out from it, sparkles
-- gathering into the ball, and dust spinning out behind; all turning gold at full charge. On the
-- dash (move RideDash): a burst at the ball, a dust blast behind it and speed streaks ahead.

local Ball = require("@Shared/Movement/Tuning").Of("Ball")
local CHARGE_WHITE = Color3.fromRGB(150, 220, 255)
local charging = {} -- [Model] = { connection, parts }

local function ballOf(model: Model): BasePart?
	local id = model:GetAttribute("BumpId")
	if not id then
		local owner = Players:GetPlayerFromCharacter(model)
		id = owner and tostring(owner.UserId)
	end
	if not id then
		return nil
	end
	for _, ball in CollectionService:GetTagged("BumpBall") do
		if ball:IsA("BasePart") and ball:GetAttribute("Rider") == id then
			return ball
		end
	end
	return nil
end

function chargeFx.Stop(model: Model)
	local fx = charging[model]
	if not fx then
		return
	end
	charging[model] = nil
	fx.connection:Disconnect()
	for _, thing in fx.things do
		thing:Destroy()
	end
end

function chargeFx.Start(model: Model)
	chargeFx.Stop(model)
	local ball = ballOf(model)
	if not ball then
		return
	end
	local radius = ball.Size.Y / 2
	local ringPart = Instance.new("Part")
	ringPart.Name = "ChargeRing"
	ringPart.Shape = Enum.PartType.Cylinder
	ringPart.Anchored, ringPart.CanCollide, ringPart.CanQuery, ringPart.CanTouch, ringPart.CastShadow = true, false, false, false, false
	ringPart.Material = Enum.Material.Neon
	ringPart.Color = CHARGE_WHITE
	ringPart.Transparency = 0.55
	ringPart.Size = Vector3.new(0.12, radius * 1.4, radius * 1.4)
	ringPart.Parent = Workspace
	-- the aura's emitter sits in an invisible sphere round the ball: a part's shape sets where
	-- the sparkles start (on its surface), and they fly inward
	local centre = Instance.new("Part")
	centre.Name = "ChargeAura"
	centre.Shape = Enum.PartType.Ball
	centre.Size = Vector3.one * radius * 3.2
	centre.Anchored, centre.CanCollide, centre.CanQuery, centre.CanTouch, centre.CastShadow = true, false, false, false, false
	centre.Transparency = 1
	centre.Parent = Workspace
	local aura = emitter({
		Texture = "Sparkle", Color = CHARGE_WHITE, Rate = 20, Speed = { 4, 7 }, Life = { 0.25, 0.4 },
		Size = { { 0, 0.2 }, { 0.5, 0.7 }, { 1, 0 } }, Transparency = { { 0, 0.1 }, { 1, 1 } }, Glow = 1, LightInfluence = 0,
	})
	aura.Shape = Enum.ParticleEmitterShape.Sphere
	aura.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	aura.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	aura.Parent = centre
	local back = Instance.new("Attachment")
	back.Parent = Workspace.Terrain
	local dust = emitter({
		Texture = "Cloud", Color = DUST, Rate = 12, Speed = { 6, 12 }, Life = { 0.3, 0.55 },
		Size = { { 0, 0.6 }, { 1, 2.2 } }, Transparency = { { 0, 0.5 }, { 1, 1 } }, Spread = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 4, 0), Drag = 4, RotSpeed = { -90, 90 }, Direction = Enum.NormalId.Back,
	})
	dust.Parent = back
	local glow = Instance.new("PointLight")
	glow.Color = CHARGE_WHITE
	glow.Range = 12
	glow.Brightness = 0.5
	glow.Parent = centre
	local started = os.clock()
	local nextRipple = 0
	local fullFlash = false
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not ball.Parent or not model.Parent then
			chargeFx.Stop(model)
			return
		end
		local t = os.clock() - started
		local charge = math.clamp(t / Ball.ChargeTime, 0, 1)
		local color = CHARGE_WHITE:Lerp(GOLD, charge)
		local ground = ball.Position - Vector3.new(0, radius - 0.12, 0)
		local pulse = 1 + math.sin(t * (10 + 20 * charge)) * 0.06
		local size = radius * (1.4 + 1.6 * charge) * pulse
		ringPart.Size = Vector3.new(0.12, size, size)
		ringPart.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
		ringPart.Color = color
		ringPart.Transparency = 0.55 - 0.3 * charge
		centre.CFrame = CFrame.new(ball.Position)
		aura.Rate = 20 + 70 * charge
		aura.Color = ColorSequence.new(color)
		aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.5 + 0.6 * charge), NumberSequenceKeypoint.new(1, 0) })
		glow.Color = color
		glow.Brightness = 0.5 + 2.5 * charge
		-- dust thrown out behind, from where the ball meets the floor
		local root = model:FindFirstChild("HumanoidRootPart")
		local look = root and Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
		look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
		back.WorldCFrame = CFrame.lookAt(ground - look * (radius * 0.6), ground - look * (radius * 0.6) + look)
		dust.Rate = 12 + 50 * charge
		if t >= nextRipple then
			nextRipple = t + (0.32 - 0.18 * charge)
			burst(CFrame.new(ground), { ring(radius * (2.2 + 2.5 * charge), color) })
		end
		if charge >= 1 and not fullFlash then
			fullFlash = true
			burst(CFrame.new(ball.Position), { stars(8, { 8, 14 }, 0.6), sparkles(14, 0.8) })
		end
	end)
	charging[model] = { connection = connection, things = { ringPart, centre, back } }
end

function chargeFx.Launch(model: Model)
	local ball = ballOf(model)
	if not ball then
		return
	end
	local radius = ball.Size.Y / 2
	local velocity = ball.AssemblyLinearVelocity
	local ahead = Vector3.new(velocity.X, 0, velocity.Z)
	ahead = ahead.Magnitude > 1 and ahead.Unit or Vector3.new(0, 0, -1)
	local ground = ball.Position - Vector3.new(0, radius - 0.15, 0)
	-- a burst ring on the ground and a dust blast thrown out behind
	burst(CFrame.new(ground), { ring(radius * 4.5, GOLD), puff(14, { 14, 24 }, 2.4) })
	burst(CFrame.lookAt(ground, ground - ahead), {
		{
			Texture = "Cloud", Color = DUST, Count = 16, Speed = { 18, 32 }, Life = { 0.4, 0.7 },
			Direction = Enum.NormalId.Front, Spread = Vector2.new(30, 30), Size = { { 0, 1.2 }, { 1, 3.4 } },
			Transparency = { { 0, 0.35 }, { 1, 1 } }, Drag = 5, RotSpeed = { -60, 60 }, Acceleration = Vector3.new(0, 3, 0),
		},
		sparkles(12, 0.8),
	})
	-- speed streaks shooting ahead from round the ball
	local side = ahead:Cross(Vector3.yAxis)
	for i = 1, 7 do
		local offset = side * ((i - 4) * radius * 0.3) + Vector3.new(0, (i % 3) * radius * 0.35, 0)
		streak(ball.Position + offset - ahead * radius, ahead, 22 + (i % 3) * 8, 0.7, i % 2 == 0 and WHITE or GOLD, 0.35)
	end
	if model == player.Character then
		kick(0.7)
	end
end

local function onBombPass(data)
	burst(CFrame.new(data.Position), { ring(6, GOLD), stars(6, { 8, 12 }, 0.55), sparkles(8, 0.6) })
	local holder = Instance.new("Attachment")
	holder.WorldPosition = data.Position
	holder.Parent = Workspace.Terrain
	sound(BumpSounds.BombPass, BumpSounds.PassVolume, holder):Play()
	Debris:AddItem(holder, 2)
end

-- The pieces other effects are built from (Client/Systems/PowerUpFx uses them).
BumpFx.Burst = burst
BumpFx.Recipes = { Puff = puff, Ring = ring, Stars = stars, Sparkles = sparkles }
BumpFx.GlowPart = glowPart
BumpFx.Streak = streak
BumpFx.Sound = sound
BumpFx.Kick = kick

function BumpFx.start()
	CollectionService:GetInstanceAddedSignal(BOMB_TAG):Connect(function(bomb)
		if bomb:IsA("BasePart") then
			watchBomb(bomb)
		end
	end)
	for _, bomb in CollectionService:GetTagged(BOMB_TAG) do
		if bomb:IsA("BasePart") then
			watchBomb(bomb)
		end
	end
	Remotes.HookFx(function(name, data)
		if name == "Boom" and data and typeof(data.Position) == "Vector3" then
			onBoom(data)
			return
		elseif name == "KO" and data and typeof(data.Position) == "Vector3" then
			onKO(data)
			return
		elseif name == "BombPass" and data and typeof(data.Position) == "Vector3" then
			onBombPass(data)
			return
		end
		if name == "Bump" and data and typeof(data.Position) == "Vector3" then
			onBump(data.Position, data.Kind)
		elseif name == "BallHit" and data and typeof(data.Position) == "Vector3" then
			onBallHit(data)
		elseif name == "Ripple" and data and typeof(data.Position) == "Vector3" then
			onRipple(data)
		end
	end)
end

return BumpFx
