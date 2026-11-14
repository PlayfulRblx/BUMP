--!nonstrict
--[[
	Bomber Bloxians' bomb on every machine: the carried bomb each client draws for itself (sprung to
	the holder's hands, ticking and flashing as the hidden fuse burns), the explosion (Fx "Boom")
	and a pass (Fx "BombPass"). Wired up by BumpFx.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local Kit = require("@Client/Fx/FxKit")
local emitter = Kit.Emitter
local puff = Kit.Puff
local ring = Kit.Ring
local stars = Kit.Stars
local sparkles = Kit.Sparkles
local burst = Kit.Burst
local rootOf = Kit.RootOf
local kick = Kit.Kick
local sound = Kit.Sound
local DUST = Kit.Dust
local GOLD = Kit.Gold

local player = Players.LocalPlayer

local BombFx = {}

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

-- The bomb changing hands: a gold ring and stars where it landed, and a pass sound.
local function onBombPass(data)
	burst(CFrame.new(data.Position), { ring(6, GOLD), stars(6, { 8, 12 }, 0.55), sparkles(8, 0.6) })
	local holder = Instance.new("Attachment")
	holder.WorldPosition = data.Position
	holder.Parent = Workspace.Terrain
	sound(BumpSounds.BombPass, BumpSounds.PassVolume, holder):Play()
	Debris:AddItem(holder, 2)
end

-- Draws every bomb there is and every one that comes.
function BombFx.Watch()
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
end

BombFx.OnBoom = onBoom
BombFx.OnPass = onBombPass

return BombFx
