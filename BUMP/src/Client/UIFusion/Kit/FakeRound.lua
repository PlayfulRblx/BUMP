--!nonstrict
--[[
	A round that isn't happening: a source (see Kit/Source) the style board plays the real HUD
	against, so every screen can be judged with believable data before the systems behind it
	exist. Each scenario has a still (Play off) and a short script that loops (Play on).

	    local round = FakeRound.new()
	    round.Play("Playing", true)
	    round.Stop()

	Names are made up. The real round feeds the HUD through the same three functions.
]]

local FakeRound = {}

FakeRound.Scenarios = {
	"Lobby",
	"Intro",
	"Your moment",
	"Playing",
	"Knocked out",
	"Results",
	"Standings",
	"Shop",
	"Level up",
}

-- The shop's list as RoundClient builds it from Shared/PowerUps/PowerUpInfo (copied: the board
-- can't reach Shared modules).
local PRICES, GATES = { 20, 50, 100 }, { 1, 3, 6 }
local CATALOGUE = {
	{ Id = "Shield", Name = "Shield", Glyph = "🛡", Prices = PRICES, Gates = GATES,
		Blurb = "A bubble that shrugs off hits, knock-offs and blasts, and the bomb.",
		Describe = { "3 s bubble", "4 s bubble", "5 s bubble" } },
	{ Id = "Turbo", Name = "Turbo", Glyph = "⚡", Prices = PRICES, Gates = GATES,
		Blurb = "On a ball: a full-power dash, no charging. On foot: a burst of speed.",
		Describe = { "dash x1.0, run 2.0 s", "dash x1.1, run 2.5 s", "dash x1.2, run 3.0 s" } },
	{ Id = "Shockwave", Name = "Shockwave", Glyph = "💥", Prices = PRICES, Gates = GATES,
		Blurb = "A ripple from where you stand: riders it reaches wobble, people on foot are thrown.",
		Describe = { "20 stud ripple", "25 stud ripple", "30 stud ripple" } },
	{ Id = "SecondChance", Name = "Second Chance", Glyph = "❤", Prices = PRICES, Gates = GATES, Automatic = true,
		Blurb = "Fall off once and you're bounced back onto the floor. Works by itself.",
		Describe = { "back on the floor", "back with a 2 s shield", "back with a 4 s shield" } },
}

local BUMP = {
	Id = "Bump",
	Title = "BUMP",
	Blurb = "Jump on a ball and roll everyone else off the hex platform. One ball short, and the floor keeps shrinking.",
	Controls = {
		{ Key = "WASD", Label = "Roll" },
		{ Key = "Hold Click", Label = "Charge dash" },
		{ Key = "Pull back", Label = "Skrrt" },
		{ Key = "Space", Label = "Hop off" },
	},
}

local function seats(goldOffsets)
	local gold = goldOffsets or {}
	return {
		{ Id = "you", Name = "You", Seat = 1, Gold = gold[1] or 0, You = true },
		{ Id = "b1", Name = "Pipsqueak", Seat = 2, Gold = gold[2] or 0, Bot = true },
		{ Id = "p2", Name = "Builderman", UserId = 156, Seat = 3, Gold = gold[3] or 0 },
		{ Id = "b2", Name = "Wobbles", Seat = 4, Gold = gold[4] or 0, Bot = true },
		{ Id = "b3", Name = "Bonkers", Seat = 5, Gold = gold[5] or 0, Bot = true },
		{ Id = "b4", Name = "Zippy", Seat = 6, Gold = gold[6] or 0, Bot = true },
		{ Id = "b5", Name = "Mochi", Seat = 7, Gold = gold[7] or 0, Bot = true },
		{ Id = "b6", Name = "Pogo", Seat = 8, Gold = gold[8] or 0, Bot = true },
	}
end

local function copy(list)
	local out = {}
	for index, entry in ipairs(list) do
		out[index] = table.clone(entry)
	end
	return out
end

function FakeRound.new()
	local values = {}
	local subscribers = {}
	local handlers = {}
	local serial = 0

	local round = {}

	function round.Get(key: string)
		return values[key]
	end

	function round.Subscribe(callback)
		subscribers[callback] = true
		return function()
			subscribers[callback] = nil
		end
	end

	function round.On(event: string, callback)
		handlers[event] = handlers[event] or {}
		handlers[event][callback] = true
		return function()
			handlers[event][callback] = nil
		end
	end

	local function set(key: string, value)
		values[key] = value
		for callback in pairs(subscribers) do
			task.spawn(callback, key, value)
		end
	end
	round.Set = set

	local function emit(event: string, data)
		for callback in pairs(handlers[event] or {}) do
			task.spawn(callback, data)
		end
	end

	local function base()
		set("GameIndex", 2)
		set("GameCount", 5)
		set("Minigame", BUMP)
		set("MyGold", 148)
		set("Charge", 0)
		set("Players", seats({ 10, 3, 6, 1 }))
		set("Total", 4)
		set("Alive", 4)
		set("TimeLeft", 90)
		set("Catalogue", CATALOGUE)
		set("MyXp", 160)
		set("MyLevel", 3)
		set("MyXpInto", 35)
		set("MyXpNeed", 125)
		set("PowerUps", { Shield = 2, Turbo = 1 })
		set("Equipped", "Shield")
		set("IntroHero", false)
		set("Power", false)
		set("ShopOpen", false)
	end

	local function results()
		return {
			{ Name = "Builderman", UserId = 156, Seat = 3, Place = 1, Gold = 10 },
			{ Name = "You", Seat = 1, Place = 2, Gold = 6, Xp = 20, You = true },
			{ Name = "Wobbles", Seat = 4, Place = 3, Gold = 3 },
			{ Name = "Pipsqueak", Seat = 2, Place = 4, Gold = 5 },
			{ Name = "Bonkers", Seat = 5, Place = 5, Gold = 4 },
			{ Name = "Zippy", Seat = 6, Place = 6, Gold = 3 },
			{ Name = "Mochi", Seat = 7, Place = 7, Gold = 2 },
			{ Name = "Pogo", Seat = 8, Place = 8, Gold = 1 },
		}
	end

	local function standings()
		return {
			{ Name = "Builderman", UserId = 156, Seat = 3, Rank = 1, Gold = 34, Wins = 3 },
			{ Name = "You", Seat = 1, Rank = 2, Gold = 27, Wins = 2, You = true },
			{ Name = "Pipsqueak", Seat = 2, Rank = 3, Gold = 15, Wins = 0 },
			{ Name = "Wobbles", Seat = 4, Rank = 4, Gold = 12, Wins = 0 },
			{ Name = "Zippy", Seat = 6, Rank = 5, Gold = 11, Wins = 0 },
			{ Name = "Bonkers", Seat = 5, Rank = 6, Gold = 9, Wins = 0 },
			{ Name = "Pogo", Seat = 8, Rank = 7, Gold = 6, Wins = 0 },
			{ Name = "Mochi", Seat = 7, Rank = 8, Gold = 4, Wins = 0 },
		}
	end

	-- What each scenario looks like held still.
	local posters = {
		Lobby = function()
			base()
			set("Phase", "Lobby")
			set("Countdown", 7)
		end,
		Intro = function()
			base()
			set("Phase", "Intro")
			set("Countdown", 13)
		end,
		["Your moment"] = function()
			base()
			set("Phase", "Intro")
			set("Countdown", 6)
			set("IntroHero", true)
		end,
		Playing = function()
			base()
			set("Phase", "Play")
			set("TimeLeft", 64)
			local players = seats({ 10, 3, 6, 1 })
			players[4].Out = true
			set("Players", players)
			set("Alive", 3)
			set("Charge", 0.6)
			set("Power", { Id = "Shield", Level = 2, Used = false })
		end,
		Shop = function()
			base()
			set("Phase", "Practice")
			set("ShopOpen", true)
		end,
		["Level up"] = function()
			base()
			set("Phase", "Results")
			set("Results", results())
			emit("XpEarned", { Amount = 20, Level = 3, LeveledUp = true })
		end,
		["Knocked out"] = function()
			base()
			set("Phase", "Play")
			set("TimeLeft", 41)
			local players = seats({ 10, 3, 6, 1 })
			players[1].Out = true
			players[4].Out = true
			set("Players", players)
			set("Alive", 2)
			emit("KnockedOut", { Place = 3, Total = 4, Gold = 3, Reason = "knocked off", By = "Mochi", BySeat = 3 })
			emit("Eliminated", { Name = "Fizz", Seat = 4, Reason = "knocked off", By = "Zippy", BySeat = 2 })
		end,
		Results = function()
			base()
			set("Phase", "Results")
			set("Results", results())
			set("Players", seats({ 16, 4, 16, 4 }))
		end,
		Standings = function()
			base()
			set("Phase", "Standings")
			set("GameIndex", 5)
			set("Standings", standings())
		end,
	}

	-- What each scenario does on a loop.
	local scripts = {
		Lobby = function(alive)
			for seconds = 10, 0, -1 do
				if not alive() then
					return
				end
				set("Countdown", seconds)
				task.wait(1)
			end
		end,
		Intro = function(alive)
			-- the title card, the lineup, your name card, then 3, 2, 1 and GO! as play starts
			for seconds = 14, 1, -1 do
				if not alive() then
					return
				end
				set("Countdown", seconds)
				set("IntroHero", seconds <= 7 and seconds >= 5)
				task.wait(1)
			end
			if alive() then
				set("Phase", "Play")
			end
			task.wait(1.4)
		end,
		Playing = function(alive)
			local players = seats({ 10, 3, 6, 1 })
			set("Players", copy(players))
			set("Alive", 4)
			for second = 0, 14 do
				if not alive() then
					return
				end
				set("TimeLeft", 20 - second)
				set("Charge", (second % 4) / 3)
				if second == 4 or second == 9 then
					local out = second == 4 and 4 or 2
					players[out].Out = true
					set("Players", copy(players))
					set("Alive", (values.Alive or 4) - 1)
				end
				task.wait(1)
			end
			set("Charge", 0)
		end,
		["Knocked out"] = function(alive)
			task.wait(0.4)
			if alive() then
				emit("KnockedOut", { Place = 3, Total = 4, Gold = 3, Reason = "knocked off", By = "Mochi", BySeat = 3 })
			emit("Eliminated", { Name = "Fizz", Seat = 4, Reason = "knocked off", By = "Zippy", BySeat = 2 })
				emit("GoldEarned", { Amount = 3 })
				set("MyGold", 151)
			end
			task.wait(3.6)
		end,
		Results = function(alive)
			set("Results", {})
			task.wait(0.3)
			if alive() then
				set("Results", results())
				emit("GoldEarned", { Amount = 6 })
				set("MyGold", 154)
			end
			task.wait(4)
		end,
		Shop = function(alive)
			task.wait(1.2)
			if alive() then
				round.Do("ShopBuy", "Turbo")
			end
			task.wait(2.5)
		end,
		Standings = function(alive)
			set("Standings", {})
			task.wait(0.3)
			if alive() then
				set("Standings", standings())
			end
			task.wait(5)
		end,
	}

	-- Shows a scenario: held still, or looping its script.
	function round.Play(name: string, playing: boolean?)
		serial += 1
		local mine = serial
		local function alive()
			return serial == mine
		end
		local poster = posters[name] or posters.Lobby
		poster()
		if not playing then
			return
		end
		task.spawn(function()
			while alive() do
				poster()
				local script = scripts[name]
				if script then
					script(alive)
				end
				task.wait(0.6)
			end
		end)
	end

	-- The shop, played out here: buying takes the gold and raises the level, as the server would.
	function round.Do(action: string, id: string?)
		if action == "ShopToggle" then
			set("ShopOpen", not values.ShopOpen)
		elseif action == "ShopClose" then
			set("ShopOpen", false)
		elseif action == "ShopEquip" then
			set("Equipped", id)
			emit("ShopReply", { Ok = true, Message = id .. " equipped", Id = id })
		elseif action == "ShopBuy" then
			local owned = table.clone(values.PowerUps or {})
			local nextLevel = (owned[id] or 0) + 1
			local price = PRICES[nextLevel]
			if not price or (values.MyLevel or 1) < GATES[nextLevel] or (values.MyGold or 0) < price then
				emit("ShopReply", { Ok = false, Message = "Can't buy that yet", Id = id })
				return
			end
			owned[id] = nextLevel
			set("PowerUps", owned)
			set("MyGold", values.MyGold - price)
			emit("ShopReply", { Ok = true, Message = string.format("%s is now level %d!", id, nextLevel), Id = id })
		elseif action == "PowerUse" and values.Power then
			local power = table.clone(values.Power)
			power.Used = true
			set("Power", power)
		end
	end

	function round.Stop()
		serial += 1
	end

	return round
end

return FakeRound
