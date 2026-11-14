--!nonstrict
--[[
	Hits, felt on every machine: a bump or shove landing (BumpServer's Fx "Bump"), a ball hitting a
	ball (BumpGame's ballImpact, Fx "BallHit"), and a ground pound's ripple through the hex tiles
	(Fx "Ripple"). Wired up by BumpFx.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local Kit = require("@Client/Fx/FxKit")
local puff = Kit.Puff
local ring = Kit.Ring
local stars = Kit.Stars
local sparkles = Kit.Sparkles
local burst = Kit.Burst
local rootOf = Kit.RootOf
local kick = Kit.Kick
local sound = Kit.Sound
local glowPart = Kit.GlowPart
local streak = Kit.Streak
local comicPop = Kit.ComicPop
local GOLD = Kit.Gold
local WHITE = Kit.White

local player = Players.LocalPlayer

local HitFx = {}

-- A bump landing on someone: a ring, a pop of cloud and stars where they met.
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

HitFx.OnBump = onBump
HitFx.OnBallHit = onBallHit
HitFx.OnRipple = onRipple

return HitFx
