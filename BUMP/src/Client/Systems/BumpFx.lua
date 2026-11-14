--!nonstrict
--[[
	Effects on every body and every hit (Animator hands every change of move here, for your body
	and everyone else's, so a landing kicks dust whoever made it).

	This module: the effects of moves (OnMove: launches, landings, slides, wall dust, dazed stars;
	lasting ones run while their move lasts and stop when it changes), and the wiring of the
	server's Fx events to the effect modules in Client/Fx: HitFx (bumps, ball hits, ripples), BombFx
	(the carried bomb, the explosion, passes), KnockoutFx (the KO blast) and ChargeFx (the ball
	dash). FxKit is what they're all built from; its pieces are re-exported here for PowerUpFx and
	RoundIntro.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local BallSounds = require("@Client/Systems/BallSounds")
local ChargeFx = require("@Client/Fx/ChargeFx")
local BombFx = require("@Client/Fx/BombFx")
local HitFx = require("@Client/Fx/HitFx")
local KnockoutFx = require("@Client/Fx/KnockoutFx")
local Remotes = require("@Shared/Movement/Remotes")
local Kit = require("@Client/Fx/FxKit")
local emitter = Kit.Emitter
local puff = Kit.Puff
local ring = Kit.Ring
local stars = Kit.Stars
local sparkles = Kit.Sparkles
local burst = Kit.Burst
local rootOf = Kit.RootOf
local feet = Kit.Feet
local wallPoint = Kit.WallPoint
local kick = Kit.Kick
local sound = Kit.Sound
local DUST = Kit.Dust
local GOLD = Kit.Gold

local BumpFx = {}

local player = Players.LocalPlayer
local lasting = {} -- [Model] = { emitters to stop }

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

-- ═══ moves ════════════════════════════════════════════════════════════════════════

local LAUNCHES = { Jump = 0.8, AirJump = 1.1, Backflip = 1.2, LongJump = 1.1, PoundJump = 1.4, Rollout = 0.7 }
local AIRBORNE = {
	Jump = true, AirJump = true, Backflip = true, LongJump = true, PoundJump = true, Rollout = true,
	Fall = true, WallJump = true, Dive = true, Knocked = true,
}
local BIG_LANDINGS = { Backflip = true, LongJump = true, PoundJump = true, WallJump = true }

function BumpFx.OnMove(model: Model, move: string, previous: string)
	BallSounds.OnMove(model, move, previous)
	if move == "RideCharge" then
		ChargeFx.Start(model)
	elseif previous == "RideCharge" then
		ChargeFx.Stop(model)
	end
	if move == "RideDash" then
		ChargeFx.Launch(model)
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

-- The pieces other effects are built from (Client/Systems/PowerUpFx, RoundIntro use them).
BumpFx.Burst = burst
BumpFx.Recipes = { Puff = puff, Ring = ring, Stars = stars, Sparkles = sparkles }
BumpFx.GlowPart = Kit.GlowPart
BumpFx.Streak = Kit.Streak
BumpFx.Sound = Kit.Sound
BumpFx.Kick = kick

function BumpFx.start()
	BombFx.Watch()
	Remotes.HookFx(function(name, data)
		if not data or typeof(data.Position) ~= "Vector3" then
			return
		end
		if name == "Boom" then
			BombFx.OnBoom(data)
		elseif name == "KO" then
			KnockoutFx.OnKO(data)
		elseif name == "BombPass" then
			BombFx.OnPass(data)
		elseif name == "Bump" then
			HitFx.OnBump(data.Position, data.Kind)
		elseif name == "BallHit" then
			HitFx.OnBallHit(data)
		elseif name == "Ripple" then
			HitFx.OnRipple(data)
		end
	end)
end

return BumpFx
