--!nonstrict
--[[
	The round as the HUD reads it: a source (UIFusion/Kit/Source) fed from the server's round
	state (attributes on ReplicatedStorage.BumpRound, see RoundInfo), your gold from the engine's
	money handler, your progress (level, XP, power-ups: attributes Server/Systems/Progress keeps on
	you), the power-up you hold in a game (your character's attributes, Server/Rounds/PowerUps),
	and the events the server sends you (KnockedOut, Eliminated, GoldEarned, XpEarned, ShopReply). Countdown and
	TimeLeft are worked out every frame from the phase's EndsAt. Other client systems can put
	values here too (BallRider sets Charge).

	Loaded before the UI host (ClientMaster's preload list), and reached from UI through
	RuntimeDependencies, never an alias.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require("@Shared/Movement/Remotes")
local RoundInfo = require("@Shared/Rounds/RoundInfo")
local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")

local RoundClient = {}

local player = Players.LocalPlayer
local myId = tostring(player.UserId)

local values = {
	Phase = "Practice", Charge = 0, MyGold = 0, Players = {}, Results = {}, Standings = {},
	MyXp = 0, MyLevel = 1, MyXpInto = 0, MyXpNeed = PowerUpInfo.XpToNext(1), PowerUps = {}, Equipped = "",
	Power = false, ShopOpen = false, IntroHero = false,
}
local subscribers = {}
local handlers = {}
local started = false

function RoundClient.Get(key: string)
	return values[key]
end

function RoundClient.Subscribe(callback)
	subscribers[callback] = true
	return function()
		subscribers[callback] = nil
	end
end

function RoundClient.On(event: string, callback)
	handlers[event] = handlers[event] or {}
	handlers[event][callback] = true
	return function()
		handlers[event][callback] = nil
	end
end

local function set(key: string, value)
	if values[key] == value and type(value) ~= "table" then
		return
	end
	values[key] = value
	for callback in pairs(subscribers) do
		task.spawn(callback, key, value)
	end
end
RoundClient.Set = set

local function emit(event: string, data)
	for callback in pairs(handlers[event] or {}) do
		task.spawn(callback, data)
	end
end

local function decode(text)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, text or "[]")
	if not ok or type(list) ~= "table" then
		return {}
	end
	for _, entry in list do
		if type(entry) == "table" then
			entry.You = entry.Id == myId
		end
	end
	return list
end

local function watch(folder: Instance)
	local function read(key)
		local value = folder:GetAttribute(key)
		if key == "Players" or key == "Results" or key == "Standings" then
			set(key, decode(value))
		elseif key == "Minigame" then
			set("Minigame", RoundInfo.Minigames[value] or false)
		elseif key ~= "EndsAt" and key ~= "Frozen" then
			set(key, value)
		end
	end
	for _, key in { "Phase", "GameIndex", "GameCount", "Minigame", "Alive", "Total", "Note", "Players", "Results", "Standings" } do
		read(key)
		folder:GetAttributeChangedSignal(key):Connect(function()
			read(key)
		end)
	end
	RunService.Heartbeat:Connect(function()
		local endsAt = folder:GetAttribute("EndsAt") or 0
		local left = math.max(0, endsAt - Workspace:GetServerTimeNow())
		local phase = values.Phase
		if phase == "Play" then
			set("TimeLeft", math.ceil(left))
		elseif phase == "Lobby" or phase == "Intro" then
			set("Countdown", math.ceil(left))
		end
	end)
end

-- The shop's list, for UI that can't reach Shared modules: { Id, Name, Glyph, Blurb, Automatic,
-- Prices, Gates, Describe = { per level } } in shop order.
local function catalogue()
	local list = {}
	for _, id in PowerUpInfo.List do
		local item = PowerUpInfo.Items[id]
		local describe = {}
		for level, stats in item.Levels do
			describe[level] = item.Describe(stats)
		end
		table.insert(list, {
			Id = id, Name = item.Name, Glyph = item.Glyph, Blurb = item.Blurb, Automatic = item.Automatic == true,
			Prices = PowerUpInfo.Prices, Gates = PowerUpInfo.LevelGates, Describe = describe,
		})
	end
	return list
end
values.Catalogue = catalogue()

-- Your progress, from the attributes the server keeps on you.
local function watchProgress()
	local function read()
		local xp = player:GetAttribute(PowerUpInfo.XpAttr) or 0
		local level, into, need = PowerUpInfo.LevelFor(xp)
		set("MyXp", xp)
		set("MyLevel", level)
		set("MyXpInto", into)
		set("MyXpNeed", need)
		local ok, owned = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute(PowerUpInfo.OwnedAttr) or "{}")
		set("PowerUps", ok and type(owned) == "table" and owned or {})
		set("Equipped", player:GetAttribute(PowerUpInfo.EquippedAttr) or "")
	end
	for _, key in { PowerUpInfo.XpAttr, PowerUpInfo.OwnedAttr, PowerUpInfo.EquippedAttr } do
		player:GetAttributeChangedSignal(key):Connect(read)
	end
	read()
end

-- The power-up you hold in this game: { Id, Level, Used }, or false.
local function watchPower(character: Model)
	local function read()
		local id, level = PowerUpInfo.Decode(character:GetAttribute(PowerUpInfo.PowerAttr))
		if id and PowerUpInfo.Get(id) then
			set("Power", { Id = id, Level = level, Used = character:GetAttribute(PowerUpInfo.UsedAttr) == true })
		else
			set("Power", false)
		end
	end
	character:GetAttributeChangedSignal(PowerUpInfo.PowerAttr):Connect(read)
	character:GetAttributeChangedSignal(PowerUpInfo.UsedAttr):Connect(read)
	read()
end

-- What the HUD asks for: "ShopBuy" (id), "ShopEquip" (id), "ShopToggle", "ShopClose",
-- "PowerUse" (fire the power-up you hold; the server checks it's yours and unused).
function RoundClient.Do(action: string, id)
	if action == "PowerUse" then
		local power = values.Power
		if power and not power.Used and values.Phase == "Play" then
			Remotes.Act("PowerUp")
		end
	elseif action == "ShopBuy" then
		Remotes.Act("Shop", "Buy", id)
	elseif action == "ShopEquip" then
		Remotes.Act("Shop", "Equip", id)
	elseif action == "ShopToggle" then
		set("ShopOpen", not values.ShopOpen)
	elseif action == "ShopClose" then
		set("ShopOpen", false)
	end
end

local function watchGold()
	local handler = require("@Engine/Shared/Handlers/Money/MoneyHandler")
	task.spawn(function()
		local subscribed, problem = pcall(handler.SubscribeToMoney, player, function(money)
			if money and type(money.Soft) == "number" then
				set("MyGold", money.Soft)
			end
		end)
		if not subscribed then
			warn("[RoundClient] gold isn't readable yet:", problem)
		end
	end)
end

function RoundClient.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		watch(ReplicatedStorage:WaitForChild(RoundInfo.Folder))
	end)
	Remotes.HookYou(function(name, data)
		if name == "KnockedOut" then
			emit("KnockedOut", data)
		elseif name == "Eliminated" then
			-- someone else went out: { Name, Seat, By?, BySeat?, Reason } (the HUD's feed)
			emit("Eliminated", data)
		elseif name == "GoldEarned" then
			emit("GoldEarned", data)
		elseif name == "XpEarned" then
			emit("XpEarned", data)
		elseif name == "Shop" then
			emit("ShopReply", data)
		elseif name == "OpenShop" then
			-- a lobby store's prompt (Server/Systems/Stations)
			set("ShopOpen", true)
		end
	end)
	watchProgress()
	player.CharacterAdded:Connect(watchPower)
	if player.Character then
		watchPower(player.Character)
	end
	task.spawn(function()
		-- the profile has to have loaded before the money handler can read it
		while player:GetAttribute("PlayerDataLoaded") ~= true do
			task.wait(0.2)
		end
		watchGold()
	end)
end

return RoundClient
