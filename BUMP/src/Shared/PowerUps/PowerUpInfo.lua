--!nonstrict
--[[
	Power-ups and progression (the user, 2026-11-13: "We should add power ups and progression
	elements that can be purchased with gold"). Their choices: bring one power-up into each game
	and press a button to use it, once a game (bots bring one too); gold unlocks a power-up and
	then upgrades it (levels 1 to 3); a player level, from XP for playing, gates the higher
	upgrades; a shop button that works anywhere.

	Both sides read this: the shop UI for names, prices and gates; the server for the same prices
	(it never trusts the client's) and for each level's numbers. Every number is a first guess.

	    PowerUpInfo.List                  ids in shop order
	    PowerUpInfo.Get(id)               the entry, or nil
	    PowerUpInfo.Stats(id, level)      that level's numbers
	    PowerUpInfo.Price(id, level)      gold to reach `level` (1 = unlock)
	    PowerUpInfo.LevelNeeded(level)    player level a power-up level needs
	    PowerUpInfo.LevelFor(xp)          player level, xp into it, xp it needs
	    PowerUpInfo.XpFor(place)          xp for a game finished in `place`
	    PowerUpInfo.Decode(text)          "Shield:2" -> "Shield", 2
]]

local PowerUpInfo = {}

PowerUpInfo.MaxLevel = 3

-- Gold to reach each level (1 = unlock), and the player level it needs.
PowerUpInfo.Prices = { 20, 50, 100 }
PowerUpInfo.LevelGates = { 1, 3, 6 }

-- XP: every game played, a bonus by place (1st to 8th), and one for seeing a session through.
PowerUpInfo.XpPerGame = 10
PowerUpInfo.XpByPlace = { 20, 15, 11, 8, 5, 3, 1, 0 }
PowerUpInfo.XpPerSession = 20

-- The daily reward (the REWARDS store, 2026-11-14): claim once a UTC day; coming back the next
-- day grows a streak, missing a day starts it again. Gold = Base + PerDay x (streak - 1), the
-- streak counting up to MaxStreak.
PowerUpInfo.Daily = table.freeze({ Base = 15, PerDay = 5, MaxStreak = 7 })

-- The day number the daily reward counts in (UTC days since 1970).
function PowerUpInfo.DayOf(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- The gold a claim on this streak day pays.
function PowerUpInfo.DailyGold(streak: number): number
	local daily = PowerUpInfo.Daily
	return daily.Base + daily.PerDay * (math.clamp(streak, 1, daily.MaxStreak) - 1)
end

-- Attributes. On the player (the server mirrors their save here, the HUD reads it):
PowerUpInfo.XpAttr = "BumpXp"
PowerUpInfo.LevelAttr = "BumpLevel"
PowerUpInfo.OwnedAttr = "BumpPowerUps" -- JSON { [id] = level }
PowerUpInfo.EquippedAttr = "BumpEquipped" -- an id, or ""
PowerUpInfo.DailyDayAttr = "BumpDailyDay" -- the day number of the last claim (0 = never)
PowerUpInfo.DailyStreakAttr = "BumpDailyStreak" -- the streak that claim was on
-- On a contestant's character during a game:
PowerUpInfo.PowerAttr = "BumpPower" -- "Shield:2", or nil when they have none
PowerUpInfo.UsedAttr = "BumpPowerUsed"
PowerUpInfo.ShieldAttr = "BumpShieldUntil" -- server time the shield drops
PowerUpInfo.BoostAttr = "BumpBoostUntil" -- server time a Turbo on foot ends
PowerUpInfo.BoostScaleAttr = "BumpBoostScale" -- run speed times this until then

PowerUpInfo.List = { "Shield", "Turbo", "Shockwave", "SecondChance" }

PowerUpInfo.Items = {
	Shield = {
		Id = "Shield",
		Name = "Shield",
		Glyph = "🛡",
		Color = Color3.fromRGB(90, 200, 255), -- the world's effects; the UI's is Tokens.Colors.Power<Id>
		Blurb = "A bubble that shrugs off hits, knock-offs and blasts, and the bomb.",
		Levels = {
			{ Seconds = 3 },
			{ Seconds = 4 },
			{ Seconds = 5 },
		},
		Describe = function(stats)
			return string.format("%d s bubble", stats.Seconds)
		end,
	},
	Turbo = {
		Id = "Turbo",
		Name = "Turbo",
		Glyph = "⚡",
		Color = Color3.fromRGB(255, 150, 50), -- the world's effects; the UI's is Tokens.Colors.Power<Id>
		Blurb = "On a ball: a full-power dash, no charging. On foot: a burst of speed.",
		Levels = {
			{ Dash = 1.0, Run = 1.5, Seconds = 2 },
			{ Dash = 1.1, Run = 1.5, Seconds = 2.5 },
			{ Dash = 1.2, Run = 1.5, Seconds = 3 },
		},
		Describe = function(stats)
			return string.format("dash x%.1f, run %.1f s", stats.Dash, stats.Seconds)
		end,
	},
	Shockwave = {
		Id = "Shockwave",
		Name = "Shockwave",
		Glyph = "💥",
		Color = Color3.fromRGB(190, 110, 255), -- the world's effects; the UI's is Tokens.Colors.Power<Id>
		Blurb = "A ripple from where you stand: riders it reaches wobble, people on foot are thrown.",
		Levels = {
			{ Radius = 20 },
			{ Radius = 25 },
			{ Radius = 30 },
		},
		Describe = function(stats)
			return string.format("%d stud ripple", stats.Radius)
		end,
	},
	SecondChance = {
		Id = "SecondChance",
		Name = "Second Chance",
		Glyph = "❤",
		Color = Color3.fromRGB(110, 230, 140), -- the world's effects; the UI's is Tokens.Colors.Power<Id>
		Blurb = "Fall off once and you're bounced back onto the floor. Works by itself.",
		Automatic = true,
		Levels = {
			{ Shield = 0 },
			{ Shield = 2 },
			{ Shield = 4 },
		},
		Describe = function(stats)
			return stats.Shield > 0 and string.format("back with a %d s shield", stats.Shield) or "back on the floor"
		end,
	},
}

function PowerUpInfo.Get(id: string?)
	return id and PowerUpInfo.Items[id] or nil
end

function PowerUpInfo.Stats(id: string, level: number)
	local item = PowerUpInfo.Items[id]
	return item and item.Levels[math.clamp(level, 1, PowerUpInfo.MaxLevel)] or nil
end

function PowerUpInfo.Price(_id: string, level: number): number
	return PowerUpInfo.Prices[level] or math.huge
end

function PowerUpInfo.LevelNeeded(level: number): number
	return PowerUpInfo.LevelGates[level] or math.huge
end

-- XP to go from `level` to the next: 50 + 25 per level.
function PowerUpInfo.XpToNext(level: number): number
	return 50 + 25 * level
end

-- (player level from 1, xp into this level, xp this level needs)
function PowerUpInfo.LevelFor(xp: number): (number, number, number)
	local level = 1
	local rest = math.max(xp or 0, 0)
	while rest >= PowerUpInfo.XpToNext(level) do
		rest -= PowerUpInfo.XpToNext(level)
		level += 1
	end
	return level, rest, PowerUpInfo.XpToNext(level)
end

function PowerUpInfo.XpFor(place: number): number
	return PowerUpInfo.XpPerGame + (PowerUpInfo.XpByPlace[place] or 0)
end

function PowerUpInfo.Encode(id: string, level: number): string
	return id .. ":" .. level
end

function PowerUpInfo.Decode(text: string?): (string?, number)
	if type(text) ~= "string" then
		return nil, 0
	end
	local id, level = string.match(text, "^(%w+):(%d+)$")
	return id, tonumber(level) or 0
end

return PowerUpInfo
