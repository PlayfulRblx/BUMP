--!nonstrict
--[[
	How the balls sound (2026-11-14, the user: "we should have sound effects when rolling on the
	balls"). Everything here is local to each client and heard in 3D from the ball.

	- Rolling: every ball (tag BumpBall) carries a looping roll that follows its speed along the
	  floor: silent at rest, louder and higher the faster it goes (full at Ball.MaxSpeed, and a
	  little past it in a dash), cut while the ball is in the air. Landing after a hop thumps.
	- A rider's moves (BumpFx hands them over, BallSounds.OnMove): a tyre screech on a skrrt
	  (RideSkrrt), a rising whoosh while the dash charges (RideCharge, sped up as it fills over
	  Ball.ChargeTime), and a whoosh when it launches (RideDash).

	Sounds are in Shared/Audio/BumpSounds.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local Ball = require("@Shared/Movement/Tuning").Of("Ball")

local BallSounds = {}

local BALL_TAG = "BumpBall"
local RIDER_ATTR = "Rider"
local FADE = 10 -- how fast the roll's volume follows the speed (per second)
local AIR_GAP = 1.2 -- studs between the ball's bottom and the floor before it counts as airborne
local LAND_AFTER = 0.3 -- seconds in the air before a landing thumps
local HEAR = 160 -- studs a ball can be heard from

local rolling = {} -- [BasePart] = { Sound, Airborne, AirSince, Volume }
local charging = {} -- [Model] = Sound

local function newSound(id: string, volume: number, parent: Instance): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = HEAR
	s.Parent = parent
	return s
end

local function oneShot(id: string, volume: number, parent: Instance, speed: number?)
	local s = newSound(id, volume, parent)
	s.PlaybackSpeed = speed or 1
	s.Ended:Connect(function()
		s:Destroy()
	end)
	s:Play()
end

-- The ball this body rides: the tagged ball whose Rider is this body's id (a bot's BumpId, or a
-- player's UserId), as BumpFx finds it.
local function ballOf(model: Model): BasePart?
	local id = model:GetAttribute("BumpId")
	if not id then
		local owner = Players:GetPlayerFromCharacter(model)
		id = owner and tostring(owner.UserId)
	end
	if not id then
		return nil
	end
	for ball in rolling do
		if ball:GetAttribute(RIDER_ATTR) == id then
			return ball
		end
	end
	return nil
end

-- Somewhere to play a rider's sound: their ball, or failing that their body.
local function sourceFor(model: Model): Instance?
	return ballOf(model) or model:FindFirstChild("HumanoidRootPart")
end

local function addBall(ball: Instance)
	if not ball:IsA("BasePart") or rolling[ball] then
		return
	end
	local roll = newSound(BumpSounds.BallRoll, 0, ball)
	roll.Looped = true
	roll.PlaybackRegionsEnabled = true
	roll.LoopRegion = NumberRange.new(BumpSounds.BallRollLoopFrom, 30)
	roll.TimePosition = BumpSounds.BallRollLoopFrom + math.random() * 20 -- balls don't roll in step
	roll:Play()
	rolling[ball] = { Sound = roll, Airborne = false, AirSince = 0, Volume = 0 }
	ball.AncestryChanged:Connect(function()
		if not ball:IsDescendantOf(game) then
			rolling[ball] = nil
		end
	end)
end

local function onFloor(ball: BasePart): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ball.Parent }
	local reach = ball.Size.Y / 2 + AIR_GAP
	-- starting inside the ball, the ray doesn't hit the ball itself
	return workspace:Raycast(ball.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

local function update(dt: number)
	local now = os.clock()
	local top = math.max(Ball.MaxSpeed, 1)
	for ball, state in rolling do
		local velocity = ball.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local grounded = onFloor(ball)
		if not grounded and not state.Airborne then
			state.Airborne = true
			state.AirSince = now
		elseif grounded and state.Airborne then
			state.Airborne = false
			if now - state.AirSince > LAND_AFTER then
				oneShot(BumpSounds.BallLand, BumpSounds.BallLandVolume, ball, 1.6)
			end
		end
		local share = math.clamp(speed / top, 0, 1.4)
		local target = grounded and speed > 1.5 and BumpSounds.BallRollVolume * (0.25 + 0.75 * math.min(share, 1)) or 0
		state.Volume += (target - state.Volume) * math.min(1, FADE * dt)
		state.Sound.Volume = state.Volume
		state.Sound.PlaybackSpeed = 0.7 + 0.6 * share
	end
end

local function stopCharge(model: Model)
	local s = charging[model]
	if s then
		charging[model] = nil
		s:Destroy()
	end
end

function BallSounds.OnMove(model: Model, move: string, previous: string)
	if previous == "RideCharge" and move ~= "RideCharge" then
		stopCharge(model)
	end
	local source = sourceFor(model)
	if not source then
		return
	end
	if move == "RideSkrrt" then
		oneShot(BumpSounds.BallSkid, BumpSounds.BallSkidVolume, source, 0.9 + math.random() * 0.25)
	elseif move == "RideCharge" then
		stopCharge(model)
		local s = newSound(BumpSounds.BallCharge, BumpSounds.BallChargeVolume, source)
		s:Play()
		charging[model] = s
		local started = os.clock()
		task.spawn(function()
			-- rising as the charge fills, then held near the top until the dash or a let-go
			while charging[model] == s and s.Parent do
				local fill = math.clamp((os.clock() - started) / math.max(Ball.ChargeTime, 0.05), 0, 1)
				s.PlaybackSpeed = 1.4 + 1.4 * fill
				task.wait()
			end
		end)
	elseif move == "RideDash" then
		oneShot(BumpSounds.BallLaunch, BumpSounds.BallLaunchVolume, source, 1.1)
	end
end

function BallSounds.start()
	CollectionService:GetInstanceAddedSignal(BALL_TAG):Connect(addBall)
	for _, ball in CollectionService:GetTagged(BALL_TAG) do
		addBall(ball)
	end
	RunService.Heartbeat:Connect(update)
end

return BallSounds
