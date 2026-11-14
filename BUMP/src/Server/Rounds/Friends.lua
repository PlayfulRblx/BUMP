--!nonstrict
--[[
	Bots that look like the players' friends (the user, 2026-11-14: "make the NPCs resemble players
	from the playing players' friends lists and add an "[AI]" tag next to their names").

	Each player's friends list is fetched when they join (Players:GetFriendsAsync, a few pages), so
	a session can deal friends into the bot seats at once. Friends.Pick hands out friends of the
	people playing, shuffled, none of them in the server, no one twice; Friends.Look fetches a
	friend's avatar (Players:GetHumanoidDescriptionFromUserId), cached, and Friends.Prefetch starts
	that early so the bodies are ready by the time a game places them. Everything is a web call that
	can fail: a failure just means fewer friends, and the bots keep their own names and looks.
]]

local Players = game:GetService("Players")

local Friends = {}

local PAGES = 4 -- of 50: up to 200 friends a player
local lists = {} -- [userId] = { { UserId, Name } }, or false while it's being fetched
local looks = {} -- [userId] = HumanoidDescription, or false when it couldn't be had

local function fetchList(player: Player)
	if lists[player.UserId] ~= nil then
		return
	end
	lists[player.UserId] = false
	task.spawn(function()
		local ok, pages = pcall(Players.GetFriendsAsync, Players, player.UserId)
		local list = {}
		if ok and pages then
			for _ = 1, PAGES do
				for _, friend in pages:GetCurrentPage() do
					table.insert(list, { UserId = friend.Id, Name = friend.DisplayName or friend.Username })
				end
				if pages.IsFinished or not pcall(pages.AdvanceToNextPageAsync, pages) then
					break
				end
			end
		else
			warn("[Friends] couldn't get " .. player.Name .. "'s friends: " .. tostring(pages))
		end
		if player.Parent == Players then
			lists[player.UserId] = list
			print(string.format("[Friends] %s: %d friends", player.Name, #list))
		end
	end)
end

function Friends.Watch()
	Players.PlayerAdded:Connect(fetchList)
	for _, player in Players:GetPlayers() do
		fetchList(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lists[player.UserId] = nil
	end)
end

-- Up to `count` friends of `players` ({ UserId, Name }), shuffled: none in the server, none twice.
function Friends.Pick(players: { Player }, count: number)
	local here, seen, pool = {}, {}, {}
	for _, player in Players:GetPlayers() do
		here[player.UserId] = true
	end
	for _, player in players do
		for _, friend in lists[player.UserId] or {} do
			if not here[friend.UserId] and not seen[friend.UserId] then
				seen[friend.UserId] = true
				table.insert(pool, friend)
			end
		end
	end
	local picked = {}
	while #picked < count and #pool > 0 do
		table.insert(picked, table.remove(pool, math.random(1, #pool)))
	end
	return picked
end

-- A friend's avatar, or nil if it couldn't be had. Yields the first time for each friend.
function Friends.Look(userId: number): HumanoidDescription?
	local cached = looks[userId]
	if cached ~= nil then
		return cached or nil
	end
	local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
	looks[userId] = ok and description or false
	if not ok then
		warn("[Friends] couldn't get the avatar of " .. tostring(userId) .. ": " .. tostring(description))
	end
	return ok and description or nil
end

-- Starts fetching these friends' avatars now, so they're ready when the bots are built.
function Friends.Prefetch(userIds: { number })
	for _, userId in userIds do
		if looks[userId] == nil then
			task.spawn(Friends.Look, userId)
		end
	end
end

return Friends
