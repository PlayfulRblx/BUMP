--!nonstrict
--[[
	A player's saved progress, and the shop.

	Saved under the profile's `Bump` table (Server/DefaultProfileData): Xp, PowerUps ({ [id] =
	level }), Equipped and Daily ({ Day, Streak }). Mirrored onto the player as attributes the HUD
	reads (PowerUpInfo's
	XpAttr, LevelAttr, OwnedAttr, EquippedAttr).

	The shop is client actions on the shared "Act" stream:
	    Act("Shop", "Buy", id)     unlock (level 1) or upgrade (next level), paid in gold
	    Act("Shop", "Equip", id)   bring this one into games ("" for none)
	and answers each with You("Shop", { Ok, Message, Id }). Prices and level gates come from
	PowerUpInfo here, never from the client. Gold goes through the engine's money handler, which
	refuses a spend the player can't cover.

	    Progress.AwardXp(player, amount)   fires You("XpEarned", { Amount, Level, LeveledUp })
	    Progress.Equipped(player)          id, level (nil if none or not owned)
	    Progress.ClaimDaily(player)        the daily reward (Stations' REWARDS store), gold paid

	In Studio, setting a number attribute "BumpDebugGold" on a player gives them that much gold
	(for testing the shop); it does nothing in a live server.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DataStoreHandlerServer = require("@Engine/Server/EngineSystems/DataStoreHandler/DataStoreHandlerServer")
local MoneyHandlerServer = require("@Engine/Server/EngineSystems/Money/MoneyHandlerServer")
local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")
local Remotes = require("@Shared/Movement/Remotes")
local BumpServer = require("@GameServer/Systems/BumpServer")

local XP = { "Bump", "Xp" }
local OWNED = { "Bump", "PowerUps" }
local EQUIPPED = { "Bump", "Equipped" }
local DAILY = { "Bump", "Daily" }

local Progress = {}

local saves = {} -- [Player] = data class, once loaded
local busy = {} -- [Player] = true while a purchase is going through

local function owned(player: Player): { [string]: number }
	local data = saves[player]
	local list = data and data:Get(OWNED, true)
	return type(list) == "table" and list or {}
end

local function publish(player: Player)
	local data = saves[player]
	if not data then
		return
	end
	local xp = data:Get(XP, true) or 0
	local level = PowerUpInfo.LevelFor(xp)
	player:SetAttribute(PowerUpInfo.XpAttr, xp)
	player:SetAttribute(PowerUpInfo.LevelAttr, level)
	player:SetAttribute(PowerUpInfo.OwnedAttr, HttpService:JSONEncode(owned(player)))
	player:SetAttribute(PowerUpInfo.EquippedAttr, data:Get(EQUIPPED, true) or "")
	local daily = data:Get(DAILY, true)
	player:SetAttribute(PowerUpInfo.DailyDayAttr, type(daily) == "table" and daily.Day or 0)
	player:SetAttribute(PowerUpInfo.DailyStreakAttr, type(daily) == "table" and daily.Streak or 0)
end

local function reply(player: Player, ok: boolean, message: string, id: string?)
	Remotes.You(player, "Shop", { Ok = ok, Message = message, Id = id })
end

local function buy(player: Player, id)
	local item = PowerUpInfo.Get(id)
	local data = saves[player]
	if not item or not data then
		return reply(player, false, "Not ready yet")
	end
	if busy[player] then
		return
	end
	local list = owned(player)
	local level = (list[id] or 0) + 1
	if level > PowerUpInfo.MaxLevel then
		return reply(player, false, item.Name .. " is maxed out", id)
	end
	local playerLevel = PowerUpInfo.LevelFor(data:Get(XP, true) or 0)
	if playerLevel < PowerUpInfo.LevelNeeded(level) then
		return reply(player, false, string.format("Reach level %d first", PowerUpInfo.LevelNeeded(level)), id)
	end
	local price = PowerUpInfo.Price(id, level)
	busy[player] = true
	MoneyHandlerServer.SpendCurrencyPromise(player, price, nil, "PowerUp", id)
		:andThen(function()
			if not saves[player] then
				return
			end
			local updated = table.clone(owned(player))
			updated[id] = level
			data:Set(OWNED, updated)
			-- the first one you buy comes with you straight away
			if (data:Get(EQUIPPED, true) or "") == "" then
				data:Set(EQUIPPED, id)
			end
			publish(player)
			print(string.format("[Shop] %s bought %s level %d for %d", player.Name, id, level, price))
			reply(player, true, level == 1 and (item.Name .. " unlocked!") or string.format("%s is now level %d!", item.Name, level), id)
		end)
		:catch(function()
			reply(player, false, string.format("You need %d gold", price), id)
		end)
		:finally(function()
			busy[player] = nil
		end)
end

local function equip(player: Player, id)
	local data = saves[player]
	if not data or type(id) ~= "string" then
		return
	end
	if id ~= "" and not owned(player)[id] then
		return reply(player, false, "Unlock it first", id)
	end
	data:Set(EQUIPPED, id)
	publish(player)
	local item = PowerUpInfo.Get(id)
	reply(player, true, item and (item.Name .. " equipped") or "Nothing equipped", id)
end

local function onShop(player: Player, action, id)
	if action == "Buy" then
		buy(player, id)
	elseif action == "Equip" then
		equip(player, id)
	end
end

function Progress.AwardXp(player: Player, amount: number)
	local data = saves[player]
	if not data or amount <= 0 then
		return
	end
	local before = PowerUpInfo.LevelFor(data:Get(XP, true) or 0)
	local xp = (data:Get(XP, true) or 0) + amount
	data:Set(XP, xp)
	local level = PowerUpInfo.LevelFor(xp)
	publish(player)
	Remotes.You(player, "XpEarned", { Amount = amount, Level = level, LeveledUp = level > before })
end

-- The daily reward: pays once a UTC day and grows the streak, or does nothing if today's is
-- already claimed. Returns the gold paid (0 if none). Fires You("GoldEarned") on a claim.
function Progress.ClaimDaily(player: Player): number
	local data = saves[player]
	if not data or busy[player] then
		return 0
	end
	local today = PowerUpInfo.DayOf(os.time())
	local last = data:Get(DAILY, true)
	local lastDay = type(last) == "table" and last.Day or 0
	if lastDay >= today then
		return 0
	end
	local streak = lastDay == today - 1 and (last.Streak or 0) + 1 or 1
	local gold = PowerUpInfo.DailyGold(streak)
	-- the day is marked before the gold goes out, so a second press can't claim twice
	data:Set(DAILY, { Day = today, Streak = streak })
	publish(player)
	MoneyHandlerServer.AwardCurrencyPromise(player, gold, nil, "Daily", nil, { quiet = true }):catch(warn)
	Remotes.You(player, "GoldEarned", { Amount = gold })
	print(string.format("[Daily] %s claimed %d gold (day %d of a streak)", player.Name, gold, streak))
	return gold
end

-- The power-up this player brings into a game: id and level, or nil.
function Progress.Equipped(player: Player): (string?, number)
	local data = saves[player]
	local id = data and data:Get(EQUIPPED, true)
	local level = id and owned(player)[id]
	if not PowerUpInfo.Get(id) or not level then
		return nil, 0
	end
	return id, level
end

local function playerAdded(player: Player)
	DataStoreHandlerServer.PromiseDataClass(player)
		:andThen(function(data)
			if data and player.Parent == Players then
				saves[player] = data
				publish(player)
			end
		end)
		:catch(warn)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("BumpDebugGold"):Connect(function()
			local gold = player:GetAttribute("BumpDebugGold")
			if type(gold) == "number" and gold > 0 then
				player:SetAttribute("BumpDebugGold", nil)
				MoneyHandlerServer.AwardCurrencyPromise(player, gold, nil, "Debug", nil, { quiet = true }):catch(warn)
			end
		end)
	end
end

function Progress.start()
	BumpServer.OnAct("Shop", onShop)
	Players.PlayerAdded:Connect(playerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(playerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		saves[player] = nil
		busy[player] = nil
	end)
end

return Progress
