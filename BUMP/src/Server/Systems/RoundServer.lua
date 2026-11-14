--!nonstrict
--[[
	Sessions of minigames. The test yard is the lobby: once a player is in, a count runs, then a
	session starts with every player present (up to four seats) and bots in the empty seats. A
	session is a playlist of games; each has an intro card (everyone placed in its arena, frozen),
	the game itself, and results. Then the final standings, and back to the lobby.

	Placing: the last one standing is 1st; each knocked out takes the place of how many were left
	(4 left, knocked out: 4th). If time runs out, everyone still in shares 1st. Gold by place
	(MoveConfig Rounds.Gold1..4) goes to players' saved Soft currency through the engine's money
	handler, and onto the session's tally for the standings.

	The state the HUD reads is attributes on ReplicatedStorage.BumpRound (RoundInfo). Each game
	is a module with Info, Setup(ctx), Run(ctx) and Cleanup(ctx) (Server/Rounds/BumpGame).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MoneyHandlerServer = require("@Engine/Server/EngineSystems/Money/MoneyHandlerServer")
local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local Tuning = require("@Shared/Movement/Tuning")
local Ragdoll = require("@Shared/Ragdoll")
local Bots = require("@GameServer/Rounds/Bots")
local Friends = require("@GameServer/Rounds/Friends")
local BotMind = require("@GameServer/Rounds/BotMind")
local World = require("@Shared/World")
local Spotlight = require("@GameServer/Rounds/Spotlight")
local HexArena = require("@GameServer/Rounds/HexArena")
local PowerUps = require("@GameServer/Rounds/PowerUps")
local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")
local Progress = require("@GameServer/Systems/Progress")

local Rounds = Tuning.Of("Rounds")

local GAMES = {
	Bump = require("@GameServer/Rounds/BumpGame"),
	Bomber = require("@GameServer/Rounds/BomberGame"),
}

local RoundServer = {}

local folder: Configuration = nil
local session = nil -- { Seats = { participant }, Gold = { [id] = n }, Wins = { [id] = n } }

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function set(key: string, value)
	folder:SetAttribute(key, value)
end

local function setJson(key: string, value)
	folder:SetAttribute(key, HttpService:JSONEncode(value))
end

-- ═══ participants ═════════════════════════════════════════════════════════════════

local function characterOf(participant): Model?
	if participant.Player then
		return participant.Player.Character
	end
	return participant.Model
end

local function humans(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player)
		end
	end
	return list
end

local function publishPlayers()
	if not session then
		local list = {}
		for index, player in humans() do
			table.insert(list, { Id = tostring(player.UserId), Name = player.DisplayName, UserId = player.UserId, Seat = index, Gold = 0 })
		end
		setJson("Players", list)
		return
	end
	local list = {}
	for _, participant in session.Seats do
		table.insert(list, {
			Id = participant.Id,
			Name = participant.Name,
			UserId = participant.Player and participant.Player.UserId or nil,
			FaceId = participant.FaceId, -- a bot dressed as a friend: their headshot on its portrait
			Seat = participant.Seat,
			Gold = session.Gold[participant.Id] or 0,
			Out = participant.Out == true,
			Bot = participant.Bot == true,
		})
	end
	setJson("Players", list)
end

local function aliveList()
	local list = {}
	for _, participant in session.Seats do
		if not participant.Out then
			table.insert(list, participant)
		end
	end
	return list
end

local function goldFor(place: number): number
	return Rounds["Gold" .. math.clamp(place, 1, Rounds.Seats)] or 0
end

-- ═══ phases ═══════════════════════════════════════════════════════════════════════

local function phase(name: string, seconds: number?)
	-- the end time first: a client reacting to the new phase reads the right one (the intro's
	-- camera and countdown are timed off it)
	set("EndsAt", seconds and now() + seconds or 0)
	set("Phase", name)
end

local function waitUntil(endsAt: number)
	while now() < endsAt do
		task.wait(0.1)
	end
end

local function lobby()
	phase("Lobby")
	set("Frozen", false)
	session = nil
	publishPlayers()
	-- wait for someone to play with
	while #humans() == 0 do
		set("Phase", "Practice")
		task.wait(1)
	end
	local seconds = RunService:IsStudio() and Rounds.StudioLobby or Rounds.Lobby
	phase("Lobby", seconds)
	local endsAt = now() + seconds
	while now() < endsAt do
		publishPlayers()
		if #humans() == 0 then
			return false
		end
		task.wait(0.5)
	end
	return true
end

local function startSession()
	session = { Seats = {}, Gold = {}, Wins = {} }
	local seat = 0
	for _, player in humans() do
		if seat >= Rounds.Seats then
			break
		end
		seat += 1
		table.insert(session.Seats, { Id = tostring(player.UserId), Name = player.DisplayName, Player = player, Seat = seat })
	end
	-- the empty seats go to the players' friends where there are enough (their name and avatar:
	-- Server/Rounds/Friends), the rest to the bots' own names; every bot's name carries the tag
	-- (the user, 2026-11-14: "add an "[AI]" tag next to their names")
	local players = {}
	for _, participant in session.Seats do
		table.insert(players, participant.Player)
	end
	local friends = Friends.Pick(players, Rounds.Seats - seat)
	local faces = {}
	local names = table.clone(Bots.Names)
	local botNumber = 0
	while seat < Rounds.Seats do
		seat += 1
		botNumber += 1
		local friend = friends[botNumber]
		local name = friend and friend.Name or table.remove(names, math.random(1, #names))
		table.insert(session.Seats, {
			Id = "bot" .. botNumber,
			Name = name .. " " .. RoundInfo.AITag,
			Bot = true,
			Seat = seat,
			FaceId = friend and friend.UserId or nil, -- whose avatar it wears
		})
		if friend then
			table.insert(faces, friend.UserId)
		end
	end
	Friends.Prefetch(faces)
	for _, participant in session.Seats do
		session.Gold[participant.Id] = 0
		session.Wins[participant.Id] = 0
	end
	-- every bot a personality and a skill for the session (Server/Rounds/BotMind)
	BotMind.Assign(session.Seats)
end

local function endSession()
	for _, participant in session.Seats do
		if participant.Model then
			Bots.Remove(participant.Model)
			participant.Model = nil
		end
	end
	-- everyone back to the lobby plaza
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			character:SetAttribute(Ragdoll.Attribute, false)
			character:PivotTo(World.LobbySpot())
		end
	end
end

local function playGame(index: number, gameId: string)
	local minigame = GAMES[gameId]
	local info = RoundInfo.Minigames[gameId]
	for _, participant in session.Seats do
		participant.Out = false
		participant.Place = nil
		-- a player who left mid-session sits the rest out
		if participant.Player and participant.Player.Parent ~= Players then
			participant.Out = true
		end
	end
	set("GameIndex", index)
	set("Minigame", info.Id)
	local alive = aliveList()
	set("Total", #alive)
	set("Alive", #alive)
	publishPlayers()

	local knockedOut = {}
	local ctx = {}
	ctx.Seats = session.Seats
	ctx.Character = characterOf
	ctx.Alive = aliveList
	function ctx.SpawnBot(participant, cframe)
		-- reuse the bot's body only if it's whole: one that fell into the void last game has lost
		-- its root to Roblox's kill height and would be knocked out at once ("no body")
		local model = participant.Model
		if model and (not model.Parent or not model:FindFirstChild("HumanoidRootPart")) then
			Bots.Remove(model)
			participant.Model = nil
		end
		if participant.Model then
			participant.Model:PivotTo(cframe)
		else
			local look = participant.FaceId and Friends.Look(participant.FaceId) or nil
			participant.Model = Bots.Spawn(participant.Id, participant.Name, participant.Seat, cframe, look)
		end
		return participant.Model
	end
	-- Out of the game, for `reason`, by `by` (the participant who knocked them off or passed them
	-- the bomb, or nil when nobody did: "ELIMINATED BY X" on their screen, "X eliminated Y" on
	-- everyone else's).
	function ctx.Eliminate(participant, reason: string?, by, how: string?)
		if participant.Out then
			return
		end
		if by == participant or not by then
			by, how = nil, nil
		end
		local character = characterOf(participant)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		print(string.format("[Round] %s out (%s%s) at %s", participant.Name, reason or "?", by and (" by " .. by.Name .. (how and (" with " .. how) or "")) or "", root and tostring(root.Position) or "no body"))
		local left = #aliveList()
		-- a Smash-style KO blast where they went out, in their seat colour (BumpFx.onKO)
		if root then
			local origin = World.ArenaOrigin
			local flat = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
			local out = flat.Magnitude > 1 and flat.Unit or Vector3.new(1, 0, 0)
			local at = origin + out * math.min(flat.Magnitude, World.PitRadius - 8) - Vector3.new(0, 1, 0)
			if reason == "blew up" then
				at = root.Position
			end
			Remotes.Fx("KO", { Position = at, Out = out, Color = Bots.SeatColor(participant.Seat), Final = left <= 2 })
		end
		participant.Out = true
		participant.Place = left
		table.insert(knockedOut, participant)
		set("Alive", left - 1)
		publishPlayers()
		local news = {
			Id = participant.Id, Name = participant.Name, Seat = participant.Seat, Reason = reason,
			By = by and by.Name or nil, BySeat = by and by.Seat or nil, ById = by and by.Id or nil,
			ByUserId = by and (by.Player and by.Player.UserId or by.FaceId) or nil, How = how,
		}
		if participant.Player then
			-- their body is left falling for their knockout camera, then the game moves it
			if character then
				character:SetAttribute(RoundInfo.KnockoutHoldAttr, true)
				task.delay(RoundInfo.KnockoutHold + 0.3, function()
					if character.Parent then
						character:SetAttribute(RoundInfo.KnockoutHoldAttr, nil)
					end
				end)
			end
			Remotes.You(participant.Player, "KnockedOut", {
				Place = left, Total = #session.Seats, Gold = goldFor(left),
				By = news.By, BySeat = news.BySeat, ById = news.ById, ByUserId = news.ByUserId, How = how, Reason = reason,
			})
		end
		for _, other in Players:GetPlayers() do
			if other ~= participant.Player then
				Remotes.You(other, "Eliminated", news)
			end
		end
		Spotlight.Remove(character)
		if minigame.OnEliminated then
			minigame.OnEliminated(ctx, participant)
		end
	end
	function ctx.SetClock(seconds: number)
		set("EndsAt", now() + seconds)
	end
	-- How heated the game is, 0 to 1: the music speeds up with it.
	function ctx.SetIntensity(value: number)
		set("Intensity", math.clamp(value, 0, 1))
	end
	-- A line the status bar shows in place of the clock ("Zippy has the bomb!"); "" for none.
	function ctx.SetNote(text: string)
		set("Note", text)
	end
	set("Intensity", 0)
	set("Note", "")

	-- the changeover (the user: the map "needs to visibly unload, and then reload the new map before
	-- the round even starts ... before the round even teleports the players into it"): the old arena
	-- has already flown off (end of the last game); the new one plays itself in while everyone is
	-- still on the plaza, and only then are they put on it
	phase("Changeover")
	local showSeconds = minigame.Setup(ctx) or 0
	task.wait(showSeconds)

	-- intro: everyone in place and frozen while the card shows
	phase("Intro", Rounds.Intro)
	set("Frozen", true)
	if minigame.Place then
		minigame.Place(ctx)
	end
	-- everyone's power-up for this game (players their equipped one, bots a random one)
	PowerUps.Arm(ctx)
	-- everyone in the game under a spotlight in their seat colour
	for _, participant in aliveList() do
		Spotlight.Add(characterOf(participant), Bots.SeatColor(participant.Seat))
	end
	waitUntil(now() + Rounds.Intro)

	phase("Play")
	set("Frozen", false)
	local ok, err = pcall(minigame.Run, ctx)
	if not ok then
		warn("[RoundServer] " .. gameId .. " failed:", err)
	end
	set("Frozen", false)

	-- placings: survivors share 1st
	for _, participant in aliveList() do
		participant.Place = 1
	end
	local results = {}
	for _, participant in session.Seats do
		if participant.Place then
			local gold = goldFor(participant.Place)
			local xp = participant.Player and PowerUpInfo.XpFor(participant.Place) or 0
			session.Gold[participant.Id] += gold
			if participant.Place == 1 then
				session.Wins[participant.Id] += 1
			end
			table.insert(results, {
				Name = participant.Name,
				UserId = participant.Player and participant.Player.UserId or nil,
				FaceId = participant.FaceId,
				Seat = participant.Seat,
				Place = participant.Place,
				Gold = gold,
				Xp = xp,
				Id = participant.Id,
			})
			if participant.Player and participant.Player.Parent == Players and gold > 0 then
				MoneyHandlerServer.AwardCurrencyPromise(participant.Player, gold, nil, "Minigame", nil, { quiet = true })
					:catch(function(problem)
						warn("[RoundServer] gold award failed:", problem)
					end)
				Remotes.You(participant.Player, "GoldEarned", { Amount = gold })
			end
			if participant.Player and participant.Player.Parent == Players then
				Progress.AwardXp(participant.Player, xp)
			end
		end
	end
	table.sort(results, function(a, b)
		return a.Place < b.Place
	end)
	setJson("Results", results)
	publishPlayers()
	phase("Results", Rounds.Results)
	task.wait(Rounds.Results)
	for _, participant in session.Seats do
		Spotlight.Remove(characterOf(participant))
	end
	-- whoever is still out on the arena goes back to the plaza, then the arena flies off (on every
	-- client) and the round waits until it's gone before anything else comes in
	for _, participant in session.Seats do
		local character = characterOf(participant)
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < World.PlazaY - 1 and Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude < World.PitRadius then
			character:SetAttribute(Ragdoll.Attribute, false)
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(World.LobbySpot())
		end
	end
	phase("Changeover")
	pcall(minigame.Cleanup, ctx)
	PowerUps.Disarm(ctx)
	task.wait(HexArena.LeaveSeconds + 0.4)
end

local function standings()
	local list = {}
	for _, participant in session.Seats do
		table.insert(list, {
			Name = participant.Name,
			UserId = participant.Player and participant.Player.UserId or nil,
			FaceId = participant.FaceId,
			Seat = participant.Seat,
			Gold = session.Gold[participant.Id] or 0,
			Wins = session.Wins[participant.Id] or 0,
			Id = participant.Id,
		})
	end
	table.sort(list, function(a, b)
		if a.Gold ~= b.Gold then
			return a.Gold > b.Gold
		end
		return a.Wins > b.Wins
	end)
	for rank, entry in list do
		entry.Rank = rank
	end
	setJson("Standings", list)
	-- XP for seeing a whole session through
	for _, participant in session.Seats do
		if participant.Player and participant.Player.Parent == Players then
			Progress.AwardXp(participant.Player, PowerUpInfo.XpPerSession)
		end
	end
	phase("Standings", Rounds.Standings)
	task.wait(Rounds.Standings)
end

local function loop()
	while true do
		if lobby() then
			startSession()
			set("GameCount", Rounds.Games)
			for index = 1, Rounds.Games do
				local gameId = RoundInfo.Playlist[((index - 1) % #RoundInfo.Playlist) + 1]
				playGame(index, gameId)
				if #humans() == 0 then
					break
				end
			end
			if #humans() > 0 then
				standings()
			end
			endSession()
		end
	end
end

function RoundServer.init()
	folder = Instance.new("Configuration")
	folder.Name = RoundInfo.Folder
	folder:SetAttribute("Phase", "Practice")
	folder:SetAttribute("EndsAt", 0)
	folder:SetAttribute("GameIndex", 1)
	folder:SetAttribute("GameCount", Rounds.Games)
	folder:SetAttribute("Minigame", "")
	folder:SetAttribute("Alive", 0)
	folder:SetAttribute("Total", 0)
	folder:SetAttribute("Frozen", false)
	folder:SetAttribute("Intensity", 0)
	folder:SetAttribute("Note", "")
	folder:SetAttribute("Players", "[]")
	folder:SetAttribute("Results", "[]")
	folder:SetAttribute("Standings", "[]")
	folder.Parent = ReplicatedStorage
end

function RoundServer.start()
	Ragdoll.Watch(Remotes.BodyTag)
	Friends.Watch()
	PowerUps.Init()
	for _, minigame in GAMES do
		if minigame.Init then
			minigame.Init()
		end
	end
	task.spawn(loop)
end

return RoundServer
