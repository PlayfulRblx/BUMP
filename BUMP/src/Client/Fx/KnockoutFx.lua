--!nonstrict
--[[
	The KO blast (Fx "KO", fired from RoundServer's Eliminate) where someone went out. The user
	(2026-11-13): "a super smash bros style effect for eliminations". Our own take: a flash, a fan
	of streaks and one big beam shooting up and out in their seat colour, a shockwave ring, stars,
	a bang and a shake. The last KO of a game is bigger. Wired up by BumpFx.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local Kit = require("@Client/Fx/FxKit")
local puff = Kit.Puff
local stars = Kit.Stars
local sparkles = Kit.Sparkles
local burst = Kit.Burst
local rootOf = Kit.RootOf
local kick = Kit.Kick
local sound = Kit.Sound
local glowPart = Kit.GlowPart
local streak = Kit.Streak
local WHITE = Kit.White

local player = Players.LocalPlayer

local KnockoutFx = {}

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

KnockoutFx.OnKO = onKO

return KnockoutFx
