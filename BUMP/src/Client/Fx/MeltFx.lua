--!nonstrict
--[[
	MELTDOWN's effects on every client, from the server's Fx events (Server/Rounds/MeltdownGame,
	Tower):

	    Fireball     { From, To, Flight, Radius }  a blob arcing out of the lava, a ring on the spot
	    FireballHit  { Position, Radius }          the splash where it lands
	    Debris       { To, Warn, Radius }          a shadow growing on the spot, a rock falling on it
	    DebrisHit    { Position, Radius }          the crash
	    Crumble      { Position, Size }            a platform breaking up
	    Respawn      { Position, Size }            and coming back
	    Shake        { Position, Size, Id }        a ground pound shaking a platform
	    Melt         { Position, Seat }            someone in the lava
	    Surge        { Warn, Rise, Time }          the rumble before the lava lurches up

	and a melted body (attribute "BumpMelted") smokes and burns while it flies.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Kit = require("@Client/Fx/FxKit")

local MeltFx = {}

local LAVA = Color3.fromRGB(255, 110, 40)
local HOT = Color3.fromRGB(255, 200, 90)
local SMOKE = Color3.fromRGB(70, 60, 64)
local ROCK = Color3.fromRGB(96, 84, 80)

local player = Players.LocalPlayer
local glowSurge = nil -- MeltClient.Surge, handed in (no require loop)

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

-- A camera kick by how close it is.
local function kickNear(at: Vector3, strength: number, range: number)
	local root = myRoot()
	if root then
		local distance = (root.Position - at).Magnitude
		if distance < range then
			Kit.Kick(strength * (1 - distance / range))
		end
	end
end

local function soundAt(id: string, at: Vector3, volume: number, speed: number?, seconds: number?)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = Workspace.Terrain
	local s = Kit.Sound(id, volume, holder, 260)
	s.PlaybackSpeed = speed or 1
	s:Play()
	Debris:AddItem(holder, seconds or 4)
	return s
end

local function flame(count: number, speed, size: number)
	return {
		Texture = "Cloud", Color = LAVA, Count = count, Speed = speed, Life = { 0.4, 0.8 },
		Size = { { 0, size * 0.4 }, { 0.3, size }, { 1, size * 1.3 } },
		Transparency = { { 0, 0.1 }, { 0.6, 0.5 }, { 1, 1 } },
		Acceleration = Vector3.new(0, 8, 0), Drag = 4, Spread = Vector2.new(70, 70), RotSpeed = { -90, 90 }, Glow = 0.9, LightInfluence = 0,
	}
end

local function smoke(count: number, size: number)
	return {
		Texture = "Cloud", Color = SMOKE, Count = count, Speed = { 2, 6 }, Life = { 0.8, 1.5 },
		Size = { { 0, size * 0.5 }, { 1, size * 1.6 } }, Transparency = { { 0, 0.35 }, { 1, 1 } },
		Acceleration = Vector3.new(0, 6, 0), Drag = 2, Spread = Vector2.new(50, 50), RotSpeed = { -30, 30 },
	}
end

local function sparks(count: number, speed)
	return {
		Texture = "Sparkle", Color = HOT, Count = count, Speed = speed, Life = { 0.4, 0.9 },
		Size = { { 0, 0.8 }, { 1, 0 } }, Transparency = { { 0, 0 }, { 1, 0.6 } },
		Acceleration = Vector3.new(0, -30, 0), Drag = 1, Spread = Vector2.new(70, 70), Glow = 1, LightInfluence = 0,
	}
end

local function flash(at: Vector3, size: number, color: Color3, seconds: number)
	local ball = Kit.GlowPart(Vector3.one * size * 0.4, CFrame.new(at), color, Enum.PartType.Ball)
	ball.Transparency = 0.2
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(ball, seconds + 0.1)
end

-- A flat disc on the floor at `at` (its top's middle), `radius` across, for warnings.
local function disc(at: Vector3, radius: number, color: Color3, material: Enum.Material?): BasePart
	local p = Kit.GlowPart(Vector3.new(0.15, radius * 2, radius * 2), CFrame.new(at + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
	p.Material = material or Enum.Material.Neon
	return p
end

-- ═══ fireballs ════════════════════════════════════════════════════════════════════

local function onFireball(data)
	local from, to, flight, radius = data.From, data.To, data.Flight or 1, data.Radius or 6
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	-- the warning: a ring on the spot, pulsing faster as it comes
	local ring = disc(to, radius, LAVA)
	ring.Transparency = 0.55
	local inner = disc(to + Vector3.new(0, 0.02, 0), radius * 0.15, HOT)
	-- the blob
	local ball = Kit.GlowPart(Vector3.one * 3.2, CFrame.new(from), LAVA, Enum.PartType.Ball)
	local fire = Instance.new("Fire")
	fire.Size = 7
	fire.Heat = 12
	fire.Color = LAVA
	fire.SecondaryColor = HOT
	fire.Parent = ball
	local trail = Kit.Emitter(smoke(0, 2.4))
	trail.Rate = 40
	trail.Enabled = true
	trail.Parent = ball
	local glow = Instance.new("PointLight")
	glow.Color = LAVA
	glow.Range = 14
	glow.Brightness = 2
	glow.Parent = ball
	local whoosh = Kit.Sound(BumpSounds.Fireball, 0.5, ball, 200)
	whoosh.PlaybackSpeed = 1.3
	whoosh:Play()
	Kit.Burst(CFrame.new(from), { flame(10, { 6, 14 }, 4), sparks(10, { 10, 20 }) })
	local apex = math.max(to.Y - from.Y, 0) + 14
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - started) / flight
		if u >= 1 then
			connection:Disconnect()
			ball:Destroy()
			ring:Destroy()
			inner:Destroy()
			return
		end
		local at = from:Lerp(to, u) + Vector3.new(0, 4 * apex * u * (1 - u), 0)
		ball.CFrame = CFrame.new(at)
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * (8 + 22 * u))
		ring.Transparency = 0.75 - 0.35 * pulse
		inner.Size = Vector3.new(0.15, radius * 2 * u, radius * 2 * u)
	end)
end

local function onFireballHit(data)
	local at, radius = data.Position, data.Radius or 6
	Kit.Burst(CFrame.new(at + Vector3.new(0, 0.5, 0)), {
		flame(18, { 8, 18 }, 5), smoke(8, 4), sparks(24, { 14, 30 }), Kit.Ring(radius * 3, LAVA),
	})
	flash(at, radius * 2.2, HOT, 0.3)
	soundAt("rbxasset://sounds/impact_explosion_03.mp3", at, 0.45, 1.4, 2)
	kickNear(at, 0.9, 40)
end

-- ═══ debris ═══════════════════════════════════════════════════════════════════════

local function onDebris(data)
	local to, warn, radius = data.To, data.Warn or 1.2, data.Radius or 5
	if typeof(to) ~= "Vector3" then
		return
	end
	local shadow = disc(to, radius, Color3.fromRGB(10, 8, 14), Enum.Material.SmoothPlastic)
	shadow.Transparency = 0.8
	local rim = disc(to - Vector3.new(0, 0.02, 0), radius * 1.08, Color3.fromRGB(255, 70, 70))
	rim.Transparency = 0.6
	local rock = Instance.new("Part")
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.CanTouch = false
	rock.Material = Enum.Material.Slate
	rock.Color = ROCK
	rock.Size = Vector3.new(4.5, 3.6, 4) * (0.9 + math.random() * 0.3)
	rock.Parent = Workspace
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = -6 -- the flames trail up behind it as it falls
	fire.Color = LAVA
	fire.SecondaryColor = HOT
	fire.Parent = rock
	local fall = Kit.Sound(BumpSounds.DebrisFall, 0.35, rock, 200)
	fall.PlaybackSpeed = 0.75
	fall:Play()
	local height = 70
	local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - started) / warn
		if u >= 1 then
			connection:Disconnect()
			rock:Destroy()
			shadow:Destroy()
			rim:Destroy()
			return
		end
		rock.CFrame = CFrame.new(to + Vector3.new(0, 1.8 + height * (1 - u * u), 0)) * spin * CFrame.Angles(u * 7, u * 5, 0)
		local grow = 0.3 + 0.7 * u
		shadow.Size = Vector3.new(0.15, radius * 2 * grow, radius * 2 * grow)
		shadow.Transparency = 0.8 - 0.45 * u
		rim.Transparency = 0.6 + 0.3 * math.sin(os.clock() * 18)
	end)
end

local function onDebrisHit(data)
	local at, radius = data.Position, data.Radius or 5
	Kit.Burst(CFrame.new(at + Vector3.new(0, 0.4, 0)), {
		Kit.Puff(16, { 10, 20 }, 5, Color3.fromRGB(150, 130, 120)), Kit.Ring(radius * 3), Kit.Stars(6, { 6, 12 }, 1.2), sparks(10, { 8, 18 }),
	})
	-- chips of rock thrown out
	for _ = 1, 7 do
		local chip = Instance.new("Part")
		chip.Size = Vector3.one * (0.5 + math.random() * 0.8)
		chip.Material = Enum.Material.Slate
		chip.Color = ROCK
		chip.CanCollide = false
		chip.CanQuery = false
		chip.CanTouch = false
		chip.CFrame = CFrame.new(at + Vector3.new(0, 1, 0))
		chip.Parent = Workspace
		chip.AssemblyLinearVelocity = Vector3.new(math.random() - 0.5, 0.8 + math.random(), math.random() - 0.5) * 34
		chip.AssemblyAngularVelocity = Vector3.new(math.random(), math.random(), math.random()) * 12
		TweenService:Create(chip, TweenInfo.new(1.1), { Transparency = 1 }):Play()
		Debris:AddItem(chip, 1.2)
	end
	soundAt(BumpSounds.DebrisCrash, at, 0.8, 0.9, 2)
	kickNear(at, 1.2, 45)
end

-- ═══ platforms ════════════════════════════════════════════════════════════════════

local function onCrumble(data)
	local at, size = data.Position, data.Size or 5
	Kit.Burst(CFrame.new(at), { Kit.Puff(10, { 4, 9 }, size * 0.7, Color3.fromRGB(190, 160, 140)) })
	soundAt(BumpSounds.Crumble, at, 0.55, 1, 2)
end

local function onRespawn(data)
	local at, size = data.Position, data.Size or 5
	Kit.Burst(CFrame.new(at + Vector3.new(0, 0.3, 0)), { Kit.Ring(size * 2.4, HOT), Kit.Sparkles(12, 1.4) })
end

-- The platform's model by id, in the current tower.
local function platformModel(id): Model?
	for _, child in Workspace:GetChildren() do
		if child.Name == "MeltTower" then
			for _, model in child:GetChildren() do
				if model:IsA("Model") and model:GetAttribute("PlatformId") == id then
					return model
				end
			end
		end
	end
	return nil
end

local function onShake(data)
	local at, size = data.Position, data.Size or 6
	Kit.Burst(CFrame.new(at + Vector3.new(0, 0.3, 0)), { Kit.Ring(size * 3.2), Kit.Puff(12, { 8, 16 }, 3) })
	kickNear(at, 0.8, 22)
	-- the platform jolts down and back (on this machine only; a mover is moved again next frame)
	local model = data.Id and platformModel(data.Id)
	if model and not model:GetAttribute(RoundInfo.MoverAttr) and not model:GetAttribute("Falling") then
		local home = model:GetPivot()
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			if t > 0.35 or not model.Parent or model:GetAttribute("Falling") then
				connection:Disconnect()
				if model.Parent and not model:GetAttribute("Falling") then
					model:PivotTo(home)
				end
				return
			end
			local dip = -0.7 * math.exp(-t * 9) * math.cos(t * 30)
			model:PivotTo(home + Vector3.new(0, dip, 0))
		end)
	end
end

-- ═══ the lava ═════════════════════════════════════════════════════════════════════

local function onMelt(data)
	local at = data.Position
	Kit.Burst(CFrame.new(at), {
		flame(26, { 14, 30 }, 6), sparks(36, { 20, 40 }), smoke(14, 6), Kit.Ring(22, LAVA),
		{
			Texture = "Cloud", Color = Color3.fromRGB(255, 250, 245), Count = 12, Speed = { 6, 14 }, Life = { 0.9, 1.6 },
			Size = { { 0, 3 }, { 1, 9 } }, Transparency = { { 0, 0.5 }, { 1, 1 } }, Acceleration = Vector3.new(0, 10, 0),
			Drag = 2, Spread = Vector2.new(35, 35),
		},
	})
	flash(at, 18, HOT, 0.35)
	soundAt(BumpSounds.Pop, at, 0.7, 0.55, 2)
	soundAt(BumpSounds.Fireball, at, 0.6, 2.2, 2)
	kickNear(at, 1, 50)
end

local rumble = nil
local function onSurge(data)
	local warn, rise = data.Warn or 1.5, data.Time or 1.5
	if glowSurge then
		glowSurge(warn + rise)
	end
	if not rumble or not rumble.Parent then
		rumble = Instance.new("Sound")
		rumble.Name = "MeltRumble"
		rumble.SoundId = BumpSounds.LavaRumble
		rumble.Parent = SoundService
	end
	rumble.Volume = 0.9
	rumble.TimePosition = 2
	rumble:Play()
	-- a growing shake through the warning, a jolt as it lurches, then calm
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < warn + rise do
			local t = os.clock() - started
			Kit.Kick(t < warn and 0.25 + 0.5 * t / warn or 0.9)
			task.wait(0.12)
		end
		TweenService:Create(rumble, TweenInfo.new(0.8), { Volume = 0 }):Play()
	end)
end

-- ═══ melted bodies ════════════════════════════════════════════════════════════════

local function watchBody(model: Instance)
	model:GetAttributeChangedSignal("BumpMelted"):Connect(function()
		local root = model:FindFirstChild("HumanoidRootPart")
		if not model:GetAttribute("BumpMelted") or not root then
			return
		end
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Heat = 14
		fire.Color = LAVA
		fire.SecondaryColor = HOT
		fire.Parent = root
		local trail = Kit.Emitter(smoke(0, 2.5))
		trail.Rate = 30
		trail.Enabled = true
		trail.Parent = root
		local scorch = Instance.new("Highlight")
		scorch.FillColor = Color3.fromRGB(40, 20, 16)
		scorch.FillTransparency = 0.35
		scorch.OutlineColor = LAVA
		scorch.Parent = model
		Debris:AddItem(fire, 1.6)
		Debris:AddItem(trail, 1.8)
		Debris:AddItem(scorch, 1.8)
	end)
end

-- `surge(seconds)`: how to make the lava glow hotter (MeltClient.Surge).
function MeltFx.Watch(surge)
	glowSurge = surge
	CollectionService:GetInstanceAddedSignal(Remotes.BodyTag):Connect(watchBody)
	for _, model in CollectionService:GetTagged(Remotes.BodyTag) do
		watchBody(model)
	end
	Remotes.HookFx(function(name, data)
		if type(data) ~= "table" then
			return
		end
		if name == "Fireball" then
			onFireball(data)
		elseif name == "Debris" then
			onDebris(data)
		elseif name == "Surge" then
			onSurge(data)
		elseif typeof(data.Position) ~= "Vector3" then
			return
		elseif name == "FireballHit" then
			onFireballHit(data)
		elseif name == "DebrisHit" then
			onDebrisHit(data)
		elseif name == "Crumble" then
			onCrumble(data)
		elseif name == "Respawn" then
			onRespawn(data)
		elseif name == "Shake" then
			onShake(data)
		elseif name == "Melt" then
			onMelt(data)
		end
	end)
end

return MeltFx
