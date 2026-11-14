--!nonstrict
--[[
	Music and the round whistle (the user, 2026-11-13: "music that speeds up as the game gets more
	intense as well as a whistle to mark when the rounds finish").

	Two looping tracks crossfade by the round's phase: the lobby track between games, the game
	track for play (from the top as play starts). A game's intro has its own: a sting over the
	camera's flyover, fading under the countdown, a rising ping on each of 3, 2, 1, and on GO the
	whistle pitched up over a low boom. While a game is on, the game track's tempo (and
	pitch, as Roblox's PlaybackSpeed does) climbs with the round's Intensity, which the game sets
	from how much floor is gone and how many are out. A referee whistle blows when a game ends.
	Sound ids are in Shared/Audio/BumpSounds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local BumpSounds = require("@Shared/Audio/BumpSounds")
local RoundClient = require("@Client/Systems/RoundClient")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")

local Rounds = Tuning.Of("Rounds")
local Workspace = game:GetService("Workspace")

local BumpMusic = {}

local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine)

local function sound(name: string, id: string, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Looped = looped
	s.Volume = 0
	s.Parent = SoundService
	return s
end

local function fadeTo(s: Sound, volume: number)
	if volume > 0 and not s.IsPlaying then
		s:Play()
	end
	local tween = TweenService:Create(s, FADE, { Volume = volume })
	tween.Completed:Once(function()
		if volume == 0 and s.Volume == 0 then
			s:Pause()
		end
	end)
	tween:Play()
end

function BumpMusic.start()
	local gameMusic = sound("BumpGameMusic", BumpSounds.GameMusic, true)
	local lobbyMusic = sound("BumpLobbyMusic", BumpSounds.LobbyMusic, true)
	local whistle = sound("BumpWhistle", BumpSounds.RoundOver, false)
	whistle.Volume = BumpSounds.WhistleVolume
	local sting = sound("BumpIntroSting", BumpSounds.IntroSting, false)
	local beep = sound("BumpCountdownBeep", BumpSounds.CountdownBeep, false)
	beep.Volume = BumpSounds.CountdownVolume
	local goWhistle = sound("BumpGoWhistle", BumpSounds.RoundOver, false)
	goWhistle.Volume = BumpSounds.GoVolume
	goWhistle.PlaybackSpeed = 1.35
	local goBoom = sound("BumpGoBoom", BumpSounds.KOBoom, false)
	goBoom.Volume = 0.5
	goBoom.PlaybackSpeed = 0.7
	local lastBeep = nil

	-- your own elimination: a cartoon clang and a falling slide whistle as you go, a thud as the
	-- card slams, a whoosh as the camera swings to whoever did it, a pop and a comedy tag as their
	-- name lands; the game track goes muffled under it all, then comes back (timed to the card:
	-- Tokens.Timing.KnockoutReveal 1.5, KnockoutSeconds 3.7)
	local REVEAL, DONE = 1.5, 3.7
	local muffle = Instance.new("EqualizerSoundEffect")
	muffle.Name = "KnockoutMuffle"
	muffle.HighGain, muffle.MidGain, muffle.LowGain = 0, 0, 0
	muffle.Parent = gameMusic
	local knockoutSerial = 0
	local function cue(id: string, volume: number, speed: number?, at: number?)
		task.delay(at or 0, function()
			local s = sound("BumpKnockoutCue", id, false)
			s.Volume = volume * BumpSounds.KnockoutVolume
			s.PlaybackSpeed = speed or 1
			s:Play()
			s.Ended:Once(function()
				s:Destroy()
			end)
			task.delay(8, function()
				if s.Parent then
					s:Destroy()
				end
			end)
		end)
	end
	RoundClient.On("KnockedOut", function(info)
		knockoutSerial += 1
		local mine = knockoutSerial
		info = info or {}
		cue(BumpSounds.KnockoutClang, 0.9, 1.15)
		cue(BumpSounds.KnockoutWhistle, 1, 1)
		cue(BumpSounds.KnockoutThud, 1, 1.1, 0.08)
		if info.By then
			cue(BumpSounds.KnockoutWhoosh, 0.8, 1.2, REVEAL - 0.15)
		end
		cue(BumpSounds.KnockoutPop, 0.9, 1, REVEAL)
		cue(BumpSounds.KnockoutTag, 0.8, 1, REVEAL + 0.05)
		local quick = TweenInfo.new(0.15)
		TweenService:Create(muffle, quick, { HighGain = -30, MidGain = -12, LowGain = -4 }):Play()
		task.delay(DONE, function()
			if knockoutSerial == mine then
				TweenService:Create(muffle, TweenInfo.new(0.8), { HighGain = 0, MidGain = 0, LowGain = 0 }):Play()
			end
		end)
	end)

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(RoundInfo.Folder)
		local lastPhase = nil
		local function onPhase()
			local phase = folder:GetAttribute("Phase")
			if phase == lastPhase then
				return
			end
			if lastPhase == "Play" and phase ~= "Play" then
				whistle:Play()
			end
			if phase == "Intro" then
				-- the intro's own sting; the game track waits for GO
				fadeTo(gameMusic, 0)
				fadeTo(lobbyMusic, 0)
				sting.TimePosition = 0
				sting.Volume = BumpSounds.IntroStingVolume
				sting:Play()
				lastBeep = nil
			elseif phase == "Play" then
				if lastPhase == "Intro" then
					goWhistle:Play()
					goBoom:Play()
					sting:Stop()
					gameMusic.TimePosition = 0
					gameMusic.PlaybackSpeed = 1
				end
				fadeTo(gameMusic, BumpSounds.GameVolume)
				fadeTo(lobbyMusic, 0)
			else
				fadeTo(gameMusic, 0)
				fadeTo(lobbyMusic, BumpSounds.LobbyVolume)
			end
			lastPhase = phase
		end
		folder:GetAttributeChangedSignal("Phase"):Connect(onPhase)
		onPhase()

		-- the countdown's pings, and the sting fading under them
		RunService.Heartbeat:Connect(function()
			if folder:GetAttribute("Phase") ~= "Intro" then
				return
			end
			local left = (folder:GetAttribute("EndsAt") or 0) - Workspace:GetServerTimeNow()
			local number = math.ceil(left)
			if number >= 1 and number <= Rounds.IntroCountdown and number ~= lastBeep then
				lastBeep = number
				beep.PlaybackSpeed = 1 + (Rounds.IntroCountdown - number) * 0.15
				beep:Play()
				if number == Rounds.IntroCountdown and sting.IsPlaying then
					TweenService:Create(sting, TweenInfo.new(0.6), { Volume = 0 }):Play()
				end
			end
		end)

		-- the tempo climbs with the game's intensity, eased so it never jumps
		RunService.Heartbeat:Connect(function(dt)
			local target = 1
			if folder:GetAttribute("Phase") == "Play" then
				local intensity = folder:GetAttribute("Intensity") or 0
				target = 1 + (BumpSounds.MaxSpeed - 1) * intensity
			end
			gameMusic.PlaybackSpeed += (target - gameMusic.PlaybackSpeed) * math.min(1, dt * 0.8)
		end)
	end)
end

return BumpMusic
