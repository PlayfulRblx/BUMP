--!nonstrict
--[[
	What both sides know about rounds: where the round's state lives, and each minigame's
	description for its intro card.

	The server keeps the round's state as attributes on ReplicatedStorage.BumpRound:
	    Phase        "Practice" | "Lobby" | "Changeover" | "Intro" | "Play" | "Results" | "Standings"
	                 (Changeover: between games, the old arena flying off and the next one arriving)
	    EndsAt       workspace:GetServerTimeNow() when this phase ends (lobby, intro, game clock)
	    GameIndex, GameCount
	    Minigame     the id of the game being played
	    Alive, Total
	    Frozen       true while players must stand still (the intro)
	    Intensity    0 to 1, how heated the game is (the music speeds up with it)
	    Note         a line the status bar shows instead of the clock ("Zippy has the bomb!")
	    Players, Results, Standings   JSON lists (see UIFusion/Kit/Source for their fields)
	Participants are named by Id: a player's UserId as a string, or "bot1".. for bots.
]]

local RoundInfo = {}

RoundInfo.Folder = "BumpRound"
RoundInfo.BotTag = "BumpBot"
RoundInfo.IdAttr = "BumpId" -- on every participant's character: its Id

RoundInfo.Minigames = {
	Bump = {
		Id = "Bump",
		Title = "BUMP",
		Blurb = "Jump on a ball and roll everyone else off the hex platform. One ball short, and the floor keeps shrinking.",
		Controls = {
			{ Key = "WASD", Label = "Roll" },
			{ Key = "Hold Click", Label = "Charge dash" },
			{ Key = "Pull back", Label = "Skrrt" },
			{ Key = "Space", Label = "Hop off" },
		},
	},
}

RoundInfo.Minigames.Bomber = {
	Id = "Bomber",
	Title = "Bomber Bloxians",
	Blurb = "Someone's holding an enormous ticking bomb. Run into another player to pass it on before it blows; every blast bites a hole in the arena.",
	Controls = {
		{ Key = "WASD", Label = "Run (faster with the bomb)" },
		{ Key = "Run into", Label = "Pass the bomb" },
		{ Key = "Click", Label = "Dive (passes from further)" },
	},
	NoClock = true,
}

-- The order the playlist draws from, round and round. TILT! joins when it's built.
RoundInfo.Playlist = { "Bump", "Bomber" }

-- The seat colours (seats 1 to 8), for the world: balls, spotlights, the intro's name pops. The UI
-- has the same in its tokens (Tokens.Colors.Seat1..8).
RoundInfo.SeatColors = {
	Color3.fromRGB(255, 92, 92),
	Color3.fromRGB(80, 156, 255),
	Color3.fromRGB(255, 206, 62),
	Color3.fromRGB(96, 214, 120),
	Color3.fromRGB(255, 150, 50),
	Color3.fromRGB(176, 110, 255),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(60, 214, 214),
}

-- Attributes on characters that games use.
RoundInfo.CarryingAttr = "BumpCarrying" -- holding something overhead (the bomb): the carry pose
RoundInfo.SpeedAttr = "BumpSpeedScale" -- the platformer multiplies running speed by this
-- Blown up by the bomb: while true every client flashes the body red, pops it and keeps it
-- hidden (Client/Systems/PopFx); the server clears it once the body is off the arena.
RoundInfo.PopAttr = "BumpPopped"
-- A player just knocked out of a game (the user, 2026-11-14: "show ELIMINATED BY X ... and show a
-- camera shot of the character"): their body is left where it went for this many seconds while
-- their camera watches it go (Client/Systems/KnockoutCam), then the game moves it to the stand;
-- meanwhile it has this attribute, and the lobby's fall catch leaves it alone.
RoundInfo.KnockoutHold = 1.5
RoundInfo.KnockoutHoldAttr = "BumpKnockoutHold"

return RoundInfo
