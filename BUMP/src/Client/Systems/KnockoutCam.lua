--!nonstrict
--[[
	Your knockout camera (the user, 2026-11-14: "show "ELIMINATED BY X"'s and show a camera shot
	of the character on deaths"; their choices: only your own eliminations get the shot, and it
	shows you going down, then who did it). When the server tells you you're out (RoundClient's
	KnockedOut, with By / ById when someone knocked you off or passed you the bomb), the camera
	takes over on one of the engine's camera layers (as RoundIntro does):

	    0 to SELF_SECONDS      just above where you went out, looking down at your body as it
	                           sinks away in slow motion (your own client holds its fall to
	                           SLOW_FALL studs a second: at full speed it was a dot 130 studs off
	                           within half a second), or at the pop if the bomb got you, pushing in
	    then OTHER_SECONDS     a swing round to whoever eliminated you, a close shot from in front
	                           (skipped when nobody did, or their body has gone)
	    then OUT_SECONDS       the layer fades into the gameplay camera, now on the stand

	The server leaves your body falling for RoundInfo.KnockoutHold seconds before moving it to the
	stand; the camera stops following it if it jumps (moved) and holds where it was. The card
	("ELIMINATED BY X") is the HUD's (HudKnockout).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraHandlerClient = require("@Engine/Client/EngineSystems/CameraHandler/CameraHandlerClient")
local CameraState = require("@Engine/Client/EngineSystems/CameraHandler/Camera/CameraState")
local FallCam = require("@Client/Systems/FallCam")
local RoundClient = require("@Client/Systems/RoundClient")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local World = require("@Shared/World")

local KnockoutCam = {}

local SELF_SECONDS = 1.4
local OTHER_SECONDS = 1.6
local NOBODY_SECONDS = 0.6 -- held on your shot a little longer when nobody did it
local OUT_SECONDS = 0.5
local SWING_SECONDS = 0.4 -- the move from your shot to theirs
local SELF_FOV_FROM, SELF_FOV_TO, OTHER_FOV = 64, 50, 46
local LAYER_PRIORITY = 45 -- under the intro's (50)
local FOLLOW_JUMP = 40 -- studs in a frame: the body was moved, not falling; stop following it
local SLOW_FALL = 16 -- studs a second your body may fall at while the camera's on it

local player = Players.LocalPlayer
local running = nil -- { layer, serial }
local serial = 0

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- A contestant's body by their round id: a player's (their UserId) or a bot's (BumpBot, IdAttr).
local function modelFor(id): Model?
	if id == nil then
		return nil
	end
	local userId = tonumber(id)
	local who = userId and Players:GetPlayerByUserId(userId)
	if who and who.Character then
		return who.Character
	end
	for _, model in CollectionService:GetTagged("BumpBot") do
		if model:GetAttribute(RoundInfo.IdAttr) == id then
			return model
		end
	end
	return nil
end

local function stop()
	if not running then
		return
	end
	local current = running
	running = nil
	if current.layer then
		pcall(function()
			current.layer:remove()
		end)
	end
end

local function begin(data)
	stop()
	data = data or {}
	-- a fall nobody caused: the Mario-style fall instead (FallCam); blown up, melted (MELTDOWN's
	-- lava) or knocked off by someone, this camera shows it
	if not data.By and data.Reason ~= "blew up" and data.Reason ~= "no body" and data.Reason ~= "melted" then
		FallCam.Play(false)
		return
	end
	local service = CameraHandlerClient.getService()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not service or not root then
		return
	end
	serial += 1
	local mine = serial
	local start = root.Position
	local follow = start
	local killer = modelFor(data.ById)
	local selfEnd = SELF_SECONDS + (killer and 0 or NOBODY_SECONDS)
	local total = selfEnd + (killer and OTHER_SECONDS or 0)
	local startedAt = os.clock()
	local lastSelf = nil
	local fading = false

	-- where to watch your body from: inside the arena from where you went out (so the shot looks
	-- out and down over the edge), at least a little above the floor
	local outward = flat(start - World.ArenaOrigin)
	outward = outward.Magnitude > 1 and outward.Unit or Vector3.new(1, 0, 0)
	local eyeHeight = start.Y + 11
	local eyeFrom = start - outward * 11

	-- your body sinks slowly while the camera's on it (every part, so the limp limbs keep up)
	local slow
	slow = RunService.Heartbeat:Connect(function()
		if os.clock() - startedAt > selfEnd or not running or running.serial ~= mine or character:GetAttribute(RoundInfo.PopAttr) then
			slow:Disconnect()
			return
		end
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and not part.Anchored then
				local velocity = part.AssemblyLinearVelocity
				if velocity.Magnitude > SLOW_FALL then
					part.AssemblyLinearVelocity = velocity.Unit * SLOW_FALL
				end
				part.AssemblyAngularVelocity *= 0.9
			end
		end
	end)

	local function selfShot(t: number): (CFrame, Vector3, number)
		local body = character.Parent and character:FindFirstChild("HumanoidRootPart")
		if body and not character:GetAttribute(RoundInfo.PopAttr) and (body.Position - follow).Magnitude < FOLLOW_JUMP then
			follow = body.Position
		end
		local s = smooth(t / selfEnd)
		-- leaning out over the edge after it, a little lower and closer
		local eye = Vector3.new(eyeFrom.X, eyeHeight - 3 * s, eyeFrom.Z) + outward * (4 * s)
		local fov = SELF_FOV_FROM + (SELF_FOV_TO - SELF_FOV_FROM) * s
		return CFrame.lookAt(eye, follow), follow, fov
	end

	local function killerShot(): (CFrame?, Vector3?)
		local theirs = killer and killer.Parent and killer:FindFirstChild("HumanoidRootPart")
		if not theirs then
			return nil, nil
		end
		local ahead = flat(theirs.CFrame.LookVector)
		ahead = ahead.Magnitude > 0.5 and ahead.Unit or Vector3.new(0, 0, -1)
		local side = Vector3.new(-ahead.Z, 0, ahead.X)
		local aim = theirs.Position + Vector3.new(0, 1.2, 0)
		local eye = aim + ahead * 9 + side * 2.5 + Vector3.new(0, 1.8, 0)
		return CFrame.lookAt(eye, aim), aim
	end

	local function provider(_dt, base)
		if not running or running.serial ~= mine then
			return base
		end
		local t = os.clock() - startedAt
		if t >= total and not fading then
			fading = true
			running.layer:tweenWeight(0, TweenInfo.new(OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut))
			task.delay(OUT_SECONDS + 0.05, function()
				if running and running.serial == mine then
					stop()
				end
			end)
		end
		if t < selfEnd or not killer then
			local cf, target, fov = selfShot(math.min(t, selfEnd))
			lastSelf = cf
			return CameraState.new(cf, fov, CFrame.new(target))
		end
		local cf, target = killerShot()
		if not cf then
			killer = nil -- gone (a bot out too): stay on yours
			local selfCf, selfTarget, fov = selfShot(selfEnd)
			return CameraState.new(selfCf, fov, CFrame.new(selfTarget))
		end
		local u = (t - selfEnd) / SWING_SECONDS
		if u < 1 and lastSelf then
			cf = lastSelf:Lerp(cf, smooth(u))
		end
		local fov = SELF_FOV_TO + (OTHER_FOV - SELF_FOV_TO) * smooth(u)
		return CameraState.new(cf, fov, CFrame.new(target))
	end

	local ok, layer = pcall(function()
		return service:AddLayer(provider, LAYER_PRIORITY, { KeepBaseCamera = true })
	end)
	if not ok or not layer then
		return
	end
	running = { layer = layer, serial = mine }
	layer:setWeight(1)
	-- a safety net
	task.delay(total + OUT_SECONDS + 1, function()
		if running and running.serial == mine then
			stop()
		end
	end)
end

function KnockoutCam.start()
	task.spawn(function()
		CameraHandlerClient.PromiseReady(20):await()
		RoundClient.On("KnockedOut", begin)
		local round = ReplicatedStorage:WaitForChild(RoundInfo.Folder)
		round:GetAttributeChangedSignal("Phase"):Connect(function()
			local phase = round:GetAttribute("Phase")
			if phase ~= "Play" and phase ~= "Results" then
				stop()
			end
		end)
	end)
	player.CharacterAdded:Connect(stop)
end

return KnockoutCam
