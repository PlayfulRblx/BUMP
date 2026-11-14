--!nonstrict
--[[
	Your own words on the lobby's daily reward prompt (Server/Systems/Stations). The prompt is
	the server's, shared by everyone; here it's rewritten locally from your save (the
	BumpDaily* attributes Progress mirrors onto you): what today's claim pays and which streak
	day it is, or how long until the next one.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PowerUpInfo = require("@Shared/PowerUps/PowerUpInfo")

local StationClient = {}

local TAG = "BumpStation"
local player = Players.LocalPlayer

local function dailyText(): (string, string)
	local now = Workspace:GetServerTimeNow()
	local today = PowerUpInfo.DayOf(now)
	local lastDay = player:GetAttribute(PowerUpInfo.DailyDayAttr) or 0
	local streak = player:GetAttribute(PowerUpInfo.DailyStreakAttr) or 0
	if lastDay >= today then
		local left = math.max(0, (today + 1) * 86400 - now)
		return string.format("Back in %dh %02dm", left // 3600, (left % 3600) // 60), string.format("Day %d streak", streak)
	end
	local next = lastDay == today - 1 and streak + 1 or 1
	return string.format("Claim %d gold", PowerUpInfo.DailyGold(next)), string.format("Daily Reward, day %d", next)
end

function StationClient.start()
	task.spawn(function()
		while true do
			local action, object = dailyText()
			for _, prompt in CollectionService:GetTagged(TAG) do
				if prompt:GetAttribute("Station") == "Daily" then
					if prompt.ActionText ~= action then
						prompt.ActionText = action
					end
					if prompt.ObjectText ~= object then
						prompt.ObjectText = object
					end
				end
			end
			task.wait(1)
		end
	end)
end

return StationClient
