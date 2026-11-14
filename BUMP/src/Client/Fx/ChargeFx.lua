--!nonstrict
--[[
	The ball dash on every body. The user (2026-11-13): "the dash on the ball should charge up like
	the player's running in spot on the ball, VFX on the ground and around the ball to indicate the
	player's building up power, and then a launch". While a rider charges (move RideCharge): a
	glowing ring on the ground under the ball that grows and pulses faster, rings rippling out,
	sparkles gathering into the ball, dust spinning out behind, all turning gold at full charge. On
	the dash (RideDash): a burst, a dust blast behind and speed streaks ahead. BumpFx.OnMove calls
	Start, Stop and Launch.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Kit = require("@Client/Fx/FxKit")
local emitter = Kit.Emitter
local puff = Kit.Puff
local ring = Kit.Ring
local stars = Kit.Stars
local sparkles = Kit.Sparkles
local burst = Kit.Burst
local kick = Kit.Kick
local streak = Kit.Streak
local DUST = Kit.Dust
local GOLD = Kit.Gold
local WHITE = Kit.White

local player = Players.LocalPlayer

local ChargeFx = {}

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

function ChargeFx.Stop(model: Model)
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

function ChargeFx.Start(model: Model)
	ChargeFx.Stop(model)
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
			ChargeFx.Stop(model)
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

function ChargeFx.Launch(model: Model)
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

return ChargeFx
