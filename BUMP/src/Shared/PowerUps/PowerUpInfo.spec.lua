--!nonstrict

local require =
	require(game:GetService("ServerScriptService"):FindFirstChild("LoaderUtils", true).Parent).bootstrapStory(script)

local Jest = require("Jest")
local PowerUpInfo = require(script.Parent.PowerUpInfo)

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

describe("PowerUpInfo", function()
	it("turns XP into a level and how far into it you are", function()
		local first = PowerUpInfo.XpToNext(1)
		expect((PowerUpInfo.LevelFor(0))).toBe(1)
		expect((PowerUpInfo.LevelFor(first - 1))).toBe(1)
		local level, into, need = PowerUpInfo.LevelFor(first + 10)
		expect(level).toBe(2)
		expect(into).toBe(10)
		expect(need).toBe(PowerUpInfo.XpToNext(2))
		expect((PowerUpInfo.LevelFor(-5))).toBe(1)
	end)

	it("pays more XP for a better place, and something for taking part", function()
		for place = 1, #PowerUpInfo.XpByPlace - 1 do
			expect(PowerUpInfo.XpFor(place) >= PowerUpInfo.XpFor(place + 1)).toBe(true)
		end
		expect(PowerUpInfo.XpFor(99)).toBe(PowerUpInfo.XpPerGame)
	end)

	it("prices each upgrade higher and gates it behind a higher level, with nothing past the top", function()
		for level = 2, PowerUpInfo.MaxLevel do
			expect(PowerUpInfo.Price("Shield", level) > PowerUpInfo.Price("Shield", level - 1)).toBe(true)
			expect(PowerUpInfo.LevelNeeded(level) > PowerUpInfo.LevelNeeded(level - 1)).toBe(true)
		end
		expect(PowerUpInfo.Price("Shield", PowerUpInfo.MaxLevel + 1)).toBe(math.huge)
	end)

	it("has stats for every power-up at every level, clamped at the ends", function()
		for _, id in PowerUpInfo.List do
			for level = 1, PowerUpInfo.MaxLevel do
				expect(PowerUpInfo.Stats(id, level) ~= nil).toBe(true)
			end
			expect(PowerUpInfo.Stats(id, 9)).toBe(PowerUpInfo.Stats(id, PowerUpInfo.MaxLevel))
		end
	end)

	it("writes a held power-up as text and reads it back", function()
		local id, level = PowerUpInfo.Decode(PowerUpInfo.Encode("Turbo", 2))
		expect(id).toBe("Turbo")
		expect(level).toBe(2)
		local none, zero = PowerUpInfo.Decode("not a power-up")
		expect(none).toBe(nil)
		expect(zero).toBe(0)
	end)

	it("raises the daily reward with the streak, up to a cap", function()
		local daily = PowerUpInfo.Daily
		expect(PowerUpInfo.DailyGold(1)).toBe(daily.Base)
		expect(PowerUpInfo.DailyGold(2)).toBe(daily.Base + daily.PerDay)
		expect(PowerUpInfo.DailyGold(daily.MaxStreak + 5)).toBe(PowerUpInfo.DailyGold(daily.MaxStreak))
		expect(PowerUpInfo.DayOf(86400 * 3 + 5)).toBe(3)
	end)
end)
